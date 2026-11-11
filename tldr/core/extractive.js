// The card without a model (docs/tldr.md, "Without a model"): the lead sentence, the h2 outline, and up
// to four sentences that carry a number, each anchored to its block. Works on the block list alone, so
// it runs in the page on every platform and in Node.
(() => {
  const T = globalThis.__tldr ??= {};
  const NUMBER = /\d|[$€£¥]/;
  const STOP = new Set('the a an and or of to in on for with by at from is are was were be as that this it its how why what when'.split(' '));

  function sentences(text, lang) {
    try {
      const parts = [...new Intl.Segmenter(lang || undefined, { granularity: 'sentence' }).segment(text)].map(s => s.segment.trim());
      return parts.filter(Boolean);
    } catch {
      return text.match(/[^.!?]+[.!?]+(?=\s|$)|[^.!?]+$/g)?.map(s => s.trim()) || [];
    }
  }
  const words = s => new Set(s.toLowerCase().match(/[\p{L}\p{N}]{3,}/gu)?.filter(w => !STOP.has(w)) || []);

  // { lead, points, outline } from an article's blocks: lead and points are { text, anchor }, outline is
  // the h2 headings as { text, anchor }, given when there are three or more.
  T.extractive = article => {
    const blocks = article.blocks.filter(b => !b.out);
    const paragraphs = blocks.filter(b => b.kind === 'paragraph');
    const first = paragraphs.find(b => b.text.length >= 140) || paragraphs[0];
    const lead = first ? { text: sentences(first.text, article.lang)[0] || first.text, anchor: first.id } : null;
    const title = words(article.title || '');
    const scored = [];
    paragraphs.forEach((b, at) => {
      for (const s of sentences(b.text, article.lang)) {
        if (s.length < 40 || s.length > 300 || !NUMBER.test(s) || s === lead?.text) continue;
        const shared = [...words(s)].filter(w => title.has(w)).length;
        scored.push({ text: s, anchor: b.id, score: 2 * shared + 1 / (1 + at / 10) });
      }
    });
    const seen = new Set(lead ? [lead.anchor] : []);
    const points = scored.sort((a, b) => b.score - a.score).filter(p => !seen.has(p.anchor) && seen.add(p.anchor)).slice(0, 4)
      .sort((a, b) => a.anchor - b.anchor).map(({ text, anchor }) => ({ text, anchor }));
    const h2 = blocks.filter(b => b.kind === 'heading' && b.level === 2);
    return { lead, points, outline: h2.length >= 3 ? h2.map(b => ({ text: b.text, anchor: b.id })) : [] };
  };
})();
