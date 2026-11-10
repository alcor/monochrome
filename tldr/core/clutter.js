// Clutter by rule (docs/tldr.md, "Clutter"): which elements under the article's root the reader leaves
// out, and under which label. Three passes: structure (the element's own tag, role and position), the
// selector list (selectors.js), and shape (link density, cards, share bars, stock phrases). Nothing is
// removed from the page; the walker (extract.js) records a left-out block and moves on.
(() => {
  const T = globalThis.__tldr ??= {};

  const STRUCTURE = { NAV: 'navigation', FOOTER: 'navigation', ASIDE: 'other', FORM: 'other', DIALOG: 'other', MENU: 'navigation' };
  const ROLES = { navigation: 'navigation', complementary: 'other', banner: 'navigation', contentinfo: 'navigation', search: 'other',
                  dialog: 'other', alertdialog: 'other', menu: 'navigation', toolbar: 'other' };
  const SHARE = /facebook\.com\/shar|twitter\.com\/(intent|share)|x\.com\/(intent|share)|linkedin\.com\/share|reddit\.com\/submit|wa\.me\/|api\.whatsapp\.com|t\.me\/share|pinterest\.[a-z.]+\/pin\/create|^mailto:\?/i;
  const PHRASES = [
    [/^(advertisement|advertising|ad)s?\.?$/i, 'ad'],
    [/^(sponsored|sponsored content|paid post|paid content|promoted|partner content)\.?$/i, 'sponsored'],
    [/^(sign up (for|to)|subscribe to|get) (our|the) .{0,40}newsletter/i, 'promo'],
    [/^(read more|read next|related|related articles|related stories|see also|more from .{0,30}|recommended|you may also like)\s*:/i, 'promo'],
    [/^(related|related articles|related stories|recommended|you may also like|most read|most popular|trending)\.?$/i, 'promo'],
    [/^(share this( article| story| post)?|follow us( on .{0,30})?)\s*:?$/i, 'other'],
    [/^(edit this page|edit on github|improve this page|back to top|print|skip to (main )?content)\.?$/i, 'navigation'],
  ];

  let lists = null; // [label, selector] pairs for this page
  function selectors() {
    if (lists) return lists;
    lists = [];
    const add = set => { for (const [label, list] of Object.entries(set)) lists.push([label, list.join(',')]); };
    add(T.selectors.generic);
    for (const [host, set] of Object.entries(T.selectors.hosts)) {
      if (location.hostname === host || location.hostname.endsWith('.' + host)) add(set);
    }
    return lists;
  }

  const textLength = el => (el.textContent || '').replace(/\s+/g, ' ').trim().length;

  // The label of the list selector an element matches, or null.
  T.listed = el => {
    for (const [label, selector] of selectors()) if (el.matches(selector)) return label;
    return null;
  };

  // The label of a stock phrase that is the whole of a short text ("Advertisement", "Edit this page"), or null.
  T.phrase = text => {
    if (text.length < 120) for (const [phrase, label] of PHRASES) if (phrase.test(text)) return label;
    return null;
  };

  function shape(el) {
    const tag = el.tagName;
    const text = (el.textContent || '').replace(/\s+/g, ' ').trim();
    if (tag === 'P' || tag === 'DIV' || tag === 'SPAN' || tag === 'H2' || tag === 'H3' || tag === 'H4' || tag === 'H5' || tag === 'STRONG') {
      const phrase = T.phrase(text);
      if (phrase) return phrase;
    }
    if (tag === 'P' || /^H[1-6]$/.test(tag) || tag === 'PRE' || tag === 'TABLE' || tag === 'BLOCKQUOTE' || tag === 'FIGURE') return null;
    const links = [...el.querySelectorAll('a[href]')];
    if (links.length < 2) return null;
    if (links.filter(a => SHARE.test(a.getAttribute('href'))).length >= 2 && text.length < 300) return 'other';
    const linked = links.reduce((n, a) => n + textLength(a), 0);
    if (links.length >= 3 && linked > 0.5 * text.length && text.length - linked < 200) return 'navigation';
    // Cards: children that are each a link with an image and a line of text, to the page's own site.
    const cards = [...el.children].filter(c => {
      const a = c.matches('a[href]') ? c : c.querySelector('a[href]');
      return a && c.querySelector('img, picture') && textLength(c) < 100;
    });
    if (cards.length >= 2 && cards.length >= el.children.length - 1) return 'promo';
    return null;
  }

  // Why an element is left out: { label, pass }, or null for content. `ctx.total` is the root's text
  // length: nothing that holds a third of the article is taken for clutter by its class name or shape.
  T.clutter = (el, ctx) => {
    const tag = el.tagName;
    if (STRUCTURE[tag]) return { label: STRUCTURE[tag], pass: 'structure' };
    const role = (el.getAttribute('role') || '').toLowerCase();
    if (ROLES[role]) return { label: ROLES[role], pass: 'structure' };
    if (el.id === 'comments' || el.id === 'disqus_thread') return { label: 'other', pass: 'structure' };
    const position = getComputedStyle(el).position;
    if (position === 'fixed') return { label: 'navigation', pass: 'structure' };
    // The two guards, from Catalyst's false positive: a figure is content, and so is a block whose
    // images all come from the page's own host or the host of its og:image.
    if (tag === 'FIGURE' || tag === 'FIGCAPTION') return null;
    if (ctx.total && textLength(el) > ctx.total / 3) return null;
    const listed = T.listed(el);
    if (listed) {
      if (el.querySelector('figure, figcaption')) return null;
      if (listed !== 'promo' && listed !== 'navigation' && ownImages(el, ctx)) return null;
      return { label: listed, pass: 'list' };
    }
    const shaped = shape(el);
    if (shaped) {
      if (shaped !== 'promo' && el.querySelector('figure, figcaption')) return null;
      return { label: shaped, pass: 'shape' };
    }
    return null;
  };

  function ownImages(el, ctx) {
    const imgs = [...el.querySelectorAll('img')];
    if (!imgs.length) return false;
    return imgs.every(img => {
      try { return ctx.hosts.has(new URL(img.currentSrc || img.src, document.baseURI).hostname); } catch { return false; }
    });
  }

  // The hosts whose images count as the article's own: the page's, and the og:image's.
  T.ownHosts = () => {
    const hosts = new Set([location.hostname]);
    const og = document.querySelector('meta[property="og:image"]')?.content;
    try { if (og) hosts.add(new URL(og, document.baseURI).hostname); } catch {}
    return hosts;
  };
})();
