// Locked tabs. A tab is locked when it's pinned or sits in one of LOCKED_GROUPS; it
// remembers the URL it had when it got locked. Closing it (⌘W, middle-click) puts it back at that
// URL in the same spot; ⌃R or the toolbar button resets it in place. Unpin it or drag it out of the
// group first to really close it.
//
// ⌘W is taken over by this extension so it closes tabs itself: Chrome's own ⌘W on a pinned tab
// shows a "press ⌘W again" toast first, and there's no setting to turn that off.
//
// Tab and group ids don't survive a browser restart, so locked URLs are also saved per slot
// ('pinned', or the group title) in tab order. During the first minute of a browser session
// (or after the extension reloads) a locked tab we haven't seen takes the URL saved at its position
// in its slot; after that, a newly locked tab takes its own current URL.
// ponytail: position matching assumes Chrome restores tabs in the same order across all windows;
// closing a window that has locked tabs and then quitting can shift URLs by one.
// "Replace pinned URL with current" or re-locking fixes a wrong one.

// The locked group's title, set on the options page; CoreCore until then.
let LOCKED_GROUPS = ['CoreCore'];
chrome.storage.local.get('lockedGroup').then(({ lockedGroup }) => { if (lockedGroup) LOCKED_GROUPS = [lockedGroup]; });
chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== 'local' || !changes.lockedGroup) return;
  LOCKED_GROUPS = [changes.lockedGroup.newValue || 'CoreCore'];
  resync();
});

// Every read-modify-write goes through this queue so overlapping tab events can't clobber each other.
let queue = Promise.resolve();
const run = fn => (queue = queue.then(fn).catch(console.error));

// What the worker knows without asking Chrome: which tabs are locked, every tab's window, title and
// URL, and the recently-used order. A service worker starts over with empty globals on any event, so
// all of it is rebuilt once at start (one query) and then kept from events; session storage backs up
// the MRU order and the locked URLs, which must outlive a restart.
const lockedIds = new Set();
const tabInfo = new Map(); // tabId -> { windowId, title, url }
let mru = []; // tab ids, most recently used first

const noteTab = t => tabInfo.set(t.id, { windowId: t.windowId, title: t.title || '', url: t.url || t.pendingUrl || '' });

async function loadState() {
  const tabs = await chrome.tabs.query({});
  tabs.forEach(noteTab);
  const { mru: saved = [] } = await chrome.storage.session.get('mru');
  const known = saved.filter(id => tabInfo.has(id));
  const rest = tabs.filter(t => !known.includes(t.id)).sort((a, b) => b.lastAccessed - a.lastAccessed);
  mru = [...known, ...rest.map(t => t.id)];
  await sync();
}
const ready = run(loadState);

chrome.tabs.onCreated.addListener(noteTab);
chrome.tabs.onUpdated.addListener((tabId, change, tab) => { if ('title' in change || 'url' in change) noteTab(tab); });
chrome.tabs.onAttached.addListener((tabId, { newWindowId }) => { const t = tabInfo.get(tabId); if (t) t.windowId = newWindowId; });
chrome.tabs.onRemoved.addListener(tabId => {
  tabInfo.delete(tabId);
  lockedIds.delete(tabId);
  if (mru.includes(tabId)) {
    mru = mru.filter(id => id !== tabId);
    chrome.storage.session.set({ mru });
  }
});

async function lockedTabs() {
  const groups = await chrome.tabGroups.query({});
  const locked = new Map(groups.filter(g => LOCKED_GROUPS.includes(g.title)).map(g => [g.id, g]));
  const tabs = await chrome.tabs.query({});
  return {
    ids: new Set(tabs.map(t => t.id)),
    locked: tabs.filter(t => t.pinned || locked.has(t.groupId))
      .map(t => ({ t, group: t.pinned ? null : locked.get(t.groupId) })),
  };
}

