'use strict';
/**
 * Sweep test site: a temp copy of demo/ (symlinks such as demo/api/*.php
 * dereferenced, so api/ltx.php finds ../db-config.php next to it) with the
 * SQLite db-config stub, served by `php -S` so /api/*.php and
 * relay-server.php work alongside the static pages.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const net = require('net');
const http = require('http');
const { spawn } = require('child_process');

const REPO = path.resolve(__dirname, '../../../..');

function freePort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.unref();
    s.on('error', reject);
    s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)); });
  });
}

function get(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (c) => { body += c; });
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body }));
    }).on('error', reject);
  });
}

async function startSite() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ip-sweep-site-'));
  const site = path.join(root, 'site');
  fs.cpSync(path.join(REPO, 'demo'), site, { recursive: true, dereference: true });
  // cpSync's dereference misses nested symlinks: replace any left with copies.
  (function derefLinks(dir) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isSymbolicLink()) {
        const real = fs.realpathSync(p);
        fs.unlinkSync(p);
        fs.cpSync(real, p, { recursive: true, dereference: true });
      } else if (e.isDirectory()) derefLinks(p);
    }
  })(site);
  fs.copyFileSync(path.join(__dirname, 'db-config.sqlite.php'), path.join(site, 'db-config.php'));
  const port = await freePort();
  const env = Object.assign({}, process.env, { SWEEP_SQLITE: path.join(root, 'sweep.sqlite') });
  const proc = spawn('php', ['-S', '127.0.0.1:' + port, '-t', site, path.join(__dirname, 'router.php')],
    { env, stdio: ['ignore', 'ignore', 'pipe'] });
  let log = '';
  proc.stderr.on('data', (d) => { log += d; });
  const base = 'http://127.0.0.1:' + port;
  for (let i = 0; i < 100; i++) {
    try { await get(base + '/robots.txt'); break; } catch (_) { await new Promise((r) => setTimeout(r, 100)); }
  }
  return {
    base, site, root, port,
    log: () => log,
    stop() {
      try { proc.kill(); } catch (_) {}
      try { fs.rmSync(root, { recursive: true, force: true }); } catch (_) {}
    },
  };
}

/** php -S on an existing docroot (e.g. the repo's demo/, for mcp-server.php, which loads ../php/). */
async function startPhp(docroot, env) {
  const port = await freePort();
  const proc = spawn('php', ['-S', '127.0.0.1:' + port, '-t', docroot],
    { env: Object.assign({}, process.env, env || {}), stdio: ['ignore', 'ignore', 'ignore'] });
  const base = 'http://127.0.0.1:' + port;
  for (let i = 0; i < 100; i++) {
    try { await get(base + '/robots.txt'); break; } catch (_) { await new Promise((r) => setTimeout(r, 100)); }
  }
  return { base, port, stop() { try { proc.kill(); } catch (_) {} } };
}

module.exports = { REPO, startSite, startPhp, freePort, get };
