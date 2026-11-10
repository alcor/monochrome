// Verification (docs/tldr.md, "Verification"): every bullet and fact a model writes is checked against
// the blocks it was given before it is drawn, whichever model wrote it and on every platform. This file
// touches neither the DOM nor an extension API, so the same code runs in the page and in Node
// (tldr/check-verify.mjs, which checks the app's --check-tldr output).
//
// A bullet is kept when:
//   1. its anchor is a block that was in the prompt and is not a heading;
//   2. its quote is in the anchor block; or in exactly one other block, which becomes the anchor; or,
//      failing both, enough of the bullet's own four-word runs are in the anchor or one of its two
//      neighbours;
//   3. every number in it is in the anchor block, or in one of the two blocks on each side, which
//      becomes the anchor.
// A fact is kept when its value is in its anchor block, or in exactly one other block.
(() => {
  const T = globalThis.__tldr ??= {};
  const BULLET_MAX = 240, FACT_MAX = 80, LABEL_MAX = 40, OVERLAP_MIN = 0.25, PROMPT_MAX = 256 * 1024;

  // The same text however it was typed: case, spacing, curly quotes, dashes.
  const norm = s => String(s || '').toLowerCase().replace(/[\u2018\u2019\u201A\u2032]/g, "'").replace(/[\u201C\u201D\u201E\u2033]/g, '"')
    .replace(/[\u2010-\u2015\u2212]/g, '-').replace(/\u2026/g, '...').replace(/\s+/g, ' ').trim();

  // Model output is text: bracket citations and addresses come out, and it is cut at a word.
  const tidy = (s, max) => {
    s = String(s || '').replace(/\s*\[\s*\d+(?:\s*[,;-]\s*\d+)*\s*\](?:\s*\[\s*\d+\s*\])*/g, '').replace(/\b(?:https?:\/\/|www\.)\S+/gi, '')
      .replace(/\s+([.,;:!?])/g, '$1').replace(/\s+/g, ' ').trim();
    if (s.length <= max) return s;
    return s.slice(0, max).replace(/\s+\S*$/, '') + '…';
  };

  const numbers = s => (String(s).match(/\d[\d,.]*\d|\d/g) || []).map(n => n.replace(/,/g, '').replace(/\.$/, ''));
  const grams = s => {
    const w = norm(s).match(/[\p{L}\p{N}']+/gu) || [], out = [];
    for (let i = 0; i + 4 <= w.length; i++) out.push(w.slice(i, i + 4).join(' '));
    return out;
  };

  // What a model is sent: the article's text blocks and headings, media that has a caption, cut at a
  // block boundary once the text passes 256 KB.
  T.promptBlocks = blocks => {
    const out = [];
    let size = 0, truncated = false;
    for (const b of blocks) {
      if (b.out || !b.text) continue;
      if (b.kind === 'code' || b.kind === 'math' || b.kind === 'rule') continue; // media is in by its caption
      size += b.text.length;
      if (size > PROMPT_MAX) { truncated = true; break; }
      out.push({ id: b.id, kind: b.kind, text: b.text });
    }
    return { blocks: out, truncated };
  };

  // A checker over the blocks that were in the prompt.
  T.verifier = blocks => {
    const text = blocks.filter(b => b.kind !== 'heading');
    const at = new Map(text.map((b, i) => [b.id, i]));
    const normal = text.map(b => norm(b.text));
    const sets = text.map(b => new Set(numbers(b.text)));
    const gramSets = text.map(b => new Set(grams(b.text)));
    const near = (i, reach) => { // i, then its neighbours outward
      const out = [i];
      for (let d = 1; d <= reach; d++) { if (i - d >= 0) out.push(i - d); if (i + d < text.length) out.push(i + d); }
      return out;
    };

    function bullet(piece) {
      const said = tidy(piece.text, BULLET_MAX);
      let i = at.get(piece.anchor);
      if (!said || i === undefined) return null;
      const quote = norm(piece.quote);
      let quoted = quote.length >= 8 && normal[i].includes(quote);
      if (!quoted) {
        const found = quote.length >= 8 ? normal.flatMap((t, j) => t.includes(quote) ? [j] : []) : [];
        if (found.length === 1) { i = found[0]; quoted = true; } else {
          const mine = grams(said);
          const best = near(i, 1).map(j => [j, mine.length ? mine.filter(g => gramSets[j].has(g)).length / mine.length : 0]).sort((a, b) => b[1] - a[1])[0];
          if (best[1] < OVERLAP_MIN) return null;
          i = best[0];
        }
      }
      const cited = numbers(said);
      if (!cited.every(n => sets[i].has(n))) {
        const holder = near(i, 2).find(j => cited.every(n => sets[j].has(n)));
        if (holder === undefined) return null;
        if (quoted && !normal[holder].includes(quote)) quoted = false;
        i = holder;
      }
      return { text: said, anchor: text[i].id, quote: quoted ? String(piece.quote).trim() : '' };
    }

    function fact(piece) {
      const label = tidy(piece.label, LABEL_MAX), value = tidy(piece.value, FACT_MAX);
      let i = at.get(piece.anchor);
      const wanted = norm(value);
      if (!label || !wanted || norm(label) === wanted) return null; // a label that repeats its value says nothing
      if (i === undefined || !normal[i].includes(wanted)) {
        const found = normal.flatMap((t, j) => t.includes(wanted) ? [j] : []);
        if (found.length !== 1) return null;
        i = found[0];
      }
      return { label, value, anchor: text[i].id };
    }

    return { bullet, fact };
  };
})();
