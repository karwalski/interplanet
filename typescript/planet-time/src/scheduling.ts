/**
 * scheduling.ts — Meeting window finder for @interplanet/time
 */

import type { Planet, MeetingWindow } from './types.js';
import { EARTH_DAY_MS } from './constants.js';
import { getPlanetTime } from './time.js';

const STEP_MS = 15 * 60_000; // 15-minute resolution

/**
 * Find overlapping work windows between two planets over a period.
 *
 * @param planetA    first planet key
 * @param planetB    second planet key
 * @param fromMs     UTC milliseconds start of search range
 * @param earthDays  number of Earth days to scan (default: 7)
 * @returns array of overlapping work windows
 */
export function findMeetingWindows(
  planetA: Planet,
  planetB: Planet,
  fromMs: number,
  earthDays = 7,
): MeetingWindow[] {
  const endMs   = fromMs + earthDays * EARTH_DAY_MS;
  const windows: MeetingWindow[] = [];
  let inWindow    = false;
  let windowStart = 0;

  for (let t = fromMs; t < endMs; t += STEP_MS) {
    const ta      = getPlanetTime(planetA, t);
    const tb      = getPlanetTime(planetB, t);
    const overlap = ta.isWorkHour && tb.isWorkHour;
    if (overlap && !inWindow)  { inWindow = true; windowStart = t; }
    if (!overlap && inWindow)  {
      inWindow = false;
      windows.push({ startMs: windowStart, endMs: t, durationMinutes: (t - windowStart) / 60_000 });
    }
  }
  if (inWindow) {
    windows.push({ startMs: windowStart, endMs, durationMinutes: (endMs - windowStart) / 60_000 });
  }
  return windows;
}
