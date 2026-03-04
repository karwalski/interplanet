'use strict';
/**
 * fixtures.js — Cross-language fixture validation for @interplanet/time TypeScript library.
 * Reads libinterplanet/fixtures/reference.json and checks results match JS/Java/Python.
 * Story 18.5
 */

const path = require('path');
const fs   = require('fs');
const ipt  = require('../dist/cjs/index.js');

const FIXTURE_PATH = path.resolve(__dirname, '../../../c/planet-time/fixtures/reference.json');

if (!fs.existsSync(FIXTURE_PATH)) {
  console.log('SKIP: fixture file not found at', FIXTURE_PATH);
  console.log('0 passed  0 failed  (fixtures skipped)');
  process.exit(0);
}

const data    = JSON.parse(fs.readFileSync(FIXTURE_PATH, 'utf8'));
const entries = data.entries;

let passed = 0;
let failed = 0;

function check(name, cond) {
  if (cond) { passed++; }
  else { failed++; console.log('FAIL:', name); }
}

function approx(name, actual, expected, delta) {
  const ok = Math.abs(actual - expected) <= delta;
  if (ok) { passed++; }
  else { failed++; console.log(`FAIL: ${name} — expected ${expected.toFixed(3)}, got ${actual.toFixed(3)}`); }
}

let count = 0;

for (const entry of entries) {
  const { utc_ms, planet, hour: expHour, minute: expMin, light_travel_s: lt } = entry;

  // Skip unknown planet keys
  try {
    const pt  = ipt.getPlanetTime(planet, utc_ms);
    const tag = `${planet}@${utc_ms}`;

    check(`${tag} hour=${expHour}`,  pt.hour === expHour);
    check(`${tag} minute=${expMin}`, pt.minute === expMin);

    if (lt != null && planet !== 'earth' && planet !== 'moon') {
      const actLt = ipt.lightTravelSeconds('earth', planet, utc_ms);
      approx(`${tag} lightTravel`, actLt, lt, 2.0);
    }

    count++;
  } catch (e) {
    failed++;
    console.log(`FAIL: ${planet}@${utc_ms} — ${e.message}`);
  }
}

console.log(`Fixture entries checked: ${count}`);
console.log(`${passed} passed  ${failed} failed`);

if (failed > 0) process.exit(1);
