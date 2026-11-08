// The helper app (helper/): one native messaging port, opened here and kept open. The helper pings it
// every 20 seconds so this service worker isn't stopped for being idle. Over it go, out: the recently
// used tab list with favicons for the ⌃Tab switcher, a thumbnail of a tab whenever it's been in front,
// the mini browser windows for the helper's bar and peek shade, and the mini player's state; in: the tab
// the switcher picked, a link from another app to open as a mini browser, the bar's actions, a scroll
// seen by the tap, an ⌥⌘-click seen by the tap, and mini player button presses. Without the helper (not installed, or not running yet)
// nothing here matters: ⌃Tab still arrives as the recent-* commands and links still arrive as tabs.
const HELPER = 'monochrome_helper';
const MRU_SENT = 12;
const THUMB_WIDTH = 480, THUMB_MIN_MS = 1000, THUMB_SETTLE_MS = 400;

let helper = null, helperRetryMs = 1000;
const helperSend = msg => helper?.postMessage(msg);

function helperConnect() {
  if (helper) return;
  const port = chrome.runtime.connectNative(HELPER);
  port.onMessage.addListener(helperMessage);
  port.onDisconnect.addListener(() => {
    helper = null;
    setTimeout(helperConnect, helperRetryMs);
    helperRetryMs = Math.min(helperRetryMs * 2, 60_000);
  });
  helper = port;
  helperRetryMs = 1000;
  helperHello();
}
helperConnect();
// A timer dies with the worker; the alarm doesn't.
chrome.alarms.create('helper-connect', { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener(a => { if (a.name === 'helper-connect') helperConnect(); });

// Tab ids start over when Chrome restarts, so the helper drops its thumbnails when the session changes.
async function helperHello() {
  let { session } = await chrome.storage.session.get('session');
  if (!session) {
    session = crypto.randomUUID();
    await chrome.storage.session.set({ session });
  }
  faviconSent.clear();
  helperSend({ hello: { session } });
  helperSend({ shortcuts: Object.fromEntries((await chrome.commands.getAll()).map(c => [c.name, c.shortcut])) });
  playerResend();
  helperMruSoon();
  helperMinisSoon();
}

function helperMessage(msg) {
  if (msg.activate) helperActivate(msg.activate);
  else if (msg.open) routeOpen(msg.open, msg.to).catch(console.error);
  else if (msg.player) playerAction(msg.player);
  else if (msg.mini) miniFromHelper(msg.mini).catch(console.error);
  else if (msg.miniNew) openMiniBrowser();
  else if (msg.scrolled) helperThumbFront();
  else if (msg.miniNext) miniNextUntil = Date.now() + 1500;
  else if (msg.resend) helperHello(); // the app restarted under a host that stayed up
}

// The helper's mini browser bar: open in Chrome, move to a window or group, go to an address, or close
// a peek (a click on its shade).
async function miniFromHelper({ window, action, to, text }) {
  if (action === 'closePeekBrowser') return chrome.windows.remove(window).catch(() => {});
  const [tab] = await chrome.tabs.query({ windowId: window, active: true });
  if (!tab) return;
  if (action === 'open') await moveToMain(tab.id);
  else if (action === 'move') await moveToMain(tab.id, to);
  else if (action === 'go') await miniGo(tab.id, text);
}

// mini browser windows: where they are and what's in them, which of them are peek browsers and over which
// window, and where they can be moved to, for the helper's bar and shade.
// Window events fire per frame of any drag; with no mini browser open there is nothing to send, except
// once, so the helper hears that the last one closed.
let minisTimer = null, minisSent = false;
function helperMinisSoon() {
  if (!helper || minisTimer || (!miniOpen.size && !minisSent)) return;
  minisTimer = setTimeout(() => { minisTimer = null; helperMinis().catch(console.error); }, 50);
}

async function helperMinis() {
  const { mini, peek } = await miniState();
  minisSent = Object.keys(mini).length > 0;
  const windows = await chrome.windows.getAll({ populate: true });
  const bounds = w => ({ left: w.left, top: w.top, width: w.width, height: w.height });
  const minis = [];
  for (const w of windows) {
    if (!(w.id in mini)) continue;
    const tab = w.tabs.find(t => t.active);
    const over = peek[w.id] && await chrome.tabs.get(peek[w.id].tabId).then(t => chrome.windows.get(t.windowId)).catch(() => null);
    minis.push({ id: w.id, ...bounds(w), url: tab?.url || '', title: tab?.title || '', over: over ? bounds(over) : null });
  }
  helperSend({ minis, targets: await miniTargets() });
}
chrome.windows.onCreated.addListener(helperMinisSoon);
chrome.windows.onRemoved.addListener(helperMinisSoon);
chrome.windows.onBoundsChanged.addListener(helperMinisSoon);
chrome.windows.onFocusChanged.addListener(helperMinisSoon);
chrome.tabGroups.onCreated.addListener(helperMinisSoon);
chrome.tabGroups.onUpdated.addListener(helperMinisSoon);
chrome.tabGroups.onRemoved.addListener(helperMinisSoon);

function helperActivate(tabId) {
  return run(async () => {
    await endWalk();
    const tab = await chrome.tabs.update(tabId, { active: true }).catch(() => null);
    if (tab) await chrome.windows.update(tab.windowId, { focused: true });
  });
}

// The list: most recently used first, as mruList() orders it, every window's tabs with their window id
// and which window is in front, so the switcher can keep to that window; favicons as data: URLs.
let mruTimer = null;
function helperMruSoon() {
  if (!helper || mruTimer) return;
  mruTimer = setTimeout(() => { mruTimer = null; helperMru().catch(console.error); }, 100);
}

// A favicon goes over once per tab and page (the helper keeps it); null means the page has none.
const faviconSent = new Map(); // tabId -> url it was sent for
let mruSentIds = new Set();

async function helperMru() {
  await ready;
  const ids = mruList().slice(0, MRU_SENT);
  mruSentIds = new Set(ids);
  const mru = await Promise.all(ids.map(async id => {
    const t = tabInfo.get(id);
    const entry = { id, windowId: t.windowId, title: t.title || t.url };
    if (faviconSent.get(id) !== t.url) {
      entry.favicon = await favicon(t.url);
      faviconSent.set(id, t.url);
    }
    return entry;
  }));
  // This profile's front window, by id, bounds and tab title: the helper has one connection per
  // profile and matches these against the window in front on screen to know whose tabs ⌃Tab walks.
  // Chrome titles a window after its tab and, with more than one profile, the profile's name.
  const front = await chrome.windows.getLastFocused().catch(() => null);
  const [frontTab] = front ? await chrome.tabs.query({ active: true, windowId: front.id }) : [];
  helperSend({ mru, window: front?.id ?? -1,
               front: front && { left: front.left, top: front.top, width: front.width, height: front.height, title: frontTab?.title || '' } });
}

const favicons = new Map();
async function favicon(pageUrl) {
  if (!pageUrl) return null;
  if (favicons.has(pageUrl)) return favicons.get(pageUrl);
  const url = chrome.runtime.getURL(`/_favicon/?pageUrl=${encodeURIComponent(pageUrl)}&size=32`);
  const data = await fetch(url).then(r => r.blob()).then(dataUrl).catch(() => null);
  if (favicons.size > 500) favicons.clear();
  favicons.set(pageUrl, data);
  return data;
}

function dataUrl(blob) {
  return new Promise(resolve => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => resolve(null);
    reader.readAsDataURL(blob);
  });
}

chrome.tabs.onUpdated.addListener((tabId, change) => {
  // A title ticking in a tab the switcher never shows (a timer, an unread count) is not a reason to resend.
  if (('title' in change || 'favIconUrl' in change) && mruSentIds.has(tabId)) helperMruSoon();
  if ('title' in change || 'url' in change) helperMinisSoon();
  if (change.status === 'complete') helperThumbSoon(tabId);
});
chrome.tabs.onRemoved.addListener(tabId => {
  faviconSent.delete(tabId);
  helperSend({ closed: tabId });
  helperMruSoon();
});
chrome.tabs.onActivated.addListener(({ tabId }) => helperThumbSoon(tabId, THUMB_SETTLE_MS));
chrome.windows.onFocusChanged.addListener(async windowId => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) return;
  helperMruSoon(); // the list carries which window is in front
  const [tab] = await chrome.tabs.query({ active: true, windowId });
  if (tab) helperThumbSoon(tab.id);
});
// A scroll in Chrome, seen by the helper's tap: the tab in front has changed its look.
async function helperThumbFront() {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (tab) helperThumbSoon(tab.id);
}

