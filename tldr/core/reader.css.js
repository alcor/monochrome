// The reader's stylesheet, as a string for a constructed sheet in the shadow root (render.js). Sizes
// are in em from a pixel size set on .reader: rem would follow the page's own root font size.
(() => {
  const T = globalThis.__tldr ??= {};
  T.css = `
:host { all: initial; position: fixed; inset: 0; z-index: 2147483647; display: block; color-scheme: light dark; }
.reader {
  --paper: #fbfaf8; --ink: #1d1d1f; --soft: #6e6e73; --line: #e2e0db; --card: #ffffff; --accent: #0a5fd8; --mark: #ffe89a; --code: #f2f0eb;
  position: absolute; inset: 0; overflow-y: auto; overflow-x: hidden; overscroll-behavior: contain; background: var(--paper); color: var(--ink);
  font: 18px/1.6 ui-serif, "New York", "Iowan Old Style", Charter, Georgia, serif; -webkit-font-smoothing: antialiased; text-size-adjust: 100%;
  outline: none; scroll-padding-top: 4em;
}
@media (prefers-color-scheme: dark) {
  .reader { --paper: #1c1c1e; --ink: #ececee; --soft: #9a9aa0; --line: #38383c; --card: #26262a; --accent: #6eb0ff; --mark: #6b5a16; --code: #2a2a2e; }
}
* { box-sizing: border-box; }
.bar { position: sticky; top: 0; z-index: 2; display: flex; justify-content: flex-end; padding: 0.6em 0.8em; pointer-events: none; }
.bar button { pointer-events: auto; }
button { font: inherit; color: inherit; background: none; border: 0; padding: 0; margin: 0; cursor: pointer; text-align: inherit; }
.original, .load, .more { font: 500 0.72em/1 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; padding: 0.7em 1em;
  border-radius: 999px; background: var(--card); border: 1px solid var(--line); color: var(--ink); box-shadow: 0 1px 6px rgba(0,0,0,.08); }
.original:hover, .load:hover, .more:hover { border-color: var(--soft); }
button:focus-visible, a:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.page { max-width: 900px; margin: 0 auto; padding: 0 1.25em 5em; }
.page > * { max-width: 680px; margin-left: auto; margin-right: auto; }
.page > figure, .page > .embed, .page > video, .page > .wide { max-width: 900px; }
header { margin-top: 0.5em; }
h1 { font: 700 2em/1.15 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; letter-spacing: -0.015em; margin: 0 0 0.4em; text-wrap: balance; }
.meta { font: 0.78em/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; color: var(--soft); margin: 0 0 1.6em; }
.meta span + span::before { content: " · "; }
h2, h3, h4, h5, h6 { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; line-height: 1.25; margin: 1.8em auto 0.5em; text-wrap: balance; }
h2 { font-size: 1.4em; } h3 { font-size: 1.15em; } h4, h5, h6 { font-size: 1em; }
p, ul, ol, blockquote, pre, table, figure, hr { margin-top: 0; margin-bottom: 1.1em; }
a { color: var(--accent); text-decoration: underline; text-decoration-thickness: 1px; text-underline-offset: 2px; overflow-wrap: anywhere; }
ul, ol { padding-left: 1.4em; }
li { margin: 0.25em 0; }
li.term { list-style: none; font-weight: 600; margin-left: -1.4em; }
li[data-level="1"] { margin-left: 1.4em; } li[data-level="2"] { margin-left: 2.8em; } li[data-level="3"] { margin-left: 4.2em; }
blockquote { margin-left: auto; margin-right: auto; padding: 0.1em 0 0.1em 1em; border-left: 3px solid var(--line); color: var(--soft); font-style: italic; }
code, pre { font: 0.82em/1.5 ui-monospace, "SF Mono", Menlo, Consolas, monospace; }
code { background: var(--code); padding: 0.1em 0.3em; border-radius: 4px; }
pre { background: var(--code); padding: 0.9em 1em; border-radius: 8px; overflow-x: auto; white-space: pre; tab-size: 2; }
pre code { background: none; padding: 0; font-size: 1em; }
.table { overflow-x: auto; margin-bottom: 1.1em; }
table { border-collapse: collapse; font: 0.82em/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; margin-bottom: 0; }
caption { caption-side: top; text-align: left; color: var(--soft); padding-bottom: 0.4em; }
th, td { border: 1px solid var(--line); padding: 0.4em 0.7em; text-align: left; vertical-align: top; }
th { background: var(--code); font-weight: 600; }
figure { margin-left: auto; margin-right: auto; text-align: center; }
figure .items { display: flex; flex-direction: column; gap: 0.6em; align-items: center; }
figure.gallery .items { flex-direction: row; flex-wrap: wrap; justify-content: center; align-items: flex-start; }
figure.gallery .items > * { flex: 1 1 180px; min-width: 0; max-width: 440px; }
figure.gallery img { width: 100%; }
sup, sub { font-size: 0.7em; line-height: 0; }
img, video { max-width: 100%; height: auto; border-radius: 6px; }
video { display: block; width: 100%; max-height: 80vh; background: #000; }
figure img, .page > img { display: block; margin: 0 auto; }
p img { vertical-align: middle; }
audio { width: 100%; }
figcaption { font: 0.76em/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; color: var(--soft); margin: 0.6em auto 0; max-width: 680px; text-align: left; }
hr { border: 0; border-top: 1px solid var(--line); margin: 2em auto; }
mark { background: var(--mark); color: inherit; }
.embed { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 0.8em; aspect-ratio: 16 / 9; width: 100%;
  margin-bottom: 1.1em; border: 1px solid var(--line); border-radius: 10px; background: var(--card); padding: 1em; text-align: center; }
.embed.loaded { padding: 0; border: 0; background: none; }
.embed iframe { width: 100%; height: 100%; border: 0; border-radius: 10px; }
.embed .host { font: 0.76em/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; color: var(--soft); overflow-wrap: anywhere; }
.card { font: 0.86em/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; background: var(--card); border: 1px solid var(--line);
  border-radius: 14px; padding: 1.1em 1.25em 0.9em; margin-bottom: 2em; position: relative; overflow: hidden; }
.card .label { font-size: 0.74em; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; color: var(--soft); margin: 0 0 0.6em; }
.card ul { list-style: none; padding: 0; margin: 0 0 0.8em; }
.card li { margin: 0; }
.bullet { display: block; width: 100%; padding: 0.35em 0 0.35em 1.1em; position: relative; border-radius: 6px; }
.bullet::before { content: ""; position: absolute; left: 0.15em; top: 0.95em; width: 0.38em; height: 0.38em; border-radius: 50%; background: var(--accent); }
.bullet:hover { color: var(--accent); }
.facts { display: grid; grid-template-columns: max-content 1fr; gap: 0.2em 1em; margin: 0 0 0.8em; padding-top: 0.7em; border-top: 1px solid var(--line); }
.facts button { display: contents; }
.facts .k { color: var(--soft); } .facts .v { font-weight: 600; }
.outline { margin: 0 0 0.8em; padding-top: 0.7em; border-top: 1px solid var(--line); display: flex; flex-wrap: wrap; gap: 0.2em 1.1em; }
.outline button { color: var(--accent); }
.source { font-size: 0.82em; color: var(--soft); margin: 0; }
.progress { position: absolute; left: 0; right: 0; bottom: 0; height: 2px; background: linear-gradient(90deg, transparent, var(--accent), transparent);
  background-size: 40% 100%; background-repeat: no-repeat; animation: slide 1.2s linear infinite; }
.progress[hidden] { display: none; }
@keyframes slide { from { background-position: -40% 0; } to { background-position: 140% 0; } }
@media (prefers-reduced-motion: reduce) { .progress { animation: none; background-size: 100% 100%; opacity: .5; } }
[data-block] { scroll-margin-top: 4em; }
.flash { animation: flash 2s ease-out; border-radius: 4px; }
@keyframes flash { from { background: var(--mark); box-shadow: 0 0 0 0.3em var(--mark); } to { background: transparent; box-shadow: 0 0 0 0.3em transparent; } }
::highlight(tldr-quote) { background: var(--mark); color: inherit; }
.left { font: 0.78em/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; color: var(--soft); margin-top: 3em; padding-top: 1em; border-top: 1px solid var(--line); }
.left button { text-decoration: underline; text-underline-offset: 2px; }
.left ul { list-style: none; padding: 0; margin: 0.5em 0 0; }
.notice { position: absolute; top: 16px; right: 16px; font: 13px/1.3 -apple-system, BlinkMacSystemFont, sans-serif; padding: 10px 14px; border-radius: 10px;
  background: rgba(32,32,36,.92); color: #fff; box-shadow: 0 6px 24px rgba(0,0,0,.3); }
@media (max-width: 600px) {
  .reader { font-size: 17px; }
  h1 { font-size: 1.6em; }
  .page { padding: 0 1.1em 4em; }
  .facts { grid-template-columns: 1fr; gap: 0; } .facts .v { margin-bottom: 0.4em; }
}
`;
})();
