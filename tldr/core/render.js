// The reader's view (docs/tldr.md, "Rendering"): one host element on the page's <html>, with a closed
// shadow root, drawn from the block list. Every element is made with createElement from a fixed set of
// tags and attributes; page HTML is never parsed into it, so no script, event attribute, style
// attribute or form can arrive. The page underneath stays as it was: while the reader is open its body
// is hidden and its scrolling stopped through one class on <html>, and both go back when it closes.
(() => {
  const T = globalThis.__tldr ??= {};
  const HOST_ID = 'monochrome-tldr', OPEN_CLASS = 'monochrome-tldr-open';
  const HOST_STYLE = 'all: initial !important; position: fixed !important; inset: 0 !important; z-index: 2147483647 !important; display: block !important;';
  const SANDBOX = 'allow-scripts allow-same-origin allow-popups allow-presentation';

  let pageSheet = null;
  // overflow: hidden on <html> and visibility: hidden on <body>, through a sheet the page's own
  // stylesheets do not contain; inline styles are the fallback where a constructed sheet is refused.
  function hidePage(on) {
    const html = document.documentElement;
    try {
      if (!pageSheet) {
        pageSheet = new CSSStyleSheet();
        pageSheet.replaceSync(`html.${OPEN_CLASS} { overflow: hidden !important; } html.${OPEN_CLASS} > body { visibility: hidden !important; }`);
      }
      const others = document.adoptedStyleSheets.filter(s => s !== pageSheet);
      document.adoptedStyleSheets = on ? [...others, pageSheet] : others;
    } catch { pageSheet = null; }
    html.classList.toggle(OPEN_CLASS, on);
    if (!html.classList.length) html.removeAttribute('class');
    if (!pageSheet && document.body) {
      html.style.overflow = on ? 'hidden' : '';
      document.body.style.visibility = on ? 'hidden' : '';
    }
  }

  function sheet(root) {
    try {
      const s = new CSSStyleSheet();
      s.replaceSync(T.css);
      root.adoptedStyleSheets = [s];
    } catch {
      const style = document.createElement('style');
      style.textContent = T.css;
      root.append(style);
    }
  }

  const el = (tag, props = {}, ...kids) => {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) {
      if (v === null || v === undefined || v === false) continue;
      if (k === 'class') node.className = v; else if (k === 'text') node.textContent = v; else node.setAttribute(k, v === true ? '' : v);
    }
    node.append(...kids.flat().filter(Boolean));
    return node;
  };

  function image(img) {
    const node = el('img', { src: img.src, srcset: img.srcset, sizes: img.srcset ? img.sizes : null, alt: img.alt, width: img.width, height: img.height,
                             loading: 'lazy', decoding: 'async' });
    if (!img.sources?.length) return node;
    return el('picture', {}, img.sources.map(s => el('source', { srcset: s.srcset, media: s.media, type: s.type })), node);
  }

  function inline(nodes, view) {
    return nodes.map(n => {
      if (n.t !== undefined) return document.createTextNode(n.t);
      if (n.tag === 'br') return el('br');
      if (n.tag === 'img') return image(n.img);
      if (n.tag === 'a') {
        if (!n.href) return el('span', {}, inline(n.c, view));
        const a = el('a', { href: n.href, rel: 'noopener noreferrer' }, inline(n.c, view));
        a.addEventListener('click', e => { if (view.follow(n.href)) e.preventDefault(); });
        return a;
      }
      return el(n.tag, { title: n.title, datetime: n.datetime }, inline(n.c, view));
    });
  }

  function mediaItem(item, view) {
    if (item.type === 'image') return image(item);
    if (item.type === 'embed') {
      const box = el('div', { class: 'embed' });
      const load = el('button', { class: 'load', text: `Load from ${item.host}` });
      load.addEventListener('click', () => {
        // A new frame for the same address, sandboxed: its host sees a load only after this click.
        box.replaceChildren(el('iframe', { src: item.src, sandbox: SANDBOX, allowfullscreen: true, loading: 'lazy', title: item.title || item.host,
                                           referrerpolicy: 'strict-origin-when-cross-origin' }));
        box.classList.add('loaded');
      });
      box.append(load, el('span', { class: 'host', text: item.title ? `${item.title} · ${item.host}` : `Embedded from ${item.host}` }));
      return box;
    }
    if (item.page) { // a player fed by the page's script: it plays there, not here
      const box = el('div', { class: 'embed' });
      const back = el('button', { class: 'load', text: 'Play on the original page' });
      back.addEventListener('click', () => view.toPage(item.block));
      box.append(back, el('span', { class: 'host', text: 'This video is played by the page and cannot be moved into the reader.' }));
      return box;
    }
    return el(item.tag, { src: item.src, poster: item.tag === 'video' ? item.poster : null, controls: true, preload: 'metadata', playsinline: item.tag === 'video' },
      item.sources.map(s => el('source', { src: s.src, type: s.type })),
      item.tracks.map(t => el('track', { src: t.src, kind: t.kind, srclang: t.srclang, label: t.label })));
  }

  function block(b, view) {
    const items = (b.media?.items || []).map(i => mediaItem({ ...i, block: b.id }, view));
    const caption = () => b.inline?.length ? el('figcaption', {}, inline(b.inline, view)) : null;
    switch (b.kind) {
      case 'heading': return el('h' + Math.min(6, Math.max(2, b.level)), {}, b.text);
      case 'paragraph': return el('p', {}, inline(b.inline, view));
      case 'quote': return el('blockquote', {}, inline(b.inline, view));
      case 'list': return el(b.ordered ? 'ol' : 'ul', {}, b.items.map(i => el('li', { 'data-level': i.level || null, class: i.term ? 'term' : null }, inline(i.inline, view))));
      case 'code': return el('pre', {}, el('code', { class: b.lang ? `language-${b.lang}` : null, text: b.code }));
      case 'math': return el('p', {}, el('code', { text: b.code }));
      case 'rule': return el('hr');
      case 'table': return el('div', { class: 'table' }, el('table', {}, b.caption ? el('caption', { text: b.caption }) : null,
        b.rows.map(r => el('tr', {}, r.map(c => el(c.head ? 'th' : 'td', { colspan: c.colspan, rowspan: c.rowspan }, inline(c.inline, view)))))));
      case 'figure': return el('figure', { class: items.length > 1 ? 'gallery' : null }, el('div', { class: 'items' }, items), caption());
      case 'image': return el('figure', {}, items);
      case 'video': case 'audio': case 'embed': return items[0].matches?.('.embed') ? items[0] : el('figure', {}, items);
    }
    return null;
  }

  // A small message in the corner for a page with no article on it; gone after three seconds.
  T.notice = text => {
    document.getElementById(HOST_ID + '-notice')?.remove();
    const host = document.createElement('div');
    host.id = HOST_ID + '-notice';
    host.style.cssText = 'all: initial !important; position: fixed !important; top: 0 !important; right: 0 !important; z-index: 2147483647 !important;';
    const root = host.attachShadow({ mode: 'closed' });
    sheet(root);
    root.append(el('div', { class: 'notice', role: 'status', text }));
    document.documentElement.append(host);
    setTimeout(() => host.remove(), 3000);
  };

  // Draws the article and returns the view: { setCard, setBusy, goTo, close, probe }.
  T.render = (article, { onClose }) => {
    const host = document.createElement('div');
    host.id = HOST_ID;
    host.style.cssText = HOST_STYLE;
    const root = host.attachShadow({ mode: 'closed' });
    sheet(root);

    const view = {
      // A link to a place on this page scrolls the reader to the block that holds it.
      follow(href) {
        let u;
        try { u = new URL(href); } catch { return false; }
        if (!u.hash || u.href.split('#')[0] !== location.href.split('#')[0]) return false;
        const target = document.getElementById(decodeURIComponent(u.hash.slice(1)));
        const at = target ? article.els.findIndex(e => e === target || e.contains(target)) : -1;
        if (at >= 0 && nodes.has(at)) view.goTo(at);
        return true;
      },
      toPage(id) { onClose(); article.els[id]?.scrollIntoView({ block: 'center' }); },
    };

    const nodes = new Map(); // block id -> its element in the reader
    const page = el('main', { class: 'page' });
    const reader = el('div', { class: 'reader', tabindex: '-1', lang: article.lang || null });
    const original = el('button', { class: 'original', text: 'Original page', title: 'Back to the page (Esc)' });
    original.addEventListener('click', onClose);
    const meta = [article.byline, article.published && date(article.published), article.site || location.hostname.replace(/^www\./, '')].filter(Boolean);
    const card = el('section', { class: 'card', 'aria-live': 'polite' });
    page.append(el('header', {}, el('h1', { text: article.title || document.title }), el('p', { class: 'meta' }, meta.map(m => el('span', { text: m })))), card);
    for (const b of article.blocks) {
      if (b.out) continue;
      const node = block(b, view);
      if (!node) continue;
      node.setAttribute('data-block', b.id);
      nodes.set(b.id, node);
      page.append(node);
    }
    const left = article.blocks.filter(b => b.out);
    if (left.length) {
      const counts = {};
      for (const b of left) counts[b.out.label] = (counts[b.out.label] || 0) + 1;
      const list = el('ul', { hidden: true }, Object.entries(counts).sort((a, b) => b[1] - a[1]).map(([label, n]) => el('li', { text: `${label}: ${n}` })));
      const toggle = el('button', { text: `${left.length} block${left.length === 1 ? '' : 's'} left out`, 'aria-expanded': 'false' });
      toggle.addEventListener('click', () => { list.hidden = !list.hidden; toggle.setAttribute('aria-expanded', String(!list.hidden)); });
      page.append(el('footer', { class: 'left' }, toggle, list));
    }
    reader.append(el('div', { class: 'bar' }, original), page);
    root.append(reader);

    let drawn = null, flashTimer = null;
    view.goTo = (id, quote) => {
      const node = nodes.get(id);
      if (!node) return false;
      node.scrollIntoView({ block: 'center', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
      node.classList.remove('flash');
      void node.offsetWidth;
      node.classList.add('flash');
      clearTimeout(flashTimer);
      flashTimer = setTimeout(() => { node.classList.remove('flash'); globalThis.CSS?.highlights?.delete('tldr-quote'); }, 2000);
      if (quote) highlight(node, quote);
      return true;
    };

    // The quote inside the block, marked for two seconds, when the browser has the Highlight API.
    function highlight(node, quote) {
      if (!globalThis.CSS?.highlights || !globalThis.Highlight) return;
      const walk = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
      let text = '';
      const spans = [];
      for (let n = walk.nextNode(); n; n = walk.nextNode()) { spans.push([n, text.length]); text += n.nodeValue; }
      const start = text.toLowerCase().indexOf(quote.toLowerCase());
      if (start < 0) return;
      const locate = offset => {
        const [n, base] = spans.findLast(([, at]) => at <= offset);
        return [n, Math.min(offset - base, n.nodeValue.length)];
      };
      const range = new Range();
      range.setStart(...locate(start));
      range.setEnd(...locate(start + quote.length));
      CSS.highlights.set('tldr-quote', new Highlight(range));
    }

    // The card: { label, bullets: [{ text, anchor, quote }], facts: [{ label, value, anchor }],
    // outline: [{ text, anchor }], source }.
    view.setCard = state => {
      drawn = state;
      const busy = card.querySelector('.progress');
      const jump = (kids, anchor, quote, cls) => {
        const b = el('button', { class: cls }, kids);
        b.addEventListener('click', () => view.goTo(anchor, quote));
        return b;
      };
      card.replaceChildren(...[
        el('p', { class: 'label', text: state.label }),
        el('ul', {}, state.bullets.map(b => el('li', {}, jump(b.text, b.anchor, b.quote, 'bullet')))),
        state.facts.length ? el('div', { class: 'facts' }, state.facts.map(f => jump([el('span', { class: 'k', text: f.label }), el('span', { class: 'v', text: f.value })], f.anchor, f.value))) : null,
        state.outline.length ? el('div', { class: 'outline' }, state.outline.map(o => jump(o.text, o.anchor))) : null,
        el('p', { class: 'source', text: state.source }),
        busy || el('div', { class: 'progress', hidden: true })].filter(Boolean));
    };
    view.setBusy = (on, note) => {
      const bar = card.querySelector('.progress');
      if (bar) bar.hidden = !on;
      if (note !== undefined && drawn) { drawn.source = note; card.querySelector('.source').textContent = note; }
    };

    const key = e => {
      if (e.key !== 'Escape') return;
      // First in line and the last to hear it: Esc closes the reader and nothing else, in a mini browser too.
      e.preventDefault();
      e.stopImmediatePropagation();
      onClose();
    };
    const paused = [];
    view.open = () => {
      for (const m of document.querySelectorAll('video, audio')) if (!m.paused) { m.pause(); paused.push(m); }
      hidePage(true);
      document.documentElement.append(host);
      addEventListener('keydown', key, true);
      reader.focus({ preventScroll: true });
    };
    view.close = () => {
      removeEventListener('keydown', key, true);
      clearTimeout(flashTimer);
      globalThis.CSS?.highlights?.delete('tldr-quote');
      host.remove();
      hidePage(false);
    };
    view.attached = () => host.isConnected;

    // What is drawn, for the tests: the shadow root is closed, so this is the way in (index.js, snapshot).
    view.probe = () => ({
      closed: host.shadowRoot === null,
      tags: [...new Set([...root.querySelectorAll('*')].map(e => e.tagName.toLowerCase()))].sort(),
      handlers: [...root.querySelectorAll('*')].flatMap(e => e.getAttributeNames().filter(a => /^on/i.test(a) || a === 'style')),
      title: root.querySelector('h1')?.textContent || '',
      images: [...root.querySelectorAll('img')].map(i => ({ src: i.getAttribute('src'), loaded: i.complete && i.naturalWidth > 1, block: +i.closest('[data-block]')?.getAttribute('data-block') })),
      embeds: [...root.querySelectorAll('.embed')].map(e => ({ block: +e.closest('[data-block]')?.getAttribute('data-block'), host: e.querySelector('.host')?.textContent || '',
        button: e.querySelector('button')?.textContent || '', frame: e.querySelector('iframe')?.getAttribute('src') || null, sandbox: e.querySelector('iframe')?.getAttribute('sandbox') || null })),
      frames: [...root.querySelectorAll('iframe')].map(f => f.getAttribute('src')),
      text: page.textContent,
      card: drawn && { label: drawn.label, bullets: drawn.bullets.map(b => ({ ...b })), facts: drawn.facts.map(f => ({ ...f })), outline: drawn.outline.map(o => o.text), source: drawn.source,
                       busy: !card.querySelector('.progress')?.hidden },
      leftOut: root.querySelector('.left button')?.textContent || '',
      flashed: [...root.querySelectorAll('.flash')].map(n => +n.getAttribute('data-block')),
      inView: [...nodes].filter(([, n]) => { const r = n.getBoundingClientRect(); return r.bottom > 0 && r.top < innerHeight; }).map(([id]) => id),
    });
    // For the screenshots: the reader scrolled to a fraction of its length.
    view.scrollTo = fraction => { reader.scrollTop = fraction * (reader.scrollHeight - reader.clientHeight); };
    // For the tests: a click on what a person would click.
    view.press = what => {
      const target = what === 'original' ? original : what === 'embed' ? root.querySelector('.embed .load')
        : what === 'left' ? root.querySelector('.left button') : root.querySelectorAll('.bullet')[what.bullet];
      target?.click();
      return !!target;
    };
    return view;
  };

  function date(value) {
    const d = new Date(value);
    if (isNaN(d)) return String(value).slice(0, 40);
    return d.toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' });
  }
})();
