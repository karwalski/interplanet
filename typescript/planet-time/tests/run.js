'use strict';
/**
 * run.js — Unit tests for @interplanet/time TypeScript library.
 * Story 18.5 · No external test framework · Runs with: node tests/run.js
 * Requires: npm run build first (or run via Makefile: make test)
 */

const assert = require('assert');
const ipt    = require('../dist/cjs/index.js');

let passed = 0;
let failed = 0;

function check(name, cond) {
  if (cond) { passed++; }
  else { failed++; console.log('FAIL:', name); }
}

function approx(name, actual, expected, delta) {
  const ok = Math.abs(actual - expected) <= delta;
  if (ok) { passed++; }
  else { failed++; console.log(`FAIL: ${name} — expected ${expected}, got ${actual}`); }
}

// ── Constants ──────────────────────────────────────────────────────────────

console.log('\n── Constants ────────────────────────────────');
check('J2000_MS is number',          typeof ipt.J2000_MS === 'number');
check('J2000_MS == 946728000000',    ipt.J2000_MS === 946728000000);
check('J2000_JD == 2451545.0',       ipt.J2000_JD === 2451545.0);
check('EARTH_DAY_MS == 86400000',    ipt.EARTH_DAY_MS === 86400000);
check('MARS_SOL_MS == 88775244',     ipt.MARS_SOL_MS === 88775244);
check('MARS_EPOCH_MS < 0',           ipt.MARS_EPOCH_MS < 0);
approx('AU_SECONDS ≈ 499.004',       ipt.AU_SECONDS, 499.004, 0.01);
check('VERSION is string',           typeof ipt.VERSION === 'string');
check('VERSION matches semver',      /^\d+\.\d+\.\d+$/.test(ipt.VERSION));

// ── PLANETS data ───────────────────────────────────────────────────────────

console.log('\n── PLANETS ──────────────────────────────────');
check('PLANETS.earth.name',          ipt.PLANETS.earth.name === 'Earth');
check('PLANETS.mars.name',           ipt.PLANETS.mars.name === 'Mars');
check('PLANETS.moon.name',           ipt.PLANETS.moon.name === 'Moon');
check('PLANETS.earth.solarDayMs',    ipt.PLANETS.earth.solarDayMs === 86400000);
check('PLANETS.mars.solarDayMs',     ipt.PLANETS.mars.solarDayMs === 88775244);
check('PLANETS.earth.workHoursStart', ipt.PLANETS.earth.workHoursStart === 9);
check('PLANETS.earth.workHoursEnd',  ipt.PLANETS.earth.workHoursEnd === 17);

// ── jde / jc ───────────────────────────────────────────────────────────────

console.log('\n── jde / jc ─────────────────────────────────');
approx('jde(J2000_MS) ≈ J2000_JD',  ipt.jde(ipt.J2000_MS), ipt.J2000_JD, 0.001);
approx('jc(J2000_MS) ≈ 0',          ipt.jc(ipt.J2000_MS), 0, 0.001);

// ── getMTC ─────────────────────────────────────────────────────────────────

console.log('\n── getMTC ───────────────────────────────────');
const mtc = ipt.getMTC(ipt.J2000_MS);
check('MTC sol >= 0',                mtc.sol >= 0);
check('MTC hour [0,23]',             mtc.hour >= 0 && mtc.hour < 24);
check('MTC minute [0,59]',           mtc.minute >= 0 && mtc.minute < 60);
check('MTC hour at J2000 [14,17]',   mtc.hour >= 14 && mtc.hour <= 17);
check('MTC mtcString format',        /^\d{2}:\d{2}$/.test(mtc.mtcString));

// ── getPlanetTime ──────────────────────────────────────────────────────────

console.log('\n── getPlanetTime ────────────────────────────');
const j2000 = ipt.J2000_MS;

// Earth at epoch
const earth = ipt.getPlanetTime('earth', j2000);
check('Earth hour == 0 at epoch',    earth.hour === 0);
check('Earth minute valid',          earth.minute >= 0 && earth.minute < 60);
check('Earth second valid',          earth.second >= 0 && earth.second < 60);
check('Earth solInfo null',          earth.solInfo === null);
check('Earth timeString format',     /^\d{2}:\d{2}$/.test(earth.timeString));
check('Earth timeStringFull format', /^\d{2}:\d{2}:\d{2}$/.test(earth.timeStringFull));
check('Earth planet name',           earth.planet === 'Earth');
check('Earth symbol',                earth.symbol === '♁');

