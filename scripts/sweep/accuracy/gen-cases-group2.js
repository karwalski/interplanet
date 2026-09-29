#!/usr/bin/env node
// Planet-time accuracy check beyond the fixtures (issue #38), for the ports in
// scripts/sweep/ports-group2.txt.
//
//   node gen-cases-group2.js                 write instants-group2.txt (200 instants, fixed seed)
//   node gen-cases-group2.js --compare FILE  compare a port's output (FILE or - for stdin)
//                                            with javascript/planet-time/planet-time.js
//
// Each port harness (scripts/sweep/accuracy/<port>/) reads instants-group2.txt
// (one integer UTC millisecond per line) and prints, per instant, one line per
// body plus one MTC line, tab-separated:
//
//   <ms> <body> <hour> <minute> <second> <dayNumber> <dayInYear> <yearNumber>
//        <periodInWeek> <isWorkPeriod 0|1> <isWorkHour 0|1> <lightSecondsToEarth>
//   <ms> mtc <sol> <hour> <minute> <second>
//
// Bodies: mercury venus earth mars jupiter saturn uranus neptune moon. A port
// that has no moon prints no moon line (reported as missing, not failed).
// lightSecondsToEarth is lightTravelSeconds(body, 'earth') and must agree
// within 1 s; every other field must match exactly.
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..', '..');
const PT = require(path.join(ROOT, 'javascript', 'planet-time', 'planet-time.js'));
const INSTANTS = path.join(__dirname, 'instants-group2.txt');
const BODIES = ['mercury', 'venus', 'earth', 'mars', 'jupiter', 'saturn', 'uranus', 'neptune', 'moon'];
const N = 200;
const SEED = 38;
const FROM = Date.UTC(1990, 0, 1);
const TO = Date.UTC(2100, 0, 1);

function mulberry32(a) {
  return function () {
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function generate() {
  const rnd = mulberry32(SEED);
  const out = [];
  for (let i = 0; i < N; i++) out.push(FROM + Math.floor(rnd() * (TO - FROM)));
  fs.writeFileSync(INSTANTS, out.join('\n') + '\n');
  console.log(`wrote ${out.length} instants to ${path.relative(process.cwd(), INSTANTS)}`);
}

function expected(ms, body) {
  const d = new Date(ms);
  const pt = PT.getPlanetTime(body, d);
  return {
    hour: pt.hour, minute: pt.minute, second: pt.second,
    dayNumber: pt.dayNumber, dayInYear: pt.dayInYear, yearNumber: pt.yearNumber,
    periodInWeek: pt.periodInWeek, isWorkPeriod: pt.isWorkPeriod ? 1 : 0,
    isWorkHour: pt.isWorkHour ? 1 : 0,
    light: PT.lightTravelSeconds(body, 'earth', d),
  };
}

const FIELDS = ['hour', 'minute', 'second', 'dayNumber', 'dayInYear', 'yearNumber',
  'periodInWeek', 'isWorkPeriod', 'isWorkHour'];

function compare(file) {
  const text = fs.readFileSync(file === '-' ? 0 : file, 'utf8');
  const instants = fs.readFileSync(INSTANTS, 'utf8').trim().split('\n').map(Number);
  const seen = new Set();
  let checked = 0, failed = 0, bad = 0;
  const failures = [];
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line) continue;
    const c = line.split(/\t|\s+/);
    const ms = Number(c[0]);
    if (!Number.isFinite(ms) || c.length < 2) { bad++; continue; }
    const body = c[1];
    const key = `${ms} ${body}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const errs = [];
    if (body === 'mtc') {
      const m = PT.getMTC(new Date(ms));
      const got = c.slice(2, 6).map(Number);
      const want = [m.sol, m.hour, m.minute, m.second];
      ['sol', 'hour', 'minute', 'second'].forEach((f, i) => {
        if (got[i] !== want[i]) errs.push(`${f} got ${c[2 + i]} want ${want[i]}`);
      });
    } else if (BODIES.includes(body)) {
      const e = expected(ms, body);
      FIELDS.forEach((f, i) => {
        const got = Number(c[2 + i]);
        if (got !== e[f]) errs.push(`${f} got ${c[2 + i]} want ${e[f]}`);
      });
      const lt = Number(c[11]);
      if (!(Math.abs(lt - e.light) <= 1)) errs.push(`light got ${c[11]} want ${e.light.toFixed(3)}`);
    } else { bad++; continue; }
    checked++;
    if (errs.length) { failed++; if (failures.length < 25) failures.push(`${new Date(ms).toISOString()} (${ms}) ${body}: ${errs.join('; ')}`); }
  }
  const missing = [];
  for (const ms of instants) {
    for (const b of [...BODIES, 'mtc']) if (!seen.has(`${ms} ${b}`)) missing.push(b);
  }
  const missingBodies = [...new Set(missing)];
  for (const f of failures) console.log('FAIL ' + f);
  if (bad) console.log(`unparsed lines: ${bad}`);
  console.log(`accuracy: ${checked} checked, ${checked - failed} agree, ${failed} disagree` +
    (missing.length ? `, ${missing.length} missing (${missingBodies.join(', ')})` : ''));
  // A port without a moon is not a failure; anything else missing is.
  const hardMissing = missing.filter((b) => b !== 'moon').length;
  process.exit(failed || hardMissing || bad || checked === 0 ? 1 : 0);
}

const args = process.argv.slice(2);
if (args[0] === '--compare') compare(args[1] || '-');
else generate();
