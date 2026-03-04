'use strict';

/**
 * cli_test.js — Unit/integration tests for interplanet CLI (Story 26.1)
 *
 * Runs the CLI as a child process and validates stdout/stderr/exit codes.
 * No external test framework required — stdlib only.
 */

const { execFileSync } = require('child_process');
const path = require('path');
const assert = require('assert');

const CLI = path.resolve(__dirname, '../bin/interplanet.js');

// ── Helpers ───────────────────────────────────────────────────────────────────

let passed = 0;
let failed = 0;

function run(args, opts = {}) {
  try {
    const out = execFileSync(process.execPath, [CLI, ...args], {
      encoding: 'utf8',
      env: process.env,
      ...(opts.input !== undefined ? { input: opts.input } : {}),
    });
    return { stdout: out, stderr: '', code: 0 };
  } catch (e) {
    return { stdout: e.stdout || '', stderr: e.stderr || '', code: e.status || 1 };
  }
}

function test(name, fn) {
  try {
    fn();
    console.log(`  ✓  ${name}`);
    passed++;
  } catch (e) {
    console.error(`  ✗  ${name}`);
    console.error(`     ${e.message}`);
    failed++;
  }
}

// ── Test Sections ─────────────────────────────────────────────────────────────

console.log('\ninterplanet CLI tests\n');

// 1. Help / unknown command
console.log('1. Help & error handling');

test('help with no args exits 0', () => {
  const r = run([]);
  assert.strictEqual(r.code, 0, 'exit code');
  assert.ok(r.stdout.includes('interplanet'), 'contains "interplanet"');
});

test('help command exits 0', () => {
  const r = run(['help']);
  assert.strictEqual(r.code, 0);
  assert.ok(r.stdout.includes('Commands:'), 'contains "Commands:"');
});

test('--help flag exits 0', () => {
  const r = run(['--help']);
  assert.strictEqual(r.code, 0);
});

test('-h flag exits 0', () => {
  const r = run(['-h']);
  assert.strictEqual(r.code, 0);
});

test('unknown command exits 1', () => {
  const r = run(['flibbertigibbet']);
  assert.strictEqual(r.code, 1, 'exit code should be 1');
  assert.ok(r.stderr.includes('Unknown command'), 'stderr includes "Unknown command"');
});

// 2. planets
console.log('\n2. planets command');

test('planets exits 0', () => {
  const r = run(['planets']);
  assert.strictEqual(r.code, 0);
});

test('planets lists earth', () => {
  const r = run(['planets']);
  assert.ok(r.stdout.includes('earth'), 'lists earth');
});

test('planets lists mars', () => {
  const r = run(['planets']);
  assert.ok(r.stdout.includes('mars'), 'lists mars');
});

test('planets lists all 8 planets', () => {
  const r = run(['planets']);
  const EXPECTED = ['mercury', 'venus', 'earth', 'mars', 'jupiter', 'saturn', 'uranus', 'neptune'];
  EXPECTED.forEach(p => assert.ok(r.stdout.includes(p), `lists ${p}`));
});

// 3. time
console.log('\n3. time command');

test('time mars exits 0', () => {
  const r = run(['time', 'mars']);
  assert.strictEqual(r.code, 0);
});

test('time mars shows Planet label', () => {
  const r = run(['time', 'mars']);
  assert.ok(r.stdout.includes('Planet'), 'includes "Planet"');
});

test('time mars shows Local time', () => {
  const r = run(['time', 'mars']);
  assert.ok(/Local\s*:\s*\d{2}:\d{2}:\d{2}/.test(r.stdout), 'Local HH:MM:SS');
});

test('time mars shows Sol info', () => {
  const r = run(['time', 'mars']);
  assert.ok(r.stdout.includes('Sol'), 'includes Sol');
});

test('time earth exits 0', () => {
  const r = run(['time', 'earth']);
  assert.strictEqual(r.code, 0);
});

test('time jupiter exits 0', () => {
  const r = run(['time', 'jupiter']);
  assert.strictEqual(r.code, 0);
});

test('time with no planet exits 1', () => {
  const r = run(['time']);
  assert.strictEqual(r.code, 1);
});

test('time with bad planet exits 1', () => {
  const r = run(['time', 'pluto']);
  assert.strictEqual(r.code, 1);
  assert.ok(r.stderr.includes('Unknown planet'), 'stderr includes "Unknown planet"');
});

test('time mars --tz 5 exits 0', () => {
  const r = run(['time', 'mars', '--tz', '5']);
  assert.strictEqual(r.code, 0);
});

// 4. mtc
console.log('\n4. mtc command');

test('mtc exits 0', () => {
  const r = run(['mtc']);
  assert.strictEqual(r.code, 0);
});

test('mtc shows MTC label', () => {
  const r = run(['mtc']);
  assert.ok(/MTC\s*:\s*\d{2}:\d{2}:\d{2}/.test(r.stdout), 'MTC HH:MM:SS');
});

test('mtc shows Sol', () => {
  const r = run(['mtc']);
  assert.ok(r.stdout.includes('Sol'), 'includes Sol');
});

test('mtc shows UTC now', () => {
  const r = run(['mtc']);
  assert.ok(r.stdout.includes('UTC now'), 'includes UTC now');
});

