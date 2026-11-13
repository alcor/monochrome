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
//
// What this extension does is switched in the app's settings window, not here: the app sends the
// switches it obeys as `prefs` (below), and every reader checks PREFS when it runs.

// Safari runs the same files (docs/safari.md). It has no tab groups, so there only pinned tabs are
// locked; each feature checks for its API (chrome.tabGroups, chrome.search) rather than for Safari.
// SAFARI itself is for what differs by browser rather than by API: the native messaging transport
// (helper.js) and the browser's name in the bar.
const SAFARI = chrome.runtime.getURL('').startsWith('safari-web-extension:');
const BROWSER_NAME = SAFARI ? 'Safari' : 'Chrome';
const HAS_GROUPS = !!chrome.tabGroups;
const inGroup = t => HAS_GROUPS && t.groupId !== undefined && t.groupId !== -1;

// Settings. The app owns them (helper/Prefs.swift, docs/settings.md) and sends the ones the extension
// obeys as one `prefs` message, the whole set, when this copy says hello and whenever one changes
// (helper.js). They are kept in chrome.storage.local under `prefs`, so they hold when the browser starts
// before the app does; a copy that has never heard from the app runs on PREF_DEFAULTS, which is how it
// behaved before the settings existed. Unknown keys are dropped and missing ones keep their default.
// The options page sets the locked group's title while the app is not connected.
const PREF_DEFAULTS = {
  lockedTabs: true, lockedGroup: 'Locked', newTabsAtTop: true, peek: true, miniIdleHours: 12,
  routeDefault: 'mini', thumbnails: true, player: true, playerStopPopout: true,
};
let PREFS = { ...PREF_DEFAULTS };
// The locked group's title, or none: then only pinned tabs lock.
let LOCKED_GROUPS = ['Locked'];

function prefsFrom(p = {}) {
  const next = { ...PREF_DEFAULTS };
  for (const key in PREF_DEFAULTS) if (p && typeof p[key] === typeof PREF_DEFAULTS[key]) next[key] = p[key];
  if (!['mini', 'front', 'same-site'].includes(next.routeDefault)) next.routeDefault = PREF_DEFAULTS.routeDefault;
  return next;
}

// What a change does beyond the readers that check PREFS as they run.
function prefsChanged(next) {
  const before = PREFS;
  if (JSON.stringify(before) === JSON.stringify(next)) return;
  PREFS = next;
  LOCKED_GROUPS = next.lockedGroup ? [next.lockedGroup] : [];
  // Off: nothing is locked and the saved order empties (sync), so on again locks each tab where it is.
  if (before.lockedGroup !== next.lockedGroup) run(() => renameOldLockedGroup(next.lockedGroup));
  if (before.lockedTabs !== next.lockedTabs || before.lockedGroup !== next.lockedGroup) resync();
  if (before.peek !== next.peek) run(async () => peekEverywhere(next.peek));
  if (before.player !== next.player && typeof playerResend === 'function') playerResend();
}

// From the app. The legacy title the options page kept goes once the app has sent a set.
async function applyPrefs(p) {
  const next = prefsFrom(p);
  await chrome.storage.local.set({ prefs: next });
  await chrome.storage.local.remove('lockedGroup');
  prefsChanged(next);
  return next;
}

// The locked group was titled CoreCore by default through 1.2.1. While the title in force is the new
// default, a group still titled CoreCore takes it, so its tabs stay locked; run ahead of the resync.
const OLD_LOCKED_GROUP = 'CoreCore';
async function renameOldLockedGroup(title) {
  if (!HAS_GROUPS || title !== PREF_DEFAULTS.lockedGroup) return false;
  const old = await chrome.tabGroups.query({ title: OLD_LOCKED_GROUP });
  for (const g of old) await chrome.tabGroups.update(g.id, { title });
  return old.length > 0;
}