// Thumbnails. Chrome can only capture the tab that's in front, so each tab's picture is from the last
// time it was: taken shortly after it's activated, when a page finishes loading, and after a scroll
// (the helper's tap reports those), at most once a second per tab, scaled down here before it leaves
// the worker.
const thumbAt = new Map(), thumbTimers = new Map();
function helperThumbSoon(tabId, after = 0) {
  if (!helper) return;
  const wait = Math.max(after, THUMB_MIN_MS - (Date.now() - (thumbAt.get(tabId) || 0)));
  if (thumbTimers.has(tabId)) return;
  thumbTimers.set(tabId, setTimeout(() => {
    thumbTimers.delete(tabId);
    helperThumb(tabId).catch(() => {});
  }, wait));
}

async function helperThumb(tabId) {
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (!tab?.active || !/^https?:/.test(tab.url)) return;
  thumbAt.set(tabId, Date.now());
  const shot = await chrome.tabs.captureVisibleTab(tab.windowId, { format: 'jpeg', quality: 70 }).catch(() => null);
  if (!shot) return;
  const bitmap = await createImageBitmap(await (await fetch(shot)).blob());
  const height = Math.round(bitmap.height * THUMB_WIDTH / bitmap.width);
  const canvas = new OffscreenCanvas(THUMB_WIDTH, height);
  canvas.getContext('2d').drawImage(bitmap, 0, 0, THUMB_WIDTH, height);
  bitmap.close();
  const data = await dataUrl(await canvas.convertToBlob({ type: 'image/jpeg', quality: 0.6 }));
  if (data) helperSend({ thumb: { id: tabId, data } });
}
