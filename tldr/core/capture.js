// Capture (docs/tldr.md, "Capture"): wait for the page to go quiet before reading it, and scroll it
// only when the article's text is missing. Lazy media needs no step here: media.js reads the addresses
// from the page's attributes without changing them.
(() => {
  const T = globalThis.__tldr ??= {};
  const QUIET_MS = 300, SETTLE_MAX_MS = 2000, SCROLL_STEP_MS = 100, SCROLL_MAX_MS = 3000;
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  // Resolves when no node has been added for 300 ms, or after 2 s.
  T.settle = () => new Promise(resolve => {
    if (!document.body) return resolve();
    let quiet;
    const done = () => { observer.disconnect(); clearTimeout(quiet); clearTimeout(limit); resolve(); };
    const observer = new MutationObserver(records => {
      if (!records.some(r => r.addedNodes.length)) return;
      clearTimeout(quiet);
      quiet = setTimeout(done, QUIET_MS);
    });
    observer.observe(document.body, { childList: true, subtree: true });
    quiet = setTimeout(done, QUIET_MS);
    const limit = setTimeout(done, SETTLE_MAX_MS);
  });

  // Pages that add paragraphs on scroll: when the text found is short and the page is long, walk the
  // page to its end one viewport at a time, then put it back where it was. True if it scrolled.
  T.scrollForText = async prose => {
    const page = document.documentElement;
    if (prose >= 1500 || page.scrollHeight <= 4 * innerHeight) return false;
    const x = scrollX, y = scrollY, started = Date.now();
    for (let top = y; top < page.scrollHeight && Date.now() - started < SCROLL_MAX_MS; top += innerHeight) {
      scrollTo({ left: x, top, behavior: 'instant' });
      await sleep(SCROLL_STEP_MS);
    }
    scrollTo({ left: x, top: y, behavior: 'instant' });
    await T.settle();
    return true;
  };
})();
