// Loads the extension into a throwaway Chromium and checks pinned-tab reset.
// Run: npm install && npx playwright-core install chromium && npm test
import { chromium } from 'playwright-core';
import http from 'node:http';
import assert from 'node:assert';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import net from 'node:net';

const ext = import.meta.dirname;
const server = http.createServer((req, res) => res.end(`<title>${req.url}</title>${req.url}`)).listen(0);
const base = `http://127.0.0.1:${server.address().port}`;

const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'monochrome-test-'));
const ctx = await chromium.launchPersistentContext(profile, {
  channel: 'chromium',
  headless: !process.env.HEADFUL,
  args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`],
});
const sw = ctx.serviceWorkers()[0] || await ctx.waitForEvent('serviceworker');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const settle = () => sw.evaluate(() => queue).then(() => sleep(300)).then(() => sw.evaluate(() => queue));
const pinnedUrls = () => sw.evaluate(async () => (await chrome.tabs.query({ pinned: true })).map(t => t.pendingUrl || t.url));
const open = (p, pinned = false) => sw.evaluate(async ([url, pinned]) => {
  const t = await chrome.tabs.create({ url });
  await new Promise(r => setTimeout(r, 300));
  if (pinned) await chrome.tabs.update(t.id, { pinned: true });
  return t.id;
}, [base + p, pinned]);
const go = (id, p) => sw.evaluate(([id, url]) => chrome.tabs.update(id, { url }), [id, base + p]).then(() => sleep(300));
const urlOf = id => sw.evaluate(async id => { const t = await chrome.tabs.get(id); return t.pendingUrl || t.url; }, id);
// A reset navigates the tab; on a loaded CI runner that can take longer than a fixed sleep, so wait up to 3 s for the URL.
const urlBecomes = async (id, url) => { for (let i = 0; i < 30 && (await urlOf(id)) !== url; i++) await sleep(100); return urlOf(id); };
const call = (fn, id) => sw.evaluate(async ([fn, id]) => { await self[fn](await chrome.tabs.get(id)); }, [fn, id]);
const close = id => sw.evaluate(id => chrome.tabs.remove(id), id).then(settle);
const pageFor = async url => {
  for (let i = 0; i < 50; i++) {
    const p = ctx.pages().find(p => p.url().startsWith(url));
    if (p) return p;
    await sleep(100);
  }
  throw new Error('no page for ' + url);
};

const a = await open('/a', true);
const b = await open('/b', true);
await settle();

await go(a, '/a2');
await call('reset', a);
assert.equal(await urlBecomes(a, `${base}/a`), `${base}/a`);
console.log('reset after navigation: ok');

// Closing a pinned tab puts it back at its pinned URL in the same spot.
await go(a, '/a3');
await close(a);
assert.deepEqual(await pinnedUrls(), [`${base}/a`, `${base}/b`]);
console.log('close brings pinned tab back: ok');

// Simulated restart: session map forgotten, tabs have drifted, URLs come back from saved order.
const [a2, b2] = await sw.evaluate(async () => (await chrome.tabs.query({ pinned: true })).map(t => t.id));
await go(a2, '/x');
await go(b2, '/y');
await sw.evaluate(async () => { await queue; await chrome.storage.session.clear(); });
await call('reset', b2);
assert.equal(await urlBecomes(b2, `${base}/b`), `${base}/b`);
console.log('reset after simulated restart: ok');

// Replace pinned URL with current.
await call('repin', a2);
await go(a2, '/z');
await call('reset', a2);
assert.equal(await urlBecomes(a2, `${base}/x`), `${base}/x`);
console.log('repin: ok');

// Pinning a new tab records its own URL, not a neighbour's.
const c = await open('/c', true);
await settle();
await go(c, '/c2');
await call('reset', c);
assert.equal(await urlBecomes(c, `${base}/c`), `${base}/c`);
console.log('newly pinned tab keeps its own URL: ok');

// Unpinned tabs: reset does nothing, close really closes.
await sw.evaluate(id => chrome.tabs.update(id, { pinned: false }), c);
await settle();
await go(c, '/c3');
await call('reset', c);
assert.equal(await urlBecomes(c, `${base}/c3`), `${base}/c3`);
await close(c);
assert.deepEqual(await pinnedUrls(), [`${base}/x`, `${base}/b`]);
console.log('unpinned tab ignored: ok');

// Locked tab group: tabs in "CoreCore" behave like pinned tabs. (New tabs open at the top, so g1,
// opened last, ends up first.)
const g2 = await open('/g2');
const g1 = await open('/g1');
await sw.evaluate(async ids => {
  const groupId = await chrome.tabs.group({ tabIds: ids });
  await chrome.tabGroups.update(groupId, { title: 'CoreCore', color: 'blue' });
}, [g1, g2]);
await settle();
const groupUrls = () => sw.evaluate(async () => {
  const [g] = await chrome.tabGroups.query({ title: 'CoreCore' });
  if (!g) return [];
  return (await chrome.tabs.query({ groupId: g.id })).map(t => t.pendingUrl || t.url);
});
await go(g1, '/g1-drift');
await close(g1);
assert.deepEqual(await groupUrls(), [`${base}/g1`, `${base}/g2`]);
console.log('closed group tab comes back in group: ok');

// ⌘W command closes the active tab through the extension; a locked one comes back.
await sw.evaluate(id => chrome.tabs.update(id, { active: true }), g2);
await go(g2, '/g2-drift');
await sw.evaluate(() => closeTabs());
await settle();
assert.deepEqual(await groupUrls(), [`${base}/g1`, `${base}/g2`]);
console.log('close command on group tab: ok');

// Closing every tab in the group brings the whole group back.
const groupIds = await sw.evaluate(async () => {
  const [g] = await chrome.tabGroups.query({ title: 'CoreCore' });
  return (await chrome.tabs.query({ groupId: g.id })).map(t => t.id);
});
await sw.evaluate(ids => chrome.tabs.remove(ids), groupIds);
await settle();
assert.deepEqual(await groupUrls(), [`${base}/g1`, `${base}/g2`]);
console.log('whole group comes back: ok');

// A tab dragged out of the group is a normal tab again.
const [out] = await sw.evaluate(async () => {
  const [g] = await chrome.tabGroups.query({ title: 'CoreCore' });
  return (await chrome.tabs.query({ groupId: g.id })).map(t => t.id);
});
await sw.evaluate(id => chrome.tabs.ungroup(id), out);
await settle();
await close(out);
assert.deepEqual(await groupUrls(), [`${base}/g2`]);
console.log('ungrouped tab really closes: ok');

// Order saved for the next launch, per slot.
assert.deepEqual((await sw.evaluate(() => chrome.storage.local.get('order'))).order,
  { pinned: [`${base}/x`, `${base}/b`], CoreCore: [`${base}/g2`] });
console.log('saved order: ok');

// New tabs open right under the locked tabs: pinned, then the CoreCore group.
const lastLockedIndex = () => sw.evaluate(async () => {
  const [g] = await chrome.tabGroups.query({ title: 'CoreCore' });
  const tabs = await chrome.tabs.query({ windowId: g.windowId });
  return Math.max(...tabs.filter(t => t.pinned || t.groupId === g.id).map(t => t.index));
});
const indexOf = id => sw.evaluate(async id => (await chrome.tabs.get(id)).index, id);
const n1 = await open('/n1');
await settle();
assert.equal(await indexOf(n1), (await lastLockedIndex()) + 1);
console.log('new tab opens under CoreCore: ok');

// A new tab that lands in CoreCore (a link opened from a CoreCore tab) is taken out and not locked.
const corePage = await pageFor(`${base}/g2`);
await corePage.bringToFront(); // Chrome records the active tab as a link's opener
await corePage.evaluate(url => { document.body.innerHTML = `<a href="${url}">go</a>`; }, `${base}/from-core`);
await corePage.click('a', { modifiers: ['Meta'] });
await settle();
const n2 = await sw.evaluate(async url => (await chrome.tabs.query({ url }))[0].id, `${base}/from-core`);
assert.equal(await sw.evaluate(async id => (await chrome.tabs.get(id)).groupId, n2), -1);
assert.equal(await indexOf(n2), (await lastLockedIndex()) + 1);
assert.deepEqual(await groupUrls(), [`${base}/g2`]);
console.log('new tab dropped into CoreCore is taken out: ok');

// A link opened in a new tab from a normal tab lands right after that tab, not at the top.
const n1Page = await pageFor(`${base}/n1`);
await n1Page.bringToFront();
await n1Page.evaluate(url => { document.body.innerHTML = `<a href="${url}">go</a>`; }, `${base}/from-n1`);
await n1Page.click('a', { modifiers: ['Meta'] });
await settle();
const n3 = await sw.evaluate(async url => (await chrome.tabs.query({ url }))[0].id, `${base}/from-n1`);
assert.equal(await indexOf(n3), (await indexOf(n1)) + 1);
console.log('link from a normal tab opens right after it: ok');

// ⌘T: Chrome gives the new tab an opener too, but a New Tab page still goes to the top.
const n4 = await sw.evaluate(async opener => (await chrome.tabs.create({ url: 'chrome://newtab/', openerTabId: opener })).id, n1);
await settle();
assert.equal(await indexOf(n4), (await lastLockedIndex()) + 1);
await sw.evaluate(ids => chrome.tabs.remove(ids), [n1, n2, n3, n4]);
await settle();
console.log('new tab page with an opener goes to the top: ok');

// Recent tabs. Karabiner sends recent-next for the first ⌃Tab after Control goes down, recent-continue
// for more ⌃Tabs while Control is held, recent-prev for ⌃⇧Tab.
const activate = id => sw.evaluate(id => chrome.tabs.update(id, { active: true }), id).then(() => sleep(50));
const active = () => sw.evaluate(async () => (await chrome.tabs.query({ active: true, lastFocusedWindow: true }))[0].id);
const command = name => sw.evaluate(async name => {
  const fn = { 'recent-next': () => recent(1, true), 'recent-continue': () => recent(1, false), 'recent-prev': () => recent(-1, false) }[name];
  await fn();
}, name);
const r1 = await open('/r1'), r2 = await open('/r2'), r3 = await open('/r3');
await activate(r1); await activate(r2); await activate(r3);
await command('recent-next'); // ⌃Tab, release
assert.equal(await active(), r2);
await command('recent-next'); // ⌃Tab again right away: back where we came from
assert.equal(await active(), r3);
console.log('ctrl+tab, release, ctrl+tab goes back: ok');
await command('recent-next'); // hold Control: ⌃Tab, ⌃Tab
await command('recent-continue');
assert.equal(await active(), r1);
await command('recent-prev'); // still holding: ⌃⇧Tab
assert.equal(await active(), r2);
console.log('holding control walks back, ctrl+shift+tab steps back: ok');

// From A, ⌃Tab ⌃Tab to C, release, ⌃Tab: back to A (the tab the walk passed through doesn't count).
const [tabA, tabB, tabC] = [r1, r2, r3];
await activate(tabC); await activate(tabB); await activate(tabA); // recent order: A, B, C
await sleep(1100);
await command('recent-next');
await command('recent-continue');
assert.equal(await active(), tabC);
await sleep(300);
await command('recent-next');
assert.equal(await active(), tabA);
console.log('walk A to C, release, ctrl+tab goes back to A: ok');

// Clicking a tab yourself counts as using it.
await activate(tabB);
await sleep(300);
await command('recent-next');
assert.equal(await active(), tabA);
console.log('clicked tab counts, ctrl+tab returns to the one before: ok');

// A link opened in a background tab is next: ⌃Tab goes to it, then ⌃Tab comes back.
const bg = await sw.evaluate(async () => (await chrome.tabs.create({ url: 'about:blank', active: false })).id);
await settle();
await command('recent-next');
assert.equal(await active(), bg);
await sleep(300);
await command('recent-next');
assert.equal(await active(), tabA);
await close(bg);
console.log('background tab is next for ctrl+tab: ok');

// mini browser.
const miniBrowsers = () => sw.evaluate(async () => {
  const { mini = {} } = await chrome.storage.session.get('mini');
  const wins = await chrome.windows.getAll({ populate: true });
  return wins.filter(w => w.id in mini).map(w => ({ id: w.id, type: w.type, urls: w.tabs.map(t => t.pendingUrl || t.url) }));
});

// ⌥⌘N: blank mini browser with a search box; typing a URL goes there and the bar shows up.
await sw.evaluate(() => miniCommand('mini-new'));
let [lw] = await miniBrowsers();
assert.equal(lw.type, 'popup');
assert.match(lw.urls[0], /mini-browser\.html$/);
const box = await pageFor(lw.urls[0]);
await box.fill('input', `${base}/mini-typed`);
await box.press('input', 'Enter');
const typed = await pageFor(`${base}/mini-typed`);
await typed.waitForSelector('#monochrome-mini-bar', { state: 'attached' });
console.log('mini browser: new, type URL, bar shows: ok');

// ⌘L opens the address field with the URL selected; typing a new one and Enter goes there.
await typed.keyboard.press('Meta+l');
assert.equal(await typed.evaluate(() => getSelection().toString()), `${base}/mini-typed`); // ready to ⌘C
await typed.keyboard.type(`${base}/mini-cmd-l`);
await typed.keyboard.press('Enter');
await pageFor(`${base}/mini-cmd-l`);
console.log('mini browser: cmd+L address field: ok');

// ⌘O: moves the page into the main window as a normal tab; the mini browser goes away.
const miniTab = await sw.evaluate(async id => (await chrome.tabs.query({ windowId: id }))[0].id, lw.id);
await sw.evaluate(id => moveToMain(id), miniTab);
await sleep(300);
assert.deepEqual(await miniBrowsers(), []);
assert.equal(await sw.evaluate(async id => (await chrome.windows.get((await chrome.tabs.get(id)).windowId)).type, miniTab), 'normal');
assert.equal(await indexOf(miniTab), (await lastLockedIndex()) + 1);
console.log('mini browser: open in Chrome, lands under CoreCore: ok');

// ⌥⌘-click: the helper's tap turns it into a ⌘-click and says a mini browser is coming; the background
// tab Chrome then makes becomes one.
await go(await open('/with-link'), '/with-link');
const linkPage = await pageFor(`${base}/with-link`);
await linkPage.evaluate(url => { document.body.innerHTML = `<a href="${url}">go</a>`; }, `${base}/clicked`);
await sw.evaluate(() => { miniNextUntil = Date.now() + 1500; });
await linkPage.click('a', { modifiers: ['Meta'] });
await sleep(500);
[lw] = await miniBrowsers();
assert.deepEqual(lw.urls, [`${base}/clicked`]);
assert.equal(linkPage.url(), `${base}/with-link`);
console.log('mini browser: alt-cmd-click via the helper: ok');

// peek: a link from a locked tab that opens a new tab (target=_blank) becomes a mini browser over the
// window, the locked page dimmed behind it; another window taking focus closes it and undims the page.
// The content script catches the click, so the page opens in the peek directly: its tab has no opener.
const pinnedPage = await pageFor(`${base}/x`);
await pinnedPage.bringToFront();
const peekWindow = async url => (await miniBrowsers()).find(w => w.urls[0] === `${base}${url}`);
const dimmed = () => pinnedPage.evaluate(() => !!document.getElementById('monochrome-peek-dim'));
const waitFor = async check => { for (let i = 0; i < 30 && !(await check()); i++) await sleep(100); return check(); };
const openerOf = async url => sw.evaluate(async url => (await chrome.tabs.query({ url }))[0]?.openerTabId, `${base}${url}`);
const mainWindow = await sw.evaluate(async id => (await chrome.tabs.get(id)).windowId, a2);
const focusMain = async () => { await sw.evaluate(id => run(() => miniFocused(id)), mainWindow); await settle(); };

await pinnedPage.evaluate(url => { document.body.innerHTML = `<a href="${url}" target="_blank">go</a>`; }, `${base}/peeked`);
await pinnedPage.click('a');
assert.ok(await waitFor(() => peekWindow('/peeked')));
assert.equal((await peekWindow('/peeked')).type, 'popup');
assert.equal(await openerOf('/peeked'), undefined);
assert.equal(await sw.evaluate(async () => Object.keys((await chrome.storage.session.get('peek')).peek).length), 1);
assert.ok(await waitFor(dimmed));
await focusMain();
assert.equal(await peekWindow('/peeked'), undefined);
assert.equal(await dimmed(), false);
console.log('mini browser: peek from a locked tab, closed by focus elsewhere: ok');

// window.open from the locked page's own script is caught the same way and returns null.
assert.equal(await pinnedPage.evaluate(url => window.open(url) === null, `${base}/peek-opened`), true);
assert.ok(await waitFor(() => peekWindow('/peek-opened')));
assert.equal(await openerOf('/peek-opened'), undefined);
await focusMain();
console.log('mini browser: peek from window.open: ok');

// A new tab the content script didn't catch (here: made with an opener directly) still becomes a peek,
// moved out of the main window.
const fallback = await sw.evaluate(async ([url, opener, windowId]) => (await chrome.tabs.create({ url, openerTabId: opener, windowId, active: true })).id, [`${base}/peek-fallback`, a2, mainWindow]);
assert.ok(await waitFor(() => peekWindow('/peek-fallback')));
assert.equal(await sw.evaluate(async id => (await chrome.tabs.query({ windowId: id }))[0].id, (await peekWindow('/peek-fallback')).id), fallback);
await focusMain();
assert.deepEqual((await miniBrowsers()).filter(w => w.urls[0].startsWith(`${base}/peek`)), []);
console.log('mini browser: peek fallback for a tab Chrome already opened: ok');

// An unlocked tab's new-tab links are left to Chrome.
await sw.evaluate(id => chrome.tabs.update(id, { pinned: false }), a2);
await settle();
await pinnedPage.evaluate(url => { document.body.innerHTML = `<a href="${url}" target="_blank">go</a>`; }, `${base}/not-peeked`);
await pinnedPage.click('a');
await sleep(500);
assert.equal(await peekWindow('/not-peeked'), undefined);
assert.equal(await openerOf('/not-peeked'), a2);
await sw.evaluate(id => chrome.tabs.update(id, { pinned: true }), a2);
await settle();
console.log('mini browser: no peek from an unpinned tab: ok');

// A page that finished loading before it moved into a mini browser still gets the bar.
const loaded = await open('/already-loaded');
await sleep(300);
await sw.evaluate(id => openMiniBrowser({ tabId: id }), loaded);
await (await pageFor(`${base}/already-loaded`)).waitForSelector('#monochrome-mini-bar', { state: 'attached', timeout: 3000 });
await sw.evaluate(id => chrome.tabs.remove(id), loaded);
console.log('mini browser: bar on an already-loaded page: ok');

// Left alone for 12 hours, it closes.
await sw.evaluate(async () => { await chrome.storage.session.set({ focused: -1 }); await archiveMiniBrowsers(Date.now() + 13 * 3600e3); });
await sleep(300);
assert.deepEqual(await miniBrowsers(), []);
console.log('mini browser: archived after 12 hours: ok');

// Routed links (routes.js): the helper's rule names a destination inside this profile.
const route = (p, to) => sw.evaluate(([url, to]) => routeOpen(url, to), [p, to]);
const tabOf = id => sw.evaluate(async id => {
  const t = await chrome.tabs.get(id);
  const w = await chrome.windows.get(t.windowId);
  return { url: t.pendingUrl || t.url, index: t.index, groupId: t.groupId, windowType: w.type };
}, id);
// same-site: a tab already on that host is reused and navigated; the front window's wins.
const siteTab = await open('/site/one');
const reused = await route(`${base}/site/two`, { window: 'same-site' });
assert.equal(reused, siteTab);
await sleep(300);
assert.equal((await tabOf(reused)).url, `${base}/site/two`);
// same-site with no tab on that host (localhost is another hostname here): a new tab at the top of the window.
const fresh = await route(`http://localhost:${server.address().port}/elsewhere`, { window: 'same-site' });
await settle();
const freshTab = await tabOf(fresh);
assert.equal(freshTab.windowType, 'normal');
assert.equal(freshTab.index, await sw.evaluate(async id => topIndex((await chrome.tabs.get(id)).windowId, id), fresh));
await close(fresh);
// group: the tab joins the named group, made if missing; a second one joins the same group.
const rg1 = await route(`${base}/routed/1`, { group: 'Routed' });
const rg2 = await route(`${base}/routed/2`, { group: 'Routed' });
await settle();
assert.notEqual((await tabOf(rg1)).groupId, -1);
assert.equal((await tabOf(rg1)).groupId, (await tabOf(rg2)).groupId);
assert.deepEqual(await sw.evaluate(() => chrome.tabGroups.query({ title: 'Routed' }).then(gs => gs.length)), 1);
await close(rg1); await close(rg2); await close(siteTab);
// no destination: a mini browser, as before rules.
const plain = await route(`${base}/routed/mini`, {});
await settle();
assert.equal((await tabOf(plain)).windowType, 'popup');
await close(plain);
console.log('routes: same-site, front, group, mini: ok');

// The ⌘L/⌘T box (omnibox.js): this profile's history, bookmarks, open tabs and front tab for the app,
// favicons for its rows, and where to go: the front tab, a new tab at the top, or an open tab.
const visited = await open('/omnibox/visited');
await sw.evaluate(async url => chrome.bookmarks.create({ title: 'Marked', url }), `${base}/omnibox/marked`);
const data = await sw.evaluate(() => omniboxData());
assert.ok(data.history.some(h => h.url === `${base}/omnibox/visited` && h.visits >= 1 && h.last > 0));
assert.ok(data.bookmarks.some(b => b.url === `${base}/omnibox/marked` && b.title === 'Marked'));
assert.ok(data.tabs.some(t => t.id === visited && t.url === `${base}/omnibox/visited`));
assert.equal(data.current?.id, visited);
const icons = await sw.evaluate(url => omniboxFavicons([url]), `${base}/omnibox/visited`);
assert.ok(`${base}/omnibox/visited` in icons);
await sw.evaluate(url => omniboxGo({ url }), `${base}/omnibox/went`);
assert.equal(await urlBecomes(visited, `${base}/omnibox/went`), `${base}/omnibox/went`);
await sw.evaluate(url => omniboxGo({ url, newTab: true }), `${base}/omnibox/new`);
await settle();
const made = await sw.evaluate(async url => (await chrome.tabs.query({ url }))[0], `${base}/omnibox/new`);
assert.equal(made?.index, await sw.evaluate(([w, id]) => topIndex(w, id), [made.windowId, made.id]));
await sw.evaluate(id => omniboxGo({ tab: id }), visited);
await settle();
assert.equal(await sw.evaluate(async id => (await chrome.tabs.get(id)).active, visited), true);
await close(made.id); await close(visited);
console.log('omnibox: history, bookmarks, tabs, favicons, go: ok');

// A link from another app (a second launch handing a URL to the running browser) opens in a mini browser.
// Headless Chromium doesn't accept that hand-off, so this one needs HEADFUL=1.
if (process.env.HEADFUL) {
  spawn(chromium.executablePath(), [`--user-data-dir=${profile}`, `${base}/from-other-app`], { stdio: 'ignore', detached: true }).unref();
  for (let i = 0; i < 50 && !(await miniBrowsers()).length; i++) await sleep(100);
  [lw] = await miniBrowsers();
  assert.deepEqual(lw?.urls, [`${base}/from-other-app`]);
  console.log('mini browser: link from another app: ok');
} else console.log('mini browser: link from another app: skipped (run with HEADFUL=1)');

// The extension ID Chrome assigns comes from the manifest key, the way the project's run script computes it.
const idFromKey = key => [...crypto.createHash('sha256').update(Buffer.from(key, 'base64')).digest('hex').slice(0, 32)]
  .map(c => String.fromCharCode(97 + parseInt(c, 16))).join('');
assert.equal(await sw.evaluate(() => chrome.runtime.id), idFromKey(JSON.parse(fs.readFileSync(path.join(ext, 'manifest.json'), 'utf8')).key));
console.log('extension id from the manifest key: ok');

// Safari: the generated manifest drops what is Chrome's alone, and the stand-ins for Chrome's search and
// favicon APIs build the URLs Safari uses (Google search, Google's favicon service).
{
  const out = path.join(profile, 'safari-manifest.json');
  const gen = spawn('python3', [path.join(ext, 'store/safari-manifest.py'), path.join(ext, 'manifest.json'), out], { stdio: 'inherit' });
  assert.equal(await new Promise(r => gen.on('exit', r)), 0);
  const m = JSON.parse(fs.readFileSync(out, 'utf8'));
  assert.equal(m.key, undefined);
  assert.equal(m.minimum_chrome_version, undefined);
  for (const p of ['tabGroups', 'search', 'favicon']) assert.ok(!m.permissions.includes(p), p);
  assert.ok(m.permissions.includes('nativeMessaging'));
  assert.equal(m.version, JSON.parse(fs.readFileSync(path.join(ext, 'manifest.json'), 'utf8')).version);
  const urls = await sw.evaluate(() => [searchUrl('a b&c'), faviconUrl('https://news.example.com/x?y', false), faviconUrl('about:blank', false),
    faviconUrl('https://example.com/'), SAFARI, HAS_GROUPS]);
  assert.deepEqual(urls.slice(0, 3), ['https://www.google.com/search?q=a%20b%26c',
    'https://www.google.com/s2/favicons?domain_url=https%3A%2F%2Fnews.example.com&sz=32', null]);
  assert.match(urls[3], /\/_favicon\/\?pageUrl=/); // Chrome keeps its own favicon cache
  assert.deepEqual(urls.slice(4), [false, true]);
  console.log('safari: manifest, search and favicon stand-ins: ok');

  // Messages from the app in Safari come wrapped by dispatchMessage and may name another profile.
  const unwrapped = await sw.evaluate(() => {
    const open = { open: 'https://example.com/', to: { window: 'front' }, safariProfile: 'A' };
    return [helperUnwrap({ name: 'monochrome', userInfo: open }, true, 'A'), helperUnwrap({ name: 'monochrome', userInfo: open }, true, 'B'),
      helperUnwrap({ name: 'monochrome', userInfo: { ping: true } }, true, 'B'), helperUnwrap(open, true, null),
      helperUnwrap({ activate: 3 }, false, null), helperUnwrap(null, true, 'A')];
  });
  assert.deepEqual(unwrapped[0], { open: 'https://example.com/', to: { window: 'front' }, safariProfile: 'A' });
  assert.equal(unwrapped[1], null); // another profile's link
  assert.deepEqual(unwrapped[2], { ping: true }); // no profile named: every copy
  assert.equal(unwrapped[3].open, 'https://example.com/'); // profile not known yet: taken
  assert.deepEqual(unwrapped[4], { activate: 3 }); // Chrome: as sent
  assert.equal(unwrapped[5], null);
  // focusFront, the app's switch to a connected Safari profile, focuses this copy's last normal window.
  assert.equal(await sw.evaluate(() => focusFront()), await sw.evaluate(async () => (await chrome.windows.getLastFocused({ windowTypes: ['normal'] })).id));
  console.log('safari: profile message unwrapping and focusFront: ok');
}

// A music site's track reaches the player, and the player's buttons reach the site's handlers.
await ctx.route('https://open.spotify.com/**', route => route.fulfill({ contentType: 'text/html', body: `<script>
  navigator.mediaSession.metadata = new MediaMetadata({ title: 'Song', artist: 'Band', artwork: [{ src: '/small.png' }, { src: '/big.png' }] });
  navigator.mediaSession.setActionHandler('nexttrack', () => { document.title = 'next'; });
</script>` }));
const songPage = await ctx.newPage(); // (tabs the extension opens don't go through ctx.route)
await songPage.goto('https://open.spotify.com/');
const song = await sw.evaluate(async () => (await chrome.tabs.query({ url: 'https://open.spotify.com/*' }))[0].id);
for (let i = 0; i < 50 && !(await sw.evaluate(id => music.has(id), song)); i++) await sleep(100);
const state = await sw.evaluate(() => playerState());
assert.deepEqual([state.title, state.artist, state.artwork], ['Song', 'Band', 'https://open.spotify.com/big.png']);
await sw.evaluate(() => playerAction({ action: 'nexttrack' }));
await songPage.waitForFunction(() => document.title === 'next', null, { timeout: 3000 });
// Shows while you're on another tab with the sidebar open; × hides it until you've been back on the
// music tab. (Headless Chromium has no sidebar and won't move focus, so the focused window is faked.)
const onTab = id => sw.evaluate(async id => {
  chrome.windows.getLastFocused = async () => ({ type: 'normal', state: 'normal', left: 0, top: 0, width: 1200, height: 800,
    tabs: [{ id, active: true, width: 950 }] });
  return (await playerState()).show;
}, id);
assert.equal(await onTab(-1), true);
await sw.evaluate(() => playerAction({ action: 'close' }));
assert.equal(await onTab(-1), false);
assert.equal(await onTab(song), false); // on the music tab: never shown
assert.equal(await onTab(-1), true);
await close(song);
assert.equal(await sw.evaluate(id => music.has(id), song), false);
console.log('mini player: track info and buttons: ok');

// The helper's host role (if built: make build, or make install; ~/Applications/Monochrome.app, a
// release, otherwise) reads a message that arrives in pieces, stays up without the app half, and quits when Chrome closes
// the connection.
const builtApp = path.join(ext, 'build/Build/Products/Release/Monochrome.app');
const helperApp = fs.existsSync(builtApp) ? builtApp : path.join(os.homedir(), 'Applications/Monochrome.app');
const helperBinary = path.join(helperApp, 'Contents/MacOS/Monochrome');
if (fs.existsSync(helperBinary)) {
  const p = spawn(helperBinary, ['--host'], { stdio: ['pipe', 'ignore', 'inherit'],
    env: { ...process.env, MONOCHROME_SOCKET: path.join(profile, 'no.sock'), MONOCHROME_NO_LAUNCH: '1' } });
  const body = Buffer.from(JSON.stringify({ mru: [] }));
  const header = Buffer.alloc(4);
  header.writeUInt32LE(body.length);
  const frame = Buffer.concat([header, body]);
  p.stdin.write(frame.subarray(0, 2));
  await sleep(200);
  p.stdin.write(frame.subarray(2));
  await sleep(500);
  assert.equal(p.exitCode, null);
  p.stdin.end();
  assert.equal(await new Promise(r => p.on('exit', r)), 0);
  console.log('helper: host reads messages, quits with Chrome: ok');
} else console.log('helper: host: skipped (run make build)');

// The app's Safari readers (helper/Safari.swift), on given input: profile names from File → New Window's
// item titles, the 27.3 gate for vertical tabs, the sidebar pick, the profile envelope that goes to
// dispatchMessage, and the App Shortcuts written to a scratch domain (never Safari's own).
if (fs.existsSync(helperBinary)) {
  const check = async request => {
    const p = spawn(helperBinary, ['--check-safari', JSON.stringify(request)], { stdio: ['ignore', 'pipe', 'inherit'] });
    let out = '';
    p.stdout.on('data', d => { out += d; });
    const code = await new Promise(r => p.on('exit', r));
    return { code, result: out ? JSON.parse(out).result : undefined };
  };
  const strings = (await check({ op: 'strings' })).result;
  console.log(`safari: titles in use: "${strings.profileWindow}", "${strings.privateWindow}", Safari ${strings.version || 'not found'}`);
  const titles = ['New Personal Window', 'New Work (acme.com) Window', 'New Private Window', 'New Window', 'New Tab', 'New  Window', 'New Work (acme.com) Window'];
  assert.deepEqual((await check({ op: 'profiles', titles, format: 'New %@ Window', private: 'New Private Window' })).result, ['Personal', 'Work (acme.com)']);
  assert.deepEqual((await check({ op: 'profiles', titles: ['Nouvelle fenêtre Travail'], format: 'Nouvelle fenêtre %@', private: 'Nouvelle fenêtre privée' })).result, ['Travail']);
  assert.deepEqual((await check({ op: 'profiles', titles: ['New Personal Window'] })).result, ['Personal']); // Safari.framework's own format
  for (const [v, want] of [['27.2', false], ['27.3', true], ['27.10', true], ['28.0', true], ['26.4', false], ['', false]]) {
    assert.equal((await check({ op: 'version', version: v })).result, want, v);
  }
  const win = [100, 50, 1200, 800];
  const sidebar = { role: 'AXOutline', frame: [100, 102, 260, 748], tabs: 1 };
  assert.deepEqual((await check({ op: 'sidebar', window: win, candidates: [
    { role: 'AXScrollArea', frame: [100, 102, 260, 748], tabs: 1 }, sidebar, { role: 'AXGroup', frame: [360, 102, 940, 748], tabs: 0 },
  ] })).result, [100, 102, 260, 748]);
  assert.equal((await check({ op: 'sidebar', window: win, candidates: [{ ...sidebar, tabs: 0 }] })).result, null); // no tab items
  assert.equal((await check({ op: 'sidebar', window: win, candidates: [{ ...sidebar, frame: [1040, 102, 260, 748] }] })).result, null); // not at the left edge
  assert.equal((await check({ op: 'sidebar', window: win, candidates: [{ ...sidebar, frame: [100, 102, 260, 200] }] })).result, null); // too short
  assert.equal((await check({ op: 'sidebar', window: win, candidates: [] })).result, null);
  // A routed link for one Safari profile names it; the copy of the extension in that profile takes it.
  const wrapped = (await check({ op: 'wrap', profile: 'F00D-1', message: { open: 'https://example.com/', to: { window: 'same-site' } } })).result;
  assert.deepEqual(wrapped, { open: 'https://example.com/', to: { window: 'same-site' }, safariProfile: 'F00D-1' });
  assert.deepEqual((await check({ op: 'wrap', profile: '', message: { ping: true } })).result, { ping: true });
  assert.deepEqual(await sw.evaluate(w => [helperUnwrap({ name: 'monochrome', userInfo: w }, true, 'F00D-1')?.open ?? null,
    helperUnwrap({ name: 'monochrome', userInfo: w }, true, 'BEEF-2')], wrapped), ['https://example.com/', null]);
  // App Shortcuts, against a scratch domain; Safari's own is refused.
  assert.equal((await check({ op: 'shortcuts', domain: 'com.apple.Safari' })).code, 2);
  const domain = `com.artifact.monochrome.test-shortcuts-${process.pid}`;
  const plist = path.join(os.homedir(), 'Library/Preferences', `${domain}.plist`);
  try {
    const before = spawn('defaults', ['write', domain, 'NSUserKeyEquivalents', '-dict', 'Keep Me', '@k']);
    assert.equal(await new Promise(r => before.on('exit', r)), 0);
    const written = await check({ op: 'shortcuts', domain });
    assert.equal(written.result.written, true);
    const exported = spawn('sh', ['-c', `defaults export ${domain} - | plutil -convert json -o - -`], { stdio: ['ignore', 'pipe', 'inherit'] });
    let json = '';
    exported.stdout.on('data', d => { json += d; });
    await new Promise(r => exported.on('exit', r));
    const keys = JSON.parse(json).NSUserKeyEquivalents;
    assert.deepEqual(keys, { 'Keep Me': '@k', ...written.result.shortcuts });
    assert.deepEqual(Object.keys(written.result.shortcuts).sort(), ['Hide Sidebar', 'Save As…', 'Show Next Tab', 'Show Previous Tab', 'Show Sidebar']);
    assert.equal(keys['Show Next Tab'], '@~\uF701');
    assert.equal((await check({ op: 'shortcuts', domain })).result.written, true); // already in place: unchanged
  } finally {
    await new Promise(r => spawn('defaults', ['delete', domain], { stdio: 'ignore' }).on('exit', r));
    fs.rmSync(plist, { force: true });
  }
  console.log('safari: profile titles, vertical tab gate, sidebar pick, profile envelope, App Shortcuts: ok');
} else console.log('safari: app readers: skipped (run make build)');

await ctx.close();

// The app registers its own native messaging host (Install.swift): with the manifest it writes, a fresh
// Chromium's extension reaches the host, and the host reaches a socket standing in for the app.
if (fs.existsSync(helperBinary)) {
  const fresh = fs.mkdtempSync(path.join(os.tmpdir(), 'monochrome-host-test-'));
  const hosts = path.join(fresh, 'NativeMessagingHosts');
  const register = spawn(helperBinary, ['--register-host'], { stdio: 'inherit', env: { ...process.env, MONOCHROME_HOSTS: hosts } });
  assert.equal(await new Promise(r => register.on('exit', r)), 0);
  const manifest = JSON.parse(fs.readFileSync(path.join(hosts, 'monochrome_helper.json'), 'utf8'));
  assert.equal(manifest.path, path.join(helperApp, 'Contents/Resources/host.sh'));
  const id = idFromKey(JSON.parse(fs.readFileSync(path.join(ext, 'manifest.json'), 'utf8')).key);
  assert.ok(manifest.allowed_origins.includes(`chrome-extension://${id}/`));
  const sock = path.join(fresh, 'app.sock');
  const lines = [];
  const app = net.createServer(c => c.on('data', d => lines.push(...d.toString().split('\n').filter(Boolean)))).listen(sock);
  const ctx2 = await chromium.launchPersistentContext(fresh, {
    channel: 'chromium', headless: !process.env.HEADFUL,
    args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`],
    env: { ...process.env, MONOCHROME_SOCKET: sock, MONOCHROME_NO_LAUNCH: '1' },
  });
  for (let i = 0; i < 100 && !lines.length; i++) await sleep(100);
  assert.ok(lines.length, 'no message reached the app socket through the registered host');
  await ctx2.close();
  app.close();
  fs.rmSync(fresh, { recursive: true, force: true });
  console.log('helper: app-registered host connects the extension to the app: ok');
} else console.log('helper: registered host: skipped (run make build)');

server.close();
fs.rmSync(profile, { recursive: true, force: true });
