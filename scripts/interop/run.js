#!/usr/bin/env node
/**
 * Cross-port LTX planId interop runner (issue #32).
 *
 * For every LTX port whose toolchain is available, runs a tiny driver in
 * scripts/interop/drivers/<port>/ and checks three things against the
 * JavaScript reference SDK (javascript/ltx/ltx-sdk.js):
 *
 *   (a)+(b) the port builds the representative plan with its own typed API,
 *           serialises it with its own wire serialiser and computes its own
 *           planId; JS parses the wire JSON and must compute the same planId.
 *           Done for v2 and, where the port can upgrade, v3.
 *   (c)     the port computes the planId of a JS createPlan plan (v2) and of
 *           its JS upgradePlanToV3 successor (v3) from the JSON text, and
 *           must match JS makePlanId.
 *   (c) pfx the same for a JS createPlan plan whose node names stress the
 *           planId prefix (Unicode upper-casing, JS whitespace, UTF-16 cut;
 *           plan.js PREFIX_NODES, issue #37). Optional: a driver that does
 *           not print JS_VP is reported as n/a.
 *
 * Driver contract:  <driver> <inDir> <outDir>
 *   inDir/js-v2.json, inDir/js-v3.json          JS-built plans (UTF-8, compact)
 *   inDir/js-vP.json                            JS-built prefix plan (optional)
 *   outDir/wire-v2.json, outDir/wire-v3.json    the port's own wire JSON
 *   stdout lines:  ID_V2 <id> | ID_V3 <id> | JS_V2 <id> | JS_V3 <id> | JS_VP <id> | NOTE <text>
 *   A missing line means "not supported by this port" and is reported as n/a.
 *
 * Usage:  node scripts/interop/run.js [--only a,b] [--skip a,b] [--verbose]
 * Exit code: 0 when every port that ran passes (ports marked xfail in
 * ports.js may fail), 1 otherwise.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const DRIVERS = path.join(__dirname, 'drivers');
const LTX = require(path.join(ROOT, 'javascript/ltx/ltx-sdk.js'));
const { REP, V3_EXTRAS, PREFIX_NODES } = require('./plan.js');
const PORTS = require('./ports.js');

// Extra PATH entries (e.g. a local julia or zig) may be given in INTEROP_PATH.
const ENV = { ...process.env, ROOT };
if (process.env.INTEROP_PATH) ENV.PATH = process.env.INTEROP_PATH + path.delimiter + ENV.PATH;

function which(cmd) {
  if (path.isAbsolute(cmd)) return fs.existsSync(cmd);
  return spawnSync('sh', ['-c', 'command -v "$0" >/dev/null', cmd], { env: ENV }).status === 0;
}

function sh(cmd, cwd, timeout) {
  return spawnSync('sh', ['-c', cmd], {
    cwd, env: ENV, encoding: 'utf8', timeout: timeout || 1800000,
    maxBuffer: 64 * 1024 * 1024,
  });
}

function tail(r) {
  const text = (r.stderr || '') + (r.stdout || '') + (r.error ? String(r.error) : '');
  return text.trim().split('\n').filter(l => !/^Picked up JAVA_TOOL_OPTIONS/.test(l)).slice(-6).join(' | ');
}

function parseLines(out) {
  const r = { notes: [] };
  for (const line of out.split(/\r?\n/)) {
    const m = /^(ID_V2|ID_V3|JS_V2|JS_V3|JS_VP|NOTE)\s+(.*)$/.exec(line.trim());
    if (!m) continue;
    if (m[1] === 'NOTE') r.notes.push(m[2]); else r[m[1]] = m[2].trim();
  }
  return r;
}

function describeOrder(parsed, ref) {
  const k = Object.keys(parsed).join(',');
  if (k === Object.keys(ref).join(',')) return 'segments first (as JS)';
  if (k === 'v,title,start,quantum,mode,nodes,segments') return 'nodes first';
  return k;
}

// ── Main ────────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const argList = (flag) => { const i = args.indexOf(flag); return i >= 0 ? args[i + 1].split(',') : null; };
const only = argList('--only');
const skip = argList('--skip') || [];
const verbose = args.includes('--verbose');

const work = fs.mkdtempSync(path.join(os.tmpdir(), 'ltx-interop-'));
const inDir = path.join(work, 'in');
fs.mkdirSync(inDir);
const jsV2 = LTX.createPlan(REP);
const jsV3 = LTX.upgradePlanToV3(jsV2, V3_EXTRAS);
fs.writeFileSync(path.join(inDir, 'js-v2.json'), JSON.stringify(jsV2));
fs.writeFileSync(path.join(inDir, 'js-v3.json'), JSON.stringify(jsV3));
const jsVP = LTX.createPlan({ ...REP, nodes: PREFIX_NODES });
fs.writeFileSync(path.join(inDir, 'js-vP.json'), JSON.stringify(jsVP));
const expectJsV2 = LTX.makePlanId(jsV2);
const expectJsV3 = LTX.makePlanId(jsV3);
const expectJsVP = LTX.makePlanId(jsVP);
console.log(`JS createPlan v2 planId:      ${expectJsV2}`);
console.log(`JS upgradePlanToV3 v3 planId: ${expectJsV3}`);
console.log(`JS prefix plan planId:        ${expectJsVP}\n`);

const rows = [];
const built = {};
for (const port of PORTS) {
  if (only && !only.includes(port.name)) continue;
  if (skip.includes(port.name)) continue;
  const row = { port: port.name, status: '', a2: '-', a3: '-', c2: '-', c3: '-', cp: '-', order: '-', notes: [] };
  rows.push(row);
  const missing = (port.need || []).filter(c => !which(c));
  if (missing.length) {
    row.status = 'SKIP';
    row.notes.push(`toolchain not found: ${missing.join(', ')}`);
    continue;
  }
  const dir = path.join(DRIVERS, port.dir || port.name);
  process.stderr.write(`[interop] ${port.name}...\n`);
  if (port.build && built[dir] === undefined) {
    const b = sh(port.build, dir);
    built[dir] = b;
    if (verbose) process.stdout.write(`--- ${port.name} build\n${b.stdout}${b.stderr}`);
  }
  if (port.build && built[dir].status !== 0) { row.status = 'BUILD-FAIL'; row.notes.push(tail(built[dir])); continue; }
  const outDir = path.join(work, port.name);
  fs.mkdirSync(outDir, { recursive: true });
  const r = sh(`${port.run} "${inDir}" "${outDir}"`, dir);
  if (verbose) process.stdout.write(`--- ${port.name} run\n${r.stdout}${r.stderr}`);
  if (r.status !== 0) { row.status = 'RUN-FAIL'; row.notes.push(tail(r)); continue; }
  const o = parseLines(r.stdout);
  row.notes.push(...o.notes);
  let bad = 0;
  const check = (cell, got, want, label) => {
    if (got === undefined) { row[cell] = 'n/a'; return; }
    if (got === want) { row[cell] = 'ok'; return; }
    row[cell] = 'MISMATCH';
    row.notes.push(`${label}: port ${got}, JS ${want}`);
    bad++;
  };
  for (const v of ['2', '3']) {
    const wf = path.join(outDir, `wire-v${v}.json`);
    const id = o[`ID_V${v}`];
    const hasWire = fs.existsSync(wf);
    if (!hasWire || id === undefined) {
      row[`a${v}`] = hasWire === (id !== undefined) ? 'n/a' : 'INCOMPLETE';
      if (row[`a${v}`] === 'INCOMPLETE') bad++;
      continue;
    }
    let parsed;
    try { parsed = JSON.parse(fs.readFileSync(wf, 'utf8')); } catch (e) {
      row[`a${v}`] = 'BAD-JSON'; row.notes.push(`wire-v${v}: ${e.message}`); bad++; continue;
    }
    check(`a${v}`, id, LTX.makePlanId(parsed), `(a) v${v} own planId vs JS on its wire JSON`);
    if (v === '2') {
      row.order = describeOrder(parsed, jsV2);
      if (parsed.title !== REP.title) row.notes.push(`wire title is ${JSON.stringify(parsed.title)}`);
      const segs = parsed.segments || [];
      if (!segs.some(s => s.speaker === 'N1' && s.label === REP.segments[3].label)) {
        row.notes.push('wire v2 segments carry no speaker/label');
      }
      if ((parsed.nodes || []).length !== 3) row.notes.push('wire v2 does not have 3 nodes');
    }
  }
  check('c2', o.JS_V2, expectJsV2, '(c) v2 planId of JS JSON');
  check('c3', o.JS_V3, expectJsV3, '(c) v3 planId of JS JSON');
  check('cp', o.JS_VP, expectJsVP, '(c) prefix planId of JS JSON');
  row.status = bad ? 'FAIL' : 'PASS';
  if (port.xfail) {
    row.status = bad ? 'XFAIL' : 'XPASS';
    row.notes.push(`known incompatibility: ${port.xfail}`);
  }
}

// ── Report ──────────────────────────────────────────────────────────────────
const cols = ['port', 'status', 'a2', 'a3', 'c2', 'c3', 'cp', 'order'];
const head = { port: 'port', status: 'status', a2: '(a) v2', a3: '(a) v3', c2: '(c) v2', c3: '(c) v3', cp: '(c) pfx', order: 'wire key order' };
const w = Object.fromEntries(cols.map(c => [c, Math.max(head[c].length, ...rows.map(r => String(r[c]).length))]));
const line = r => cols.map(c => String(r[c]).padEnd(w[c])).join('  ').trimEnd();
console.log(line(head));
console.log(cols.map(c => '-'.repeat(w[c])).join('  '));
for (const r of rows) {
  console.log(line(r));
  for (const n of r.notes) console.log(`    ${n}`);
}
if (verbose) console.log(`\nwork dir kept: ${work}`);
else fs.rmSync(work, { recursive: true, force: true });
const n = s => rows.filter(r => r.status === s).length;
const failed = rows.length - n('PASS') - n('SKIP') - n('XFAIL');
console.log(`\n${n('PASS')} pass, ${failed} fail, ${n('XFAIL')} known-incompatible (xfail), ${n('SKIP')} skipped`);
process.exit(failed ? 1 : 0);
