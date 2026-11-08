// Passes messages between music.js (the page's world) and the extension (player.js).
addEventListener('message', e => {
  if (e.source === window && e.data?.monochromeMusic !== undefined) chrome.runtime.sendMessage({ music: e.data.monochromeMusic }).catch(() => {});
});
chrome.runtime.onMessage.addListener(msg => {
  if (msg.musicAction) postMessage({ monochromeMusicAction: msg.musicAction }, location.origin);
});
