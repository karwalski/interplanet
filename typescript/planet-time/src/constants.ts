/**
 * constants.ts — Numeric constants and planet data for @interplanet/time
 */

import type { Planet } from './types.js';

export const VERSION = '1.1.0';

export const J2000_MS       = Date.UTC(2000, 0, 1, 12, 0, 0, 0);
export const J2000_JD       = 2451545.0;
export const EARTH_DAY_MS   = 86_400_000;
export const MARS_EPOCH_MS  = Date.UTC(1953, 4, 24, 9, 3, 58, 464);
export const MARS_SOL_MS    = 88_775_244;
export const AU_KM          = 149_597_870.7;
export const C_KMS          = 299_792.458;
export const AU_SECONDS     = AU_KM / C_KMS;

// ── Planet data ──────────────────────────────────────────────────────────────

export interface PlanetData {
  name: string;
  symbol: string;
  solarDayMs: number;
  siderealYrMs: number;
  daysPerPeriod: number;
  periodsPerWeek: number;
  workPeriodsPerWeek: number;
  workHoursStart: number;
  workHoursEnd: number;
  epochMs: number;
  earthClockSched?: boolean;  // true for Mercury and Venus
}

export const PLANETS: Record<Planet, PlanetData> = {
  mercury: {
    name: 'Mercury', symbol: '☿',
    solarDayMs: 175.9408 * EARTH_DAY_MS,
    siderealYrMs: 87.9691 * EARTH_DAY_MS,
    daysPerPeriod: 1, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 9, workHoursEnd: 17,
    epochMs: J2000_MS,
    earthClockSched: true,
  },
  venus: {
    name: 'Venus', symbol: '♀',
    solarDayMs: 116.7500 * EARTH_DAY_MS,
    siderealYrMs: 224.701 * EARTH_DAY_MS,
    daysPerPeriod: 1, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 9, workHoursEnd: 17,
    epochMs: J2000_MS,
    earthClockSched: true,
  },
  earth: {
    name: 'Earth', symbol: '♁',
    solarDayMs: 86_400_000,
    siderealYrMs: 365.25636 * EARTH_DAY_MS,
    daysPerPeriod: 1, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 9, workHoursEnd: 17,
    epochMs: J2000_MS,
  },
  mars: {
    name: 'Mars', symbol: '♂',
    solarDayMs: 88_775_244,
    siderealYrMs: 686.9957 * EARTH_DAY_MS,
    daysPerPeriod: 1, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 9, workHoursEnd: 17,
    epochMs: MARS_EPOCH_MS,
  },
  jupiter: {
    name: 'Jupiter', symbol: '♃',
    solarDayMs: 9.9250 * 3_600_000,
    siderealYrMs: 4332.589 * EARTH_DAY_MS,
    daysPerPeriod: 2.5, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 8, workHoursEnd: 16,
    epochMs: J2000_MS,
  },
  saturn: {
    name: 'Saturn', symbol: '♄',
    solarDayMs: 38_080_800,  // Mankovich et al. 2023: 10.578 h
    siderealYrMs: 10759.22 * EARTH_DAY_MS,
    daysPerPeriod: 2.25, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 8, workHoursEnd: 16,
    epochMs: J2000_MS,
  },
  uranus: {
    name: 'Uranus', symbol: '⛢',
    solarDayMs: 17.2479 * 3_600_000,
    siderealYrMs: 30688.5 * EARTH_DAY_MS,
    daysPerPeriod: 1, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 8, workHoursEnd: 16,
    epochMs: J2000_MS,
  },
  neptune: {
    name: 'Neptune', symbol: '♆',
    solarDayMs: 16.1100 * 3_600_000,
    siderealYrMs: 60195.0 * EARTH_DAY_MS,
    daysPerPeriod: 1, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 8, workHoursEnd: 16,
    epochMs: J2000_MS,
  },
  moon: {
    // Moon uses Earth's solar day (tidally locked; work schedules on Earth time)
    name: 'Moon', symbol: '☽',
    solarDayMs: 86_400_000,
    siderealYrMs: 365.25636 * EARTH_DAY_MS,
    daysPerPeriod: 1, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 9, workHoursEnd: 17,
    epochMs: J2000_MS,
  },
};

