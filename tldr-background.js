// TLDR, the reader (docs/tldr.md): the service worker's side. The reader itself is tldr/core, plain
// scripts injected into the tab when it is asked for and at no other time; no page gets them before
// that. This file injects them, answers the command, the app's ⌥⇧R and the mini browser bar's button,
// and relays model requests between the page's port and the Monochrome app (helper.js). It reads none
// of what it relays.
const TLDR_CORE = ['tldr/vendor/Readability.js', 'tldr/vendor/Readability-readerable.js', 'tldr/core/capture.js', 'tldr/core/media.js',
                   'tldr/core/selectors.js', 'tldr/core/clutter.js', 'tldr/core/extract.js', 'tldr/core/extractive.js', 'tldr/core/verify.js',
                   'tldr/core/reader.css.js', 'tldr/core/render.js', 'tldr/core/index.js'];
const TLDR_FILES = [...TLDR_CORE, 'tldr/adapters/extension.js'];
const TLDR_STATUS_MS = 2000;

// Opens or closes the reader in a tab: the given one, or the tab in front of the focused window.
async function tldrToggle(tabId, files = TLDR_FILES) {
  if (tabId === undefined) {
    const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    if (!tab || !/^https?:/.test(tab.url || '')) return false;
    tabId = tab.id;
  }
  const target = { tabId };
  try {
    const [{ result: loaded }] = await chrome.scripting.executeScript({ target, func: () => !!globalThis.__tldr?.toggle });
    if (!loaded) await chrome.scripting.executeScript({ target, files });
    const [{ result }] = await chrome.scripting.executeScript({ target, func: () => globalThis.__tldr.toggle() });
    return !!result;
  } catch (e) { // a page the extension may not script: the Web Store, a browser page
    console.warn('tldr:', e.message);
    return false;
  }
}

// The page's requests carry ids of the page's own; the worker gives each one of its own for the app,
// since several tabs ask over the one port to it, and puts the page's id back on every answer.
let tldrNext = 1;
const tldrRequests = new Map(); // worker id -> { port, id, timer }

function tldrAnswer(workerId, piece, last) {
  const request = tldrRequests.get(workerId);
  if (!request) return;
  if (last) { clearTimeout(request.timer); tldrRequests.delete(workerId); }
  try { request.port.postMessage({ ...piece, id: request.id }); } catch {}
}

chrome.runtime.onConnect.addListener(port => {
  if (port.name !== 'tldr' || port.sender?.id !== chrome.runtime.id) return;
  port.onMessage.addListener(msg => {
    if (msg.op === 'cancel') {
      for (const [workerId, r] of tldrRequests) {
        if (r.port === port && r.id === msg.id) { tldrRequests.delete(workerId); helperSend({ tldr: { op: 'cancel', id: workerId } }); }
      }
      return;
    }
    if (msg.op !== 'status' && msg.op !== 'summarize' && msg.op !== 'classify') return;
    const workerId = tldrNext++;
    tldrRequests.set(workerId, { port, id: msg.id });
    if (!helperUp()) return tldrAnswer(workerId, msg.op === 'status' ? { op: 'status', model: 'none', reason: 'noApp' } : { op: 'error', code: 'unavailable' }, true);
    // An app from before the reader does not answer: the page hears "no model" instead of waiting.
    if (msg.op === 'status') tldrRequests.get(workerId).timer = setTimeout(() => tldrAnswer(workerId, { op: 'status', model: 'none', reason: 'noApp' }, true), TLDR_STATUS_MS);
    helperSend({ tldr: { ...msg, id: workerId } });
  });
  port.onDisconnect.addListener(() => {
    for (const [workerId, r] of tldrRequests) {
      if (r.port !== port) continue;
      clearTimeout(r.timer);
      tldrRequests.delete(workerId);
      helperSend({ tldr: { op: 'cancel', id: workerId } });
    }
  });
});

// From the app: ⌥⇧R seen by its tap, or a piece of an answer.
function tldrFromHelper(msg) {
  if (msg.op === 'toggle') return tldrToggle();
  tldrAnswer(msg.id, msg, msg.op === 'status' || msg.op === 'done' || msg.op === 'error' || msg.op === 'verdicts');
}

// The in-page mini browser bar's reader button.
chrome.runtime.onMessage.addListener((msg, sender) => {
  if (msg.tldr === 'toggle' && sender.id === chrome.runtime.id && sender.tab) tldrToggle(sender.tab.id);
});
