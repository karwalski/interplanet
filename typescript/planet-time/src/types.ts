/**
 * types.ts — Public interfaces for @interplanet/time
 * Story 18.5 — TypeScript native port
 */

/** Supported solar-system body keys. */
export type Planet =
  | 'mercury' | 'venus' | 'earth' | 'mars'
  | 'jupiter' | 'saturn' | 'uranus' | 'neptune' | 'moon';

/** Mars sol-year information attached to PlanetTime for Mars only. */
export interface SolInfo {
  solInYear: number;
  solsPerYear: number;
}

/** Result of getPlanetTime(). */
export interface PlanetTime {
  planet: string;
  symbol: string;
  hour: number;
  minute: number;
  second: number;
  localHour: number;
  dayFraction: number;
  dayNumber: number;
  dayInYear: number;
  yearNumber: number;
  solInfo: SolInfo | null;
  periodInWeek: number;
  isWorkPeriod: boolean;
  isWorkHour: boolean;
  dowName: string;
  dowShort: string;
  solarDayMs: number;
  daysPerPeriod: number;
  periodsPerWeek: number;
  workPeriodsPerWeek: number;
  timeString: string;       // "HH:MM"
  timeStringFull: string;   // "HH:MM:SS"
}

/** Result of getMTC(). */
export interface MTC {
  sol: number;
  hour: number;
  minute: number;
  second: number;
  mtcString: string;        // "HH:MM"
}

/** Result of getMarsTimeAtOffset(). */
export interface MarsLocalTime {
  sol: number;
  hour: number;
  minute: number;
  second: number;
  timeString: string;
  offsetHours: number;
}

/** Heliocentric ecliptic position. */
export interface HelioPos {
  x: number;   // AU
  y: number;   // AU
  r: number;   // AU (heliocentric distance)
  lon: number; // radians (ecliptic longitude)
}

/** Result of checkLineOfSight(). */
export interface LineOfSight {
  clear: boolean;
  blocked: boolean;
  degraded: boolean;
  closestSunAu: number | null;
  elongDeg: number;
}

/** One overlapping work-hour window returned by findMeetingWindows(). */
export interface MeetingWindow {
  startMs: number;
  endMs: number;
  durationMinutes: number;
}
