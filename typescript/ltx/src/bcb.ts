/**
 * @interplanet/ltx — BPSec Bundle Confidentiality Block (BCB)
 * Story 28.11 — AES-256-GCM confidentiality for LTX window payloads.
 *
 * generateSessionKey(): Generate a 32-byte AES-256 session key.
 * encryptWindow():      Encrypt a payload object -> BCB bundle.
 * decryptWindow():      Decrypt a BCB bundle -> DecryptResult.
 */

// ── BCB types ─────────────────────────────────────────────────────────────────

/** A BCB-encrypted bundle produced by encryptWindow(). */
export interface BCBBundle {
  type: 'BCB';
  /** Base64url-encoded 12-byte AES-GCM nonce. */
  nonce: string;
  /** Base64url-encoded AES-GCM ciphertext. */
  ciphertext: string;
  /** Base64url-encoded 16-byte AES-GCM authentication tag. */
  tag: string;
}

/** Result returned by decryptWindow(). */
export interface DecryptResult {
  valid: boolean;
  plaintext?: unknown;
  reason?: string;
}

// ── BCB functions ─────────────────────────────────────────────────────────────

/**
 * Generate a fresh 32-byte AES-256 session key.
 * @returns Buffer of 32 random bytes
 */
export function generateSessionKey(): Buffer {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const crypto = require('node:crypto') as {
    randomBytes: (size: number) => Buffer;
  };
  return crypto.randomBytes(32);
}

/**
 * Encrypt a payload object using AES-256-GCM (BPSec BCB).
 * Generates a fresh 12-byte nonce per call.
 *
 * @param payload     Plain object to encrypt (will be JSON-serialised)
 * @param sessionKey  32-byte AES-256 key (from generateSessionKey)
 * @returns           BCB bundle with base64url-encoded nonce, ciphertext, tag
 */
export function encryptWindow(payload: unknown, sessionKey: Buffer): BCBBundle {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const crypto = require('node:crypto') as {
    randomBytes: (size: number) => Buffer;
    createCipheriv: (alg: string, key: Buffer, iv: Buffer) => {
      update: (data: string, encoding: string) => Buffer;
      final: () => Buffer;
      getAuthTag: () => Buffer;
    };
  };
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', sessionKey, nonce);
  const ct = Buffer.concat([
    cipher.update(JSON.stringify(payload), 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  const b64url = (buf: Buffer): string => buf.toString('base64url');
  return {
    type: 'BCB',
    nonce: b64url(nonce),
    ciphertext: b64url(ct),
    tag: b64url(tag),
  };
}

/**
 * Decrypt a BCB bundle using AES-256-GCM.
 * Verifies the AEAD authentication tag; returns { valid: false } on failure.
 *
 * @param bundle      BCB bundle object ({ type, nonce, ciphertext, tag })
 * @param sessionKey  32-byte AES-256 key
 * @returns           { valid: true, plaintext } or { valid: false, reason }
 */
export function decryptWindow(
  bundle: { type?: string; nonce?: string; ciphertext?: string; tag?: string },
  sessionKey: Buffer,
): DecryptResult {
  if (bundle.type !== 'BCB') {
    return { valid: false, reason: 'not_bcb' };
  }
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const crypto = require('node:crypto') as {
    createDecipheriv: (alg: string, key: Buffer, iv: Buffer) => {
      setAuthTag: (tag: Buffer) => void;
      update: (data: Buffer) => Buffer;
      final: () => Buffer;
    };
  };
  const nonce = Buffer.from(bundle.nonce ?? '', 'base64url');
  const ct    = Buffer.from(bundle.ciphertext ?? '', 'base64url');
  const tag   = Buffer.from(bundle.tag ?? '', 'base64url');
  const decipher = crypto.createDecipheriv('aes-256-gcm', sessionKey, nonce);
  decipher.setAuthTag(tag);
  try {
    const pt = Buffer.concat([decipher.update(ct), decipher.final()]);
    return { valid: true, plaintext: JSON.parse(pt.toString('utf8')) };
  } catch (_) {
    return { valid: false, reason: 'tag_mismatch' };
  }
}
