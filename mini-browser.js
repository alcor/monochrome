// Mini browsers: small throwaway windows for quick lookups.
// - a Global shortcut opens one with a search box (mini-browser.html), from any app
// - links opened from other apps open in one
// - ⌥⌘-click a link opens it in one (peek-click.js)
// - a link from a locked tab (pinned or CoreCore) that opens a new tab opens as a peek: a mini browser
//   over the window it came from, page behind dimmed; focusing any other window closes it
// - "Open in Chrome" moves the page into the main window as a normal tab; ▾ picks a window or tab group, or another profile (the app opens it there)
//   (both also have shortcuts, see README)
// - an "Open in Chrome" bar sits top-right of the page (mini-browser-bar.js)
// - left unfocused for 12 hours (Settings → Mini Browsers → Close when unused for), a mini browser closes
// mini browsers are Chrome popup windows: no tab strip, no sidebar, back with ⌘[.
//
// Links from other apps come through the helper app, the default browser (helper/App.swift), straight to
// openMiniBrowser; only without it do they land as a tab in the main window first and get moved out.

// With no Chrome window to sit over, a mini browser opens at this size; otherwise it fills the last
// focused window inset on every side.
const MINI_SIZE = { width: 900, height: 700 };
const MINI_INSET = 40;

// The open mini browsers' window ids, in memory for the checks that run per window event; session
// storage holds the rest and is read back once when the worker starts.
const miniOpen = new Set();
chrome.storage.session.get('mini').then(({ mini = {} }) => { for (const id of Object.keys(mini)) miniOpen.add(+id); });

// Session-state writes go through run() (background.js) so focus events can't clobber a new window.
async function miniState() {
  const { mini = {}, peek = {}, lastNormal, focused } = await chrome.storage.session.get(['mini', 'peek', 'lastNormal', 'focused']);
  return { mini, peek, lastNormal, focused };
}

// Centered over the front window, at one size: a size remembered from the last mini browser was
// whatever that one had been shrunk or clamped to, and every later one inherited it.
async function miniBounds() {
  const w = await chrome.windows.getLastFocused({ windowTypes: ['normal'] }).catch(() => null);
  if (!w) return MINI_SIZE;
  return {
    left: w.left + MINI_INSET,
    top: w.top + MINI_INSET,
    width: w.width - 2 * MINI_INSET,
    height: w.height - 2 * MINI_INSET,
  };
}

async function openMiniBrowser({ url, tabId, bounds } = {}) {
  const source = tabId ? { tabId } : { url: url || chrome.runtime.getURL('mini-browser.html') };
  const w = await chrome.windows.create({ ...source, ...(bounds || await miniBounds()), type: 'popup', focused: true });
  miniOpen.add(w.id);
  await run(async () => {
    const { mini } = await miniState();
    mini[w.id] = Date.now();
    await chrome.storage.session.set({ mini });
  });
  helperMinisSoon();
  // The page may have finished loading before this window counted as a mini browser.
  if (!source.url?.startsWith(chrome.runtime.getURL(''))) await showMiniBar(w.tabs[0].id);
  return w;
}

async function isMiniBrowser(windowId) {
  return windowId in (await miniState()).mini;
}

// Peek browser: a link from a locked tab that would open a new tab opens as a mini browser sized to
// sit over the window it came from, with that page dimmed behind it. Any other window taking focus
// (clicking the dimmed page counts) closes it; Open in Chrome keeps it as a tab. It's a popup window
// in front of Chrome, not a sheet inside it, so it has its own title bar.
const PEEK_INSET = { x: 80, y: 40 };
const PEEK_MAX_WIDTH = 1100;

// source: { url } straight from a click the content script caught (no tab in the main window first),
// or { tabId } for a tab Chrome already made (what the content script didn't see: forms, a click
// before it knew the tab was locked). over: the locked tab it came from.
async function openPeekBrowser(source, over) {
  const win = await chrome.windows.get(over.windowId);
  const width = Math.min(PEEK_MAX_WIDTH, win.width - 2 * PEEK_INSET.x);
  const bounds = {
    width,
    height: win.height - 2 * PEEK_INSET.y,
    left: Math.round(win.left + (win.width - width) / 2),
    top: win.top + PEEK_INSET.y,
  };
  const w = await openMiniBrowser({ ...source, bounds });
  await run(async () => {
    const { peek } = await miniState();
    peek[w.id] = { tabId: over.id };
    await chrome.storage.session.set({ peek });
  });
  helperMinisSoon();
  await dim(over.id, true);
  return w;
}

