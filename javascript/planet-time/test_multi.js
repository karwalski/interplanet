'use strict';
/**
 * test_multi.js — Unit tests for computeSegmentsMulti and buildDelayMatrix
 * Story 39.1 — Multi-party LTX conference
 *
 * Run: node interplanet-github/js/test_multi.js
 */

const LTX = require('./ltx-sdk.js');

let passed = 0;
let failed = 0;

function check(name, v) {
  if (v) {
    passed++;
  } else {
    failed++;
    console.log('FAIL:', name);
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

function make3NodePlan() {
  return {
    v:       2,
    title:   '3-Node Test',
    start:   '2026-06-01T12:00:00Z',
    quantum: 3,
    mode:    'LTX',
    nodes: [
      { id: 'N0', name: 'Earth HQ',       role: 'HOST',        delay: 0,    location: 'earth' },
      { id: 'N1', name: 'Mars Base',       role: 'PARTICIPANT', delay: 1240, location: 'mars'  },
      { id: 'N2', name: 'Jupiter Station', role: 'PARTICIPANT', delay: 3240, location: 'other' },
    ],
    segments: [
      { type: 'PLAN_CONFIRM', q: 2 },
      { type: 'TX',           q: 2 },
      { type: 'RX',           q: 2 },
      { type: 'TX',           q: 2 },
      { type: 'RX',           q: 2 },
      { type: 'CAUCUS',       q: 2 },
      { type: 'BUFFER',       q: 1 },
    ],
  };
}

// ── computeSegmentsMulti — function exists ─────────────────────────────────

check('computeSegmentsMulti is a function', typeof LTX.computeSegmentsMulti === 'function');
check('buildDelayMatrix is a function', typeof LTX.buildDelayMatrix === 'function');

// ── computeSegmentsMulti — 3-node plan ────────────────────────────────────

const plan3 = make3NodePlan();
const segs3 = LTX.computeSegmentsMulti(plan3);

check('3-node: returns an array', Array.isArray(segs3));
check('3-node: correct segment count (7)', segs3.length === 7);

// Every segment has required fields
check('3-node: seg[0] has segType', typeof segs3[0].segType === 'string');
check('3-node: seg[0] has nodeId', typeof segs3[0].nodeId === 'string');
check('3-node: seg[0] has startMs (number)', typeof segs3[0].startMs === 'number');
check('3-node: seg[0] has endMs (number)', typeof segs3[0].endMs === 'number');
check('3-node: seg[0] has durationMs (number)', typeof segs3[0].durationMs === 'number');

// PLAN_CONFIRM goes to host (N0)
check('3-node: PLAN_CONFIRM assigned to host (N0)', segs3[0].segType === 'PLAN_CONFIRM' && segs3[0].nodeId === 'N0');

// First TX: speakerIdx=0 -> N0
const txSegs = segs3.filter(s => s.segType === 'TX');
check('3-node: has 2 TX segments', txSegs.length === 2);
check('3-node: first TX assigned to N0 (Earth HQ)', txSegs[0] && txSegs[0].nodeId === 'N0');

// First RX: next speaker after N0 = N1
const rxSegs = segs3.filter(s => s.segType === 'RX');
check('3-node: has 2 RX segments', rxSegs.length === 2);
check('3-node: first RX assigned to N1 (Mars Base)', rxSegs[0] && rxSegs[0].nodeId === 'N1');

// Second TX: speakerIdx=1 -> N1
check('3-node: second TX assigned to N1 (Mars Base)', txSegs[1] && txSegs[1].nodeId === 'N1');

// Second RX: next speaker after N1 = N2
check('3-node: second RX assigned to N2 (Jupiter Station)', rxSegs[1] && rxSegs[1].nodeId === 'N2');

// CAUCUS goes to host (N0)
const caucus = segs3.find(s => s.segType === 'CAUCUS');
check('3-node: CAUCUS assigned to host (N0)', caucus && caucus.nodeId === 'N0');

// BUFFER goes to host (N0)
const buffer = segs3.find(s => s.segType === 'BUFFER');
check('3-node: BUFFER assigned to host (N0)', buffer && buffer.nodeId === 'N0');

// Timing: segments must be consecutive
let consecutive = true;
for (let i = 1; i < segs3.length; i++) {
  if (segs3[i].startMs !== segs3[i - 1].endMs) consecutive = false;
}
check('3-node: segments are consecutive', consecutive);

// Start time matches plan start
check('3-node: seg[0].startMs matches plan start',
  segs3[0].startMs === new Date('2026-06-01T12:00:00Z').getTime());

// Duration correctness
const qMs = plan3.quantum * 60 * 1000;
check('3-node: seg[0] durationMs = 2 * quantum', segs3[0].durationMs === 2 * qMs);
check('3-node: endMs = startMs + durationMs',
  segs3[0].endMs === segs3[0].startMs + segs3[0].durationMs);

// ── computeSegmentsMulti — 2-node fallback ─────────────────────────────────

const plan2 = {
  v:       2,
  title:   '2-Node Fallback',
  start:   '2026-06-01T12:00:00Z',
  quantum: 3,
  mode:    'LTX',
  nodes: [
    { id: 'N0', name: 'Earth HQ',    role: 'HOST',        delay: 0,   location: 'earth' },
    { id: 'N1', name: 'Mars Hab-01', role: 'PARTICIPANT',  delay: 900, location: 'mars'  },
  ],
  segments: [
    { type: 'TX', q: 2 },
    { type: 'RX', q: 2 },
  ],
};
const segs2 = LTX.computeSegmentsMulti(plan2);
check('2-node fallback: returns array', Array.isArray(segs2));
check('2-node fallback: correct segment count (2)', segs2.length === 2);
check('2-node fallback: has segType field', typeof segs2[0].segType === 'string');
check('2-node fallback: has nodeId field', typeof segs2[0].nodeId === 'string');

// ── buildDelayMatrix — 3-node ─────────────────────────────────────────────

const matrix3 = LTX.buildDelayMatrix(plan3);
check('buildDelayMatrix: returns array', Array.isArray(matrix3));
// 3 nodes -> 3*(3-1) = 6 pairs
check('buildDelayMatrix: 6 pairs for 3 nodes', matrix3.length === 6);

// Earth->Mars
const e2m = matrix3.find(p => p.fromId === 'N0' && p.toId === 'N1');
check('buildDelayMatrix: Earth->Mars pair exists', !!e2m);
check('buildDelayMatrix: Earth->Mars delay = 1240s', e2m && e2m.delaySeconds === 1240);

// Mars->Earth (symmetric)
const m2e = matrix3.find(p => p.fromId === 'N1' && p.toId === 'N0');
check('buildDelayMatrix: Mars->Earth delay = 1240s', m2e && m2e.delaySeconds === 1240);

// Earth->Jupiter
const e2j = matrix3.find(p => p.fromId === 'N0' && p.toId === 'N2');
check('buildDelayMatrix: Earth->Jupiter delay = 3240s', e2j && e2j.delaySeconds === 3240);

// Mars->Jupiter (non-host to non-host = 1240 + 3240 = 4480)
const m2j = matrix3.find(p => p.fromId === 'N1' && p.toId === 'N2');
check('buildDelayMatrix: Mars->Jupiter delay = 4480s', m2j && m2j.delaySeconds === 4480);

// Jupiter->Mars (non-host to non-host = 3240 + 1240 = 4480)
const j2m = matrix3.find(p => p.fromId === 'N2' && p.toId === 'N1');
check('buildDelayMatrix: Jupiter->Mars delay = 4480s', j2m && j2m.delaySeconds === 4480);

// All pairs have required fields
const allHaveFields = matrix3.every(p =>
  typeof p.fromId === 'string' &&
  typeof p.fromName === 'string' &&
  typeof p.toId === 'string' &&
  typeof p.toName === 'string' &&
  typeof p.delaySeconds === 'number'
);
check('buildDelayMatrix: all pairs have required fields', allHaveFields);

// No self-pairs
const noSelfPairs = matrix3.every(p => p.fromId !== p.toId);
check('buildDelayMatrix: no self-pairs', noSelfPairs);

// Name fields are correct
check('buildDelayMatrix: e2m fromName = Earth HQ', e2m && e2m.fromName === 'Earth HQ');
check('buildDelayMatrix: e2m toName = Mars Base', e2m && e2m.toName === 'Mars Base');

// ── buildDelayMatrix — 2-node ─────────────────────────────────────────────

const matrix2 = LTX.buildDelayMatrix(plan2);
check('buildDelayMatrix 2-node: 2 pairs', matrix2.length === 2);
const e2mArr = matrix2.find(p => p.fromId === 'N0' && p.toId === 'N1');
check('buildDelayMatrix 2-node: Earth->Mars delay = 900s', e2mArr && e2mArr.delaySeconds === 900);

// ── Summary ────────────────────────────────────────────────────────────────

console.log("\n" + passed + " passed  " + failed + " failed");
if (failed > 0) process.exit(1);
