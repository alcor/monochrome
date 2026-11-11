// The fixture pages' server, for test-tldr.mjs and tldr/shots.mjs: three synthetic pages written for the
// tests (a news story, a recipe, a documentation page), their images drawn as SVG on request, and the
// frames their ad slots load. The pages reach it as 127.0.0.1; their ads use "localhost", the same
// server under another host name, so an ad's image is from another host as it would be on a real site.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const dir = import.meta.dirname;
const GIF = Buffer.from('R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==', 'base64');
export const FIXTURES = ['news', 'recipe', 'docs'];

function svg(name, w, h) {
  const hue = [...name].reduce((n, c) => (n * 31 + c.charCodeAt(0)) % 360, 7);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="hsl(${hue} 55% 62%)"/><stop offset="1" stop-color="hsl(${(hue + 40) % 360} 55% 38%)"/></linearGradient></defs>
<rect width="100%" height="100%" fill="url(#g)"/>
<text x="50%" y="50%" fill="#fff" font-family="Helvetica, Arial, sans-serif" font-size="${Math.max(12, Math.round(Math.min(w, h) / 8))}" text-anchor="middle" dominant-baseline="middle">${name}</text>
</svg>`;
}

// Listens on a free port; resolves to { base, other, close }.
export function serve() {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    const other = `http://localhost:${server.address().port}`;
    const name = url.pathname.slice(1);
    if (FIXTURES.includes(name)) {
      res.setHeader('content-type', 'text/html; charset=utf-8');
      return res.end(fs.readFileSync(path.join(dir, `${name}.html`), 'utf8').replaceAll('{{OTHER}}', other));
    }
    if (url.pathname.startsWith('/img/')) {
      const file = path.basename(url.pathname), w = +url.searchParams.get('w') || 600, h = +url.searchParams.get('h') || 400;
      if (file.endsWith('.gif')) { res.setHeader('content-type', 'image/gif'); return res.end(GIF); }
      res.setHeader('content-type', 'image/svg+xml');
      return res.end(svg(file.replace(/\.svg$/, ''), w, h));
    }
    if (url.pathname === '/short') { // a page with no article on it
      res.setHeader('content-type', 'text/html');
      return res.end('<title>Sign in</title><h1>Sign in</h1><form><input name="user"><button>Go</button></form><p>Forgot your password?</p>');
    }
    if (url.pathname === '/ad-frame' || url.pathname === '/tracker-widget') {
      res.setHeader('content-type', 'text/html');
      return res.end('<body style="margin:0;background:#ffe9a8;font:14px sans-serif">BUY NOW: an ad frame</body>');
    }
    res.statusCode = 404;
    res.end('not found');
  });
  return new Promise(resolve => server.listen(0, () => {
    const port = server.address().port;
    resolve({ base: `http://127.0.0.1:${port}`, other: `http://localhost:${port}`, close: () => server.close() });
  }));
}