// At start: the last set, or (before the app ever sent one) the legacy title on its own.
const prefsReady = chrome.storage.local.get(['prefs', 'lockedGroup']).then(({ prefs, lockedGroup }) => {
  prefsChanged(prefsFrom(prefs || (lockedGroup ? { lockedGroup } : {})));
  run(async () => { if (await renameOldLockedGroup(PREFS.lockedGroup)) await sync(); });
});
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && changes.prefs?.newValue) prefsChanged(prefsFrom(changes.prefs.newValue));
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
  await prefsReady;
  const tabs = await chrome.tabs.query({});
  tabs.forEach(noteTab);
  const { mru: saved = [] } = await chrome.storage.session.get('mru');
  const known = saved.filter(id => tabInfo.has(id));
  // Safari has no lastAccessed: restored tabs keep the order the query gave until visited.
  const rest = tabs.filter(t => !known.includes(t.id)).sort((a, b) => (b.lastAccessed || 0) - (a.lastAccessed || 0));
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
  if (!PREFS.lockedTabs) return { ids: new Set((await chrome.tabs.query({})).map(t => t.id)), locked: [] };
  const groups = HAS_GROUPS ? await chrome.tabGroups.query({}) : [];
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
if (HAS_GROUPS) chrome.tabGroups.onUpdated.addListener(resync);

