/**
 * @interplanet/ltx — BPSec Bundle Integrity Block (BIB)
 * Story 28.3 — BPSec BIB (RFC 9173, Context ID 1) using HMAC-SHA-256
 *
 * addBIB:        Attach a BIB HMAC-SHA-256 integrity tag to any LTX bundle.
 * verifyBIB:     Verify the BIB tag on a bundle.
 * generateBIBKey: Generate a fresh 32-byte base64url-encoded HMAC key.
 */

import { canonicalJSON } from './security.js';

// ── BIB types ─────────────────────────────────────────────────────────────────

/** Bundle Integrity Block embedded in a bundle. */
export interface BIB {
  /** BPSec Security Context ID (1 = BIB-HMAC-SHA2, RFC 9173). */
  contextId: number;
  /** Target block number (0 = primary block / whole bundle). */
  targetBlockNumber: number;
  /** Base64url-encoded HMAC-SHA-256 digest (no padding). */
  hmac: string;
}

/** A bundle that carries a BIB field. */
export interface BIBBundle {
  bib: BIB;
  [key: string]: unknown;
}

/** Result of verifyBIB(). */
export interface BIBVerifyResult {
  valid: boolean;
  reason?: string;
}

// ── BIB functions ─────────────────────────────────────────────────────────────

/**
 * Generate a fresh base64url-encoded 32-byte random key for HMAC-SHA-256.
 *
 * @returns  43-character base64url string (256 bits, no padding)
 */
export function generateBIBKey(): string {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const crypto = require('node:crypto') as {
    randomBytes: (size: number) => Buffer;
  };
  return crypto.randomBytes(32).toString('base64url');
}

/**
 * Add a BPSec Bundle Integrity Block (Context ID 1, RFC 9173) to any LTX bundle.
 * Strips any existing bib field before computing the HMAC, then returns a new
 * bundle object with the bib field appended. The input bundle is not mutated.
 *
 * @param bundle      Any LTX message bundle (plain JS object)
 * @param hmacKeyB64  Base64url-encoded raw 32-byte HMAC-SHA-256 key
 * @returns           New bundle: { ...bundleWithoutBib, bib: { contextId, targetBlockNumber, hmac } }
 */
export function addBIB(bundle: Record<string, unknown>, hmacKeyB64: string): BIBBundle {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const crypto = require('node:crypto') as {
    createHmac: (algorithm: 'sha256', key: Buffer) => {
      update(data: Buffer): { digest(): Buffer };
    };
  };

  // Strip any existing bib field (do not mutate original)
  const { bib: _bib, ...bundleWithoutBib } = bundle;
  const rawKey = Buffer.from(hmacKeyB64, 'base64url');
  const msg = Buffer.from(canonicalJSON(bundleWithoutBib), 'utf8');
  const hmacBytes = crypto.createHmac('sha256', rawKey).update(msg).digest();

  return {
    ...bundleWithoutBib,
    bib: {
      contextId: 1,
      targetBlockNumber: 0,
      hmac: hmacBytes.toString('base64url'),
    },
  };
}

/**
 * Verify a BPSec Bundle Integrity Block (Context ID 1, RFC 9173).
 * Extracts the bib field, recomputes HMAC-SHA-256 over canonicalJSON of the
 * remaining bundle fields, and compares with bib.hmac using constant-time
 * comparison where available.
 *
 * @param bundle      Bundle containing a bib field
 * @param hmacKeyB64  Base64url-encoded raw 32-byte HMAC-SHA-256 key
 * @returns           { valid: true } or { valid: false, reason }
 */
export function verifyBIB(bundle: Record<string, unknown>, hmacKeyB64: string): BIBVerifyResult {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const crypto = require('node:crypto') as {
    createHmac: (algorithm: 'sha256', key: Buffer) => {
      update(data: Buffer): { digest(): Buffer };
    };
    timingSafeEqual(a: Buffer, b: Buffer): boolean;
  };

  const { bib, ...bundleWithoutBib } = bundle;
  const bibObj = bib as BIB | undefined;
  if (!bibObj || typeof bibObj.hmac !== 'string') {
    return { valid: false, reason: 'missing_bib' };
  }

  const rawKey = Buffer.from(hmacKeyB64, 'base64url');
  const msg = Buffer.from(canonicalJSON(bundleWithoutBib), 'utf8');
  const computed = crypto.createHmac('sha256', rawKey).update(msg).digest();
  const expected = Buffer.from(bibObj.hmac, 'base64url');

  // Constant-time comparison via crypto.timingSafeEqual
  let valid = false;
  try {
    valid = computed.length === expected.length && crypto.timingSafeEqual(computed, expected);
  } catch (_) {
    valid = computed.toString('base64url') === bibObj.hmac;
  }

  if (!valid) return { valid: false, reason: 'hmac_mismatch' };
  return { valid: true };
}
