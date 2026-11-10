// Music sites (see manifest.json), in the page's own world, where the site's media session is: tells
// the extension what's playing and takes the sidebar mini player's buttons back (player.js), through
// music-relay.js in the extension's world, which can talk to the extension.

{ // a block, so these names can't clash with the site's own globals
  // Sites give their play/pause/next/previous to navigator.mediaSession for the Mac's media keys;
  // keep a copy so the player's buttons can call them too.
  const handlers = {};
  const setActionHandler = MediaSession.prototype.setActionHandler;
  // With this action a site asks Chrome to pop its own mini player out into a floating window when
  // you switch tabs; on music sites the sidebar player does that job, so it is held back. It is passed
  // on only once music-relay.js says the setting is off (Settings → Player), since the site may set it
  // before the relay's word arrives.
  const PIP = 'enterpictureinpicture';
  let pip = null, stopPopout = true;
  const passPip = () => {
    try { setActionHandler.call(navigator.mediaSession, PIP, stopPopout ? null : pip); } catch {} // a browser that doesn't know it
    if (stopPopout || !pip) delete handlers[PIP];
    else handlers[PIP] = pip;
  };
  MediaSession.prototype.setActionHandler = function (action, handler) {
    if (action === PIP) { pip = handler; if (!stopPopout) passPip(); return; }
    setActionHandler.call(this, action, handler); // throws for an action the browser doesn't know
    handlers[action] = handler;
  };
  addEventListener('message', e => {
    const prefs = e.source === window && e.data?.monochromeMusicPrefs;
    if (!prefs || prefs.stopPopout === stopPopout) return;
    stopPopout = prefs.stopPopout;
    if (pip) passPip();
  });

  let sent, sentAt = 0;
  setInterval(() => {
    const m = navigator.mediaSession.metadata;
    const now = JSON.stringify(m ? { title: m.title, artist: m.artist, artwork: m.artwork.at(-1)?.src || '' } : null);
    // Also resend every 10s, so a restarted service worker hears about it again.
    if (now === sent && Date.now() - sentAt < 10_000) return;
    sent = now;
    sentAt = Date.now();
    postMessage({ monochromeMusic: JSON.parse(now) }, location.origin);
  }, 1000);

  addEventListener('message', e => {
    const action = e.source === window && e.data?.monochromeMusicAction;
    if (!action) return;
    if (handlers[action]) return handlers[action]({ action });
    // No handler from the site: play or pause its audio/video directly.
    const media = [...document.querySelectorAll('audio, video')];
    if (action === 'play') media[0]?.play();
    if (action === 'pause') media.forEach(el => el.pause());
  });
}