// Entries for closed tabs are kept (onRemoved still needs them if it runs after this) and dropped
// by onRemoved itself; session storage is wiped on restart anyway.
async function sync(change) {
  let { pins = {}, where = {}, restoreUntil } = await chrome.storage.session.get(['pins', 'where', 'restoreUntil']);
  restoreUntil ??= Date.now() + 60_000; // session storage is empty: browser just started or extension reloaded
  const restoring = Date.now() < restoreUntil;
  let { order = {} } = await chrome.storage.local.get('order');
  if (Array.isArray(order)) order = { pinned: order }; // saved before groups were supported
  change?.(pins);
  const { ids, locked } = await lockedTabs();
  const next = {};
  for (const { t, group } of locked) {
    const slot = group ? group.title : 'pinned';
    next[slot] ??= [];
    pins[t.id] ??= (restoring && order[slot]?.[next[slot].length]) || t.url;
    next[slot].push(pins[t.id]);
    where[t.id] = { windowId: t.windowId, index: t.index, group: group?.title, color: group?.color };
  }
  lockedIds.clear();
  for (const { t } of locked) lockedIds.add(t.id);
  for (const id in pins) if (ids.has(+id) && !lockedIds.has(+id)) delete pins[id];
  await chrome.storage.session.set({ pins, where, restoreUntil });
  await chrome.storage.local.set({ order: next });
  return pins;
}

const resync = () => run(() => sync());
chrome.runtime.onStartup.addListener(resync);
chrome.runtime.onInstalled.addListener(({ reason }) => {
  resync();
  if (reason === 'install') chrome.runtime.openOptionsPage();
});
chrome.tabs.onMoved.addListener(resync);
chrome.tabs.onAttached.addListener(resync);
chrome.tabGroups.onUpdated.addListener(resync);

chrome.tabs.onUpdated.addListener((tabId, change) => {
  if (!('pinned' in change) && !('groupId' in change)) return;
  run(async () => {
    // Chrome also reports pinned:false / ungrouped just before closing a tab; that's not a real unlock.
    const tab = await chrome.tabs.get(tabId).catch(() => null);
    if (!tab) return;
    const group = tab.groupId === -1 ? null : await chrome.tabGroups.get(tab.groupId);
    const isLocked = tab.pinned || LOCKED_GROUPS.includes(group?.title);
    await sync(p => { if (isLocked) p[tabId] ??= tab.url || tab.pendingUrl; else delete p[tabId]; });
    if (isLocked) injectPeekCatch(tabId);
    else chrome.tabs.sendMessage(tabId, { mini: 'locked', value: false }).catch(() => {});
  });
});

chrome.tabs.onRemoved.addListener((tabId, { isWindowClosing }) => {
  if (isWindowClosing) return; // window closed or Chrome quitting: keep the saved order for next launch
  run(async () => {
    const { pins = {}, where = {} } = await chrome.storage.session.get(['pins', 'where']);
    const url = pins[tabId], at = where[tabId];
    delete where[tabId];
    await chrome.storage.session.set({ where });
    if (!url || !at) return sync(p => { delete p[tabId]; });
    recreating++;
    try {
      const tab = await chrome.tabs.create({ url, pinned: !at.group, active: false, windowId: at.windowId, index: at.index });
      if (at.group) {
        const [g] = await chrome.tabGroups.query({ windowId: at.windowId, title: at.group });
        const groupId = await chrome.tabs.group(g ? { groupId: g.id, tabIds: tab.id } : { tabIds: tab.id, createProperties: { windowId: at.windowId } });
        if (!g) await chrome.tabGroups.update(groupId, { title: at.group, color: at.color });
      }
      await sync(p => { delete p[tabId]; p[tab.id] = url; });
    } finally {
      recreating--;
    }
  });
});

// New tabs open at the top of the tab list, just under the locked tabs (pinned, then the CoreCore
// group). A tab opened from a link in a normal tab stays where Chrome puts
// it, right after that tab. One opened in the background from a locked tab goes to the top, and if
// Chrome dropped it into the locked group it's taken out, so it doesn't get locked; one opened in the
// foreground from a locked tab becomes a peek (mini-browser.js). Tabs in other groups are left alone.
const STARTUP_GRACE_MS = 5000; // session restore recreates every tab; leave those where they are
let browserStarted = 0;
let recreating = 0; // locked tabs we're putting back stay where they're put
chrome.runtime.onStartup.addListener(() => { browserStarted = Date.now(); });
const starting = () => browserStarted && Date.now() - browserStarted < STARTUP_GRACE_MS;