// The in-page shade is the fallback; the helper draws its own over the window.
function dim(tabId, on) {
  if (helperUp()) return Promise.resolve();
  return chrome.scripting.executeScript({ target: { tabId }, args: [on], func: on => {
    const id = 'monochrome-peek-dim';
    document.getElementById(id)?.remove();
    if (!on) return;
    const shade = document.createElement('div');
    shade.id = id;
    shade.style.cssText = 'all: initial; display: block; position: fixed; inset: 0; z-index: 2147483647; background: rgba(0,0,0,.35);';
    document.documentElement.append(shade);
  } }).catch(() => {});
}

async function closePeekBrowsers(exceptWindowId) {
  const { peek } = await miniState();
  for (const id of Object.keys(peek)) {
    if (+id !== exceptWindowId) await chrome.windows.remove(+id).catch(() => {});
  }
}

// Normal windows and their tab groups, most recently focused window first: where a mini browser can go.
// A window is named by the tab it's on and how many it holds.
async function miniTargets() {
  const { lastNormal } = await miniState();
  const wins = (await chrome.windows.getAll({ windowTypes: ['normal'], populate: true }))
    .sort((a, b) => (b.id === lastNormal) - (a.id === lastNormal));
  const groups = HAS_GROUPS ? await chrome.tabGroups.query({}) : [];
  return wins.map(w => {
    const active = w.tabs.find(t => t.active);
    const name = (active?.title || active?.url || BROWSER_NAME).slice(0, 40);
    return {
      windowId: w.id,
      title: wins.length > 1 ? `${name} · ${w.tabs.length} tab${w.tabs.length === 1 ? '' : 's'}` : name,
      groups: groups.filter(g => g.windowId === w.id).map(g => ({ id: g.id, title: g.title || 'Unnamed group', color: g.color })),
    };
  });
}

async function moveToMain(tabId, { windowId, groupId } = {}) {
  if (!HAS_GROUPS) groupId = undefined;
  if (!windowId) windowId = (await miniTargets())[0]?.windowId;
  if (!windowId) {
    const w = await chrome.windows.create({ tabId, type: 'normal', focused: true });
    return w;
  }
  await chrome.tabs.move(tabId, { windowId, index: groupId || !PREFS.newTabsAtTop ? -1 : await topIndex(windowId) });
  if (groupId) await chrome.tabs.group({ groupId, tabIds: tabId });
  await chrome.tabs.update(tabId, { active: true });
  await chrome.windows.update(windowId, { focused: true });
}

async function activeMiniTab() {
  const w = await chrome.windows.getLastFocused({ populate: true }).catch(() => null);
  if (!w || !(await isMiniBrowser(w.id))) return null;
  return w.tabs.find(t => t.active);
}

// The in-page bar is the fallback; with the helper app connected the bar is its own panel (helper.js).
async function showMiniBar(tabId) {
  if (helperUp()) return;
  await chrome.scripting.executeScript({ target: { tabId }, files: ['mini-browser-bar.js'] }).catch(() => {});
}

async function archiveMiniBrowsers(now = Date.now()) {
  if (!PREFS.miniIdleHours) return; // never
  const { mini, focused } = await miniState();
  for (const [id, last] of Object.entries(mini)) {
    if (+id !== focused && now - last > PREFS.miniIdleHours * 3600e3) await chrome.windows.remove(+id).catch(() => {});
  }
}

// Links from other apps that reached the browser without the app. Startup pages also arrive as
// 'start_page'; starting() leaves those alone. Settings → Mini Browsers → Links from other apps
// (routeDefault): a mini browser; a new tab in the front window, which this one already is; or a tab
// already on that site, which takes the link while this one closes.
chrome.webNavigation.onCommitted.addListener(async d => {
  if (d.frameId !== 0 || d.transitionType !== 'start_page' || starting()) return;
  const tab = await chrome.tabs.get(d.tabId).catch(() => null);
  if (!tab || tab.pinned || (await isMiniBrowser(tab.windowId))) return;
  const win = await chrome.windows.get(tab.windowId);
  if (win.type !== 'normal') return;
  if (PREFS.routeDefault === 'front') return;
  if (PREFS.routeDefault === 'same-site') {
    await ready;
    const other = sameSiteTab(d.url, tab.windowId, d.tabId);
    if (!other) return;
    await chrome.tabs.update(other.id, other.url === d.url ? { active: true } : { url: d.url, active: true });
    await chrome.windows.update(other.windowId, { focused: true });
    return chrome.tabs.remove(d.tabId).catch(() => {});
  }
  await openMiniBrowser({ tabId: d.tabId });
});

