/**
 * @interplanet/ltx — BPSec Bundle Integrity Block (BIB)
 * Story 28.3 — BPSec BIB (RFC 9173, Context ID 1) using HMAC-SHA-256
 * Story 70.3 — LTX-native Ed25519 BIB (LTX-SECURITY.md §8.2, "ltx-ed25519")
 *
 * addBIB:            Attach a BIB HMAC-SHA-256 integrity tag to any LTX bundle.
 * verifyBIB:         Verify the HMAC BIB tag on a bundle.
 * addBIBEd25519:     Attach an Ed25519 NIK-signed BIB (non-repudiation, no
 *                    pre-shared pairwise key).
 * verifyBIBEd25519:  Verify an Ed25519 BIB against the sender's NIK.
 * generateBIBKey:    Generate a fresh 32-byte base64url-encoded HMAC key.
 *
 * Context-confusion defence: each verifier rejects a BIB whose declared
 * context does not match its verification method.
 */

import { canonicalJSON } from './security.js';
import type { NIK } from './security.js';

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

/** LTX-native Ed25519 BIB (LTX-SECURITY.md §8.2). */
export interface BIBEd25519 {
  /** LTX application security context identifier. */
  securityContext: 'ltx-ed25519';
  /** Target block number (0 = primary block / whole bundle). */
  targetBlockNumber: number;
  /** Base64url-encoded Ed25519 signature over canonicalJSON(bundle sans bib). */
  sig: string;
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
  const bibObj = bib as (BIB & Partial<BIBEd25519>) | undefined;
  if (!bibObj) return { valid: false, reason: 'missing_bib' };
  if (bibObj.securityContext === 'ltx-ed25519') {
    // Context-confusion defence: an Ed25519 BIB must not pass HMAC verification.
    return { valid: false, reason: 'context_mismatch' };
  }
  if (typeof bibObj.hmac !== 'string') {
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

// ── LTX-native Ed25519 BIB (Story 70.3) ──────────────────────────────────────

const PKCS8_HEADER = '302e020100300506032b657004220420';
const SPKI_HEADER = '302a300506032b6570032100';

/**
 * Add an LTX-native Ed25519 BIB (LTX-SECURITY.md §8.2): the bundle is signed
 * with the originating node's NIK, giving per-bundle non-repudiation without
 * a pre-shared pairwise key. The input bundle is not mutated.
 */
export function addBIBEd25519(
  bundle: Record<string, unknown>,
  privateKeyB64: string,
): Record<string, unknown> {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const crypto = require('node:crypto') as {
    createPrivateKey: (opts: { key: Buffer; format: string; type: string }) => unknown;
    sign: (alg: null, data: Buffer, key: unknown) => Buffer;
  };
  const { bib: _bib, ...bundleWithoutBib } = bundle;
  const rawSeed = Buffer.from(privateKeyB64, 'base64url');
  const privKey = crypto.createPrivateKey({
    key: Buffer.concat([Buffer.from(PKCS8_HEADER, 'hex'), rawSeed]),
    format: 'der', type: 'pkcs8',
  });
  const msg = Buffer.from(canonicalJSON(bundleWithoutBib), 'utf8');
  const sig = crypto.sign(null, msg, privKey).toString('base64url');
  const bib: BIBEd25519 = { securityContext: 'ltx-ed25519', targetBlockNumber: 0, sig };
  return { ...bundleWithoutBib, bib };
}

/**
 * Verify an LTX-native Ed25519 BIB against the sender's NIK.
 * Rejects HMAC-context BIBs (context-confusion defence).
 */
export function verifyBIBEd25519(
  bundle: Record<string, unknown>,
  nik: NIK,
): BIBVerifyResult {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const crypto = require('node:crypto') as {
    createPublicKey: (opts: { key: Buffer; format: string; type: string }) => unknown;
    verify: (alg: null, data: Buffer, key: unknown, sig: Buffer) => boolean;
  };
  const { bib, ...bundleWithoutBib } = bundle;
  const bibObj = bib as (BIBEd25519 & Partial<BIB>) | undefined;
  if (!bibObj) return { valid: false, reason: 'missing_bib' };
  if (bibObj.securityContext !== 'ltx-ed25519' || typeof bibObj.sig !== 'string') {
    return { valid: false, reason: 'context_mismatch' };
  }
  const rawPub = Buffer.from(nik.publicKey, 'base64url');
  const pubKey = crypto.createPublicKey({
    key: Buffer.concat([Buffer.from(SPKI_HEADER, 'hex'), rawPub]),
    format: 'der', type: 'spki',
  });
  const msg = Buffer.from(canonicalJSON(bundleWithoutBib), 'utf8');
  const ok = crypto.verify(null, msg, pubKey, Buffer.from(bibObj.sig, 'base64url'));
  return ok ? { valid: true } : { valid: false, reason: 'signature_invalid' };
}
