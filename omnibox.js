// The app's ⌘L and ⌘T box (helper/Omnibox.swift) asks this profile's copy for what Chrome's address
// bar draws on: history, bookmarks, the open tabs and the tab in front, then favicons for the rows it
// shows, and tells it where to go. The app ranks; this side only reads and navigates.
// Safari gives extensions neither history nor bookmarks, so there the app reads the profile's
// History.db itself and these lists come back empty.
const OMNIBOX_HISTORY_DAYS = 90, OMNIBOX_HISTORY_MAX = 5000, OMNIBOX_BOOKMARKS_MAX = 5000;

async function omniboxData() {
  const startTime = Date.now() - OMNIBOX_HISTORY_DAYS * 864e5;
  const [history, tree, tabs, front] = await Promise.all([
    chrome.history?.search({ text: '', startTime, maxResults: OMNIBOX_HISTORY_MAX }).catch(() => []) ?? [],
    chrome.bookmarks?.getTree().catch(() => []) ?? [],
    chrome.tabs.query({}),
    chrome.windows.getLastFocused({ windowTypes: ['normal'] }).catch(() => null),
  ]);
  const bookmarks = [];
  const walk = nodes => {
    for (const n of nodes) {
      if (bookmarks.length >= OMNIBOX_BOOKMARKS_MAX) return;
      if (n.url) bookmarks.push({ url: n.url, title: n.title || '' });
      if (n.children) walk(n.children);
    }
  };
  walk(tree);
  const current = front && tabs.find(t => t.active && t.windowId === front.id);
  return {
    history: history.filter(h => h.url).map(h => ({ url: h.url, title: h.title || '', visits: h.visitCount || 0, typed: h.typedCount || 0, last: h.lastVisitTime || 0 })),
    bookmarks,
    tabs: tabs.filter(t => t.url && !miniOpen.has(t.windowId)).map(t => ({ id: t.id, url: t.url, title: t.title || '', windowId: t.windowId })),
    current: current ? { id: current.id, url: current.url || '', title: current.title || '' } : null,
  };
}

async function omniboxFavicons(urls) {
  const icons = {};
  await Promise.all(urls.slice(0, 40).map(async url => { icons[url] = await favicon(url); }));
  return icons;
}

// url: go there. text: search for it, with the default search engine where the browser lets an
// extension use it (Chrome's search API), else Google. tab: switch to that open tab. newTab: the page
// opens as a new tab at the top of the front window, as a routed link does; otherwise it replaces the
// front window's tab.
async function omniboxGo({ url, text, tab, newTab }) {
  if (tab) return helperActivate(tab);
  if (!url && !text) return;
  const target = url || (chrome.search ? null : searchUrl(text));
  if (newTab) {
    const id = await routeOpen(target || 'about:blank', { window: 'front' });
    if (!target && id) await chrome.search.query({ text, tabId: id });
    return;
  }
  const front = await chrome.windows.getLastFocused({ windowTypes: ['normal'] }).catch(() => null);
  const [active] = front ? await chrome.tabs.query({ active: true, windowId: front.id }) : [];
  if (!active) return routeOpen(target || 'about:blank', { window: 'front' });
  if (target) await chrome.tabs.update(active.id, { url: target });
  else await chrome.search.query({ text, tabId: active.id });
  await chrome.windows.update(active.windowId, { focused: true });
}

async function omniboxFromHelper({ op, id, urls, ...go }) {
  if (op === 'data') helperSend({ omniboxData: { id, ...(await omniboxData()) } });
  else if (op === 'favicons') helperSend({ omniboxFavicons: { id, icons: await omniboxFavicons(urls || []) } });
  else if (op === 'go') await omniboxGo(go);
}