// The "Open in Chrome" bar, on every page load inside a mini browser.
chrome.webNavigation.onCompleted.addListener(async d => {
  if (d.frameId !== 0 || d.url.startsWith(chrome.runtime.getURL(''))) return;
  const tab = await chrome.tabs.get(d.tabId).catch(() => null);
  if (tab && (await isMiniBrowser(tab.windowId))) await showMiniBar(d.tabId);
});

async function miniFocused(windowId) {
  const { mini, focused } = await miniState();
  const now = Date.now();
  if (focused in mini) mini[focused] = now;
  if (windowId in mini) mini[windowId] = now;
  const set = { mini, focused: windowId };
  if (windowId === chrome.windows.WINDOW_ID_NONE) return chrome.storage.session.set(set); // another app: peek browsers stay
  if (!(windowId in mini)) {
    const w = await chrome.windows.get(windowId).catch(() => null);
    if (w?.type === 'normal') set.lastNormal = windowId;
  }
  await chrome.storage.session.set(set);
  await closePeekBrowsers(windowId);
}
chrome.windows.onFocusChanged.addListener(windowId => run(() => miniFocused(windowId)));

chrome.windows.onRemoved.addListener(windowId => run(async () => {
  miniOpen.delete(windowId);
  const { mini, peek } = await miniState();
  if (!(windowId in mini)) return;
  delete mini[windowId];
  const over = peek[windowId];
  delete peek[windowId];
  await chrome.storage.session.set({ mini, peek });
  if (over) await dim(over.tabId, false);
}));

chrome.storage.local.remove('miniBounds'); // the size earlier versions kept

chrome.alarms.create('mini-archive', { periodInMinutes: 30 });
chrome.alarms.onAlarm.addListener(a => { if (a.name === 'mini-archive') archiveMiniBrowsers(); });

// What a mini browser search box or address field means: a URL goes straight there, anything else is a
// search with Chrome's default engine. Safari has no search API and tells extensions nothing about its
// engine, so there it is a Google search.
const searchUrl = text => `https://www.google.com/search?q=${encodeURIComponent(text)}`;

function asUrl(text) {
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(text)) return text;
  if (/\s/.test(text)) return null;
  if (/^(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?(\/|$)/.test(text) || /^[^/]+\.[a-z]{2,}(:\d+)?(\/|$)/i.test(text)) {
    return (text.startsWith('localhost') ? 'http://' : 'https://') + text;
  }
  return null;
}

async function miniGo(tabId, text) {
  const url = asUrl(text);
  if (url) await chrome.tabs.update(tabId, { url });
  else if (chrome.search) await chrome.search.query({ text, tabId });
  else await chrome.tabs.update(tabId, { url: searchUrl(text) });
}

chrome.runtime.onMessage.addListener((msg, sender, reply) => {
  if (msg.mini === 'open') openMiniBrowser({ url: msg.url }).then(() => reply(true));
  else if (msg.mini === 'peek') openPeekBrowser({ url: msg.url }, sender.tab).then(() => reply(true));
  else if (msg.mini === 'locked?') isLocked(sender.tab.id).then(reply);
  else if (msg.mini === 'go') miniGo(sender.tab.id, msg.text).then(() => reply(true));
  else if (msg.mini === 'targets') miniTargets().then(reply);
  else if (msg.mini === 'browser') reply(BROWSER_NAME);
  else if (msg.mini === 'shortcuts') chrome.commands.getAll().then(cs => reply(Object.fromEntries(cs.map(c => [c.name, c.shortcut]))));
  else if (msg.mini === 'move') moveToMain(sender.tab.id, msg.to).then(() => reply(true));
  else return;
  return true; // reply comes later
});

async function miniCommand(command) {
  if (command === 'mini-new') return openMiniBrowser();
  const tab = await activeMiniTab();
  if (!tab) return;
  if (command === 'mini-open') return moveToMain(tab.id);
  if (command === 'mini-open-in') {
    if (helperUp()) return helperSend({ miniMenu: tab.windowId });
    return chrome.tabs.sendMessage(tab.id, { mini: 'menu' }).catch(() => {});
  }
}
