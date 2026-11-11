// Finding the content, and the block walker (docs/tldr.md, "Finding the content", "Blocks").
//
// Readability, unmodified, runs on a clone of the document and picks the article's root and metadata.
// The clone's elements carry an index into an array of the live document's elements, made by walking
// both trees in step, so the root maps back to a live element and the page itself is never written to.
// Readability's cleaned HTML is not used: the block list is built from the live root by the walker
// below, which is where the media and clutter rules apply.
//
// A block is { id, kind, text, level, out, media } plus what the renderer draws it from: `inline` (a
// small tree of allowlisted inline nodes), `items` for a list, `rows` for a table, `lang` for code. The
// live element each block came from is kept beside the list, in `els`, and never leaves the page.
(() => {
  const T = globalThis.__tldr ??= {};

  const SKIP = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'LINK', 'META', 'HEAD', 'TITLE', 'BUTTON', 'INPUT', 'SELECT', 'TEXTAREA',
                        'LABEL', 'OPTION', 'OBJECT', 'EMBED', 'APPLET', 'MAP', 'AREA', 'DATALIST', 'PROGRESS', 'METER', 'SLOT', 'PARAM']);
  const BLOCK = new Set(['P', 'DIV', 'SECTION', 'ARTICLE', 'MAIN', 'HEADER', 'FOOTER', 'NAV', 'ASIDE', 'FORM', 'UL', 'OL', 'DL', 'TABLE', 'PRE',
                         'BLOCKQUOTE', 'FIGURE', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'HR', 'IFRAME', 'VIDEO', 'AUDIO', 'PICTURE', 'DETAILS',
                         'SUMMARY', 'ADDRESS', 'CENTER', 'LI', 'DD', 'DT', 'CANVAS', 'DIALOG', 'MENU', 'FIELDSET', 'HGROUP', 'FIGCAPTION']);
  const BLOCKS = [...BLOCK].join(',');
  const INLINE = { A: 'a', EM: 'em', I: 'em', STRONG: 'strong', B: 'strong', CODE: 'code', KBD: 'code', SAMP: 'code', SUB: 'sub', SUP: 'sup',
                   ABBR: 'abbr', MARK: 'mark', TIME: 'time', CITE: 'em', Q: 'em', VAR: 'em', DFN: 'em', S: 's', DEL: 's', U: 'em' };

  const clean = s => (s || '').replace(/\s+/g, ' ').trim();

  function rgb(color) {
    const m = /rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[,/\s]+([\d.]+%?))?/.exec(color || '');
    if (!m) return null;
    const alpha = m[4] === undefined ? 1 : m[4].endsWith('%') ? parseFloat(m[4]) / 100 : +m[4];
    return [+m[1], +m[2], +m[3], alpha];
  }

  function backdrop(el) {
    for (let e = el; e; e = e.parentElement) {
      const cs = getComputedStyle(e);
      if (cs.backgroundImage !== 'none') return null; // a picture or gradient: its colour is not known
      const c = rgb(cs.backgroundColor);
      if (c && c[3] > 0.5) return c;
    }
    return [255, 255, 255, 1];
  }

  // Text a person cannot see is dropped here, so it reaches neither the reader nor a model's prompt:
  // display: none, hidden, zero size, moved off screen, clipped to a pixel, fully transparent, or
  // written in the colour of what is behind it.
  T.hidden = el => {
    if (el.hidden || el.getAttribute('aria-hidden') === 'true') return true;
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden' || cs.visibility === 'collapse' || +cs.opacity === 0) return true;
    if (cs.display === 'contents') return false;
    const box = el.getBoundingClientRect();
    if (box.width === 0 && box.height === 0 && !el.getClientRects().length) return true;
    if ((box.width <= 1 || box.height <= 1) && cs.overflow !== 'visible' && clean(el.textContent)) return true;
    if (box.right + scrollX < -200 || box.bottom + scrollY < -200 || parseFloat(cs.textIndent) < -500) return true;
    if (el.firstChild && [...el.childNodes].some(n => n.nodeType === 3 && n.nodeValue.trim())) {
      const fg = rgb(cs.color);
      if (fg && fg[3] === 0) return true;
      const bg = fg && backdrop(el);
      if (fg && bg && Math.abs(fg[0] - bg[0]) + Math.abs(fg[1] - bg[1]) + Math.abs(fg[2] - bg[2]) < 12) return true;
    }
    return false;
  };

  // --- Root and metadata -------------------------------------------------------------------------

  // The live element for Readability's pick, and the article's metadata. Null when Readability finds nothing.
  function findRoot() {
    const live = [document.documentElement, ...document.documentElement.querySelectorAll('*')];
    const copy = document.cloneNode(true);
    const twins = [copy.documentElement, ...copy.documentElement.querySelectorAll('*')];
    if (twins.length !== live.length) return null; // the page changed between the two walks
    twins.forEach((el, i) => el.setAttribute('data-tldr', i));
    let article;
    try { article = new Readability(copy, { charThreshold: 500 }).parse(); } catch { return null; }
    if (!article?.content) return null;
    const kept = new DOMParser().parseFromString(article.content, 'text/html');
    const index = el => live[+el.getAttribute('data-tldr')];
    // The outermost kept elements; their common ancestor in the live page is the root.
    const tops = [...kept.querySelectorAll('[data-tldr]')].filter(el => !el.parentElement.closest('[data-tldr]')).map(index).filter(Boolean);
    if (!tops.length) return null;
    let root = tops[0];
    for (const el of tops.slice(1)) while (root && !root.contains(el)) root = root.parentElement;
    if (!root) return null;
    if (root === document.documentElement) root = document.body;
    // The page's own h1 when the title Readability took from <title> holds it: "Story - Site name".
    const h1s = [...document.querySelectorAll('h1')].map(h => clean(h.textContent)).filter(Boolean);
    if (h1s.length === 1 && h1s[0].length >= 8 && clean(article.title).includes(h1s[0])) article.title = h1s[0];
    return { root, title: clean(article.title), byline: clean(article.byline), site: clean(article.siteName),
             published: article.publishedTime || null, lang: article.lang || document.documentElement.lang || '', length: article.length || 0 };
  }

  // --- Inline content ----------------------------------------------------------------------------

  // Allowlisted inline nodes for an element's children: { t } for text, { tag, c, href?, title?, datetime?, img? }.
  function inlineOf(node, out) {
    for (const n of node.childNodes) {
      if (n.nodeType === 3) { out.push({ t: n.nodeValue.replace(/\s+/g, ' ') }); continue; }
      if (n.nodeType !== 1 || SKIP.has(n.tagName) || n.tagName === 'svg' || T.hidden(n) || T.listed(n)) continue;
      if (n.tagName === 'BR') { out.push({ tag: 'br' }); continue; }
      if (n.tagName === 'IMG' || n.tagName === 'PICTURE') {
        const img = n.tagName === 'IMG' ? T.image(n) : T.picture(n);
        if (img) out.push({ tag: 'img', img });
        continue;
      }
      const tag = INLINE[n.tagName];
      if (!tag) {
        if (BLOCK.has(n.tagName)) out.push({ t: ' ' });
        inlineOf(n, out);
        if (BLOCK.has(n.tagName)) out.push({ t: ' ' });
        continue;
      }
      const item = { tag, c: [] };
      if (tag === 'a') item.href = T.url(n.getAttribute('href'));
      if (tag === 'abbr' && n.title) item.title = n.title;
      if (tag === 'time' && n.dateTime) item.datetime = n.dateTime;
      inlineOf(n, item.c);
      if (item.c.length) out.push(item);
    }
    return out;
  }

  const inlineText = nodes => nodes.map(n => n.t ?? (n.tag === 'br' ? ' ' : n.tag === 'img' ? '' : inlineText(n.c))).join('');
  const inlineImages = nodes => nodes.flatMap(n => n.tag === 'img' ? [n.img] : n.c ? inlineImages(n.c) : []);

  // Leading and trailing space off a run of inline nodes.
  function trim(nodes) {
    const edge = (list, first) => {
      while (list.length) {
        const n = list[first ? 0 : list.length - 1];
        if (n.tag === 'br') { first ? list.shift() : list.pop(); continue; }
        if (n.t !== undefined) {
          n.t = first ? n.t.replace(/^\s+/, '') : n.t.replace(/\s+$/, '');
          if (!n.t) { first ? list.shift() : list.pop(); continue; }
        } else if (n.c) edge(n.c, first);
        break;
      }
    };
    edge(nodes, true);
    edge(nodes, false);
    return nodes;
  }

  // --- The walker --------------------------------------------------------------------------------

  function walker(meta, ctx) {
    const blocks = [], els = [];
    const add = (el, block) => {
      block = { id: blocks.length, kind: block.kind, ...block, text: clean(block.text), level: block.level || 0, out: block.out || null, media: block.media || null };
      blocks.push(block);
      els.push(el);
      return block;
    };
    const leaveOut = (el, label, pass) => add(el, { kind: el.tagName === 'IFRAME' ? 'embed' : el.tagName === 'IMG' ? 'image' : 'paragraph',
      text: clean(el.textContent).slice(0, 200), out: { by: 'rule', label, pass } });

    // A run of inline nodes becomes a paragraph, or image blocks when it holds no words.
    function flush(run, el, kind = 'paragraph', extra = {}) {
      const inline = trim(inlineOf({ childNodes: run }, []));
      const text = clean(inlineText(inline));
      if (!text) {
        for (const img of inlineImages(inline)) add(el, { kind: 'image', text: img.alt, media: { items: [{ type: 'image', ...img }] } });
        return;
      }
      // Loose text between blocks that is a stock phrase: a link that says "Edit this page".
      const phrase = kind === 'paragraph' ? T.phrase(text) : null;
      add(el, { kind, text, inline, ...extra, ...(phrase ? { out: { by: 'rule', label: phrase, pass: 'shape' } } : {}) });
    }

    function media(el) {
      const tag = el.tagName;
      if (tag === 'IMG' || tag === 'PICTURE') {
        const img = tag === 'IMG' ? T.image(el) : T.picture(el);
        return img && { type: 'image', ...img };
      }
      if (tag === 'VIDEO' || tag === 'AUDIO') return { type: tag.toLowerCase(), ...T.player(el) };
      if (tag === 'IFRAME') {
        const src = T.url(el.getAttribute('src') || el.getAttribute('data-src'));
        const host = src && T.embedHost(src);
        return host ? { type: 'embed', src, host, title: el.getAttribute('title') || '' } : null;
      }
      if (tag === 'CANVAS' || tag === 'svg') {
        const drawn = T.drawing(el);
        return drawn && { type: 'image', ...drawn };
      }
      return null;
    }

    function figure(el) {
      const caption = el.querySelector('figcaption');
      const structured = el.querySelector('table, pre, blockquote');
      if (structured) { // a figure around a table, code or quote: those blocks, then the caption
        for (const child of el.children) if (child !== caption) visit(child);
        if (caption) flush([...caption.childNodes], caption);
        return;
      }
      const items = [...el.querySelectorAll('picture, img, video, audio, iframe, canvas, svg')]
        .filter(m => !m.parentElement.closest('picture, video, audio, svg') || !el.contains(m.parentElement.closest('picture, video, audio, svg')))
        .filter(m => !caption?.contains(m) && !T.hidden(m)).map(media).filter(Boolean);
      const inline = caption ? trim(inlineOf(caption, [])) : [];
      const text = clean(inlineText(inline)) || items.map(i => i.alt).filter(Boolean).join(' ');
      if (!items.length) return text ? add(el, { kind: 'paragraph', text, inline }) : null;
      add(el, { kind: 'figure', text, inline, media: { items } });
    }

    function list(el) {
      const items = [];
      const collect = (listEl, level) => {
        for (const li of listEl.children) {
          if (!['LI', 'DT', 'DD'].includes(li.tagName) || T.hidden(li)) continue;
          const own = [...li.childNodes].filter(n => !(n.nodeType === 1 && (n.tagName === 'UL' || n.tagName === 'OL')));
          const inline = trim(inlineOf({ childNodes: own }, []));
          if (clean(inlineText(inline)) || inlineImages(inline).length) items.push({ inline, level, term: li.tagName === 'DT' });
          for (const nested of li.children) if (nested.tagName === 'UL' || nested.tagName === 'OL') collect(nested, level + 1);
        }
      };
      collect(el, 0);
      if (items.length) add(el, { kind: 'list', text: items.map(i => clean(inlineText(i.inline))).join('\n'), items, ordered: el.tagName === 'OL' });
    }

    function table(el) {
      const rows = [...el.rows].filter(r => !T.hidden(r));
      const columns = Math.max(0, ...rows.map(r => r.cells.length));
      const layout = columns <= 1 || (!el.querySelector('th') && rows.length < 2);
      if (layout) { // a table used for layout: its cells' content, in order
        for (const row of rows) for (const cell of row.cells) children(cell);
        return;
      }
      const caption = el.caption ? clean(el.caption.textContent) : '';
      const data = rows.map(r => [...r.cells].map(c => ({ head: c.tagName === 'TH', inline: trim(inlineOf(c, [])),
        colspan: c.colSpan > 1 ? c.colSpan : null, rowspan: c.rowSpan > 1 ? c.rowSpan : null })));
      const text = [caption, ...data.map(r => r.map(c => clean(inlineText(c.inline))).join(' | '))].filter(Boolean).join('\n');
      add(el, { kind: 'table', text, rows: data, caption });
    }

    function visit(el) {
      const tag = el.tagName;
      if (SKIP.has(tag) || T.hidden(el)) return;
      const why = T.clutter(el, ctx);
      if (why) return leaveOut(el, why.label, why.pass);
      if (/^H[1-6]$/.test(tag)) {
        const inline = trim(inlineOf(el, []));
        const text = clean(inlineText(inline));
        if (!text) return;
        if (tag === 'H1' && meta.title && (text === meta.title || meta.title.startsWith(text) || text.startsWith(meta.title))) return;
        return add(el, { kind: 'heading', text, level: +tag[1] });
      }
      if (tag === 'P' || tag === 'ADDRESS' || tag === 'SUMMARY' || tag === 'FIGCAPTION' || tag === 'DT' || tag === 'DD' || tag === 'LI') {
        return el.querySelector(BLOCKS) ? children(el) : flush([...el.childNodes], el);
      }
      if (tag === 'UL' || tag === 'OL' || tag === 'DL') return list(el);
      if (tag === 'BLOCKQUOTE') return flush([...el.childNodes], el, 'quote');
      if (tag === 'PRE') {
        const code = el.querySelector('code') || el;
        const lang = /(?:language|lang)-([\w+#-]+)/.exec(`${el.className} ${code.className}`)?.[1] || null;
        const text = code.textContent.replace(/\n+$/, '');
        return text.trim() ? add(el, { kind: 'code', text, code: text, lang }) : null;
      }
      if (tag === 'TABLE') return table(el);
      if (tag === 'FIGURE') return figure(el);
      if (tag === 'HR') return add(el, { kind: 'rule', text: '' });
      if (tag === 'math') {
        const tex = el.querySelector('annotation[encoding*="tex" i]')?.textContent;
        return add(el, { kind: 'math', text: clean(tex || el.textContent), code: clean(tex || el.textContent) });
      }
      if (tag === 'IMG' || tag === 'PICTURE' || tag === 'VIDEO' || tag === 'AUDIO' || tag === 'IFRAME' || tag === 'CANVAS' || tag === 'svg') {
        if (tag === 'svg' && el.getBoundingClientRect().width < 200) return; // an icon
        const item = media(el);
        if (!item) return tag === 'IFRAME' ? leaveOut(el, 'other', 'media') : null;
        const kind = item.type === 'image' ? 'image' : item.type;
        return add(el, { kind, text: item.alt || item.title || '', media: { items: [item] } });
      }
      children(el);
    }

    // An element's children in order: block children are visited, and the inline nodes between them
    // are gathered into paragraphs.
    function children(el) {
      let run = [];
      const end = () => { if (run.length) flush(run, el); run = []; };
      for (const n of el.childNodes) {
        if (n.nodeType === 3) { if (n.nodeValue.trim() || run.length) run.push(n); continue; }
        if (n.nodeType !== 1) continue;
        const blockish = BLOCK.has(n.tagName) || n.tagName === 'svg' || n.tagName === 'math' && n.getAttribute('display') === 'block' ||
          (!INLINE[n.tagName] || n.tagName === 'A') && n.tagName !== 'IMG' && n.tagName !== 'BR' && !!n.querySelector(BLOCKS);
        if (!blockish) { run.push(n); continue; }
        end();
        visit(n);
      }
      end();
    }

    return { blocks, els, visit, children, add };
  }

  // Consecutive images under one parent are one figure with several items: a gallery.
  function galleries(blocks, els) {
    const out = [], outEls = [];
    for (let i = 0; i < blocks.length; i++) {
      const b = blocks[i];
      let j = i;
      if (b.kind === 'image' && !b.out) {
        while (j + 1 < blocks.length && blocks[j + 1].kind === 'image' && !blocks[j + 1].out && els[j + 1].parentElement === els[i].parentElement) j++;
      }
      if (j > i) {
        const run = blocks.slice(i, j + 1);
        out.push({ ...b, kind: 'figure', text: clean(run.map(r => r.text).join(' ')), inline: [], media: { items: run.flatMap(r => r.media.items) } });
        outEls.push(els[i].parentElement);
        i = j;
      } else { out.push(b); outEls.push(els[i]); }
    }
    out.forEach((b, i) => { b.id = i; });
    return { blocks: out, els: outEls };
  }

  // The lead image or video: a figure, picture, video or listed embed between the page's h1 and the root.
  function lead(root, w) {
    const h1 = document.querySelector('h1');
    if (!h1 || root.contains(h1) || !(h1.compareDocumentPosition(root) & Node.DOCUMENT_POSITION_FOLLOWING)) return;
    const scope = h1.closest('header, article, main') || h1.parentElement;
    for (const el of scope.querySelectorAll('figure, picture, video')) {
      if (root.contains(el) || el.closest('figure') !== (el.tagName === 'FIGURE' ? el : null) && el.closest('figure')) continue;
      if (!(h1.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING) || !(el.compareDocumentPosition(root) & Node.DOCUMENT_POSITION_FOLLOWING)) continue;
      w.visit(el);
      return;
    }
  }

  // The article on this page: { title, byline, site, published, lang, url, blocks, els }, or null when
  // the page is not an article (docs/tldr.md, "Is this page an article").
  T.extract = () => {
    const meta = findRoot();
    if (!meta) return null;
    const ctx = { hosts: T.ownHosts(), total: clean(meta.root.textContent).length };
    const w = walker(meta, ctx);
    lead(meta.root, w);
    w.children(meta.root);
    const { blocks, els } = galleries(w.blocks, w.els);
    // The byline line above the story is in the header already.
    const first = blocks.findIndex(b => !b.out && b.kind === 'paragraph' && b.text.length >= 140);
    for (const b of blocks.slice(0, Math.max(0, first))) {
      if (!b.out && b.kind === 'paragraph' && meta.byline && b.text.length < 120 && b.text.includes(meta.byline)) b.out = { by: 'rule', label: 'other', pass: 'byline' };
    }
    // A heading with nothing kept under it: its section was left out, so it goes too.
    const keptBlocks = blocks.filter(b => !b.out);
    for (let i = keptBlocks.length - 1; i >= 0; i--) {
      const b = keptBlocks[i], next = keptBlocks.slice(i + 1).find(n => !n.out);
      if (b.kind === 'heading' && (!next || next.kind === 'heading' && next.level <= b.level)) b.out = { by: 'rule', label: 'other', pass: 'empty' };
    }
    const prose = blocks.filter(b => !b.out && (b.kind === 'paragraph' || b.kind === 'list' || b.kind === 'quote')).reduce((n, b) => n + b.text.length, 0);
    let readerable = false;
    try { readerable = isProbablyReaderable(document); } catch {}
    if (!readerable && prose < 1500) return null;
    if (!blocks.some(b => !b.out)) return null;
    const { root, length, ...rest } = meta;
    return { ...rest, url: location.href, blocks, els, prose };
  };
})();
