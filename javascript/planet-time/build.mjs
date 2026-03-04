/**
 * build.mjs — ESM + IIFE bundle generator for planet-time.js
 *
 * Usage:  node build.mjs
 * Output: dist/planet-time.esm.js   — ES module (named exports + default)
 *         dist/planet-time.iife.js  — IIFE bundle (window.PlanetTime)
 *         dist/planet-time.d.ts     — TypeScript definitions
 *
 * No external dependencies — stdlib only.
 *
 * Strategy: the source file ends with:
 *
 *   const _exports = { VERSION, ... };
 *   if (typeof module !== 'undefined' && module.exports) { ... }
 *
 * The build script slices at the `// ── Exports` comment, strips the
 * conditional, and emits the three target formats.
 */

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC  = resolve(__dirname, 'planet-time.js');
const DIST = resolve(__dirname, 'dist');

mkdirSync(DIST, { recursive: true });

// ── Read source ───────────────────────────────────────────────────────────────

const src = readFileSync(SRC, 'utf8');

// Split at the exports section comment
const EXPORTS_MARKER = '\n// ── Exports ───';
const splitIdx = src.indexOf(EXPORTS_MARKER);
if (splitIdx === -1) throw new Error('Could not locate // ── Exports section in source');

// "body" is everything before the exports section
const body = src.slice(0, splitIdx);

// Parse the export names from `const _exports = { ... }` block
// Find the object literal
const exportsStart = src.indexOf('const _exports = {', splitIdx);
const exportsEnd   = src.indexOf('\n};', exportsStart) + 3; // include closing }
const exportsBlock = src.slice(exportsStart, exportsEnd);

// Extract all export names from the `const _exports = { ... }` block.
// Strip comments, then split on comma/newline and keep valid JS identifiers.
const exportNames = exportsBlock
  .replace(/\/\/[^\n]*/g, '')           // strip line comments
  .replace(/const _exports\s*=\s*\{/, '') // strip opening
  .replace(/\};[\s\S]*$/, '')            // strip closing and everything after
  .split(/[,\n\r]+/)                     // split on commas and newlines
  .map(s => s.trim())
  .filter(s => /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(s)); // valid JS identifiers only

const version = (src.match(/const VERSION = '([^']+)'/) || [])[1] || '?';

// ── Helpers ───────────────────────────────────────────────────────────────────

const banner = (fmt) =>
`// interplanet-planet-time v${version} — ${fmt}
// https://interplanet.live | MIT License
// Auto-generated — do not edit. Regenerate: node build.mjs
`;

// ── 1. CJS is just the source file unchanged ──────────────────────────────────

console.log(`✓  CJS: planet-time.js (source, no transformation needed)`);

// ── 2. ESM ────────────────────────────────────────────────────────────────────

const esmBody = body
  .replace(/^'use strict';\n/, '')  // implicit in ES modules
  .trimEnd();

const esmNamedExports = exportNames.map(n => `export { ${n} };`).join('\n');

const esm = [
  banner('ES module'),
  '',
  esmBody,
  '',
  `// Named exports`,
  esmNamedExports,
  '',
  `// Default export (full API object)`,
  `const _interplanet = {`,
  `  ${exportNames.join(',\n  ')},`,
  `};`,
  `export default _interplanet;`,
  '',
].join('\n');

writeFileSync(`${DIST}/planet-time.esm.js`, esm, 'utf8');
console.log(`✓  ESM: dist/planet-time.esm.js  (${exportNames.length} named exports)`);

// ── 3. IIFE ───────────────────────────────────────────────────────────────────

const iifeBody = body
  .replace(/^'use strict';\n/, '')  // hoisted to IIFE header
  .trimEnd();

const iife = [
  banner('IIFE / CDN bundle  —  window.PlanetTime'),
  `// CDN: https://cdn.jsdelivr.net/npm/interplanet-planet-time@${version}/dist/planet-time.iife.js`,
  '',
  `(function (global) {`,
  `  'use strict';`,
  '',
  // Indent the body by 2 spaces
  iifeBody.split('\n').map(l => (l ? '  ' + l : '')).join('\n'),
  '',
  `  const _exports = {`,
  exportNames.map(n => `    ${n},`).join('\n'),
  `  };`,
  '',
  `  if (typeof module !== 'undefined' && module.exports) {`,
  `    module.exports = _exports;`,
  `  } else {`,
  `    global.PlanetTime = _exports;`,
  `  }`,
  `})(typeof globalThis !== 'undefined' ? globalThis`,
  `  : typeof window     !== 'undefined' ? window`,
  `  : typeof global     !== 'undefined' ? global : this);`,
  '',
].join('\n');

writeFileSync(`${DIST}/planet-time.iife.js`, iife, 'utf8');
console.log(`✓  IIFE: dist/planet-time.iife.js`);

// ── 4. TypeScript definitions ─────────────────────────────────────────────────

