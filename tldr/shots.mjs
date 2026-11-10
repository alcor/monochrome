// Screenshots of the reader, for looking at: node tldr/shots.mjs <out-dir> [url ...]
//
// Loads the extension into a throwaway Chromium (the Playwright one, as the tests do), opens each
// fixture and each given address, opens the reader, and saves PNGs at 1280x800 and 390x844, light and
// dark, and further down each page in light: at two fractions of its length and at its first embed,
// table and video. With a build (make build) the summary is the real one: a socket stands in for the app and
// answers each summarize request by running `Monochrome --check-tldr` on it, so the app is not
// launched. Without a build the card is the outline.
import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import { serve, FIXTURES } from './fixtures/server.mjs';

const ext = path.dirname(import.meta.dirname);
const [out, ...urls] = process.argv.slice(2);
if (!out) { console.error('usage: node tldr/shots.mjs <out-dir> [url ...]'); process.exit(2); }
fs.mkdirSync(out, { recursive: true });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const binary = path.join(ext, 'build/Build/Products/Release/Monochrome.app/Contents/MacOS/Monochrome');
const { base, close } = await serve();
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'monochrome-tldr-shots-'));
const env = { ...process.env };

let app = null;
if (fs.existsSync(binary)) {
  const register = spawn(binary, ['--register-host'], { stdio: 'inherit', env: { ...process.env, MONOCHROME_HOSTS: path.join(profile, 'NativeMessagingHosts') } });
  await new Promise(r => register.on('exit', r));
  env.MONOCHROME_SOCKET = path.join(profile, 'app.sock');
  env.MONOCHROME_NO_LAUNCH = '1';
  app = net.createServer(c => {
    let buffer = '';
    const say = message => c.write(JSON.stringify(message) + '\n');
    c.on('data', d => {
      buffer += d;
      const lines = buffer.split('\n');
      buffer = lines.pop();
      for (const line of lines.filter(Boolean)) {
        const tldr = JSON.parse(line).tldr;
        if (tldr?.op !== 'status' && tldr?.op !== 'summarize') continue;
        const check = spawn(binary, ['--check-tldr'], { stdio: ['pipe', 'pipe', 'inherit'] });
        let pending = '';
        check.stdout.on('data', d => {
          pending += d;
          const pieces = pending.split('\n');
          pending = pieces.pop();
          for (const piece of pieces.filter(Boolean).map(p => JSON.parse(p))) {
            if ((piece.op === 'status') === (tldr.op === 'status')) say({ tldr: { ...piece, id: tldr.id } });
          }
        });
        check.stdin.end(JSON.stringify(tldr.op === 'status' ? { blocks: [] } : tldr));
      }
    });
  }).listen(env.MONOCHROME_SOCKET);
}

const ctx = await chromium.launchPersistentContext(profile, {
  channel: 'chromium', headless: true, env, args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`],
});
const sw = ctx.serviceWorkers()[0] || await ctx.waitForEvent('serviceworker');
const inTab = (id, func, args = []) => sw.evaluate(async ([id, func, args]) =>
  (await chrome.scripting.executeScript({ target: { tabId: id }, func: new Function('...a', `return (${func})(...a)`), args }))[0].result, [id, String(func), args]);

const pages = [...FIXTURES.map(name => [name, `${base}/${name}`]), ...urls.map(url => [new URL(url).hostname.replace(/^www\./, '').replace(/\W+/g, '-'), url])];
for (const [name, url] of pages) {
  const page = await ctx.newPage();
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto(url, { waitUntil: 'load' });
  const id = await sw.evaluate(async url => (await chrome.tabs.query({})).find(t => t.url === url)?.id, page.url());
  const opened = await sw.evaluate(id => tldrToggle(id), id);
  if (!opened) { console.log(`${name}: the reader did not open`); await page.close(); continue; }
  // Wait for the summary, or for the card to say why there is none.
  let snap;
  for (let i = 0; i < 900; i++) {
    snap = await inTab(id, () => __tldr.snapshot());
    if (!snap.drawn.card.busy && (snap.summary?.done || snap.drawn.card.source !== 'Outline, no model')) break;
    await sleep(100);
  }
  const left = snap.blocks.filter(b => b.out).length;
  console.log(`${name}: ${snap.blocks.length - left} blocks, ${left} left out, card "${snap.drawn.card.label}" with ${snap.drawn.card.bullets.length} bullets and ${snap.drawn.card.facts.length} facts: ${snap.drawn.card.source}`);
  for (const [size, width, height] of [['1280x800', 1280, 800], ['390x844', 390, 844]]) {
    // Closed and opened again at each size: Chromium's video controls keep the width they were first
    // laid out at. The finished summary is kept in the page, so this asks the model nothing.
    await page.setViewportSize({ width, height });
    await sw.evaluate(id => tldrToggle(id), id);
    await sw.evaluate(id => tldrToggle(id), id);
    for (const scheme of ['light', 'dark']) {
      await page.emulateMedia({ colorScheme: scheme });
      await inTab(id, () => __tldr.scrollTo(0));
      await sleep(400);
      const file = path.join(out, `${name}-${size}-${scheme}.png`);
      await page.screenshot({ path: file });
      console.log(file);
      if (scheme !== 'light') continue;
      // The same reader further down, where the media is: by fractions of its length.
      for (const [label, at] of [['mid', 0.4], ['end', 1]]) {
        await inTab(id, at => __tldr.scrollTo(at), [at]);
        await sleep(700);
        const more = path.join(out, `${name}-${size}-${scheme}-${label}.png`);
        await page.screenshot({ path: more });
        console.log(more);
      }
      // And at the first embed, table and video, which the fractions can miss.
      for (const kind of ['embed', 'table', 'video']) {
        const block = snap.blocks.find(b => !b.out && b.kind === kind);
        if (!block) continue;
        await inTab(id, block => __tldr.goTo(block), [block.id]);
        await sleep(900);
        const more = path.join(out, `${name}-${size}-${scheme}-${kind}.png`);
        await page.screenshot({ path: more });
        console.log(more);
      }
    }
  }
  await page.close();
}
await ctx.close();
app?.close();
close();
fs.rmSync(profile, { recursive: true, force: true });
