/**
 * formatting.ts — Human-readable formatting utilities for @interplanet/time
 */

/**
 * Format a light travel time in seconds as a human-readable string.
 * e.g. 186 → "3 min 6 s", 45 → "45 s", 60 → "1 min"
 */
export function formatLightTime(seconds: number): string {
  const s = Math.round(seconds);
  if (s < 60) return `${s} s`;
  const min = Math.floor(s / 60);
  const sec = s % 60;
  if (sec === 0) return `${min} min`;
  return `${min} min ${sec} s`;
}

/**
 * Format a PlanetTime's local time as an ISO-8601–style string.
 * e.g. "MARS+00:00:00"
 */
export function formatPlanetTimeIso(
  planet: string,
  hour: number,
  minute: number,
  second: number,
): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${planet.toUpperCase()}+${pad(hour)}:${pad(minute)}:${pad(second)}`;
}
