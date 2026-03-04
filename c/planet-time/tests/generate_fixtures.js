#!/usr/bin/env node
/**
 * generate_fixtures.js — Generate cross-language reference fixtures
 *
 * Runs the JavaScript planet-time.js library against a set of known dates
 * and writes fixtures/reference.json for validation by C tests.
 *
 * Usage:
 *   node tests/generate_fixtures.js
 * or via Makefile:
 *   make fixtures
 */

'use strict';

const path = require('path');
const fs   = require('fs');

/* Load the JS reference library.
   Try the co-located interplanet-github copy first, then the repo root. */
const candidates = [
  path.join(__dirname, '../../../javascript/planet-time/planet-time.js'), // interplanet-github/javascript/planet-time/
  path.join(__dirname, '../../javascript/planet-time/planet-time.js'),
  path.join(__dirname, '../planet-time.js'),
  path.join(__dirname, '../../planet-time.js'),
];

let PT;
for (const c of candidates) {
  if (fs.existsSync(c)) {
    PT = require(c);
    console.log(`Loaded planet-time.js from: ${c}`);
    break;
  }
}
if (!PT) {
  console.error('ERROR: planet-time.js not found. Tried:\n  ' + candidates.join('\n  '));
  process.exit(1);
}

/* ── Reference dates ─────────────────────────────────────────────────────── */

const DATES = [
  { label: 'J2000',         ms: 946728000000  },  /* 2000-01-01T12:00:00Z */
  { label: 'mars_close_2003', ms: 1061977860000 },  /* 2003-08-27T09:51:00Z */
  { label: 'mars_opp_2020',   ms: 1602631560000 },  /* 2020-10-13T23:26:00Z */
  { label: 'jup_opp_2023',    ms: 1698969600000 },  /* 2023-11-03T00:00:00Z */
  { label: '2025_start',      ms: 1735689600000 },  /* 2025-01-01T00:00:00Z */
  { label: '2024_mid',        ms: 1718452800000 },  /* 2024-06-15T12:00:00Z */
];

const PLANETS = [
  'mercury', 'venus', 'earth', 'mars',
  'jupiter', 'saturn', 'uranus', 'neptune', 'moon',
];

/* ── Generate entries ────────────────────────────────────────────────────── */

const entries = [];

for (const { label, ms } of DATES) {
  const d = new Date(ms);

  for (const planet of PLANETS) {
    /* Planet time at UTC+0 */
    let pt;
    try {
      pt = PT.getPlanetTime(planet, d, 0);
    } catch (e) {
      console.error(`ERROR: getPlanetTime(${planet}, ${label}): ${e.message}`);
      continue;
    }

    /* Light travel from Earth (skip Earth-Earth and Moon-Earth) */
    let lightTravel_s = null;
    if (planet !== 'earth' && planet !== 'moon') {
      try {
        lightTravel_s = PT.lightTravelSeconds('earth', planet, d);
      } catch (e) {
        lightTravel_s = null;
      }
    }

    /* MTC for Mars */
    let mtc = null;
    if (planet === 'mars') {
      try {
        const raw = PT.getMTC(d);
        mtc = { sol: raw.sol, hour: raw.hour, minute: raw.minute, second: raw.second };
      } catch (e) {
        mtc = null;
      }
    }

    /* Heliocentric distance */
    let helioR_au = null;
    try {
      const h = PT.planetHelioXY(planet === 'moon' ? 'earth' : planet, d);
      helioR_au = h.r;
    } catch (e) {
      helioR_au = null;
    }

    entries.push({
      /* Identification */
      date_label:    label,
      utc_ms:        ms,
      planet:        planet,

      /* Planet time */
      hour:          pt.hour,
      minute:        pt.minute,
      second:        pt.second,
      local_hour:    pt.localHour,
      day_fraction:  pt.dayFraction,
      day_number:    pt.dayNumber,
      day_in_year:   pt.dayInYear,
      year_number:   pt.yearNumber,
      period_in_week: pt.periodInWeek,
      is_work_period: pt.isWorkPeriod ? 1 : 0,
      is_work_hour:   pt.isWorkHour   ? 1 : 0,
      time_str:       pt.timeString,
      time_str_full:  pt.timeStringFull,

      /* Mars sol info (null for other planets) */
      sol_in_year:   pt.solInfo ? pt.solInfo.solInYear : null,
      sols_per_year: pt.solInfo ? pt.solInfo.solsPerYear : null,

      /* Auxiliary */
      light_travel_s: lightTravel_s,
      mtc:            mtc,
      helio_r_au:     helioR_au,
    });
  }
}

/* ── Write output ────────────────────────────────────────────────────────── */

const outDir  = path.join(__dirname, '../fixtures');
const outFile = path.join(outDir, 'reference.json');

if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

const payload = {
  generated:    new Date().toISOString(),
  js_version:   PT.VERSION || 'unknown',
  entry_count:  entries.length,
  dates:        DATES.map(d => ({ label: d.label, utc_ms: d.ms })),
  planets:      PLANETS,
  entries,
};

fs.writeFileSync(outFile, JSON.stringify(payload, null, 2) + '\n');

console.log(`\nWrote ${entries.length} fixture entries → ${outFile}`);
console.log(`Dates: ${DATES.length}  ×  Planets: ${PLANETS.length}  =  ${DATES.length * PLANETS.length} expected`);

if (entries.length < 48) {
  console.error(`WARNING: fewer than 48 entries (got ${entries.length})`);
  process.exit(1);
}
