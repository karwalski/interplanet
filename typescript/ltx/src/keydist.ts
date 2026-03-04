/**
 * @interplanet/ltx — Key Distribution primitives
 * Story 28.6 — Pre-session key distribution (KEY_BUNDLE protocol)
 *
 * The HOST creates a KEY_BUNDLE message containing all node NIKs, signs it,
 * and distributes to participants. Receivers verify and cache the keys.
 * Supports KEY_REVOCATION.
 */

import * as nodeCrypto from 'node:crypto';
import type { NIK } from './security.js';
import { canonicalJSON, isNIKExpired } from './security.js';

// ── KEY_BUNDLE types ──────────────────────────────────────────────────────────

/** A signed bundle of all node NIKs for a session, created by the HOST. */
export interface KeyBundle {
  type: 'KEY_BUNDLE';
  planId: string;
  keys: NIK[];
  timestamp: string;
  bundleSig: string;
}

/** A signed revocation notice for a compromised or retired node key. */
export interface KeyRevocation {
  type: 'KEY_REVOCATION';
  planId: string;
  nodeId: string;
  reason: string;
  timestamp: string;
  revocationSig: string;
}

// ── Key Distribution functions ────────────────────────────────────────────────

/**
 * Create a signed KEY_BUNDLE message containing all node NIKs.
 * The host signs the canonical JSON of the keys array with their private key.
 *
 * @param planId             Plan identifier
 * @param nikArray           Array of NIK records to bundle
 * @param hostPrivateKeyB64  Base64url-encoded raw 32-byte Ed25519 private seed
 * @returns                  Signed KEY_BUNDLE message
 */
export function createKeyBundle(
  planId: string,
  nikArray: NIK[],
  hostPrivateKeyB64: string,
): KeyBundle {
  const keysStr = canonicalJSON(nikArray);
  const rawSeed = Buffer.from(hostPrivateKeyB64, 'base64url');
  const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
  const pkcs8Der = Buffer.concat([pkcs8Header, rawSeed]);
  const privKey = nodeCrypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
  const sigBytes = nodeCrypto.sign(null, Buffer.from(keysStr, 'utf8'), privKey);

  return {
    type: 'KEY_BUNDLE',
    planId,
    keys: nikArray,
    timestamp: new Date().toISOString(),
    bundleSig: sigBytes.toString('base64url'),
  };
}

/**
 * Verify a KEY_BUNDLE signature against a bootstrap NIK and return a populated key cache.
 * Expired NIKs are excluded from the returned cache.
 *
 * @param keyBundle     KEY_BUNDLE message (from createKeyBundle)
 * @param bootstrapNIK  NIK used to verify the bundle signature (typically the host's NIK)
 * @returns             Map of nodeId → NIK, or null if signature is invalid
 */
export function verifyAndCacheKeys(
  keyBundle: KeyBundle,
  bootstrapNIK: NIK,
): Map<string, NIK> | null {
  if (keyBundle.type !== 'KEY_BUNDLE') return null;

  const keysStr = canonicalJSON(keyBundle.keys);
  const rawPub = Buffer.from(bootstrapNIK.publicKey, 'base64url');
  const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');
  const spkiDer = Buffer.concat([spkiHeader, rawPub]);
  const pubKey = nodeCrypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });
  const sigBytes = Buffer.from(keyBundle.bundleSig, 'base64url');
  const valid = nodeCrypto.verify(null, Buffer.from(keysStr, 'utf8'), pubKey, sigBytes);

  if (!valid) return null;

  const cache = new Map<string, NIK>();
  for (const nik of keyBundle.keys) {
    if (!isNIKExpired(nik)) {
      cache.set(nik.nodeId, nik);
    }
  }
  return cache;
}

/**
 * Create a signed KEY_REVOCATION message.
 * The host signs the canonical JSON of the revocation payload.
 *
 * @param planId             Plan identifier
 * @param revokedNodeId      nodeId of the key to revoke
 * @param reason             Human-readable reason for revocation
 * @param hostPrivateKeyB64  Base64url-encoded raw 32-byte Ed25519 private seed
 * @returns                  Signed KEY_REVOCATION message
 */
export function createRevocation(
  planId: string,
  revokedNodeId: string,
  reason: string,
  hostPrivateKeyB64: string,
): KeyRevocation {
  const payload = {
    type: 'KEY_REVOCATION' as const,
    planId,
    nodeId: revokedNodeId,
    reason,
    timestamp: new Date().toISOString(),
  };
  const payloadStr = canonicalJSON(payload);
  const rawSeed = Buffer.from(hostPrivateKeyB64, 'base64url');
  const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
  const pkcs8Der = Buffer.concat([pkcs8Header, rawSeed]);
  const privKey = nodeCrypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
  const sigBytes = nodeCrypto.sign(null, Buffer.from(payloadStr, 'utf8'), privKey);

  return {
    ...payload,
    revocationSig: sigBytes.toString('base64url'),
  };
}

/**
 * Apply a KEY_REVOCATION to a key cache, removing the revoked entry.
 *
 * @param cache       Key cache (Map of nodeId → NIK, from verifyAndCacheKeys)
 * @param revocation  KEY_REVOCATION message
 * @returns           true if revocation was applied, false if type mismatch
 */
export function applyRevocation(
  cache: Map<string, NIK>,
  revocation: KeyRevocation,
): boolean {
  if (revocation.type !== 'KEY_REVOCATION') return false;
  cache.delete(revocation.nodeId);
  return true;
}
