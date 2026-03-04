'use strict';

/**
 * cli_ltx_test.js — Unit tests for interplanet CLI ltx subcommands (Story 33.9)
 *
 * Tests the ltx plan, segments, hash, ics, and send subcommands.
 * Stdlib only, no external test frameworks.
 */

const { execFileSync, spawnSync } = require('child_process');
const path = require('path');
const assert = require('assert');

const CLI = path.resolve(__dirname, '../bin/interplanet.js');
const LTX = require(path.resolve(__dirname, '../../javascript/ltx/ltx-sdk.js'));

// ── Helpers ───────────────────────────────────────────────────────────────────

let passed = 0;
let failed = 0;

function run(args, opts) {
  opts = opts || {};
  const result = spawnSync(process.execPath, [CLI, ...args], {
    encoding: 'utf8',
    env: process.env,
    timeout: 15000,
  });
  return {
    stdout: result.stdout || '',
    stderr: result.stderr || '',
    code:   result.status !== null ? result.status : 1,
  };
}

function test(name, fn) {
  try {
    fn();
    console.log('  \u2713  ' + name);
    passed++;
  } catch (e) {
    console.error('  \u2717  ' + name);
    console.error('     ' + e.message);
    failed++;
  }
}

// ── parseNodeStr unit tests (direct SDK calls) ────────────────────────────────

console.log('\ninterplanet CLI ltx tests\n');

// We replicate parseNodeStr logic here to test it directly via SDK plan creation
function parseNodeStr(str) {
  const parts = str.split(':');
  if (parts.length < 3) throw new Error('Invalid node format: ' + str);
  const name     = parts[0].trim();
  const role     = parts[1].trim().toUpperCase();
  const location = parts[2].trim().toLowerCase();
  const delay    = parts[3] !== undefined ? parseInt(parts[3], 10) : 0;
  return { name, role, location, delay };
}

console.log('1. parseNodeStr — unit tests');

test('parseNodeStr: basic earth host', () => {
  const n = parseNodeStr('Earth HQ:host:earth');
  assert.strictEqual(n.name, 'Earth HQ');
  assert.strictEqual(n.role, 'HOST');
  assert.strictEqual(n.location, 'earth');
  assert.strictEqual(n.delay, 0);
});

test('parseNodeStr: mars participant with delay', () => {
  const n = parseNodeStr('Mars Base:participant:mars:1240');
  assert.strictEqual(n.name, 'Mars Base');
  assert.strictEqual(n.role, 'PARTICIPANT');
  assert.strictEqual(n.location, 'mars');
  assert.strictEqual(n.delay, 1240);
});

test('parseNodeStr: role is uppercased', () => {
  const n = parseNodeStr('Station Alpha:observer:moon:600');
  assert.strictEqual(n.role, 'OBSERVER');
});

test('parseNodeStr: location is lowercased', () => {
  const n = parseNodeStr('HQ:HOST:EARTH');
  assert.strictEqual(n.location, 'earth');
});

test('parseNodeStr: delay defaults to 0 when omitted', () => {
  const n = parseNodeStr('Alpha:host:moon');
  assert.strictEqual(n.delay, 0);
});

test('parseNodeStr: delay of 800 seconds parsed correctly', () => {
  const n = parseNodeStr('Moon Base:participant:moon:800');
  assert.strictEqual(n.delay, 800);
});

test('parseNodeStr: throws on fewer than 3 parts', () => {
  assert.throws(() => parseNodeStr('Bad:only'), /Invalid/);
});

// ── LTX SDK — createPlan ───────────────────────────────────────────────────────

console.log('\n2. LTX SDK — createPlan');

test('createPlan returns v:2 schema', () => {
  const plan = LTX.createPlan({ hostName: 'Earth HQ', remoteName: 'Mars Hab', delay: 600 });
  assert.strictEqual(plan.v, 2);
});

test('createPlan default mode is LTX', () => {
  const plan = LTX.createPlan({});
  assert.strictEqual(plan.mode, 'LTX');
});

test('createPlan default quantum is 5', () => {
  const plan = LTX.createPlan({});
  assert.strictEqual(plan.quantum, 5);
});

test('createPlan nodes array has 2 entries by default', () => {
  const plan = LTX.createPlan({});
  assert.ok(Array.isArray(plan.nodes));
  assert.strictEqual(plan.nodes.length, 2);
});

