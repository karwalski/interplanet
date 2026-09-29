#!/usr/bin/env node
/**
 * js-reference-check.js: check that the JavaScript reference library still
 * reproduces c/planet-time/fixtures/reference.json.
 *
 * The other ports are tested against reference.json, which was generated
 * from javascript/planet-time/planet-time.js by c/planet-time/tests/generate_fixtures.js.
 * This script re-runs that generator, compares every field of every entry
 * with the committed file (floating-point fields to a relative tolerance of
 * 1e-9, everything else exactly), and restores the committed file afterwards.
 *
 * Usage:  node scripts/conformance/js-reference-check.js
 * Exit code: 0 if every entry matches, 1 otherwise.
 */

'use strict';

const fs   = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT      = path.resolve(__dirname, '..', '..');
const FIXTURE   = path.join(ROOT, 'c/planet-time/fixtures/reference.json');
const GENERATOR = path.join(ROOT, 'c/planet-time/tests/generate_fixtures.js');
const REL_TOL   = 1e-9;

const committedText = fs.readFileSync(FIXTURE, 'utf8');
let regeneratedText;
try {
  execFileSync(process.execPath, [GENERATOR], { stdio: ['ignore', 'ignore', 'inherit'] });
  regeneratedText = fs.readFileSync(FIXTURE, 'utf8');
} finally {
  fs.writeFileSync(FIXTURE, committedText);
}

const committed   = JSON.parse(committedText).entries;
const regenerated = JSON.parse(regeneratedText).entries;

function same(a, b) {
  if (typeof a === 'number' && typeof b === 'number' && !(Number.isInteger(a) && Number.isInteger(b))) {
    return Math.abs(a - b) <= REL_TOL * Math.max(1, Math.abs(a), Math.abs(b));
  }
  return JSON.stringify(a) === JSON.stringify(b);
}

let passed = 0, failed = 0;
if (regenerated.length !== committed.length) {
  console.log(`FAIL: entry count ${regenerated.length}, expected ${committed.length}`);
  failed++;
}
committed.forEach((want, i) => {
  const got = regenerated[i] || {};
  const bad = Object.keys(want).filter(k => !same(want[k], got[k]));
  if (bad.length) {
    failed++;
    for (const k of bad) console.log(`FAIL: ${want.planet}@${want.utc_ms} ${k}: expected ${want[k]}, got ${got[k]}`);
  } else {
    passed++;
  }
});

console.log(`Fixture entries checked: ${committed.length}`);
console.log(`${passed} passed  ${failed} failed`);
process.exit(failed ? 1 : 0);
