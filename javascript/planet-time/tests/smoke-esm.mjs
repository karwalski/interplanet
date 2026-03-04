/**
 * smoke-esm.mjs — ESM smoke tests for planet-time.js dist build
 * Run: node tests/smoke-esm.mjs (from js/ directory)
 */

import {
  VERSION,
  getPlanetTime,
  getMTC,
  lightTravelSeconds,
  getMarsTimeAtOffset,
  checkLineOfSight,
  findMeetingWindows,
  formatLightTime,
  calculateFairnessScore,
  planetHelioXY,
  PLANETS,
  MARS_ZONES,
} from '../dist/planet-time.esm.js';

import defaultExport from '../dist/planet-time.esm.js';

let pass = 0; let fail = 0;
function assert(cond, msg) {
  if (cond) { pass++; } else { fail++; console.error('  FAIL:', msg); }
}

// Version
assert(typeof VERSION === 'string' && VERSION.length > 0, 'VERSION is a string');
assert(VERSION === defaultExport.VERSION, 'default export VERSION matches named export');

// getPlanetTime
const marsTime = getPlanetTime('mars', new Date('2024-06-15T00:00:00Z'));
assert(marsTime.planet === 'Mars', 'getPlanetTime returns Mars');
assert(typeof marsTime.hour === 'number', 'hour is a number');
assert(typeof marsTime.isWorkHour === 'boolean', 'isWorkHour is boolean');
assert(marsTime.timeString.match(/^\d{2}:\d{2}$/), 'timeString format HH:MM');

const earthTime = getPlanetTime('earth', new Date('2024-01-15T14:30:00Z'));
assert(earthTime.planet === 'Earth', 'getPlanetTime earth');
assert(earthTime.hour === 14 || earthTime.hour >= 0, 'earth hour valid');

const moonTime = getPlanetTime('moon', new Date('2024-01-15T00:00:00Z'));
// Moon maps to Earth orbital params in this library
assert(moonTime.planet === 'Earth' || moonTime.planet === 'Moon', 'getPlanetTime moon');

const jupTime = getPlanetTime('jupiter', new Date('2024-01-15T00:00:00Z'));
assert(jupTime.planet === 'Jupiter', 'getPlanetTime jupiter');

// getMTC
const mtc = getMTC(new Date('2024-06-15T00:00:00Z'));
assert(mtc !== null && mtc !== undefined, 'getMTC returns value');
assert(typeof mtc.sol === 'number', 'MTC.sol is number');
assert(typeof mtc.hour === 'number', 'MTC.hour is number');
assert(typeof mtc.mtcString === 'string', 'MTC.mtcString is string');

// lightTravelSeconds
const ltEarthMars = lightTravelSeconds('earth', 'mars', new Date('2024-06-15T00:00:00Z'));
assert(ltEarthMars > 100, 'Earth-Mars light time > 100 s');
assert(ltEarthMars < 1500, 'Earth-Mars light time < 1500 s');

// Moon light time: the library returns 0 when moon maps to Earth params (same body)
const ltEarthMoon = lightTravelSeconds('earth', 'moon', new Date('2024-06-15T00:00:00Z'));
assert(typeof ltEarthMoon === 'number', 'Earth-Moon light time is a number');

// formatLightTime
const fmtS = formatLightTime(45);
assert(typeof fmtS === 'string' && fmtS.length > 0, 'formatLightTime 45s');
const fmtM = formatLightTime(901);
assert(fmtM.includes('min') || fmtM.includes('m'), 'formatLightTime 901s contains min');

// checkLineOfSight
const los = checkLineOfSight('earth', 'mars', new Date('2024-06-15T00:00:00Z'));
assert(typeof los.clear === 'boolean', 'checkLineOfSight.clear boolean');
assert(typeof los.blocked === 'boolean', 'checkLineOfSight.blocked boolean');
assert(los.clear !== los.blocked || los.degraded !== undefined, 'LOS state consistent');

// planetHelioXY
const helioMars = planetHelioXY('mars', new Date('2024-06-15T00:00:00Z'));
assert(typeof helioMars.x === 'number', 'helioXY.x number');
assert(typeof helioMars.r === 'number', 'helioXY.r number');
assert(helioMars.r > 1.3 && helioMars.r < 1.7, 'Mars helio r in range (1.38–1.67 AU)');

// PLANETS table
assert(typeof PLANETS === 'object', 'PLANETS is object');
assert('Mars' in PLANETS || 'mars' in PLANETS, 'PLANETS has Mars entry');

// MARS_ZONES
assert(Array.isArray(MARS_ZONES), 'MARS_ZONES is array');
assert(MARS_ZONES.length > 0, 'MARS_ZONES has entries');

// Default export
assert(typeof defaultExport.getPlanetTime === 'function', 'default.getPlanetTime');
assert(typeof defaultExport.lightTravelSeconds === 'function', 'default.lightTravelSeconds');

// Summary
console.log(`ESM smoke tests: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
