// peek's click catch, put into locked tabs (pinned or CoreCore) by background.js, not into every page.
// A plain click on a link that would open a new tab opens a peek instead, straight from the URL, so no
// tab passes through the main window first. Unlocking the tab turns it off (background.js says so);
// locking again puts the script back, which just turns it on. The locked flag also goes on <html> for
// peek-open.js, which runs in the page's world and wraps window.open.
(() => {
  if (globalThis.monochromePeekCatch) return globalThis.monochromePeekCatch(true);
  let locked = true;
  const setLocked = value => {
    locked = !!value;
    document.documentElement.toggleAttribute('data-monochrome-locked', locked);
  };
  globalThis.monochromePeekCatch = setLocked;
  setLocked(true);
  chrome.runtime.onMessage.addListener(msg => { if (msg.mini === 'locked') setLocked(msg.value); });

  addEventListener('click', e => {
    const a = e.target.closest?.('a[href]');
    if (!locked || !a || !/^https?:/.test(a.href)) return;
    const plain = e.button === 0 && !e.metaKey && !e.ctrlKey && !e.shiftKey && !e.altKey;
    const target = a.target || document.querySelector('base[target]')?.target;
    if (!plain || target !== '_blank') return;
    e.preventDefault();
    e.stopImmediatePropagation();
    chrome.runtime.sendMessage({ mini: 'peek', url: a.href });
  }, true);

  // window.open in a locked tab, relayed from the page's world by peek-open.js.
  addEventListener('message', e => {
    if (e.source === window && typeof e.data?.monochromePeek === 'string') chrome.runtime.sendMessage({ mini: 'peek', url: e.data.monochromePeek });
  });
})();
