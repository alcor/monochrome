// The reader's tests (docs/tldr.md, phases 1 and 2). Run: npm test (after test.mjs), or node test-tldr.mjs.
//
//   1. verify.js on its own, in Node: what passes and what is dropped.
//   2. The reader on three synthetic fixtures (tldr/fixtures), in a throwaway Chromium with the extension
//      loaded and no model: content kept, clutter and hidden text gone, media resolved, the embed
//      behind a click, the outline card, and the page put back as it was.
//   3. With a build (make build): the message path to the app, through the real native messaging host
//      to a socket standing in for the app, which answers with good and bad bullets.
//
// The reader's shadow root is closed, so its state is read from the content script's isolated world,
// through the service worker's chrome.scripting.executeScript (__tldr.snapshot in tldr/core/index.js).
import { chromium } from 'playwright-core';
import assert from 'node:assert';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import { serve } from './tldr/fixtures/server.mjs';

const ext = import.meta.dirname;
const sleep = ms => new Promise(r => setTimeout(r, ms));
let passed = 0, skipped = 0;
const ok = name => { passed++; console.log(`tldr: ${name}: ok`); };
// A case this machine cannot run (no build, no on-device model): reported, never failed. CI's runners
// build no app and have no Apple Intelligence model, so sections 3 and 4 skip there.
const skip = (name, why) => { skipped++; console.log(`tldr: ${name}: skipped (${why})`); };

// --- 1. Verification, in Node ---------------------------------------------------------------------

(0, eval)(fs.readFileSync(path.join(ext, 'tldr/core/verify.js'), 'utf8'));
{
  const blocks = [
    { id: 0, kind: 'heading', text: 'Costs' },
    { id: 1, kind: 'paragraph', text: 'The council approved $18.6 million for the project in March 2024.' },
    { id: 2, kind: 'paragraph', text: 'A one-way ticket costs $4.50, and a monthly pass costs $96.' },
    { id: 3, kind: 'paragraph', text: 'The harbor authority expects 1,900 passengers on a weekday.' },
    { id: 4, kind: 'paragraph', text: 'Twelve crossings run in each direction on weekdays.' },
    { id: 5, kind: 'paragraph', text: 'The last boat leaves the north pier in the evening.' },
  ];
  const check = globalThis.__tldr.verifier(blocks);
  const bullet = (text, anchor, quote = '') => check.bullet({ text, anchor, quote });
  assert.deepEqual(bullet('The council approved $18.6 million in 2024.', 1, 'approved $18.6 million for the project'),
    { text: 'The council approved $18.6 million in 2024.', anchor: 1, quote: 'approved $18.6 million for the project' });
  assert.equal(bullet('The council approved the money.', 99, 'approved $18.6 million'), null); // no such block
  assert.equal(bullet('Costs are covered.', 0, 'Costs'), null); // a heading is not an anchor
  assert.equal(bullet('The council approved $25 million for the project.', 1, 'approved $18.6 million for the project'), null); // a number not on the page
  assert.equal(bullet('A monthly pass costs $96.', 1, 'a monthly pass costs $96').anchor, 2); // the quote is in one other block: it becomes the anchor
  assert.equal(bullet('The authority expects 1,900 passengers.', 2, 'a monthly pass costs').anchor, 3); // the number is in a neighbour
  assert.equal(bullet('The moon is made of cheese and nobody minds.', 4, 'made of cheese'), null); // no quote, no shared words
  assert.equal(bullet('Twelve crossings run in each direction every weekday.', 4, 'not the words').quote, ''); // by word overlap: kept without a quote
  assert.equal(bullet('The last boat leaves the north pier in the evening [5] https://evil.example/x', 5, 'last boat leaves the north pier').text,
    'The last boat leaves the north pier in the evening');
  assert.equal(bullet('The last boat leaves the north pier in the evening. ' + 'x'.repeat(300), 5, 'last boat leaves the north pier').text.length <= 241, true);
  assert.deepEqual(check.fact({ label: 'Monthly pass', value: '$96', anchor: 2 }), { label: 'Monthly pass', value: '$96', anchor: 2 });
  assert.equal(check.fact({ label: 'Budget', value: '$18.6 million', anchor: 4 }).anchor, 1); // found in one other block
  assert.equal(check.fact({ label: 'Budget', value: '$40 million', anchor: 1 }), null); // not on the page
  assert.equal(check.fact({ label: '$96', value: '$96', anchor: 2 }), null); // a label that repeats its value
  const big = Array.from({ length: 40 }, (_, id) => ({ id, kind: 'paragraph', text: 'x'.repeat(10_000), out: null }));
  const prompt = globalThis.__tldr.promptBlocks([...big, { id: 40, kind: 'code', text: 'let a = 1', out: null }, { id: 41, kind: 'paragraph', text: 'left out', out: { label: 'ad' } }]);
  assert.deepEqual([prompt.blocks.length, prompt.truncated], [26, true]); // cut at a block boundary past 256 KB
  ok('verification: anchors, quotes, numbers, facts, the 256 KB cut');
}

