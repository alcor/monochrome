// The bar in the top-right of a mini browser page: an address button (🔗, or ⌘L), "Open in Chrome" and
// ▾ to pick a window or tab group, labelled with whatever shortcuts are set for them. Chrome's popup
// windows have no address bar, so ⌘L opens an address field with the URL selected, ready to copy;
// Enter goes to a URL or search, Esc closes it. Injected by mini-browser.js on each page load inside a
// mini browser.
(() => {
  if (document.getElementById('monochrome-mini-bar')) return;
  const host = document.createElement('div');
  host.id = 'monochrome-mini-bar';
  host.style.cssText = 'all: initial; position: fixed; top: 10px; right: 10px; z-index: 2147483647;';
  const root = host.attachShadow({ mode: 'closed' });
  root.innerHTML = `
    <style>
      .bar, .menu, .address { font: 13px/1 -apple-system, BlinkMacSystemFont, sans-serif; }
      .bar { display: flex; border-radius: 9px; overflow: hidden; background: rgba(32,32,36,.82);
             color: #fff; backdrop-filter: blur(12px); box-shadow: 0 2px 12px rgba(0,0,0,.25); opacity: .9; }
      .bar:hover { opacity: 1; }
      button { all: unset; cursor: default; padding: 7px 10px; }
      button:hover { background: rgba(255,255,255,.12); }
      .caret, .open { border-left: 1px solid rgba(255,255,255,.15); }
      .caret { padding: 7px 8px; }
      kbd { font: inherit; opacity: .55; margin-left: 6px; }
      .menu { position: absolute; right: 0; top: 34px; min-width: 200px; padding: 4px; border-radius: 9px;
              background: rgba(32,32,36,.95); color: #fff; box-shadow: 0 6px 24px rgba(0,0,0,.35); }
      .menu[hidden], .address[hidden] { display: none; }
      .menu button { display: flex; align-items: center; gap: 8px; width: calc(100% - 20px); border-radius: 6px; }
      .menu .head { padding: 6px 10px 2px; font-size: 11px; opacity: .5; }
      .dot { width: 8px; height: 8px; border-radius: 50%; }
      .address { position: fixed; top: 10px; left: 50%; transform: translateX(-50%); width: min(640px, calc(100vw - 32px)); }
      .address input { box-sizing: border-box; width: 100%; padding: 10px 12px; border: 0; border-radius: 10px; outline: none;
                       font: 14px -apple-system, BlinkMacSystemFont, sans-serif; color: #fff; background: rgba(32,32,36,.95);
                       box-shadow: 0 6px 24px rgba(0,0,0,.35), 0 0 0 2px #0a84ff; }
    </style>
    <div class="bar">
      <button class="url" title="Address (⌘L)">🔗</button>
      <button class="open">Open in Chrome<kbd></kbd></button>
      <button class="caret" title="Open in…">▾</button>
    </div>
    <div class="menu" hidden></div>
    <form class="address" hidden><input spellcheck="false" autocomplete="off" aria-label="Address"></form>`;
  const menu = root.querySelector('.menu');
  const address = root.querySelector('.address');
  const field = address.querySelector('input');
  const colors = { grey: '#9aa0a6', blue: '#8ab4f8', red: '#f28b82', yellow: '#fdd663', green: '#81c995',
                   pink: '#ff8bcb', purple: '#c58af9', cyan: '#78d9ec', orange: '#fcad70' };
  const move = to => chrome.runtime.sendMessage({ mini: 'move', to });

  async function toggleMenu() {
    if (!menu.hidden) return void (menu.hidden = true);
    const targets = await chrome.runtime.sendMessage({ mini: 'targets' });
    menu.replaceChildren();
    for (const w of targets) {
      const head = document.createElement('div');
      head.className = 'head';
      head.textContent = w.title;
      const today = document.createElement('button');
      today.textContent = 'New tab';
      today.onclick = () => move({ windowId: w.windowId });
      menu.append(head, today);
      for (const g of w.groups) {
        const b = document.createElement('button');
        const dot = document.createElement('span');
        dot.className = 'dot';
        dot.style.background = colors[g.color] || colors.grey;
        b.append(dot, g.title);
        b.onclick = () => move({ windowId: w.windowId, groupId: g.id });
        menu.append(b);
      }
    }
    menu.hidden = false;
  }

  function showAddress() {
    menu.hidden = true;
    field.value = location.href;
    address.hidden = false;
    field.focus();
    field.select();
  }

  address.onsubmit = e => {
    e.preventDefault();
    const text = field.value.trim();
    address.hidden = true;
    if (text && text !== location.href) chrome.runtime.sendMessage({ mini: 'go', text });
  };
  field.addEventListener('keydown', e => { if (e.key === 'Escape') { e.stopPropagation(); address.hidden = true; } });
  field.addEventListener('blur', () => { address.hidden = true; });
  addEventListener('keydown', e => {
    if (e.metaKey && !e.ctrlKey && !e.altKey && !e.shiftKey && e.key.toLowerCase() === 'l') {
      e.preventDefault();
      e.stopImmediatePropagation();
      showAddress();
    }
  }, true);

  chrome.runtime.sendMessage({ mini: 'shortcuts' }).then(keys => {
    const kbd = root.querySelector('kbd');
    if (keys['mini-open']) kbd.textContent = keys['mini-open'];
    else kbd.remove();
    if (keys['mini-open-in']) root.querySelector('.caret').title = `Open in… (${keys['mini-open-in']})`;
  });

  root.querySelector('.url').onclick = showAddress;
  root.querySelector('.open').onclick = () => move();
  root.querySelector('.caret').onclick = toggleMenu;
  chrome.runtime.onMessage.addListener(msg => {
    if (msg.mini === 'menu') toggleMenu();
    if (msg.mini === 'address') showAddress();
  });
  document.documentElement.append(host);
})();
