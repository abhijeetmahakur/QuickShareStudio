// Proves internet transfers on the native Linux app: pairs the Linux build of
// tool/e2e/internet_e2e.dart (flutter build linux -t tool/e2e/internet_e2e.dart) with the same
// harness running in real Chrome, over PeerJS Cloud signaling + WebRTC, in both directions with
// a real PDF (and again through a TURN relay), then runs every single-page scenario inside the
// Linux app so both ends use the Linux WebRTC stack (resume, retry, interruption, checksums).
//
//   xvfb-run -a node tool/e2e/run_linux_e2e.mjs --linux=<bundle>/quickshare --pdf=<file.pdf>
//        [--turn=turn:127.0.0.1:3478 --turnUser=e2e --turnPass=e2e-secret]
//        [--chrome=/usr/bin/google-chrome] [--log=linux-e2e.log]
//
// Exits non-zero if any scenario fails. Every line is also written to --log.
import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const args = Object.fromEntries(process.argv.slice(2).map((a) => {
  const i = a.indexOf('=');
  return i < 0 ? [a.replace(/^--/, ''), 'true'] : [a.slice(2, i), a.slice(i + 1)];
}));
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../build/e2e_web');
const chrome = args.chrome || process.env.CHROME_PATH || '/usr/bin/google-chrome';
const linuxApp = path.resolve(args.linux);
const pdfPath = path.resolve(args.pdf);
const pdfName = path.basename(pdfPath);
const pdfBytes = fs.readFileSync(pdfPath);
const pdfSha = crypto.createHash('sha256').update(pdfBytes).digest('hex');
const logFile = args.log ? fs.createWriteStream(args.log) : null;
const turn = args.turn ? { turn: args.turn, turnUser: args.turnUser, turnPass: args.turnPass } : null;

function log(line) {
  const stamped = `${new Date().toISOString()} ${line}`;
  console.log(stamped);
  logFile?.write(stamped + '\n');
}