async function isLocked(tabId) {
  await ready;
  return lockedIds.has(tabId);
}

async function topIndex(windowId, exceptTabId) {
  const groups = await chrome.tabGroups.query({ windowId });
  const locked = new Set(groups.filter(g => LOCKED_GROUPS.includes(g.title)).map(g => g.id));
  const tabs = await chrome.tabs.query({ windowId });
  return tabs.filter(t => t.id !== exceptTabId && (t.pinned || locked.has(t.groupId)))
    .reduce((top, t) => Math.max(top, t.index + 1), 0);
}

// peek's click catch (peek-click.js, and peek-open.js in the page's world) runs only in locked
// tabs: put there when a tab locks and on each navigation of a locked tab. (A group renamed to or from
// CoreCore isn't noticed; those tabs fall back to the tab-then-peek path until they navigate.)
async function injectPeekCatch(tabId, frameId) {
  const target = frameId === undefined ? { tabId, allFrames: true } : { tabId, frameIds: [frameId] };
  await chrome.scripting.executeScript({ target, files: ['peek-click.js'] }).catch(() => {});
  await chrome.scripting.executeScript({ target, files: ['peek-open.js'], world: 'MAIN' }).catch(() => {});
}
chrome.webNavigation.onCommitted.addListener(async d => {
  if (/^https?:/.test(d.url) && await isLocked(d.tabId)) injectPeekCatch(d.tabId, d.frameId);
});

// ⌥⌘-click on a link: the helper's tap turns it into ⌘-click (a background tab) and says so, and that
// tab becomes a mini browser.
let miniNextUntil = 0;

chrome.tabs.onCreated.addListener(created => {
  if (recreating || created.pinned || starting()) return;
  run(async () => {
    const tab = await chrome.tabs.get(created.id).catch(() => null);
    if (!tab || tab.pinned) return;
    if (!tab.active && miniNextUntil > Date.now()) {
      miniNextUntil = 0;
      openMiniBrowser({ tabId: tab.id }).catch(console.error); // queues its own run(): don't wait for it inside this one
      return;
    }
    if ((await chrome.windows.get(tab.windowId)).type !== 'normal') return;
    // Chrome records an opener for ⌘T too; only a link (not the New Tab page) stays by its opener.
    const newTabPage = /^chrome:\/\/new-?tab/.test(created.pendingUrl || created.url);
    if (tab.openerTabId && !newTabPage && !(await isLocked(tab.openerTabId))) return;
    if (tab.openerTabId && !newTabPage && tab.active) { // queues its own run(): don't wait for it inside this one
      openPeekBrowser({ tabId: tab.id }, { id: tab.openerTabId, windowId: tab.windowId }).catch(console.error);
      return;
    }
    if (tab.groupId !== -1) {
      if (!LOCKED_GROUPS.includes((await chrome.tabGroups.get(tab.groupId)).title)) return;
      await chrome.tabs.ungroup(tab.id);
    }
    const index = await topIndex(tab.windowId, tab.id);
    if (tab.index !== index) await chrome.tabs.move(tab.id, { index });
  });
});

function reset(tab) {
  return run(async () => {
    const url = (await sync())[tab.id];
    if (url && tab.url !== url) await chrome.tabs.update(tab.id, { url });
  });
}

function repin(tab) {
  return run(() => sync(p => { if (p[tab.id]) p[tab.id] = tab.url; }));
}

async function closeTabs() {
  const tabs = await chrome.tabs.query({ highlighted: true, currentWindow: true });
  await chrome.tabs.remove(tabs.map(t => t.id));
}