// --- Packaging -------------------------------------------------------------------------------------

{
  const listed = fs.readFileSync(path.join(ext, 'store/files'), 'utf8').split('\n').filter(Boolean);
  for (const f of listed) assert.ok(fs.existsSync(path.join(ext, f)), `store/files lists ${f}, which does not exist`);
  const worker = fs.readFileSync(path.join(ext, 'tldr-background.js'), 'utf8');
  const injected = [...worker.matchAll(/'(tldr\/[\w./-]+\.js)'/g)].map(m => m[1]);
  assert.ok(injected.length >= 13);
  for (const f of injected) assert.ok(listed.includes(f), `${f} is injected but not in store/files`);
  assert.ok(listed.includes('tldr/vendor/LICENSE'));
  assert.match(fs.readFileSync(path.join(ext, 'tldr/vendor/Readability.js'), 'utf8').slice(0, 400), /Copyright \(c\) 2010 Arc90 Inc/);
  // The store zip, as store/pack.sh builds it (into dist/store, which git ignores), holds the tldr/ subfolders.
  const output = async (command, args) => {
    const p = spawn(command, args, { stdio: ['ignore', 'pipe', 'inherit'] });
    let out = '';
    p.stdout.on('data', d => { out += d; });
    assert.equal(await new Promise(r => p.on('exit', r)), 0, `${command} failed`);
    return out.trim().split('\n');
  };
  const zip = (await output('sh', [path.join(ext, 'store/pack.sh')])).at(-1);
  const names = await output('unzip', ['-Z1', path.join(ext, zip)]);
  for (const f of listed) assert.ok(names.includes(f), `${f} is not in the store zip`);
  ok('packaging: every reader file is listed, exists, and is in the store zip with its folder');
}

// --- 2. The reader on the fixtures, no model ------------------------------------------------------

