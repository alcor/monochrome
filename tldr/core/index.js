// The reader's entry: the order of the stages, and open, close and toggle (docs/tldr.md, "Pipeline").
// Capture, extraction, clutter and rendering finish before a model is asked, so the reader opens with
// the outline; a summary arrives later, bullet by bullet, each one verified before it is drawn.
//
// Everything hangs off one object, globalThis.__tldr, in the content script's isolated world. This file
// and the rest of tldr/core call no extension API: the platform supplies __tldr.adapter (tldr/adapters).
(() => {
  const T = globalThis.__tldr ??= {};
  const FIRST_BULLET_MS = 20_000; // with no bullet or progress for this long, the outline stays
  const SOURCES = { apple: "Summary by Apple's on-device model, on this Mac" };
  const REASONS = {
    noApp: 'Outline, no model: the Monochrome app is not running',
    deviceNotEligible: 'Outline, no model: this Mac does not have Apple Intelligence',
    appleIntelligenceNotEnabled: 'Outline, no model: Apple Intelligence is turned off',
    modelNotReady: 'Outline, no model: the model is not ready yet',
    unsupportedOS: 'Outline, no model: the on-device model needs macOS 26',
  };
  const ERRORS = {
    guardrail: 'Outline: the model declined to summarize this page',
    context: 'Outline: the article is too long for the model',
    language: 'Outline: the model does not support this language',
    timeout: 'Outline: the model took too long',
    unavailable: 'Outline, no model',
    cancelled: 'Outline, no model',
  };

  let view = null, article = null, stale = true, watcher = null, cancel = null, opening = false;
  const state = T.state = { open: false, summary: null }; // summary: { model, bullets, facts, dropped, error, done }

  function outlineCard(source) {
    const { lead, points, outline } = T.extractive(article);
    return { label: 'Outline', bullets: [lead, ...points].filter(Boolean), facts: [], outline, source };
  }

  function summaryCard() {
    const s = state.summary;
    const left = s.dropped ? ` · ${s.dropped} point${s.dropped === 1 ? '' : 's'} left out: not found in the article` : '';
    const short = article.covered ? ` · Summary covers the first ${article.covered.toLocaleString()} words` : '';
    return { label: 'Summary', bullets: s.bullets, facts: s.facts, outline: T.extractive(article).outline, source: (SOURCES[s.model] || 'Summary by a model on this Mac') + short + left };
  }

  // Asks the adapter for a summary and draws each verified piece as it arrives.
  async function summarize() {
    const adapter = T.adapter;
    if (!adapter) return view.setBusy(false, 'Outline, no model');
    const mine = article;
    const status = await adapter.status().catch(() => ({ model: 'none' }));
    if (!view || article !== mine) return;
    if (!status || status.model === 'none') return view.setBusy(false, REASONS[status?.reason] || 'Outline, no model');
    const prompt = T.promptBlocks(article.blocks);
    const check = T.verifier(prompt.blocks);
    const summary = state.summary = { model: status.model, bullets: [], facts: [], dropped: 0, error: null, done: false };
    view.setBusy(true);
    let timer = null;
    const finish = note => {
      clearTimeout(timer);
      cancel = null;
      summary.done = true;
      if (!view || article !== mine) return;
      // Fewer than two bullets that pass: the outline stays, and the card says why.
      if (summary.bullets.length >= 2) { view.setCard(summaryCard()); view.setBusy(false); } else {
        const dropped = summary.dropped ? `Outline: ${summary.dropped} of the model's points were not found in the article` : 'Outline: the model gave no summary';
        view.setCard(outlineCard(note || dropped));
        view.setBusy(false);
      }
    };
    const wait = () => {
      clearTimeout(timer);
      timer = setTimeout(() => { summary.error = 'timeout'; stop?.(); finish(ERRORS.timeout); }, FIRST_BULLET_MS);
    };
    const stop = cancel = adapter.summarize({ url: article.url, title: article.title, lang: article.lang, blocks: prompt.blocks,
                                              want: { bullets: 5, facts: 6 }, truncated: prompt.truncated }, piece => {
      if (summary.done || !view || article !== mine) return;
      if (piece.op === 'progress') { wait(); if (piece.words) article.covered = piece.words; return; }
      if (piece.op === 'bullet') {
        clearTimeout(timer);
        const ok = check.bullet(piece);
        if (!ok || summary.bullets.some(b => b.text === ok.text)) return void summary.dropped++;
        summary.bullets.push(ok);
        if (summary.bullets.length >= 2) view.setCard(summaryCard());
      } else if (piece.op === 'fact') {
        const ok = check.fact(piece);
        if (ok && !summary.facts.some(f => f.label === ok.label)) { summary.facts.push(ok); if (summary.bullets.length >= 2) view.setCard(summaryCard()); }
      } else if (piece.op === 'done') {
        if (piece.words) article.covered = piece.words;
        finish();
      } else if (piece.op === 'error') {
        summary.error = piece.code || 'unavailable';
        finish(summary.bullets.length >= 2 ? undefined : ERRORS[summary.error] || 'Outline, no model');
      }
    });
    wait();
  }

  // A change to the page while the reader is closed means the block list is read again next time.
  function watch() {
    watcher?.disconnect();
    stale = false;
    watcher = new MutationObserver(() => { if (!state.open) { stale = true; watcher.disconnect(); } });
    watcher.observe(document.body, { childList: true, subtree: true, characterData: true });
  }

  T.open = async () => {
    if (state.open || opening) return state.open;
    opening = true;
    try {
      if (!article || stale) {
        await T.settle();
        let found = T.extract();
        if ((!found || found.prose < 1500) && await T.scrollForText(found?.prose || 0)) found = T.extract() || found;
        if (!found) { T.notice('No article found on this page'); return false; }
        article = found;
        state.summary = null;
        watch();
      }
      const again = state.summary?.done && state.summary.bullets.length >= 2;
      view = T.render(article, { onClose: T.close });
      view.setCard(again ? summaryCard() : outlineCard('Outline, no model'));
      view.open();
      state.open = true;
      if (!again) summarize();
      return true;
    } finally { opening = false; }
  };

  T.close = () => {
    if (!state.open) return false;
    cancel?.();
    cancel = null;
    if (state.summary && !state.summary.done) state.summary = null;
    view.close();
    view = null;
    state.open = false;
    return true;
  };

  T.toggle = () => state.open ? T.close() : T.open();

  // The reader's state as plain data, for the tests: read from the isolated world through the service
  // worker's chrome.scripting.executeScript, since the shadow root is closed.
  T.snapshot = () => ({
    open: state.open,
    attached: !!view?.attached(),
    pageClass: document.documentElement.classList.contains('monochrome-tldr-open'),
    scrollY,
    article: article && { title: article.title, byline: article.byline, site: article.site, lang: article.lang },
    blocks: article ? article.blocks.map(({ id, kind, text, level, out, media }) => ({ id, kind, text, level, out,
      media: media && media.items.map(i => ({ type: i.type, src: i.src || null, host: i.host || null })) })) : [],
    prompt: article ? T.promptBlocks(article.blocks) : null,
    summary: state.summary && { ...state.summary },
    drawn: view ? view.probe() : null,
  });
  T.press = what => !!view?.press(what);
  T.goTo = id => !!view?.goTo(id);
  T.scrollTo = fraction => view?.scrollTo(fraction);
})();
