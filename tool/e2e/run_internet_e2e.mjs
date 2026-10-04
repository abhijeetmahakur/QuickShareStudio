// Drives tool/e2e/internet_e2e.dart (built to build/e2e_web) in real Chrome.
//
//   cd tool/e2e && npm install && cd ../..
//   flutter build web --wasm -t tool/e2e/internet_e2e.dart -o build/e2e_web
//   node tool/e2e/run_internet_e2e.mjs [--scenarios=all] [--bigMb=500] [--two-instance]
//        [--turn=turn:127.0.0.1:3478 --turnUser=u --turnPass=p] [--chrome=path]
//
// Exits non-zero if any scenario fails.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const args = Object.fromEntries(process.argv.slice(2).map((a) => {
  const [k, v] = a.replace(/^--/, '').split('=');
  return [k, v ?? 'true'];
}));
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../build/e2e_web');
const chrome = args.chrome || process.env.CHROME_PATH ||
  (process.platform === 'win32' ? 'C:/Program Files/Google/Chrome/Application/chrome.exe' : '/usr/bin/google-chrome');

const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.css': 'text/css', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf' };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p === '/') p = '/index.html';
  const file = path.join(root, p);
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, {
      'Content-Type': types[path.extname(file)] || 'application/octet-stream',
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
    });
    res.end(data);
  });
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}/`;

async function launch(label) {
  const browser = await puppeteer.launch({ executablePath: chrome, headless: 'new', protocolTimeout: 0, args: ['--no-sandbox'] });
  const page = await browser.newPage();
  const lines = [];
  let resolveDone;
  const done = new Promise((r) => { resolveDone = r; });
  const waiters = [];
  page.on('console', (m) => {
    const text = m.text();
    if (!text.startsWith('E2E')) return;
    lines.push(text);
    console.log(`[${label}] ${text}`);
    if (text.startsWith('E2E DONE')) resolveDone(JSON.parse(text.slice('E2E DONE '.length)));
    for (const w of waiters) w(text);
  });
  page.on('pageerror', (e) => console.log(`[${label}] PAGE ERROR ${e.message}`));
  const waitFor = (prefix) => new Promise((r) => waiters.push((t) => t.startsWith(prefix) && r(t)));
  return { browser, page, lines, done, waitFor };
}

const query = (o) => Object.entries(o).filter(([, v]) => v !== undefined).map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join('&');
let results = [];
try {
  if (args['two-instance']) {
    // Two separate Chrome processes act as two devices.
    const recv = await launch('receiver');
    const send = await launch('sender');
    await recv.page.goto(`${base}?${query({ role: 'receiver' })}`);
    const codeLine = await recv.waitFor('E2E CODE');
    const code = codeLine.split(' ')[2];
    await send.page.goto(`${base}?${query({ role: 'sender', code, bigMb: args.bigMb || 50 })}`);
    results = [...(await recv.done), ...(await send.done)];
    const v1 = recv.lines.find((l) => l.startsWith('E2E VERIFY')), v2 = send.lines.find((l) => l.startsWith('E2E VERIFY'));
    console.log(`verification codes: receiver ${v1} / sender ${v2} -> ${v1 === v2 ? 'MATCH' : 'MISMATCH'}`);
    if (v1 !== v2) results.push({ name: 'two-instance-verify', ok: false, error: 'verification codes differ' });
    await recv.browser.close();
    await send.browser.close();
  } else {
    const run = await launch('page');
    await run.page.goto(`${base}?${query({ scenarios: args.scenarios || 'all', bigMb: args.bigMb, turn: args.turn, turnUser: args.turnUser, turnPass: args.turnPass })}`);
    results = await run.done;
    await run.browser.close();
  }
} finally {
  server.close();
}
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} scenarios passed`);
for (const f of failed) console.log(`FAILED ${f.name}: ${f.error}`);
process.exit(failed.length ? 1 : 0);
