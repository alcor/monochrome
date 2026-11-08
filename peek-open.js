// Runs in the page's own world, put into locked tabs with peek-click.js, so it can wrap the page's
// window.open. While the tab is locked (peek-click.js marks <html> with data-monochrome-locked) a window.open that would make a new tab becomes a peek,
// passed back to peek-click.js with postMessage. It returns null, as a blocked popup would; a site
// that opens a blank window and sets its location later isn't caught here and gets a real tab, which
// then becomes a peek the slow way (through the main window).
(() => {
  if (window.monochromeOpen) return;
  window.monochromeOpen = true;
  const pageOpen = window.open;
  window.open = function (url, target, features) {
    if ((!target || target === '_blank') && !features && url && document.documentElement.hasAttribute('data-monochrome-locked')) {
      let href = null;
      try { href = new URL(String(url), location.href).href; } catch {}
      if (href && /^https?:/.test(href)) {
        postMessage({ monochromePeek: href }, '*');
        return null;
      }
    }
    return pageOpen.apply(this, arguments);
  };
})();