// Recent tabs: ⌃Tab walks through the current window's tabs, most recently used first, for as
// long as Control is held; letting go of Control ends the walk, so the next ⌃Tab goes back to the tab
// you came from. Chrome won't give extensions the Tab key or tell them when Control is released, so
// the helper's event tap (helper/Tap.swift) sends:
//   ⌃.  first ⌃Tab since Control went down: start a new walk (recent-next)
//   ⌃⇧. more ⌃Tabs with Control still held: keep walking (recent-continue)
//   ⌃,  ⌃⇧Tab: walk back one step (recent-prev)
// The order is our own most-recently-used list (newest first, in session storage), not Chrome's
// lastAccessed: tabs a walk passes through don't count as used, only the one it ends on does. So
// A → B → C, release, ⌃Tab goes back to A, not B. Tabs we haven't seen yet fall back to lastAccessed.
let walk = null; // { list, i, visited }

// All tabs, or one window's; ⌃Tab walks the window you're in. Every open tab is in the list: the
// start seeds it from lastAccessed, and a new tab is added as it opens.
function mruList(windowId) {
  const ids = mru.filter(id => tabInfo.has(id));
  return windowId === undefined ? ids : ids.filter(id => tabInfo.get(id).windowId === windowId);
}

function touch(tabId, at = 0) {
  mru = mru.filter(id => id !== tabId);
  mru.splice(at, 0, tabId);
  chrome.storage.session.set({ mru });
  helperMruSoon();
}

// A walk ends when the next one starts or you go to a tab some other way; only then does the tab it
// ended on count as used.
async function endWalk() {
  if (!walk) return;
  const last = walk.list[walk.i];
  walk = null;
  await touch(last);
}

function recent(step, fresh) {
  return run(async () => {
    if (fresh || !walk) {
      await endWalk();
      await ready;
      const front = await chrome.windows.getLastFocused().catch(() => null);
      walk = { list: mruList(front?.id), i: 0, visited: new Set() };
    }
    walk.i = (walk.i + step + walk.list.length) % walk.list.length;
    const id = walk.list[walk.i];
    walk.visited.add(id);
    walk.at = Date.now();
    const tab = await chrome.tabs.update(id, { active: true }).catch(() => null);
    if (tab) await chrome.windows.update(tab.windowId, { focused: true });
  });
}

function activated(tabId) {
  return run(async () => {
    // The walk's own moves arrive a moment after each step; a later click on one of those tabs is yours.
    if (walk?.visited.has(tabId) && Date.now() - walk.at < 1000) return;
    await endWalk();
    await touch(tabId);
  });
}

chrome.tabs.onActivated.addListener(({ tabId }) => activated(tabId));
// A tab opened in the background (right-click ▸ Open Link in New Tab, ⌘-click) goes right after the
// current tab, so the next ⌃Tab goes to it. Locked tabs we put back and restored tabs don't.
chrome.tabs.onCreated.addListener(tab => {
  if (tab.active || recreating || starting()) return;
  run(async () => {
    await endWalk(); // so the tab you're on is first in the list
    await touch(tab.id, 1);
  });
});
chrome.windows.onFocusChanged.addListener(async windowId => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) return;
  const [tab] = await chrome.tabs.query({ active: true, windowId });
  if (tab) activated(tab.id);
});

importScripts('mini-browser.js', 'routes.js', 'player.js', 'helper.js');

chrome.action.onClicked.addListener(reset);

// The options page asks what it shows.
chrome.runtime.onMessage.addListener((msg, sender, reply) => {
  if (!msg.status) return;
  reply({ helper: !!helper, lockedGroup: LOCKED_GROUPS[0] });
});

chrome.commands.onCommand.addListener((command, tab) => {
  if (command.startsWith('mini-')) return miniCommand(command);
  if (command === 'recent-next') return recent(1, true);
  if (command === 'recent-continue') return recent(1, false);
  if (command === 'recent-prev') return recent(-1, false);
  if (command === 'close-tab') return closeTabs();
  if (command === 'reset-tab') return reset(tab);
  if (command === 'repin-current') return repin(tab);
});
