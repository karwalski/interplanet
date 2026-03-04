/**
 * @interplanet/time — TypeScript native port of planet-time.js
 * Story 18.5
 *
 * @example
 * import { getPlanetTime, getMTC, lightTravelSeconds } from '@interplanet/time';
 * const pt = getPlanetTime('mars', Date.now());
 * console.log(pt.timeString); // e.g. "21:03"
 */

export type {
  Planet,
  PlanetTime,
  MTC,
  MarsLocalTime,
  HelioPos,
  LineOfSight,
  MeetingWindow,
  SolInfo,
} from './types.js';

export {
  VERSION,
  J2000_MS,
  J2000_JD,
  EARTH_DAY_MS,
  MARS_EPOCH_MS,
  MARS_SOL_MS,
  AU_KM,
  C_KMS,
  AU_SECONDS,
  PLANETS,
  ORBITAL_ELEMENTS,
  LEAP_SECONDS,
  jde,
  jc,
  taiMinusUtc,
} from './constants.js';

export { helioPos, bodyDistanceAu, lightTravelSeconds, checkLineOfSight, lowerQuartileLightTime } from './orbital.js';

export { getPlanetTime, getMTC, getMarsTimeAtOffset } from './time.js';

export { findMeetingWindows } from './scheduling.js';

export { formatLightTime, formatPlanetTimeIso } from './formatting.js';
