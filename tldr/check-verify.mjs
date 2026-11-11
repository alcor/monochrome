// Applies the extension's verification (tldr/core/verify.js) to what `Monochrome --check-tldr` printed,
// in Node, so the model path is checked without a browser:
//
//   Monochrome --check-tldr < request.json | node tldr/check-verify.mjs request.json [--min=3] [--forbid=WORD]
//
// request.json is a summarize request: { "title", "blocks": [{ "id", "kind", "text" }] }. Prints one line
// per bullet and fact (kept or dropped, with its anchor) and a JSON summary; exits 1 when fewer than
// --min bullets are kept, when a kept bullet or fact holds a --forbid word, or when the app sent an error.
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const file = args.find(a => !a.startsWith('--'));
const option = (name, fallback) => args.find(a => a.startsWith(`--${name}=`))?.slice(name.length + 3) ?? fallback;
if (!file) { console.error('usage: node tldr/check-verify.mjs request.json [--min=3] [--forbid=WORD] < pieces.jsonl'); process.exit(2); }

// verify.js is a plain script that hangs its functions on globalThis.__tldr; it touches no DOM.
(0, eval)(fs.readFileSync(path.join(import.meta.dirname, 'core/verify.js'), 'utf8'));
const { verifier } = globalThis.__tldr;

const request = JSON.parse(fs.readFileSync(file, 'utf8'));
const pieces = fs.readFileSync(0, 'utf8').split('\n').filter(Boolean).map(line => JSON.parse(line));
const check = verifier(request.blocks);
const forbid = option('forbid', '').toLowerCase();
const out = { model: null, bullets: 0, kept: 0, moved: 0, facts: 0, factsKept: 0, firstBulletMs: null, ms: null, error: null, forbidden: 0 };
const bad = text => forbid && text.toLowerCase().includes(forbid);

for (const piece of pieces) {
  if (piece.op === 'status') out.model = piece.model;
  if (piece.op === 'error') out.error = piece.code;
  if (piece.op === 'done') out.ms = piece.ms;
  if (piece.op === 'bullet') {
    out.bullets++;
    out.firstBulletMs ??= piece.at ?? null;
    const ok = check.bullet(piece);
    if (ok) { out.kept++; if (ok.anchor !== piece.anchor) out.moved++; if (bad(ok.text)) out.forbidden++; }
    console.log(`${ok ? 'kept   ' : 'dropped'} bullet [${piece.anchor}${ok && ok.anchor !== piece.anchor ? ` -> ${ok.anchor}` : ''}] ${piece.text}`);
  }
  if (piece.op === 'fact') {
    out.facts++;
    const ok = check.fact(piece);
    if (ok) { out.factsKept++; if (bad(`${ok.label} ${ok.value}`)) out.forbidden++; }
    console.log(`${ok ? 'kept   ' : 'dropped'} fact   [${piece.anchor}] ${piece.label}: ${piece.value}`);
  }
}
console.log(JSON.stringify(out));
process.exit(out.error || out.kept < +option('min', 3) || out.forbidden ? 1 : 0);
