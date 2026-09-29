#!/usr/bin/env node
/**
 * gen.js: inputs and expected values for the planet-time accuracy sweep.
 *
 *   node gen.js <out dir> [count=200] [seed=38]
 *
 * Draws <count> instants uniformly from 1990-01-01 to 2100-01-01 (UTC, whole
 * milliseconds, seeded so every run and every port sees the same ones) and
 * writes, for all 9 bodies:
 *   inputs.txt    "<body> <utc_ms>" per line, the probes' input
 *   expected.tsv  javascript/planet-time/planet-time.js on the same inputs,
 *                 in the probes' output format (see README.md)
 */
'use strict';

const fs = require('fs');
const path = require('path');
const PT = require('../../../javascript/planet-time/planet-time.js');

const outDir = process.argv[2];
if (!outDir) { console.error('usage: gen.js <out dir> [count] [seed]'); process.exit(2); }
const count = Number(process.argv[3] || 200);
let seed = Number(process.argv[4] || 38) >>> 0;

// mulberry32
function rand() {
  seed = (seed + 0x6D2B79F5) >>> 0;
  let t = seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

const BODIES = ['mercury', 'venus', 'earth', 'mars', 'jupiter', 'saturn', 'uranus', 'neptune', 'moon'];
const FROM = Date.UTC(1990, 0, 1), TO = Date.UTC(2100, 0, 1);
const instants = [];
for (let i = 0; i < count; i++) instants.push(FROM + Math.floor(rand() * (TO - FROM)));

const inputs = [], expected = [];
for (const ms of instants) {
  const d = new Date(ms);
  for (const body of BODIES) {
    inputs.push(`${body} ${ms}`);
    const pt = PT.getPlanetTime(body, d, 0);
    const light = (body === 'earth' || body === 'moon') ? '-' : PT.lightTravelSeconds('earth', body, d).toFixed(3);
    let mtc = ['-', '-', '-', '-'];
    if (body === 'mars') { const m = PT.getMTC(d); mtc = [m.sol, m.hour, m.minute, m.second]; }
    expected.push([body, ms, pt.hour, pt.minute, pt.second, pt.dayNumber, light, ...mtc].join('\t'));
  }
}

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'inputs.txt'), inputs.join('\n') + '\n');
fs.writeFileSync(path.join(outDir, 'expected.tsv'), expected.join('\n') + '\n');
console.log(`${count} instants x ${BODIES.length} bodies = ${inputs.length} cases (planet-time.js ${PT.VERSION})`);