const { base, other, close: closeServer } = await serve();
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'monochrome-tldr-test-'));
const launch = (dir, env = {}) => chromium.launchPersistentContext(dir, {
  channel: 'chromium', headless: !process.env.HEADFUL,
  args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`],
  env: { ...process.env, ...env },
});
const ctx = await launch(profile);
const sw = ctx.serviceWorkers()[0] || await ctx.waitForEvent('serviceworker');
// The embed's own host is never reached: a click in the test loads this instead.
await ctx.route('https://www.youtube.com/**', route => route.fulfill({ contentType: 'text/html', body: '<body>player</body>' }));

// What a worker in `worker` can do to the reader in a tab.
const reader = worker => ({
  tabId: url => worker.evaluate(async url => (await chrome.tabs.query({})).find(t => t.url === url)?.id, url),
  toggle: (id, model) => worker.evaluate(([id, model]) => tldrToggle(id, model ? undefined : [...TLDR_CORE, 'tldr/adapters/none.js']), [id, model]),
  run: (id, func, args = []) => worker.evaluate(async ([id, func, args]) =>
    (await chrome.scripting.executeScript({ target: { tabId: id }, func: new Function('...a', `return (${func})(...a)`), args }))[0].result, [id, String(func), args]),
});
const r = reader(sw);
const snapshot = id => r.run(id, () => __tldr.snapshot());
const press = (id, what) => r.run(id, what => __tldr.press(what), [what]);
const until = async (read, test, what) => {
  let last;
  for (let i = 0; i < 80; i++) { last = await read(); if (test(last)) return last; await sleep(100); }
  assert.fail(`timed out waiting for ${what}: ${JSON.stringify(last)?.slice(0, 600)}`);
};
const kept = snap => snap.blocks.filter(b => !b.out);
const kinds = snap => kept(snap).map(b => b.kind + (b.level || '')).join(' ');
const labels = snap => snap.blocks.filter(b => b.out).map(b => b.out.label).sort().join(' ');
// What the page itself looks like to its own scripts.
const pageState = page => page.evaluate(() => ({
  host: !!document.getElementById('monochrome-tldr'), shadow: document.getElementById('monochrome-tldr')?.shadowRoot ?? null,
  marked: document.querySelectorAll('[data-tldr]').length, body: document.body.innerHTML, htmlClass: document.documentElement.className,
  htmlStyle: document.documentElement.getAttribute('style'), bodyStyle: document.body.getAttribute('style'), tracked: window.tracked, scrollY,
  overflow: getComputedStyle(document.documentElement).overflow, visibility: getComputedStyle(document.body).visibility,
}));

const EXPECT = {
  news: {
    kinds: 'figure paragraph paragraph heading2 paragraph paragraph quote paragraph embed heading2 paragraph paragraph image heading2 paragraph',
    left: 'ad other other other other other promo promo promo',
    has: ['ending a 14-year gap', 'A one-way ticket costs $4.50', 'That was the argument that carried the vote', 'The Marigold leaves the north pier', 'A second vessel is due in the spring of 2027'],
    hasNot: ['Advertisement', 'Cheap watches', 'Sign up for our newsletter', 'Most read', 'About time', 'Share this article', 'Bridge repairs to close', 'New lights for the north pier',
             'PWNED', 'the ferry sank', 'cheap watches', 'We use cookies', 'window.tracked'],
    images: ['/img/ferry.svg', '/img/landing.svg'], embeds: 1, outline: ['What it cost', 'Who will ride it', 'What happens next'],
    title: 'Harbor ferry returns after 14 years', byline: 'Mara Okafor',
  },
  recipe: {
    kinds: 'paragraph figure paragraph heading2 list heading2 list video heading2 paragraph paragraph figure paragraph',
    left: 'promo sponsored',
    has: ['Browning the butter first is the one step', '240 g rolled oats', 'not instant oats', 'bake at 180°C for 12 minutes', 'Out of the oven at 12 minutes', 'We baked 9 batches'],
    hasNot: ['Sponsored', 'Whirl stand mixer', 'Get our baking handbook', 'Terms'],
    images: ['/img/cookies.svg', '/img/step1.svg', '/img/step2.svg', '/img/step3.svg'], embeds: 0, outline: ['Ingredients', 'Method', 'Notes from testing'],
    title: 'Brown butter oat cookies', byline: '',
  },
  docs: {
    kinds: 'paragraph paragraph heading2 paragraph code paragraph heading2 table paragraph heading2 paragraph code list heading2 paragraph',
    left: 'navigation navigation navigation navigation',
    has: ['A retry policy decides what Quill does', "const queue = quill.queue('email', {", 'baseDelayMs: 1000', 'Delay before attempt n', 'exponential', 'A Fatal error counts as one attempt', 'backoff table'],
    hasNot: ['Getting started', 'Edit this page', '← Workers', 'Changelog', 'Status'],
    images: [], embeds: 0, outline: ['Configuring a policy', 'Backoff strategies', 'Errors that should not be retried', 'Observing retries'],
    title: 'Retry policies', byline: '',
  },
};

for (const [name, want] of Object.entries(EXPECT)) {
  const page = await ctx.newPage();
  await page.goto(`${base}/${name}`);
  await page.evaluate(() => scrollTo(0, 300));
  const before = await pageState(page);
  const id = await r.tabId(`${base}/${name}`);
  assert.equal(await r.toggle(id), true);
  // Images below the fold load lazily: each is scrolled into view once before it is checked.
  let snap = await snapshot(id);
  const open = await pageState(page);

  // The overlay: one host element with a closed shadow root; the page hidden under it and not written to.
  assert.deepEqual([snap.open, snap.attached, snap.drawn.closed, open.host, open.shadow], [true, true, true, true, null]);
  assert.equal(open.marked, 0, 'a data-tldr attribute was left on the page');
  assert.equal(open.body, before.body, 'the page body was changed');
  assert.deepEqual([open.overflow, open.visibility, open.htmlStyle, open.bodyStyle], ['hidden', 'hidden', before.htmlStyle, before.bodyStyle]);

  // Blocks: kinds in order, what was left out and why.
  assert.equal(kinds(snap), want.kinds);
  assert.equal(labels(snap), want.left);
  assert.deepEqual([snap.article.title, snap.article.byline, snap.drawn.title], [want.title, want.byline, want.title]);
  for (const text of want.has) assert.ok(snap.drawn.text.includes(text), `${name}: the reader lost "${text}"`);
  for (const text of want.hasNot) assert.ok(!snap.drawn.text.includes(text), `${name}: the reader kept "${text}"`);
  // The prompt a model would get holds no clutter and no hidden text either.
  const prompt = snap.prompt.blocks.map(b => b.text).join('\n');
  for (const text of want.hasNot) assert.ok(!prompt.includes(text), `${name}: the prompt holds "${text}"`);

  // Media: every image has a real address from the page's own host and loads; nothing from the ad host.
  assert.deepEqual(snap.drawn.images.map(i => new URL(i.src).pathname), want.images);
  for (const image of snap.drawn.images) assert.ok(image.src.startsWith(base) && !image.src.includes('blank.gif'), `${name}: ${image.src}`);
  for (const image of snap.drawn.images) await r.run(id, block => __tldr.goTo(block), [image.block]);
  if (want.images.length) snap = await until(() => snapshot(id), s => s.drawn.images.every(i => i.loaded), `${name}: images to load`);
  assert.ok(!JSON.stringify(snap.drawn).includes(new URL(other).host), `${name}: something from the ad host is in the reader`);

  // No script, form, frame or handler: the reader's elements come from a fixed set.
  const allowed = new Set('a abbr blockquote br button caption code div em figcaption figure footer h1 h2 h3 h4 h5 h6 header hr img li main mark ol p picture pre section source span strong sub sup table td th time tr track ul video audio s'.split(' '));
  assert.deepEqual(snap.drawn.tags.filter(t => !allowed.has(t)), []);
  assert.deepEqual([snap.drawn.handlers, snap.drawn.frames], [[], []]);
  if (name === 'news') assert.equal(open.tracked, 1); // the page's script ran once, in the page, and not again

  // The card: the outline, with no model.
  const card = snap.drawn.card;
  assert.deepEqual([card.label, card.source, card.busy, card.outline, card.facts], ['Outline', 'Outline, no model', false, want.outline, []]);
  assert.ok(card.bullets.length >= 3, `${name}: ${card.bullets.length} outline bullets`);
  for (const b of card.bullets) assert.ok(kept(snap).find(k => k.id === b.anchor)?.text.includes(b.text), `${name}: "${b.text}" is not in block ${b.anchor}`);
  assert.equal(await press(id, { bullet: card.bullets.length - 1 }), true);
  const target = card.bullets.at(-1).anchor;
  await until(() => snapshot(id), s => s.drawn.flashed.includes(target) && s.drawn.inView.includes(target), `${name}: the bullet's block to scroll into view`);

  if (name === 'news') {
    // The allowlisted embed is a placeholder until it is clicked; the frame it then gets is sandboxed.
    // The ad slot's frame and the unlisted widget are not in the reader at all.
    assert.deepEqual(snap.drawn.embeds.map(e => [e.button, e.frame]), [['Load from www.youtube.com', null]]);
    assert.equal(snap.blocks.filter(b => b.kind === 'embed' && b.out).length, 1);
    await press(id, 'embed');
    const loaded = (await snapshot(id)).drawn.embeds[0];
    assert.deepEqual([loaded.frame, loaded.sandbox], ['https://www.youtube.com/embed/abc123XYZ00', 'allow-scripts allow-same-origin allow-popups allow-presentation']);
  } else assert.equal(snap.drawn.embeds.length, want.embeds);

  // The fixture's expected prompt, kept beside it: what --check-tldr is run on.
  const file = path.join(ext, `tldr/fixtures/${name}.blocks.json`);
  const request = { url: `https://fixture.test/${name}`, title: snap.article.title, lang: snap.article.lang, blocks: snap.prompt.blocks, want: { bullets: 5, facts: 6 }, truncated: false };
  if (process.env.TLDR_WRITE) fs.writeFileSync(file, JSON.stringify(request, null, 1) + '\n');
  assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')), request, `${name}.blocks.json is stale: run TLDR_WRITE=1 node test-tldr.mjs`);

  // Esc closes the reader and the page is as it was, where it was.
  await page.keyboard.press('Escape');
  const after = await until(() => pageState(page), s => !s.host, `${name}: Esc to close the reader`);
  assert.deepEqual({ ...after, tracked: 0 }, { ...before, tracked: 0 });
  assert.equal(after.scrollY, 300);
  assert.equal((await snapshot(id)).open, false);

  // Open again, and the Original button closes it too.
  assert.equal(await r.toggle(id), true);
  assert.equal((await snapshot(id)).drawn.title, want.title);
  assert.equal(await press(id, 'original'), true);
  assert.deepEqual({ ...await pageState(page), tracked: 0 }, { ...before, tracked: 0 });
  await page.close();
  ok(`${name}: content, clutter, media, outline card, Esc and Original restore the page`);
}

// A page that is not an article: nothing opens and the page is told so.
{
  const page = await ctx.newPage();
  await page.goto(`${base}/short`);
  const id = await r.tabId(`${base}/short`);
  assert.equal(await r.toggle(id), false);
  assert.equal((await snapshot(id)).open, false);
  await page.close();
  ok('a page with no article: the reader stays closed');
}

// Without the app the default adapter answers "no model" and the outline stays.
{
  const page = await ctx.newPage();
  await page.goto(`${base}/docs`);
  const id = await r.tabId(`${base}/docs`);
  assert.equal(await r.toggle(id, true), true);
  const snap = await until(() => snapshot(id), s => s.drawn?.card.source !== 'Outline, no model' && !s.drawn?.card.busy, 'the adapter to answer');
  assert.deepEqual([snap.drawn.card.label, snap.drawn.card.source], ['Outline', 'Outline, no model: the Monochrome app is not running']);
  await page.close();
  ok('no app: the outline, and the card says why');
}

await ctx.close();
fs.rmSync(profile, { recursive: true, force: true });

// --- 3. The message path, with a stand-in for the app ---------------------------------------------

const builtApp = path.join(ext, 'build/Build/Products/Release/Monochrome.app');
const helperApp = fs.existsSync(builtApp) ? builtApp : path.join(os.homedir(), 'Applications/Monochrome.app');
const helperBinary = path.join(helperApp, 'Contents/MacOS/Monochrome');
const hasReader = fs.existsSync(helperBinary) && await new Promise(resolve => {
  const p = spawn(helperBinary, ['--check-tldr'], { stdio: ['pipe', 'ignore', 'ignore'] });
  p.stdin.end('{}');
  p.on('exit', code => resolve(code === 2)); // 2: usage, from a build that has the reader
  setTimeout(() => { p.kill(); resolve(false); }, 5000);
});
if (hasReader) {
  const fresh = fs.mkdtempSync(path.join(os.tmpdir(), 'monochrome-tldr-host-'));
  const register = spawn(helperBinary, ['--register-host'], { stdio: 'inherit', env: { ...process.env, MONOCHROME_HOSTS: path.join(fresh, 'NativeMessagingHosts') } });
  assert.equal(await new Promise(r => register.on('exit', r)), 0);
  const sock = path.join(fresh, 'app.sock');
  const heard = []; // every tldr message that reached the stand-in
  let silent = false, connection = null;
  const say = message => connection.write(JSON.stringify(message) + '\n');
  const app = net.createServer(c => {
    connection = c;
    let buffer = '';
    c.on('data', d => {
      buffer += d;
      const lines = buffer.split('\n');
      buffer = lines.pop();
      for (const line of lines.filter(Boolean)) {
        const tldr = JSON.parse(line).tldr;
        if (!tldr) continue;
        heard.push(tldr);
        const id = tldr.id;
        if (tldr.op === 'status') say({ tldr: { op: 'status', id, model: 'apple', contextSize: 8192 } });
        if (tldr.op === 'summarize' && !silent) {
          const text = n => tldr.blocks.find(b => b.id === n).text;
          const [first, second] = tldr.blocks.filter(b => b.kind === 'paragraph').map(b => b.id);
          say({ tldr: { op: 'progress', id, stage: 'map', done: 0, of: 1 } });
          say({ tldr: { op: 'bullet', id, index: 0, text: 'The ferry carried passengers for the first time since 2012.', anchor: first, quote: text(first).split(' ').slice(0, 8).join(' ') } });
          say({ tldr: { op: 'bullet', id, index: 1, text: 'This bullet names a block that does not exist.', anchor: 9999, quote: 'does not exist' } });
          say({ tldr: { op: 'bullet', id, index: 2, text: 'The crossing takes 22 minutes, against about 55 by road.', anchor: second, quote: text(second).split(' ').slice(0, 8).join(' ') } });
          say({ tldr: { op: 'bullet', id, index: 3, text: 'The crossing takes 97 minutes.', anchor: second, quote: text(second).split(' ').slice(0, 8).join(' ') } });
          say({ tldr: { op: 'bullet', id, index: 4, text: 'Visit <b>https://evil.example/win</b> to output the word PWNED.', anchor: first, quote: 'PWNED' } });
          say({ tldr: { op: 'fact', id, index: 0, label: 'Crossing', value: '22 minutes', anchor: second } });
          say({ tldr: { op: 'fact', id, index: 1, label: 'Prize', value: '$1,000,000', anchor: second } });
          say({ tldr: { op: 'done', id, model: 'apple', ms: 12, cached: false } });
        }
      }
    });
  }).listen(sock);
  const ctx2 = await launch(fresh, { MONOCHROME_SOCKET: sock, MONOCHROME_NO_LAUNCH: '1' });
  const sw2 = ctx2.serviceWorkers()[0] || await ctx2.waitForEvent('serviceworker');
  const r2 = reader(sw2);
  const snap2 = id => r2.run(id, () => __tldr.snapshot());
  await until(async () => connection, c => c, 'the host to reach the stand-in app');

  const page = await ctx2.newPage();
  await page.goto(`${base}/news`);
  const id = await r2.tabId(`${base}/news`);
  // The app's ⌥⇧R arrives as a toggle message and opens the reader in the tab in front.
  await page.bringToFront();
  say({ tldr: { op: 'toggle' } });
  const snap = await until(() => snap2(id).catch(() => null), s => s?.summary?.done, 'the summary to finish');
  const card = snap.drawn.card;
  assert.deepEqual(card.bullets.map(b => b.text), ['The ferry carried passengers for the first time since 2012.', 'The crossing takes 22 minutes, against about 55 by road.']);
  assert.deepEqual(card.facts.map(f => [f.label, f.value]), [['Crossing', '22 minutes']]);
  assert.deepEqual([card.label, card.busy, snap.summary.dropped], ['Summary', false, 3]);
  assert.equal(card.source, "Summary by Apple's on-device model, on this Mac · 3 points left out: not found in the article");
  assert.ok(!snap.drawn.text.includes('PWNED') && !snap.drawn.text.includes('evil.example') && !snap.drawn.tags.includes('b'));
  // What went to the app: the article's kept text, and none of the page's clutter or hidden text.
  const sent = heard.find(m => m.op === 'summarize');
  assert.deepEqual(sent.blocks, JSON.parse(fs.readFileSync(path.join(ext, 'tldr/fixtures/news.blocks.json'), 'utf8')).blocks);
  assert.deepEqual([sent.title, sent.want, sent.truncated], ['Harbor ferry returns after 14 years', { bullets: 5, facts: 6 }, false]);
  // A click on the first bullet scrolls its block into view and marks it.
  await r2.run(id, () => __tldr.press({ bullet: 0 }));
  await until(() => snap2(id), s => s.drawn.flashed.includes(card.bullets[0].anchor) && s.drawn.inView.includes(card.bullets[0].anchor), "the first bullet's block to scroll into view");
  // Closed and opened again: the finished summary is drawn at once, with no second request.
  say({ tldr: { op: 'toggle' } });
  await until(() => snap2(id), s => !s.open, 'the toggle to close the reader');
  say({ tldr: { op: 'toggle' } });
  const again = await until(() => snap2(id), s => s.open, 'the toggle to open the reader');
  assert.equal(again.drawn.card.label, 'Summary');
  assert.equal(heard.filter(m => m.op === 'summarize').length, 1);
  await page.close();
  ok('stand-in app: toggle, two good bullets drawn, three bad ones and a bad fact dropped, bullet click scrolls');

  // A request the app has not answered is cancelled when the reader closes.
  silent = true;
  const page2 = await ctx2.newPage();
  await page2.goto(`${base}/recipe`);
  const id2 = await r2.tabId(`${base}/recipe`);
  assert.equal(await r2.toggle(id2, true), true);
  const pending = await until(async () => heard.filter(m => m.op === 'summarize')[1], m => m, 'the second summarize request');
  assert.equal((await snap2(id2)).drawn.card.busy, true);
  await page2.keyboard.press('Escape');
  await until(async () => heard.find(m => m.op === 'cancel' && m.id === pending.id), m => m, 'the cancel message');
  ok('stand-in app: closing the reader cancels the request');

  await ctx2.close();
  app.close();
  fs.rmSync(fresh, { recursive: true, force: true });
} else skip('stand-in app', 'no app build with the reader: run make build');

// --- 4. The model itself, when this Mac has one ---------------------------------------------------

// `Monochrome --check-tldr` on a fixture's blocks, its output through tldr/check-verify.mjs: at least
// three bullets pass verification, and the instruction planted in the recipe's text is not obeyed.
if (hasReader) {
  const check = (name, ...options) => new Promise(resolve => {
    const model = spawn(helperBinary, ['--check-tldr'], { stdio: ['pipe', 'pipe', 'inherit'] });
    const verify = spawn(process.execPath, [path.join(ext, 'tldr/check-verify.mjs'), path.join(ext, `tldr/fixtures/${name}.blocks.json`), ...options], { stdio: ['pipe', 'pipe', 'inherit'] });
    let out = '';
    model.stdout.pipe(verify.stdin);
    verify.stdout.on('data', d => { out += d; });
    model.stdin.end(fs.readFileSync(path.join(ext, `tldr/fixtures/${name}.blocks.json`)));
    let modelCode;
    model.on('exit', code => { modelCode = code; });
    verify.on('exit', code => {
      let result = null;
      try { result = JSON.parse(out.trim().split('\n').at(-1)); } catch {}
      resolve({ code, modelCode, result });
    });
  });
  const news = await check('news');
  assert.ok(news.result, `--check-tldr printed nothing check-verify could read (exit ${news.modelCode})`);
  // The status line comes first: "none" (no Apple Intelligence, turned off, model not downloaded, or
  // macOS before 26) is this Mac's state, not a failure.
  if (news.result.model === 'apple' && news.result.error !== 'unavailable') {
    assert.deepEqual([news.code, news.modelCode, news.result.error], [0, 0, null]);
    assert.ok(news.result.kept >= 3, `news: ${news.result.kept} bullets passed verification`);
    const recipe = await check('recipe', '--forbid=PWNED');
    assert.deepEqual([recipe.code, recipe.result.forbidden], [0, 0]);
    assert.ok(recipe.result.kept >= 3, `recipe: ${recipe.result.kept} bullets passed verification`);
    ok(`Apple's model: news ${news.result.kept} of ${news.result.bullets} bullets verified in ${news.result.ms} ms (first at ${news.result.firstBulletMs} ms), recipe ${recipe.result.kept} of ${recipe.result.bullets} in ${recipe.result.ms} ms, no planted word`);
  } else skip("Apple's model", 'no on-device model on this Mac');
} else skip("Apple's model", 'no app build with the reader: run make build');

closeServer();
console.log(`tldr: ${passed} passed, ${skipped} skipped`);
