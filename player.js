// Sidebar mini player: while a music site (music.js) has a track loaded and you're on
// another tab, a small player with play/pause, next and previous sits over the bottom of the vertical
// tab sidebar; clicking the track goes to its tab, and × hides it until you've been back to that tab.
// Chrome doesn't let extensions draw in its tab strip, so the player is a panel of the helper app
// (helper/Player.swift) floating over it, told what to show over the helper's port (helper.js).
//
// The sidebar's width is the window's minus the page's.
// ponytail: a side panel open on the right also counts as sidebar, so the player gets too wide.

const PLAYER_MIN_SIDEBAR = 150; // narrower than this, the sidebar is collapsed (⌘S): no player
const music = new Map(); // tabId -> { title, artist, artwork }
let playerSent = '', playerTab = null, lastPlayed = null, playerClosed = null;

chrome.runtime.onMessage.addListener((msg, sender) => {
  if (!('music' in msg) || !sender.tab) return;
  if (msg.music) music.set(sender.tab.id, msg.music);
  else music.delete(sender.tab.id);
  playerUpdate();
});
const musicGone = id => { music.delete(id); playerUpdate(); };
chrome.tabs.onRemoved.addListener(musicGone);
// A new page loading in the tab (not a music site's own in-page navigation); a music site says so again.
chrome.tabs.onUpdated.addListener((id, change) => {
  if (change.status === 'loading' && music.has(id)) musicGone(id);
  else if ('audible' in change && music.has(id)) playerUpdate();
});

async function playerState() {
  if (!music.size) return null;
  const audible = (await chrome.tabs.query({ audible: true })).find(t => music.has(t.id));
  if (audible) lastPlayed = audible.id;
  const id = music.has(lastPlayed) ? lastPlayed : [...music.keys()].at(-1);
  if (id === undefined) return null; // the last one went while we waited
  const { title, artist, artwork } = music.get(id);
  playerTab = { id, playing: audible?.id === id };
  const win = await chrome.windows.getLastFocused({ populate: true }).catch(() => null);
  const active = win?.tabs.find(t => t.active);
  const sidebar = win && active ? win.width - active.width : 0;
  if (active?.id === id) playerClosed = null; // back on the music tab: × is undone for when you leave
  return {
    show: win?.type === 'normal' && win.state !== 'minimized' && active?.id !== id && playerClosed !== id && sidebar >= PLAYER_MIN_SIDEBAR,
    title, artist, artwork, playing: playerTab.playing, sidebar,
    window: win && { left: win.left, top: win.top, width: win.width, height: win.height },
  };
}

async function playerSync() {
  const state = await playerState();
  if (!state) playerTab = null;
  const json = JSON.stringify(state);
  if (json !== playerSent) helperSend({ player: state });
  playerSent = json;
}
const playerResend = () => { playerSent = ''; playerUpdate(); };

let playerQueue = Promise.resolve();
const playerUpdate = () => (playerQueue = playerQueue.then(playerSync).catch(console.error));
// Polled as well, for the one thing Chrome has no event for: the sidebar collapsing (⌘S).
setInterval(playerUpdate, 1000);
chrome.tabs.onActivated.addListener(playerUpdate);
chrome.windows.onFocusChanged.addListener(playerUpdate);
chrome.windows.onBoundsChanged.addListener(playerUpdate);

async function playerAction({ action }) {
  if (!playerTab) return;
  if (action === 'close') playerClosed = playerTab.id;
  else if (action === 'focus') {
    const tab = await chrome.tabs.update(playerTab.id, { active: true }).catch(() => null);
    if (tab) await chrome.windows.update(tab.windowId, { focused: true });
  } else {
    if (action === 'playpause') action = playerTab.playing ? 'pause' : 'play';
    await chrome.tabs.sendMessage(playerTab.id, { musicAction: action }).catch(() => {});
  }
  playerUpdate();
}
