/**
 * orbital.ts — Orbital mechanics for @interplanet/time
 */

import type { Planet, HelioPos, LineOfSight } from './types.js';
import { ORBITAL_ELEMENTS, AU_SECONDS, EARTH_DAY_MS, jc } from './constants.js';

/** Solve Kepler's equation M = E − e·sin(E) via Newton-Raphson. */
function keplerE(M: number, e: number): number {
  let E = M;
  for (let i = 0; i < 50; i++) {
    const dE = (M - E + e * Math.sin(E)) / (1 - e * Math.cos(E));
    E += dE;
    if (Math.abs(dE) < 1e-12) break;
  }
  return E;
}

/** Heliocentric ecliptic position (AU) for a planet at a given UTC ms. */
export function helioPos(planet: Planet, utcMs: number): HelioPos {
  const key = planet === 'moon' ? 'earth' : planet;
  const orb = ORBITAL_ELEMENTS[key as Exclude<Planet, 'moon'>];
  const T   = jc(utcMs);
  const TAU = 2 * Math.PI;
  const D2R = Math.PI / 180;

  const L   = ((orb.L0 + orb.dL * T) * D2R % TAU + TAU) % TAU;
  const om  = orb.om0 * D2R;
  const M   = ((L - om) % TAU + TAU) % TAU;
  const E   = keplerE(M, orb.e0);
  const v   = 2 * Math.atan2(
    Math.sqrt(1 + orb.e0) * Math.sin(E / 2),
    Math.sqrt(1 - orb.e0) * Math.cos(E / 2),
  );
  const r   = orb.a * (1 - orb.e0 * Math.cos(E));
  const lon = ((v + om) % TAU + TAU) % TAU;

  return { x: r * Math.cos(lon), y: r * Math.sin(lon), r, lon };
}

/** Distance in AU between two bodies at a given UTC ms. */
export function bodyDistanceAu(a: Planet, b: Planet, utcMs: number): number {
  const pA = helioPos(a, utcMs);
  const pB = helioPos(b, utcMs);
  const dx = pA.x - pB.x;
  const dy = pA.y - pB.y;
  return Math.sqrt(dx * dx + dy * dy);
}

/** One-way light travel time in seconds between two bodies. */
export function lightTravelSeconds(a: Planet, b: Planet, utcMs: number): number {
  return bodyDistanceAu(a, b, utcMs) * AU_SECONDS;
}

/** Check whether the line of sight between two bodies is clear. */
export function checkLineOfSight(a: Planet, b: Planet, utcMs: number): LineOfSight {
  const pA = helioPos(a, utcMs);
  const pB = helioPos(b, utcMs);
  const dx = pB.x - pA.x;
  const dy = pB.y - pA.y;
  const d2 = dx * dx + dy * dy;

  if (d2 < 1e-12) {
    return { clear: true, blocked: false, degraded: false, closestSunAu: null, elongDeg: 0 };
  }

  const dist    = Math.sqrt(d2);
  const t       = Math.max(0, Math.min(1, -(pA.x * dx + pA.y * dy) / d2));
  const cx      = pA.x + t * dx;
  const cy      = pA.y + t * dy;
  const closest = Math.sqrt(cx * cx + cy * cy);

  const cosEl  = (-pA.x * dx - pA.y * dy) / (pA.r * dist);
  const elongDeg = (180 / Math.PI) * Math.acos(Math.max(-1, Math.min(1, cosEl)));

  const blocked  = closest < 0.01;
  const degraded = !blocked && closest < 0.05;

  return { clear: !blocked && !degraded, blocked, degraded, closestSunAu: closest, elongDeg };
}

/** Lower-quartile (p25) light travel time over one Earth year (360 samples). */
export function lowerQuartileLightTime(a: Planet, b: Planet, refMs: number): number {
  const SAMPLES = 360;
  const stepMs  = 365.25 * EARTH_DAY_MS / SAMPLES;
  const times: number[] = [];
  for (let i = 0; i < SAMPLES; i++) {
    times.push(lightTravelSeconds(a, b, refMs + i * stepMs));
  }
  times.sort((x, y) => x - y);
  return times[Math.floor(SAMPLES * 0.25)];
}