chrome.tabs.onUpdated.addListener((tabId, change) => {
  if (!('pinned' in change) && !('groupId' in change)) return;
  run(async () => {
    // Chrome also reports pinned:false / ungrouped just before closing a tab; that's not a real unlock.
    const tab = await chrome.tabs.get(tabId).catch(() => null);
    if (!tab) return;
    const group = inGroup(tab) ? await chrome.tabGroups.get(tab.groupId) : null;
    const isLocked = PREFS.lockedTabs && (tab.pinned || LOCKED_GROUPS.includes(group?.title));
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
      if (at.group && HAS_GROUPS) {
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

// New tabs open at the top of the tab list, just under the locked tabs (pinned, then the locked
// group), unless newTabsAtTop is off. A tab opened from a link in a normal tab stays where Chrome puts
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
  const groups = HAS_GROUPS ? await chrome.tabGroups.query({ windowId }) : [];
  const locked = new Set(groups.filter(g => LOCKED_GROUPS.includes(g.title)).map(g => g.id));
  const tabs = await chrome.tabs.query({ windowId });
  return tabs.filter(t => t.id !== exceptTabId && (t.pinned || locked.has(t.groupId)))
    .reduce((top, t) => Math.max(top, t.index + 1), 0);
}

// peek's click catch (peek-click.js, and peek-open.js in the page's world) runs only in locked
// tabs: put there when a tab locks and on each navigation of a locked tab. (A group renamed to or from
// the locked group isn't noticed; those tabs fall back to the tab-then-peek path until they navigate.) With
// Settings → Mini Browsers → Peek browsers off, it isn't put anywhere, and the scripts already in
// locked tabs are told to stand down.
async function injectPeekCatch(tabId, frameId) {
  if (!PREFS.peek) return;
  const target = frameId === undefined ? { tabId, allFrames: true } : { tabId, frameIds: [frameId] };
  await chrome.scripting.executeScript({ target, files: ['peek-click.js'] }).catch(() => {});
  await chrome.scripting.executeScript({ target, files: ['peek-open.js'], world: 'MAIN' }).catch(() => {});
}
chrome.webNavigation.onCommitted.addListener(async d => {
  if (/^https?:/.test(d.url) && await isLocked(d.tabId)) injectPeekCatch(d.tabId, d.frameId);
});

async function peekEverywhere(on) {
  await ready;
  for (const id of lockedIds) {
    if (on) injectPeekCatch(id);
    else chrome.tabs.sendMessage(id, { mini: 'locked', value: false }).catch(() => {});
  }
}

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
    const newTabPage = /^(chrome|edge):\/\/new-?tab/.test(created.pendingUrl || created.url);
    if (tab.openerTabId && !newTabPage && !(await isLocked(tab.openerTabId))) return;
    if (tab.openerTabId && !newTabPage && tab.active && PREFS.peek) { // queues its own run(): don't wait for it inside this one
      openPeekBrowser({ tabId: tab.id }, { id: tab.openerTabId, windowId: tab.windowId }).catch(console.error);
      return;
    }
    if (inGroup(tab)) {
      if (!LOCKED_GROUPS.includes((await chrome.tabGroups.get(tab.groupId)).title)) return;
      await chrome.tabs.ungroup(tab.id);
    }
    if (!PREFS.newTabsAtTop) return; // Settings → Tabs: where the browser puts it
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

// Edge refuses to let an extension close its New Tab page ("Cannot remove NTP tab"), so one is moved
// off it first.
async function closeTabs() {
  const tabs = await chrome.tabs.query({ highlighted: true, currentWindow: true });
  await Promise.all(tabs.filter(t => /^edge:\/\/newtab/.test(t.pendingUrl || t.url)).map(t => chrome.tabs.update(t.id, { url: 'about:blank' })));
  await chrome.tabs.remove(tabs.map(t => t.id));
}

// ⌘W on a pinned tab, from the app (Chrome asks before it closes a pinned tab): the window goes to the
// tab used before it, and the pinned tab sleeps (is discarded) and leaves the recent-tab order until it
// is used again. If the front tab is no longer pinned by the time this runs, it closes, as ⌘W would.
function sleepFront() {
  return run(async () => {
    await endWalk();
    const front = await chrome.windows.getLastFocused({ windowTypes: ['normal'] }).catch(() => null);
    const [tab] = front ? await chrome.tabs.query({ active: true, windowId: front.id }) : [];
    if (!tab) return;
    if (!tab.pinned) return chrome.tabs.remove(tab.id);
    const others = (await chrome.tabs.query({ windowId: front.id })).filter(t => t.id !== tab.id);
    const next = mruList(front.id).find(id => id !== tab.id && others.some(t => t.id === id)) ?? others[0]?.id;
    if (next === undefined) await chrome.tabs.create({ windowId: front.id, active: true });
    else await chrome.tabs.update(next, { active: true });
    mru = mru.filter(id => id !== tab.id);
    chrome.storage.session.set({ mru });
    helperMruSoon();
    // A tab Chrome cannot discard (playing audio, say) stays awake. One it discards can come back under
    // a new id (onReplaced below); the id it ends up with is returned.
    const slept = await chrome.tabs.discard(tab.id).catch(() => null);
    return slept?.id ?? tab.id;
  });
}

// A discarded tab can come back under a new id. Everything kept by tab id moves to it: a slept locked
// tab stays locked at its locked URL, and one out of the recent order stays out. In run(), so it orders
// with sync().
chrome.tabs.onReplaced.addListener((added, removed) => run(async () => {
  const info = tabInfo.get(removed);
  if (info) { tabInfo.delete(removed); tabInfo.set(added, info); }
  if (lockedIds.delete(removed)) lockedIds.add(added);
  if (mru.includes(removed)) {
    mru = mru.map(id => id === removed ? added : id);
    chrome.storage.session.set({ mru });
  }
  const { pins = {}, where = {} } = await chrome.storage.session.get(['pins', 'where']);
  for (const byId of [pins, where]) if (removed in byId) { byId[added] = byId[removed]; delete byId[removed]; }
  await chrome.storage.session.set({ pins, where });
}));

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

importScripts('mini-browser.js', 'routes.js', 'player.js', 'helper.js', 'omnibox.js', 'tldr-background.js');

chrome.action.onClicked.addListener(reset);

// The options page asks what it shows, sets the locked group's title while the app is away (kept also
// under the legacy key, so the app adopts it at the next hello if it has none of its own), and opens
// the app's settings window.
chrome.runtime.onMessage.addListener((msg, sender, reply) => {
  if (msg.status) return reply({ helper: helperUp(), lockedGroup: PREFS.lockedGroup });
  if (msg.appSettings) return helperSend({ settings: true });
  if (typeof msg.lockedGroup !== 'string' || helperUp()) return;
  const next = prefsFrom({ ...PREFS, lockedGroup: msg.lockedGroup.trim() });
  chrome.storage.local.set({ prefs: next, lockedGroup: next.lockedGroup }).then(() => { prefsChanged(next); reply(true); });
  return true;
});

chrome.commands.onCommand.addListener((command, tab) => {
  if (command.startsWith('mini-')) return miniCommand(command);
  if (command === 'recent-next') return recent(1, true);
  if (command === 'recent-continue') return recent(1, false);
  if (command === 'recent-prev') return recent(-1, false);
  if (command === 'close-tab') return closeTabs();
  if (command === 'reset-tab') return reset(tab);
  if (command === 'repin-current') return repin(tab);
  if (command === 'tldr') return tldrToggle(tab?.id);
});
