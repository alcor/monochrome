// Media rules for the reader (docs/tldr.md, "Media rules"): what an img, picture, video, audio or iframe
// on the page becomes in a block's `media`. Nothing here writes to the page: a lazy image's address is
// read from its data attributes or its noscript twin and used in the reader's own copy.
(() => {
  const T = globalThis.__tldr ??= {};

  // Embeds the reader may load, after a click. A host matches exactly, and the path must start as listed.
  const EMBEDS = [
    ['www.youtube.com', '/embed/'], ['youtube.com', '/embed/'], ['www.youtube-nocookie.com', '/embed/'],
    ['player.vimeo.com', '/video/'], ['platform.twitter.com', '/embed/'], ['www.instagram.com', '/'],
    ['www.tiktok.com', '/embed'], ['codepen.io', '/'], ['open.spotify.com', '/embed'],
    ['w.soundcloud.com', '/player'], ['bandcamp.com', '/EmbeddedPlayer'], ['gist.github.com', '/'],
    ['datawrapper.dwcdn.net', '/'], ['flo.uri.sh', '/'], ['observablehq.com', '/embed'],
    ['www.google.com', '/maps/embed'],
  ];

  // An absolute http(s) address, or null. `image` also lets data:image/ through.
  T.url = (value, image = false) => {
    if (!value) return null;
    value = String(value).trim();
    if (image && /^data:image\//i.test(value)) return value;
    try {
      const u = new URL(value, document.baseURI);
      return u.protocol === 'http:' || u.protocol === 'https:' ? u.href : null;
    } catch { return null; }
  };

  T.srcset = value => {
    if (!value) return null;
    const out = [];
    for (const part of String(value).split(/,\s+|,(?=\S+\s+[\d.]+[wx])/)) {
      const [, address, size = ''] = part.trim().match(/^(\S+)(\s+[\d.]+[wx])?$/) || [];
      const u = T.url(address);
      if (u) out.push(u + size);
    }
    return out.length ? out.join(', ') : null;
  };

  // The host an iframe may be loaded from, or null when it is not on the list.
  T.embedHost = src => {
    let u;
    try { u = new URL(src, document.baseURI); } catch { return null; }
    if (u.protocol !== 'https:') return null;
    return EMBEDS.some(([host, path]) => u.hostname === host && u.pathname.startsWith(path)) ? u.hostname : null;
  };

  const placeholder = src => !src || /^data:/i.test(src) || /(^|\/)(blank|spacer|pixel|placeholder|1x1)[^/]*\.(gif|png|svg)/i.test(src);

  // The img a lazy loader keeps in a noscript beside its placeholder.
  function noscriptImage(img) {
    const next = img.nextElementSibling || img.parentElement?.nextElementSibling;
    if (next?.tagName !== 'NOSCRIPT') return null;
    return new DOMParser().parseFromString(next.textContent, 'text/html').querySelector('img');
  }

  // { src, srcset, sizes, alt, width, height } for an img after lazy resolution, or null when the image
  // is dropped: a tracking pixel, an icon, or an unlabelled image inside a link to another site.
  T.image = img => {
    let src = img.getAttribute('src'), srcset = img.getAttribute('srcset');
    const lazy = img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || img.getAttribute('data-original');
    const lazySet = img.getAttribute('data-srcset') || img.getAttribute('data-lazy-srcset');
    const loaded = img.complete && img.naturalWidth > 1;
    if (placeholder(src) || (lazy && !loaded)) {
      const twin = lazy || lazySet ? null : noscriptImage(img);
      src = lazy || twin?.getAttribute('src') || (lazySet ? null : src);
      srcset = lazySet || twin?.getAttribute('srcset') || srcset;
    } else if (lazySet && !srcset) srcset = lazySet;
    const out = { src: T.url(src, true), srcset: T.srcset(srcset), sizes: img.getAttribute('sizes') || null,
                  alt: img.getAttribute('alt') || '', width: +img.getAttribute('width') || img.naturalWidth || null,
                  height: +img.getAttribute('height') || img.naturalHeight || null };
    if (!out.src && out.srcset) out.src = out.srcset.split(/\s/)[0]; // an img needs a src: the set's first address
    if (!out.src) return null;
    if (loaded && img.naturalWidth <= 1 && img.naturalHeight <= 1 && !lazy && !lazySet) return null;
    const box = img.getBoundingClientRect();
    const w = box.width || out.width || 0, h = box.height || out.height || 0;
    if (w && h && (w < 40 || h < 40)) return null;
    const link = img.closest('a[href]');
    if (link && !out.alt) {
      try { if (new URL(link.href).hostname !== location.hostname) return null; } catch {}
    }
    return out;
  };

  // A picture: its sources and its img.
  T.picture = picture => {
    const img = picture.querySelector('img');
    const image = img && T.image(img);
    if (!image) return null;
    image.sources = [...picture.querySelectorAll('source')].map(s => ({
      srcset: T.srcset(s.getAttribute('srcset') || s.getAttribute('data-srcset')),
      media: s.getAttribute('media') || null, type: s.getAttribute('type') || null,
    })).filter(s => s.srcset);
    return image;
  };

  // A video or audio element. One whose address is a blob (a MediaSource player) cannot be played from
  // a second element, so it is marked `page`: the reader shows a button that goes back to the page's player.
  T.player = el => {
    const sources = [...el.querySelectorAll('source')].map(s => ({ src: T.url(s.getAttribute('src') || s.getAttribute('data-src')), type: s.getAttribute('type') || null }))
      .filter(s => s.src);
    const raw = el.getAttribute('src') || el.getAttribute('data-src') || '';
    const src = T.url(raw);
    const tracks = [...el.querySelectorAll('track')].map(t => ({ src: T.url(t.getAttribute('src')), kind: t.getAttribute('kind') || null,
      srclang: t.getAttribute('srclang') || null, label: t.getAttribute('label') || null })).filter(t => t.src);
    return { tag: el.tagName.toLowerCase(), src, sources, tracks, poster: T.url(el.getAttribute('poster'), true),
             page: !src && !sources.length && (/^blob:/i.test(raw) || /^blob:/i.test(el.currentSrc || '')) };
  };

  // An svg or canvas as an image address: scripts in an svg do not run inside an img.
  T.drawing = el => {
    try {
      if (el.tagName === 'CANVAS') return { src: el.toDataURL('image/png'), alt: el.getAttribute('aria-label') || '', width: el.width, height: el.height };
      const box = el.getBoundingClientRect();
      const copy = el.cloneNode(true);
      copy.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
      if (!copy.getAttribute('viewBox') && box.width) copy.setAttribute('viewBox', `0 0 ${Math.round(box.width)} ${Math.round(box.height)}`);
      copy.setAttribute('width', Math.round(box.width));
      copy.setAttribute('height', Math.round(box.height));
      const xml = new XMLSerializer().serializeToString(copy);
      return { src: 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(xml), alt: el.getAttribute('aria-label') || el.querySelector('title')?.textContent || '',
               width: Math.round(box.width), height: Math.round(box.height) };
    } catch { return null; } // a canvas tainted by another origin's image
  };
})();