// Moon uses Earth data
const moon = ipt.getPlanetTime('moon', j2000);
check('Moon hour == Earth hour',     moon.hour === earth.hour);

// Mars at epoch
const mars = ipt.getPlanetTime('mars', j2000);
check('Mars hour [0,23]',            mars.hour >= 0 && mars.hour < 24);
check('Mars solInfo not null',       mars.solInfo !== null);
check('Mars solsPerYear [660,675]',  mars.solInfo.solsPerYear >= 660 && mars.solInfo.solsPerYear <= 675);

// All 9 planets
const PLANETS_LIST = ['mercury','venus','earth','mars','jupiter','saturn','uranus','neptune','moon'];
for (const p of PLANETS_LIST) {
  const pt = ipt.getPlanetTime(p, j2000);
  check(`${p} hour [0,23]`, pt.hour >= 0 && pt.hour < 24);
}

// ── lightTravelSeconds ─────────────────────────────────────────────────────

console.log('\n── lightTravelSeconds ───────────────────────');
const aug2003 = 1061942400000;
const oct2020 = 1602547200000;
const nov2023 = 1699056000000;

approx('E-Mars 2003 ≈ 186 s',       ipt.lightTravelSeconds('earth','mars',aug2003), 186, 20);
approx('E-Mars 2020 ≈ 207 s',       ipt.lightTravelSeconds('earth','mars',oct2020), 207, 25);
approx('E-Jupiter 2023 ≈ 2010 s',   ipt.lightTravelSeconds('earth','jupiter',nov2023), 2010, 150);
check('E-Moon >= 0',                 ipt.lightTravelSeconds('earth','moon',aug2003) >= 0);
// Symmetry
const fwd = ipt.lightTravelSeconds('earth','mars',aug2003);
const rev = ipt.lightTravelSeconds('mars','earth',aug2003);
approx('Light time symmetric',      fwd, rev, 0.001);

// ── checkLineOfSight ───────────────────────────────────────────────────────

console.log('\n── checkLineOfSight ─────────────────────────');
const los1 = ipt.checkLineOfSight('earth','mars',aug2003);
check('E-Mars 2003: not blocked',    !los1.blocked);
check('E-Mars 2003: elong > 120°',   los1.elongDeg > 120);

const los2 = ipt.checkLineOfSight('earth','moon',aug2003);
check('E-Moon: clear',               los2.clear);
check('E-Moon: not blocked',         !los2.blocked);

const los3 = ipt.checkLineOfSight('earth','mars',aug2003);
check('LOS flags consistent',        (los3.clear || los3.degraded || los3.blocked) && !(los3.clear && los3.blocked));

// ── formatLightTime ────────────────────────────────────────────────────────

console.log('\n── formatLightTime ──────────────────────────');
check('45 s → "45 s"',               ipt.formatLightTime(45) === '45 s');
check('60 s → "1 min"',              ipt.formatLightTime(60) === '1 min');
check('186 s → contains "min"',      ipt.formatLightTime(186).includes('min'));

// ── findMeetingWindows ─────────────────────────────────────────────────────

console.log('\n── findMeetingWindows ───────────────────────');
const baseMs = 1700000000000;
const wins = ipt.findMeetingWindows('earth','mars', baseMs, 7);
check('findMeetingWindows returns array', Array.isArray(wins));
if (wins.length > 0) {
  check('window startMs < endMs',    wins[0].startMs < wins[0].endMs);
  check('window durationMinutes > 0', wins[0].durationMinutes > 0);
}

// ── getMarsTimeAtOffset ────────────────────────────────────────────────────

console.log('\n── getMarsTimeAtOffset ──────────────────────');
const mlo = ipt.getMarsTimeAtOffset(j2000, 3);
check('MarsLocalTime hour [0,23]',   mlo.hour >= 0 && mlo.hour < 24);
check('MarsLocalTime offsetHours',   mlo.offsetHours === 3);
check('MarsLocalTime timeString fmt', /^\d{2}:\d{2}$/.test(mlo.timeString));

// ── lowerQuartileLightTime ─────────────────────────────────────────────────

console.log('\n── lowerQuartileLightTime ───────────────────');
const q25 = ipt.lowerQuartileLightTime('earth','mars', j2000);
check('E-Mars q25 > 100 s',         q25 > 100);
check('E-Mars q25 < 1250 s',        q25 < 1250);

// ── Summary ────────────────────────────────────────────────────────────────

console.log('\n══════════════════════════════════════════');
console.log(`${passed} passed  ${failed} failed`);
if (failed > 0) process.exit(1);
