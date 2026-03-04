/**
 * @interplanet/ltx — URL hash encoding / decoding
 */

import type { LtxPlan, LtxPlanV1 } from './types.js';

// Safe reference to Node.js Buffer (unavailable in browsers)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const _Buf: any = typeof globalThis !== 'undefined' && (globalThis as any)['Buffer'];

function _b64enc(str: string): string {
  // Works in Node ≥ 16 (Buffer) and modern browsers (btoa)
  if (_Buf) {
    return _Buf.from(str, 'utf8').toString('base64')
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  }
  return btoa(unescape(encodeURIComponent(str)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function _b64dec(b64: string): string | null {
  const s = b64.replace(/-/g, '+').replace(/_/g, '/');
  try {
    if (_Buf) {
      return _Buf.from(s, 'base64').toString('utf8');
    }
    return decodeURIComponent(escape(atob(s)));
  } catch {
    return null;
  }
}

/**
 * Encode a plan config to a URL hash fragment (`#l=…`).
 */
export function encodeHash(cfg: LtxPlan | LtxPlanV1): string {
  return '#l=' + _b64enc(JSON.stringify(cfg));
}

/**
 * Decode a plan config from a URL hash fragment.
 * Accepts `#l=…`, `l=…`, or the raw base64 token.
 * Returns `null` if the hash is invalid.
 */
export function decodeHash(hash: string): LtxPlan | LtxPlanV1 | null {
  const str  = (hash || '').replace(/^#?l=/, '');
  const json = _b64dec(str);
  if (!json) return null;
  try { return JSON.parse(json) as LtxPlan; } catch { return null; }
}