test('createPlan custom title', () => {
  const plan = LTX.createPlan({ title: 'Daily Sync' });
  assert.strictEqual(plan.title, 'Daily Sync');
});

test('createPlan with explicit nodes array', () => {
  const nodes = [
    { id: 'N0', name: 'Earth HQ', role: 'HOST', location: 'earth', delay: 0 },
    { id: 'N1', name: 'Mars Base', role: 'PARTICIPANT', location: 'mars', delay: 1240 },
  ];
  const plan = LTX.createPlan({ nodes, title: 'Mars Meeting' });
  assert.strictEqual(plan.nodes.length, 2);
  assert.strictEqual(plan.nodes[1].delay, 1240);
  assert.strictEqual(plan.nodes[1].location, 'mars');
});

test('createPlan segments array is non-empty', () => {
  const plan = LTX.createPlan({});
  assert.ok(Array.isArray(plan.segments));
  assert.ok(plan.segments.length > 0);
});

test('createPlan start is an ISO string', () => {
  const plan = LTX.createPlan({});
  assert.ok(typeof plan.start === 'string');
  assert.ok(!isNaN(Date.parse(plan.start)));
});

// ── LTX SDK — computeSegments ─────────────────────────────────────────────────

console.log('\n3. LTX SDK — computeSegments');

test('computeSegments returns an array', () => {
  const plan = LTX.createPlan({});
  const segs = LTX.computeSegments(plan);
  assert.ok(Array.isArray(segs));
});

test('computeSegments length matches plan segments', () => {
  const plan = LTX.createPlan({});
  const segs = LTX.computeSegments(plan);
  assert.strictEqual(segs.length, plan.segments.length);
});

test('computeSegments each segment has type, start, end, durMin', () => {
  const plan = LTX.createPlan({});
  const segs = LTX.computeSegments(plan);
  segs.forEach(s => {
    assert.ok(typeof s.type === 'string', 'type is string');
    assert.ok(s.start instanceof Date, 'start is Date');
    assert.ok(s.end instanceof Date, 'end is Date');
    assert.ok(typeof s.durMin === 'number', 'durMin is number');
  });
});

test('computeSegments segments are consecutive (end of one = start of next)', () => {
  const plan = LTX.createPlan({ start: '2026-03-01T12:00:00.000Z' });
  const segs = LTX.computeSegments(plan);
  for (let i = 1; i < segs.length; i++) {
    assert.strictEqual(segs[i].start.getTime(), segs[i - 1].end.getTime(),
      'Segment ' + i + ' start should equal prev end');
  }
});

test('computeSegments first segment starts at plan start time', () => {
  const plan = LTX.createPlan({ start: '2026-03-01T12:00:00.000Z' });
  const segs = LTX.computeSegments(plan);
  assert.strictEqual(segs[0].start.toISOString(), '2026-03-01T12:00:00.000Z');
});

test('computeSegments durMin = q * quantum', () => {
  const plan = LTX.createPlan({ start: '2026-03-01T12:00:00.000Z', quantum: 3 });
  const segs = LTX.computeSegments(plan);
  segs.forEach((s, i) => {
    assert.strictEqual(s.durMin, plan.segments[i].q * plan.quantum,
      'Segment ' + i + ' durMin mismatch');
  });
});

// ── LTX SDK — encodeHash ──────────────────────────────────────────────────────

console.log('\n4. LTX SDK — encodeHash');

test('encodeHash returns string starting with #l=', () => {
  const plan = LTX.createPlan({});
  const hash = LTX.encodeHash(plan);
  assert.ok(hash.startsWith('#l='), 'Should start with #l=, got: ' + hash.slice(0, 10));
});

test('encodeHash output is a non-empty string after #l=', () => {
  const plan = LTX.createPlan({});
  const hash = LTX.encodeHash(plan);
  assert.ok(hash.length > 3, 'Hash should have content after #l=');
});

test('encodeHash is decodeable by decodeHash', () => {
  const plan = LTX.createPlan({ title: 'Round-trip test' });
  const hash = LTX.encodeHash(plan);
  const decoded = LTX.decodeHash(hash);
  assert.ok(decoded !== null, 'Should decode successfully');
  assert.strictEqual(decoded.title, 'Round-trip test');
});