const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.css': 'text/css', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf', '.pdf': 'application/pdf' };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p === '/') p = '/index.html';
  const file = p === `/${pdfName}` ? pdfPath : path.join(root, p);
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, {
      'Content-Type': types[path.extname(file)] || 'application/octet-stream',
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
      'Cross-Origin-Resource-Policy': 'cross-origin',
    });
    res.end(data);
  });
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}/`;
const fileUrl = `${base}${pdfName}`;
log(`Test file ${pdfName}: ${pdfBytes.length} bytes, sha256 ${pdfSha}`);

/** Collects the harness's "E2E ..." lines from a page or a process. */
function harness(label) {
  const lines = [];
  const waiters = [];
  let resolveDone;
  const done = new Promise((r) => { resolveDone = r; });
  const onLine = (raw) => {
    const at = raw.indexOf('E2E ');
    if (at < 0) return;
    const text = raw.slice(at).trim();
    lines.push(text);
    log(`[${label}] ${text}`);
    if (text.startsWith('E2E DONE ')) resolveDone(JSON.parse(text.slice('E2E DONE '.length)));
    for (const w of waiters) w(text);
  };
  const waitFor = (prefix, ms = 120000) => new Promise((resolve, reject) => {
    const hit = lines.find((l) => l.startsWith(prefix));
    if (hit) return resolve(hit);
    const t = setTimeout(() => reject(new Error(`${label}: no "${prefix}" within ${ms / 1000}s`)), ms);
    waiters.push((l) => { if (l.startsWith(prefix)) { clearTimeout(t); resolve(l); } });
  });
  return { lines, done, waitFor, onLine };
}

async function launchChrome(label, query) {
  const h = harness(label);
  const browser = await puppeteer.launch({ executablePath: chrome, headless: 'new', protocolTimeout: 0, args: ['--no-sandbox'] });
  const page = await browser.newPage();
  page.on('console', (m) => h.onLine(m.text()));
  page.on('pageerror', (e) => log(`[${label}] PAGE ERROR ${e.message}`));
  await page.goto(`${base}?${new URLSearchParams(query)}`);
  return { ...h, close: () => browser.close() };
}

function launchLinux(label, params) {
  const h = harness(label);
  const argv = Object.entries(params).filter(([, v]) => v !== undefined).map(([k, v]) => `--${k}=${v}`);
  log(`[${label}] start ${linuxApp} ${argv.join(' ')}`);
  const child = spawn(linuxApp, argv, { env: { ...process.env, QUICKSHARE_ALLOW_MULTIPLE: '1' } });
  let buffer = '';
  const feed = (chunk) => {
    buffer += chunk.toString();
    let nl;
    while ((nl = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, nl);
      buffer = buffer.slice(nl + 1);
      h.onLine(line);
    }
  };
  child.stdout.on('data', feed);
  child.stderr.on('data', feed);
  child.on('exit', (code, signal) => log(`[${label}] exited (${code ?? signal})`));
  return { ...h, close: () => { child.kill('SIGTERM'); } };
}

const results = [];
function record(name, ok, note) {
  results.push({ name, ok, note });
  log(`${ok ? 'PASS' : 'FAIL'} ${name}: ${note}`);
}

const withTimeout = (p, ms, what) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error(`${what} timed out`)), ms))]);

/** One transfer of the PDF between a receiver and a sender, checked end to end. */
async function transfer(name, receiverOn, senderOn, extra = {}) {
  let receiver;
  let sender;
  try {
    receiver = receiverOn === 'linux'
      ? launchLinux(`${name}/linux-receiver`, { role: 'receiver', ...extra })
      : await launchChrome(`${name}/chrome-receiver`, { role: 'receiver', ...extra });
    const code = (await receiver.waitFor('E2E CODE')).split(' ')[2];
    const senderParams = { role: 'sender', code, fileUrl, ...extra };
    sender = senderOn === 'linux'
      ? launchLinux(`${name}/linux-sender`, senderParams)
      : await launchChrome(`${name}/chrome-sender`, senderParams);
    const [recvResults, sendResults] = await withTimeout(Promise.all([receiver.done, sender.done]), 10 * 60 * 1000, name);
    const failed = [...recvResults, ...sendResults].filter((r) => !r.ok);
    const received = receiver.lines.find((l) => l.startsWith('E2E RECEIVED'))?.split(' ') ?? [];
    const verifyR = receiver.lines.find((l) => l.startsWith('E2E VERIFY'));
    const verifyS = sender.lines.find((l) => l.startsWith('E2E VERIFY'));
    const relayed = receiver.lines.find((l) => l.startsWith('E2E PATH')) ?? '';
    const problems = [
      ...failed.map((f) => `${f.name}: ${f.error}`),
      received[2] !== pdfName ? `received name ${received[2]}` : null,
      Number(received[3]) !== pdfBytes.length ? `received ${received[3]} bytes, expected ${pdfBytes.length}` : null,
      received[4] !== pdfSha ? `received sha256 ${received[4]}, expected ${pdfSha}` : null,
      verifyR !== verifyS ? `verification codes differ (${verifyR} / ${verifyS})` : null,
      extra.forceRelay && !relayed.includes('relayed=true') ? 'did not go through the TURN relay' : null,
    ].filter(Boolean);
    const note = sendResults.find((r) => r.ok)?.note ?? '';
    record(name, problems.length === 0, problems.length ? problems.join('; ') : `${note}; sha256 ${pdfSha.slice(0, 16)} matches; ${relayed.replace('E2E PATH ', '')}`);
  } catch (e) {
    record(name, false, e.message);
  } finally {
    await receiver?.close();
    await sender?.close();
  }
}

try {
  await transfer('chrome-to-linux', 'linux', 'chrome');
  await transfer('linux-to-chrome', 'chrome', 'linux');
  if (turn) {
    await transfer('chrome-to-linux-relay', 'linux', 'chrome', { ...turn, forceRelay: 1 });
    await transfer('linux-to-chrome-relay', 'chrome', 'linux', { ...turn, forceRelay: 1 });
  }
  // Both ends inside the Linux app: every protocol feature on the Linux WebRTC stack.
  const scenarios = ['small-file', 'multi-file', 'wrong-code', 'qr-nonce', 'decline', 'kill-mid-transfer', 'resume', 'retry', 'large-file'];
  if (turn) scenarios.push('forced-relay');
  const single = launchLinux('linux-single-page', { scenarios: scenarios.join(','), bigMb: args.bigMb || 50, ...(turn ?? {}) });
  try {
    const list = await withTimeout(single.done, 20 * 60 * 1000, 'single-page scenarios');
    for (const r of list) record(`linux/${r.name}`, r.ok, r.ok ? (r.note ?? '') : r.error);
  } catch (e) {
    record('linux-single-page', false, e.message);
  } finally {
    single.close();
  }
} finally {
  server.close();
}

const failed = results.filter((r) => !r.ok);
log(`\n${results.length - failed.length}/${results.length} Linux internet scenarios passed`);
for (const r of results) log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name}  ${r.note ?? ''}`);
logFile?.end();
process.exit(failed.length ? 1 : 0);