// ── Orbital elements (Meeus Table 31.a) ──────────────────────────────────────

export interface OrbitalElements {
  L0: number; dL: number; om0: number; e0: number; a: number;
}

// Moon uses Earth's orbital elements
type OrbElPlanet = Exclude<Planet, 'moon'>;

export const ORBITAL_ELEMENTS: Record<OrbElPlanet, OrbitalElements> = {
  mercury: { L0: 252.2507, dL: 149474.0722, om0:  77.4561, e0: 0.20564, a: 0.38710 },
  venus:   { L0: 181.9798, dL:  58519.2130, om0: 131.5637, e0: 0.00677, a: 0.72333 },
  earth:   { L0: 100.4664, dL:  36000.7698, om0: 102.9373, e0: 0.01671, a: 1.00000 },
  mars:    { L0: 355.4330, dL:  19141.6964, om0: 336.0600, e0: 0.09341, a: 1.52366 },
  jupiter: { L0:  34.3515, dL:   3036.3027, om0:  14.3320, e0: 0.04849, a: 5.20336 },
  saturn:  { L0:  50.0775, dL:   1223.5093, om0:  93.0572, e0: 0.05551, a: 9.53707 },
  uranus:  { L0: 314.0550, dL:    429.8633, om0: 173.0052, e0: 0.04630, a: 19.1912 },
  neptune: { L0: 304.3480, dL:    219.8997, om0:  48.1234, e0: 0.00899, a: 30.0690 },
};

// ── IERS leap seconds ─────────────────────────────────────────────────────────
// [TAI−UTC (s), UTC timestamp when this offset took effect]

export const LEAP_SECONDS: ReadonlyArray<readonly [number, number]> = [
  [10, Date.UTC(1972, 0, 1)],  [11, Date.UTC(1972, 6, 1)],  [12, Date.UTC(1973, 0, 1)],
  [13, Date.UTC(1974, 0, 1)],  [14, Date.UTC(1975, 0, 1)],  [15, Date.UTC(1976, 0, 1)],
  [16, Date.UTC(1977, 0, 1)],  [17, Date.UTC(1978, 0, 1)],  [18, Date.UTC(1979, 0, 1)],
  [19, Date.UTC(1980, 0, 1)],  [20, Date.UTC(1981, 6, 1)],  [21, Date.UTC(1982, 6, 1)],
  [22, Date.UTC(1983, 6, 1)],  [23, Date.UTC(1985, 6, 1)],  [24, Date.UTC(1988, 0, 1)],
  [25, Date.UTC(1990, 0, 1)],  [26, Date.UTC(1991, 0, 1)],  [27, Date.UTC(1992, 6, 1)],
  [28, Date.UTC(1993, 6, 1)],  [29, Date.UTC(1994, 6, 1)],  [30, Date.UTC(1996, 0, 1)],
  [31, Date.UTC(1997, 6, 1)],  [32, Date.UTC(1999, 0, 1)],  [33, Date.UTC(2006, 0, 1)],
  [34, Date.UTC(2009, 0, 1)],  [35, Date.UTC(2012, 6, 1)],  [36, Date.UTC(2015, 6, 1)],
  [37, Date.UTC(2017, 0, 1)],
];

const UNIX_EPOCH_JD = 2440587.5;

/** TAI − UTC offset in seconds for a given UTC millisecond timestamp. */
export function taiMinusUtc(utcMs: number): number {
  let offset = 10;
  for (const [s, t] of LEAP_SECONDS) {
    if (utcMs >= t) offset = s;
    else break;
  }
  return offset;
}

/** Julian Ephemeris Day (TT) from UTC ms. */
export function jde(utcMs: number): number {
  const ttMs = utcMs + (taiMinusUtc(utcMs) + 32.184) * 1000;
  return UNIX_EPOCH_JD + ttMs / 86_400_000;
}

/** Julian centuries from J2000.0. */
export function jc(utcMs: number): number {
  return (jde(utcMs) - J2000_JD) / 36525;
}
