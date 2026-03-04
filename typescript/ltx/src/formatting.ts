/**
 * @interplanet/ltx — Formatting utilities
 */

function _pad(n: number): string {
  return String(Math.floor(n)).padStart(2, '0');
}

/**
 * Format a duration in seconds as `HH:MM:SS` or `MM:SS`.
 */
export function formatHMS(sec: number): string {
  if (sec < 0) sec = 0;
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = Math.floor(sec % 60);
  if (h > 0) return `${_pad(h)}:${_pad(m)}:${_pad(s)}`;
  return `${_pad(m)}:${_pad(s)}`;
}

/**
 * Format a Date, timestamp (ms), or ISO string as `HH:MM:SS UTC`.
 */
export function formatUTC(dt: Date | number | string): string {
  return new Date(dt as number).toISOString().slice(11, 19) + ' UTC';
}