test('encodeHash output does not contain + / = (URL-safe base64)', () => {
  const plan = LTX.createPlan({});
  const hash = LTX.encodeHash(plan).slice(3); // remove #l=
  assert.ok(!hash.includes('+'), 'Should not contain +');
  assert.ok(!hash.includes('/'), 'Should not contain /');
  assert.ok(!hash.includes('='), 'Should not contain =');
});

test('encodeHash two identical plans produce the same hash', () => {
  const opts = { title: 'Same', start: '2026-03-01T10:00:00.000Z', quantum: 3, mode: 'LTX' };
  const h1 = LTX.encodeHash(LTX.createPlan(opts));
  const h2 = LTX.encodeHash(LTX.createPlan(opts));
  assert.strictEqual(h1, h2);
});

// ── LTX SDK — generateICS ─────────────────────────────────────────────────────

console.log('\n5. LTX SDK — generateICS');

test('generateICS contains BEGIN:VCALENDAR', () => {
  const plan = LTX.createPlan({});
  const ics = LTX.generateICS(plan);
  assert.ok(ics.includes('BEGIN:VCALENDAR'), 'Should contain BEGIN:VCALENDAR');
});

test('generateICS contains END:VCALENDAR', () => {
  const plan = LTX.createPlan({});
  const ics = LTX.generateICS(plan);
  assert.ok(ics.includes('END:VCALENDAR'), 'Should contain END:VCALENDAR');
});

test('generateICS contains BEGIN:VEVENT', () => {
  const plan = LTX.createPlan({});
  const ics = LTX.generateICS(plan);
  assert.ok(ics.includes('BEGIN:VEVENT'), 'Should contain BEGIN:VEVENT');
});

test('generateICS contains LTX-PLANID property', () => {
  const plan = LTX.createPlan({});
  const ics = LTX.generateICS(plan);
  assert.ok(ics.includes('LTX-PLANID:'), 'Should contain LTX-PLANID:');
});

test('generateICS contains DTSTART', () => {
  const plan = LTX.createPlan({ start: '2026-03-01T12:00:00.000Z' });
  const ics = LTX.generateICS(plan);
  assert.ok(ics.includes('DTSTART:'), 'Should contain DTSTART:');
});

test('generateICS contains the plan title in SUMMARY', () => {
  const plan = LTX.createPlan({ title: 'Earth Mars Sync' });
  const ics = LTX.generateICS(plan);
  assert.ok(ics.includes('SUMMARY:Earth Mars Sync'), 'Should contain plan title in SUMMARY');
});

// ── CLI smoke tests ───────────────────────────────────────────────────────────

console.log('\n6. CLI smoke tests');

test('ltx help exits 0', () => {
  const r = run(['ltx', 'help']);
  assert.strictEqual(r.code, 0);
});

test('ltx help mentions ltx plan', () => {
  const r = run(['ltx', 'help']);
  assert.ok(r.stdout.includes('ltx plan'), 'Should mention ltx plan');
});

test('ltx help mentions ltx segments', () => {
  const r = run(['ltx', 'help']);
  assert.ok(r.stdout.includes('ltx segments'), 'Should mention ltx segments');
});

test('ltx help mentions ltx hash', () => {
  const r = run(['ltx', 'help']);
  assert.ok(r.stdout.includes('ltx hash'), 'Should mention ltx hash');
});

test('ltx help mentions ltx ics', () => {
  const r = run(['ltx', 'help']);
  assert.ok(r.stdout.includes('ltx ics'), 'Should mention ltx ics');
});

test('ltx help mentions ltx send', () => {
  const r = run(['ltx', 'help']);
  assert.ok(r.stdout.includes('ltx send'), 'Should mention ltx send');
});

test('main help mentions ltx subcommand', () => {
  const r = run(['help']);
  assert.ok(r.stdout.includes('ltx'), 'Main help should mention ltx');
});

