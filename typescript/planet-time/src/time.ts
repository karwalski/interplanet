/**
 * time.ts — Planet time functions for @interplanet/time
 */

import type { Planet, PlanetTime, MTC, MarsLocalTime } from './types.js';
import { PLANETS, MARS_EPOCH_MS, MARS_SOL_MS } from './constants.js';

const DOW_NAMES  = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
const DOW_SHORT  = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

function pad(n: number): string {
  return String(n).padStart(2, '0');
}

/**
 * Get the current time on a planet.
 *
 * @param planet       planet key (e.g. 'earth', 'mars')
 * @param utcMs        UTC milliseconds since Unix epoch
 * @param tzOffsetHours  zone offset in local planet hours (default: 0)
 */
export function getPlanetTime(
  planet: Planet,
  utcMs: number,
  tzOffsetHours = 0,
): PlanetTime {
  // Moon uses Earth's data
  const key = planet === 'moon' ? 'earth' : planet;
  const p   = PLANETS[key as Planet];

  const elapsedMs   = utcMs - p.epochMs + (tzOffsetHours / 24) * p.solarDayMs;
  const totalDays   = elapsedMs / p.solarDayMs;
  const dayNumber   = Math.floor(totalDays);
  const dayFraction = totalDays - dayNumber;

  const localHour = dayFraction * 24;
  const h = Math.floor(localHour);
  const m = Math.floor((localHour - h) * 60);
  const s = Math.floor(((localHour - h) * 60 - m) * 60);

  const { daysPerPeriod, periodsPerWeek, workPeriodsPerWeek } = p;
  let periodInWeek: number;
  let isWorkPeriod: boolean;
  let isWorkHour: boolean;
  if (p.earthClockSched) {
    // Earth-clock scheduling: UTC day-of-week + UTC hour (Mercury and Venus)
    const utcDay = Math.floor(utcMs / 86_400_000);
    const dow = ((utcDay % 7) + 3 + 7) % 7;  // Mon=0..Sun=6
    isWorkPeriod = dow < workPeriodsPerWeek;
    const msOfDay = utcMs - utcDay * 86_400_000;
    const utcHour = Math.floor(msOfDay / 3_600_000);
    isWorkHour = isWorkPeriod && utcHour >= p.workHoursStart && utcHour < p.workHoursEnd;
    periodInWeek = dow;
  } else {
    const totalPeriods = totalDays / daysPerPeriod;
    periodInWeek = ((Math.floor(totalPeriods) % periodsPerWeek) + periodsPerWeek) % periodsPerWeek;
    isWorkPeriod = periodInWeek < workPeriodsPerWeek;
    isWorkHour   = isWorkPeriod && localHour >= p.workHoursStart && localHour < p.workHoursEnd;
  }

  const yearLenDays = p.siderealYrMs / p.solarDayMs;
  const yearNumber  = Math.floor(totalDays / yearLenDays);
  const dayInYear   = totalDays - yearNumber * yearLenDays;

  let solInfo = null;
  if (key === 'mars') {
    const solsPerYear = PLANETS.mars.siderealYrMs / PLANETS.mars.solarDayMs;
    solInfo = { solInYear: Math.floor(dayInYear), solsPerYear: Math.round(solsPerYear) };
  }

  const dowIndex = periodInWeek % 7;

  const data = planet === 'moon' ? PLANETS.moon : p;

  return {
    planet: data.name,
    symbol: data.symbol,
    hour: h, minute: m, second: s, localHour, dayFraction,
    dayNumber, dayInYear: Math.floor(dayInYear), yearNumber, solInfo,
    periodInWeek, isWorkPeriod, isWorkHour,
    dowName: DOW_NAMES[dowIndex]!, dowShort: DOW_SHORT[dowIndex]!,
    solarDayMs: p.solarDayMs, daysPerPeriod, periodsPerWeek, workPeriodsPerWeek,
    timeString: `${pad(h)}:${pad(m)}`,
    timeStringFull: `${pad(h)}:${pad(m)}:${pad(s)}`,
  };
}

/**
 * Get Mars Coordinated Time (MTC).
 *
 * @param utcMs  UTC milliseconds since Unix epoch
 */
export function getMTC(utcMs: number): MTC {
  const totalSols = (utcMs - MARS_EPOCH_MS) / MARS_SOL_MS;
  const sol  = Math.floor(totalSols);
  const frac = totalSols - sol;
  const h = Math.floor(frac * 24);
  const m = Math.floor((frac * 24 - h) * 60);
  const s = Math.floor(((frac * 24 - h) * 60 - m) * 60);
  return { sol, hour: h, minute: m, second: s, mtcString: `${pad(h)}:${pad(m)}` };
}

/**
 * Get Mars local time at a given zone offset.
 *
 * @param utcMs        UTC milliseconds since Unix epoch
 * @param offsetHours  Mars local hours relative to AMT (prime meridian)
 */
export function getMarsTimeAtOffset(utcMs: number, offsetHours: number): MarsLocalTime {
  const mtc = getMTC(utcMs);
  let h = mtc.hour + offsetHours;
  let solDelta = 0;
  if (h >= 24) { h -= 24; solDelta =  1; }
  if (h <   0) { h += 24; solDelta = -1; }
  const fh = Math.floor(h);
  return {
    sol: mtc.sol + solDelta,
    hour: fh, minute: mtc.minute, second: mtc.second,
    timeString: `${pad(fh)}:${pad(mtc.minute)}`,
    offsetHours,
  };
}