// 5. light-travel
console.log('\n5. light-travel command');

test('light-travel earth mars exits 0', () => {
  const r = run(['light-travel', 'earth', 'mars']);
  assert.strictEqual(r.code, 0);
});

test('light-travel shows One-way in seconds', () => {
  const r = run(['light-travel', 'earth', 'mars']);
  assert.ok(/One-way\s*:\s*[\d.]+\s*s/.test(r.stdout), 'One-way seconds');
});

test('light-travel shows Round-trip', () => {
  const r = run(['light-travel', 'earth', 'mars']);
  assert.ok(r.stdout.includes('Round-trip'), 'Round-trip line');
});

test('light-travel earth mars one-way is positive', () => {
  const r = run(['light-travel', 'earth', 'mars']);
  const m = r.stdout.match(/One-way\s*:\s*([\d.]+)\s*s/);
  assert.ok(m, 'One-way match');
  assert.ok(parseFloat(m[1]) > 0, 'positive seconds');
});

test('light-travel earth mars round-trip ≈ 2× one-way', () => {
  const r = run(['light-travel', 'earth', 'mars']);
  const m1 = r.stdout.match(/One-way\s*:\s*([\d.]+)\s*s/);
  const m2 = r.stdout.match(/Round-trip:\s*([\d.]+)\s*s/);
  assert.ok(m1 && m2, 'both matches');
  const ratio = parseFloat(m2[1]) / parseFloat(m1[1]);
  assert.ok(Math.abs(ratio - 2) < 0.01, `ratio ${ratio} should be ~2`);
});

test('light-travel with missing arg exits 1', () => {
  const r = run(['light-travel', 'earth']);
  assert.strictEqual(r.code, 1);
});

test('light-travel with bad planet exits 1', () => {
  const r = run(['light-travel', 'pluto', 'mars']);
  assert.strictEqual(r.code, 1);
});

test('light-travel earth earth shows ~0 s', () => {
  const r = run(['light-travel', 'earth', 'earth']);
  const m = r.stdout.match(/One-way\s*:\s*([\d.]+)\s*s/);
  assert.ok(m, 'One-way match');
  assert.ok(parseFloat(m[1]) < 1, 'near-zero for earth→earth');
});

// 6. distance
console.log('\n6. distance command');

test('distance earth mars exits 0', () => {
  const r = run(['distance', 'earth', 'mars']);
  assert.strictEqual(r.code, 0);
});

test('distance shows AU', () => {
  const r = run(['distance', 'earth', 'mars']);
  assert.ok(/Distance\s*:\s*[\d.]+\s*AU/.test(r.stdout), 'AU line');
});

test('distance shows km', () => {
  const r = run(['distance', 'earth', 'mars']);
  assert.ok(/:\s*[\d]+\s*km/.test(r.stdout), 'km line');
});

test('distance earth mars is between 0.4 and 2.7 AU', () => {
  const r = run(['distance', 'earth', 'mars']);
  const m = r.stdout.match(/Distance\s*:\s*([\d.]+)\s*AU/);
  assert.ok(m, 'AU match');
  const au = parseFloat(m[1]);
  assert.ok(au > 0.4 && au < 2.7, `AU ${au} out of expected range`);
});

test('distance with missing arg exits 1', () => {
  const r = run(['distance', 'earth']);
  assert.strictEqual(r.code, 1);
});

// 7. los
console.log('\n7. los command');

test('los earth mars exits 0', () => {
  const r = run(['los', 'earth', 'mars']);
  assert.strictEqual(r.code, 0);
});

test('los shows Status', () => {
  const r = run(['los', 'earth', 'mars']);
  assert.ok(/Status\s*:\s*(CLEAR|DEGRADED|BLOCKED)/.test(r.stdout), 'Status label');
});

test('los shows Elong in degrees', () => {
  const r = run(['los', 'earth', 'mars']);
  assert.ok(/Elong\s*:\s*[\d.]+°/.test(r.stdout), 'Elong degrees');
});

test('los with missing arg exits 1', () => {
  const r = run(['los', 'earth']);
  assert.strictEqual(r.code, 1);
});

// 8. windows
console.log('\n8. windows command');

test('windows earth earth --days 1 exits 0', () => {
  const r = run(['windows', 'earth', 'earth', '--days', '1']);
  assert.strictEqual(r.code, 0);
});

test('windows earth earth --days 1 finds at least one window', () => {
  const r = run(['windows', 'earth', 'earth', '--days', '1']);
  assert.ok(r.stdout.includes('[1]'), 'at least one window');
});

test('windows shows From / Horizon', () => {
  const r = run(['windows', 'earth', 'mars', '--days', '1']);
  assert.ok(r.stdout.includes('From'), 'From label');
  assert.ok(r.stdout.includes('Horizon'), 'Horizon label');
});

test('windows with missing arg exits 1', () => {
  const r = run(['windows', 'earth']);
  assert.strictEqual(r.code, 1);
});

// ── Summary ───────────────────────────────────────────────────────────────────

console.log(`\n${passed + failed} tests  —  ${passed} passed  ${failed} failed\n`);
if (failed > 0) process.exit(1);