test('ltx hash with two nodes exits 0', () => {
  const r = run(['ltx', 'hash', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  assert.strictEqual(r.code, 0);
});

test('ltx hash output starts with #l=', () => {
  const r = run(['ltx', 'hash', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  assert.ok(r.stdout.trim().startsWith('#l='), 'Output should start with #l=, got: ' + r.stdout.slice(0, 20));
});

test('ltx hash with delay in node string exits 0', () => {
  const r = run(['ltx', 'hash', 'Earth HQ:host:earth', 'Mars Base:participant:mars:1240']);
  assert.strictEqual(r.code, 0);
  assert.ok(r.stdout.trim().startsWith('#l='));
});

test('ltx plan exits 0', () => {
  const r = run(['ltx', 'plan', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  assert.strictEqual(r.code, 0);
});

test('ltx plan output is valid JSON', () => {
  const r = run(['ltx', 'plan', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  assert.strictEqual(r.code, 0);
  const parsed = JSON.parse(r.stdout);
  assert.ok(parsed !== null);
});

test('ltx plan JSON has v:2', () => {
  const r = run(['ltx', 'plan', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  const plan = JSON.parse(r.stdout);
  assert.strictEqual(plan.v, 2);
});

test('ltx plan JSON has nodes array', () => {
  const r = run(['ltx', 'plan', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  const plan = JSON.parse(r.stdout);
  assert.ok(Array.isArray(plan.nodes));
  assert.strictEqual(plan.nodes.length, 2);
});

test('ltx plan --title sets plan title', () => {
  const r = run(['ltx', 'plan', 'Earth HQ:host:earth', '--title', 'Daily Sync']);
  const plan = JSON.parse(r.stdout);
  assert.strictEqual(plan.title, 'Daily Sync');
});

test('ltx plan --quantum sets quantum', () => {
  const r = run(['ltx', 'plan', 'Earth HQ:host:earth', '--quantum', '5']);
  const plan = JSON.parse(r.stdout);
  assert.strictEqual(plan.quantum, 5);
});

test('ltx plan --mode sets mode', () => {
  const r = run(['ltx', 'plan', 'Earth HQ:host:earth', '--mode', 'async']);
  const plan = JSON.parse(r.stdout);
  assert.strictEqual(plan.mode, 'async');
});

test('ltx segments exits 0', () => {
  const r = run(['ltx', 'segments', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  assert.strictEqual(r.code, 0);
});

test('ltx segments output has multiple lines', () => {
  const r = run(['ltx', 'segments', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  const lines = r.stdout.trim().split('\n').filter(l => l.trim());
  assert.ok(lines.length > 1, 'Should have multiple segment lines');
});

test('ltx segments output contains PLAN_CONFIRM segment type', () => {
  const r = run(['ltx', 'segments', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  assert.ok(r.stdout.includes('PLAN_CONFIRM'), 'Should contain PLAN_CONFIRM');
});

test('ltx segments each line contains duration in minutes', () => {
  const r = run(['ltx', 'segments', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  const lines = r.stdout.trim().split('\n').filter(l => l.trim());
  lines.forEach((line, i) => {
    assert.ok(/\d+m\)$/.test(line.trim()), 'Line ' + i + ' should end with Nm): ' + line);
  });
});

test('ltx ics exits 0', () => {
  const r = run(['ltx', 'ics', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  assert.strictEqual(r.code, 0);
});

test('ltx ics output contains BEGIN:VCALENDAR', () => {
  const r = run(['ltx', 'ics', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  assert.ok(r.stdout.includes('BEGIN:VCALENDAR'), 'Should contain BEGIN:VCALENDAR');
});

test('ltx ics output contains END:VCALENDAR', () => {
  const r = run(['ltx', 'ics', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  assert.ok(r.stdout.includes('END:VCALENDAR'), 'Should contain END:VCALENDAR');
});

test('ltx ics output contains DTSTART', () => {
  const r = run(['ltx', 'ics', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  assert.ok(r.stdout.includes('DTSTART:'), 'Should contain DTSTART:');
});

test('ltx ics output contains LTX-PLANID', () => {
  const r = run(['ltx', 'ics', 'Earth HQ:host:earth', 'Mars Base:participant:mars']);
  assert.ok(r.stdout.includes('LTX-PLANID:'), 'Should contain LTX-PLANID:');
});

test('ltx unknown subcommand exits 1', () => {
  const r = run(['ltx', 'foobar']);
  assert.strictEqual(r.code, 1);
  assert.ok(r.stderr.includes('Unknown ltx subcommand'), 'stderr should mention unknown subcommand');
});

test('ltx hash no nodes exits 1 with usage error', () => {
  const r = run(['ltx', 'hash']);
  assert.strictEqual(r.code, 1);
});

// ── Summary ───────────────────────────────────────────────────────────────────

console.log('\n' + (passed + failed) + ' tests  \u2014  ' + passed + ' passed  ' + failed + ' failed\n');
if (failed > 0) process.exit(1);