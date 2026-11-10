// Passes messages between music.js (the page's world) and the extension (player.js), and tells music.js
// whether to keep the site's pop-out player stopped: Settings → Player, kept in the extension's storage
// (background.js), which the page's world cannot read. Stopped unless the mini player or the pop-out
// switch is off.
const relayPrefs = prefs => {
  const p = prefs || {};
  postMessage({ monochromeMusicPrefs: { stopPopout: p.player !== false && p.playerStopPopout !== false } }, location.origin);
};
chrome.storage.local.get('prefs').then(({ prefs }) => relayPrefs(prefs)).catch(() => {});
chrome.storage.onChanged.addListener((changes, area) => { if (area === 'local' && changes.prefs) relayPrefs(changes.prefs.newValue); });
addEventListener('message', e => {
  if (e.source === window && e.data?.monochromeMusic !== undefined && chrome.runtime?.id) chrome.runtime.sendMessage({ music: e.data.monochromeMusic }).catch(() => {});
});
chrome.runtime.onMessage.addListener(msg => {
  if (msg.musicAction) postMessage({ monochromeMusicAction: msg.musicAction }, location.origin);
});