const dts = `// Type definitions for interplanet-planet-time v${version}
// https://interplanet.live | MIT License

// ── Core types ────────────────────────────────────────────────────────────────

export interface PlanetData {
  name: string;
  symbol: string;
  /** Solar day duration in milliseconds */
  dayMs: number;
  /** Work-day shift start and end in local planet-hours */
  workStart: number;
  workEnd: number;
  [key: string]: unknown;
}

export interface PlanetTime {
  /** Planet name (e.g. "Mars") */
  planet: string;
  /** Planet symbol (e.g. "♂") */
  symbol: string;
  /** Local hour of the planet day (0–23) */
  hour: number;
  /** Local minute (0–59) */
  minute: number;
  /** Local second (0–59) */
  second: number;
  /** Fractional local hour (0.0–23.999) */
  localHour: number;
  /** Fraction of the planet day elapsed (0.0–1.0) */
  dayFraction: number;
  /** Planet-calendar day number since epoch */
  dayNumber: number;
  /** Day within the current planet year (1-based) */
  dayInYear: number;
  /** Planet year number */
  yearNumber: number;
  /** Which "work period" within the current week */
  periodInWeek: number;
  /** True if currently within a scheduled work period */
  isWorkPeriod: boolean;
  /** True if currently within a scheduled work-hour shift */
  isWorkHour: boolean;
  /** Short day-of-week abbreviation */
  dowShort: string;
  /** "HH:MM" time string */
  timeString: string;
  /** "HH:MM:SS" time string */
  timeStringFull: string;
  /** Mars only: sol number within the Mars year */
  solInfo?: { solInYear: number; solsPerYear: number } | null;
}

export interface MTC {
  /** Mars sol number since MY0 epoch */
  sol: number;
  /** Hour of the Mars sol (0–23) */
  hour: number;
  minute: number;
  second: number;
  /** "HH:MM" time string */
  mtcString: string;
}

export interface HelioXY {
  /** Heliocentric X in AU */
  x: number;
  /** Heliocentric Y in AU */
  y: number;
  /** Distance from Sun in AU */
  r: number;
  /** Ecliptic longitude in radians */
  lon: number;
}

export interface LineOfSight {
  /** Clear line of sight (no conjunction) */
  clear: boolean;
  /** Blocked — planet is behind the Sun */
  blocked: boolean;
  /** Degraded — near conjunction (3°–10°) */
  degraded: boolean;
  /** Solar elongation in degrees */
  elong_deg: number;
}

export interface MeetingWindow {
  /** Window start as Unix ms */
  startMs: number;
  /** Window end as Unix ms */
  endMs: number;
  /** Duration in minutes */
  durationMin: number;
  /** Fairness score 0–100 */
  fairnessScore: number;
}

export interface FairnessResult {
  /** Overall fairness score 0–100 */
  overall: number;
  /** 'good' | 'ok' | 'poor' */
  fairness: 'good' | 'ok' | 'poor';
  perParticipant: Array<{ index: number; tz: string; offHourCount: number; pct: number }>;
}

export interface PlanetZone {
  id: string;
  name: string;
  /** Offset in planet-hours */
  offsetH: number;
}

// ── API functions ─────────────────────────────────────────────────────────────

/** Library semver string */
export declare const VERSION: string;

// Constants
export declare const J2000_MS: number;
export declare const J2000_JD: number;
export declare const EARTH_DAY_MS: number;
export declare const AU_KM: number;
export declare const C_KMS: number;
export declare const AU_SECONDS: number;
export declare const MARS_EPOCH_MS: number;
export declare const MARS_SOL_MS: number;

// Data tables
export declare const PLANETS: Record<string, PlanetData>;
export declare const ORBITAL_ELEMENTS: unknown[];
export declare const LEAP_SECONDS: number[];
export declare const MARS_ZONES: PlanetZone[];
export declare const PLANET_ZONES: Record<string, PlanetZone[]>;
export declare const MOON_ZONES: PlanetZone[];
export declare const MERCURY_ZONES: PlanetZone[];
export declare const VENUS_ZONES: PlanetZone[];
export declare const JUPITER_ZONES: PlanetZone[];
export declare const SATURN_ZONES: PlanetZone[];
export declare const URANUS_ZONES: PlanetZone[];
export declare const NEPTUNE_ZONES: PlanetZone[];

/**
 * Compute planetary time for any solar-system body.
 * @param planet  Planet name (e.g. 'mars', 'earth', 'moon', ...)
 * @param date    Date object or UTC ms timestamp
 * @param tzOffsetHours  Planet timezone offset in local planet-hours (default 0)
 */
export declare function getPlanetTime(planet: string, date: Date | number, tzOffsetHours?: number): PlanetTime;

/**
 * Convert a UTC timestamp to planetary time at a given surface longitude.
 * @param utcTimestamp  Unix ms
 * @param planet        Planet name
 * @param longitude     Surface longitude in degrees (positive = east)
 */
export declare function convertUTCToPlanet(utcTimestamp: number, planet: string, longitude?: number): PlanetTime;

/** Return the UTC millisecond value from any Date-like value. */
export declare function convertPlanetToUTC(planetTimestamp: Date | number): number;

/**
 * Mars Coordinated Time (MTC) at a given UTC date.
 */
export declare function getMTC(date: Date | number): MTC;

/**
 * Mars local time at a specific MTC zone offset.
 * @param date    UTC date
 * @param offset  Zone offset in planet-hours
 */
export declare function getMarsTimeAtOffset(date: Date | number, offset: number): PlanetTime;

/**
 * Light travel time in seconds between two solar-system bodies.
 * @param bodyA  Body name string (e.g. 'earth', 'mars', 'moon')
 * @param bodyB  Body name string
 * @param date   Date or UTC ms
 */
export declare function lightTravelSeconds(bodyA: string, bodyB: string, date: Date | number): number;

/** Light-travel delay alias (SDK §5.5) */
export declare function calculateLightDelay(bodyA: string, bodyB: string, date: Date | number): number;

/**
 * Heliocentric X/Y position of a solar-system body.
 */
export declare function planetHelioXY(planet: string, date: Date | number): HelioXY;

/**
 * Earth–planet distance in AU.
 */
export declare function bodyDistance(bodyA: string, bodyB: string, date: Date | number): number;

/**
 * Check line-of-sight between two bodies (solar conjunction detection).
 */
export declare function checkLineOfSight(bodyA: string, bodyB: string, date: Date | number): LineOfSight;

/**
 * Lower-quartile (p25) light travel time over 360 orbital samples.
 * Conservative estimate for scheduling purposes.
 */
export declare function lowerQuartileLightTime(bodyA: string, bodyB: string, refMs: number): number;

/**
 * Find shared work-hour meeting windows between two locations.
 * @param locations  Array of { planet, tzOffset } objects
 * @param fromMs     Start of search window (UTC ms)
 * @param earthDays  Number of Earth days to scan (default 30)
 */
export declare function findMeetingWindows(
  locations: Array<{ planet: string; tzOffset?: number }>,
  fromMs: number,
  earthDays?: number
): MeetingWindow[];

/**
 * Calculate schedule fairness across multiple participants.
 */
export declare function calculateFairnessScore(
  windows: MeetingWindow[],
  participants: Array<{ tz: string }>
): FairnessResult;

/** Format a PlanetTime as a human-readable string. */
export declare function formatPlanetTime(pt: PlanetTime): string;

/** Format a light-travel duration as human-readable (e.g. '3.2 min', '1h 4m'). */
export declare function formatLightTime(seconds: number): string;

/** Format a PlanetTime as an ISO-8601-like string. */
export declare function formatPlanetTimeISO(pt: PlanetTime, date: Date | number): string;

/** Julian Ephemeris Day from a UTC Date or ms timestamp. */
export declare function toJDE(date: Date | number): number;

// ── Default export ────────────────────────────────────────────────────────────

declare const PlanetTime: {
  VERSION: typeof VERSION;
  getPlanetTime: typeof getPlanetTime;
  getMTC: typeof getMTC;
  getMarsTimeAtOffset: typeof getMarsTimeAtOffset;
  lightTravelSeconds: typeof lightTravelSeconds;
  calculateLightDelay: typeof calculateLightDelay;
  planetHelioXY: typeof planetHelioXY;
  bodyDistance: typeof bodyDistance;
  checkLineOfSight: typeof checkLineOfSight;
  lowerQuartileLightTime: typeof lowerQuartileLightTime;
  findMeetingWindows: typeof findMeetingWindows;
  calculateFairnessScore: typeof calculateFairnessScore;
  formatPlanetTime: typeof formatPlanetTime;
  formatLightTime: typeof formatLightTime;
  formatPlanetTimeISO: typeof formatPlanetTimeISO;
  convertUTCToPlanet: typeof convertUTCToPlanet;
  convertPlanetToUTC: typeof convertPlanetToUTC;
  toJDE: typeof toJDE;
  J2000_MS: number;
  J2000_JD: number;
  EARTH_DAY_MS: number;
  AU_KM: number;
  C_KMS: number;
  AU_SECONDS: number;
  MARS_EPOCH_MS: number;
  MARS_SOL_MS: number;
  PLANETS: typeof PLANETS;
  MARS_ZONES: typeof MARS_ZONES;
  [key: string]: unknown;
};

export default PlanetTime;
`;

writeFileSync(`${DIST}/planet-time.d.ts`, dts, 'utf8');
console.log(`✓  TypeScript: dist/planet-time.d.ts`);

// ── Summary ───────────────────────────────────────────────────────────────────

console.log(`\nBuild complete — interplanet-planet-time v${version}`);
console.log(`  dist/planet-time.esm.js   ${(esm.length / 1024).toFixed(1)} KB`);
console.log(`  dist/planet-time.iife.js  ${(iife.length / 1024).toFixed(1)} KB`);
console.log(`  dist/planet-time.d.ts     ${(dts.length / 1024).toFixed(1)} KB`);
