// A link the helper routed here (helper/Routes.swift): the rule's destination inside this profile.
// No destination, or mini: a mini browser, as every link from another app opened before rules.
// window "same-site": a tab already on that host, the front window's first, navigated if the URL
// differs; none, a new tab at the top of the front window. window "front": that new tab. group: a
// tab group by title, joined in whatever window has it, made in the front window if none does.
async function routeOpen(url, to = {}) {
  if (!to.window && !to.group) return miniBrowserTab(url);
  await ready;
  const front = await chrome.windows.getLastFocused({ windowTypes: ['normal'] }).catch(() => null);
  if (to.window === 'same-site') {
    const tab = sameSiteTab(url, front?.id);
    if (tab) {
      await chrome.tabs.update(tab.id, tab.url === url ? { active: true } : { url, active: true });
      await chrome.windows.update(tab.windowId, { focused: true });
      return tab.id;
    }
  }
  let windowId = front?.id, groupId = null;
  if (to.group) {
    const [group] = await chrome.tabGroups.query({ title: to.group });
    if (group) ({ windowId, id: groupId } = group);
  }
  if (!windowId) return miniBrowserTab(url);
  recreating++; // placed here, not by the new-tab rules
  try {
    const tab = await chrome.tabs.create({ url, windowId, active: true, index: groupId === null ? await topIndex(windowId) : undefined });
    if (to.group) {
      const id = await chrome.tabs.group(groupId === null ? { tabIds: tab.id, createProperties: { windowId } } : { groupId, tabIds: tab.id });
      if (groupId === null) await chrome.tabGroups.update(id, { title: to.group });
    }
    await chrome.windows.update(windowId, { focused: true });
    return tab.id;
  } finally {
    recreating--;
  }
}

const miniBrowserTab = async url => (await openMiniBrowser({ url })).tabs[0].id;

function sameSiteTab(url, frontWindowId) {
  const host = hostOf(url);
  if (!host) return null;
  const tabs = mruList().map(id => ({ id, ...tabInfo.get(id) })).filter(t => hostOf(t.url) === host);
  return tabs.find(t => t.url === url && t.windowId === frontWindowId)
    || tabs.find(t => t.windowId === frontWindowId)
    || tabs.find(t => t.url === url)
    || tabs[0] || null;
}

function hostOf(url) {
  try { return new URL(url).hostname; } catch { return null; }
}
