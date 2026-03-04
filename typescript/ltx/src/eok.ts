/**
 * @interplanet/ltx — Emergency Override Keys (EOK) and Multi-Person Authorisation
 * Story 28.7 — EOK / MULTI-AUTH primitives
 *
 * createEOK:                 Generate an Emergency Override Key
 * createEmergencyOverride:   Create a signed EMERGENCY_OVERRIDE bundle
 * verifyEmergencyOverride:   Verify an EMERGENCY_OVERRIDE bundle
 * createCoSig:               Create an ACTION_COSIG bundle
 * checkMultiAuth:            Verify multi-person authorisation
 */

import * as nodeCrypto from 'node:crypto';
import type { NIK } from './security.js';
import { canonicalJSON } from './security.js';

// ── EOK types ─────────────────────────────────────────────────────────────────

/** Emergency Override Key record — same structure as NIK but with keyType 'eok'. */
export interface EOKRecord {
  eokId: string;
  publicKey: string;
  algorithm: 'Ed25519';
  keyType: 'eok';
  validFrom: string;
  validUntil: string;
  label?: string;
}

/** Result returned by createEOK(). */
export interface CreateEOKResult {
  eok: EOKRecord;
  privateKey: string;
}

/** A signed EMERGENCY_OVERRIDE bundle. */
export interface EmergencyOverride {
  type: 'EMERGENCY_OVERRIDE';
  planId: string;
  action: string;
  timestamp: string;
  eokId: string;
  overrideSig: string;
}

/** A signed ACTION_COSIG bundle for multi-person authorisation. */
export interface CoSigBundle {
  type: 'ACTION_COSIG';
  entryId: string;
  planId: string;
  cosigNodeId: string;
  cosigTime: string;
  cosigSig: string;
}

/** Result returned by checkMultiAuth(). */
export interface MultiAuthResult {
  authorised: boolean;
  validSigCount: number;
  invalidCount: number;
}

/** Options for createEOK(). */
export interface CreateEOKOptions {
  validDays?: number;
  nodeLabel?: string;
}

// ── Helper: DER constants ─────────────────────────────────────────────────────

const PKCS8_HEADER = Buffer.from('302e020100300506032b657004220420', 'hex');
const SPKI_HEADER  = Buffer.from('302a300506032b6570032100', 'hex');

// ── EOK functions ─────────────────────────────────────────────────────────────

/**
 * Create an Emergency Override Key (EOK).
 * Same structure as a NIK but with keyType 'eok'.
 *
 * @param options  Optional configuration
 * @returns        EOK record and base64url-encoded private key seed
 */
export function createEOK(options: CreateEOKOptions = {}): CreateEOKResult {
  const validDays = options.validDays !== undefined ? options.validDays : 30;
  const nodeLabel = options.nodeLabel !== undefined ? options.nodeLabel : '';

  const { privateKey, publicKey } = nodeCrypto.generateKeyPairSync('ed25519');

  // Export raw 32-byte public key from SPKI DER (last 32 bytes)
  const rawPub    = publicKey.export({ type: 'spki', format: 'der' }).slice(-32);
  const pubKeyB64 = rawPub.toString('base64url');

  // Derive eokId: base64url of first 16 bytes of SHA-256(raw public key)
  const hash  = nodeCrypto.createHash('sha256').update(rawPub).digest();
  const eokId = hash.slice(0, 16).toString('base64url');

  const now        = new Date();
  const validUntil = new Date(now.getTime() + validDays * 86400000);

  const eok: EOKRecord = {
    eokId,
    publicKey: pubKeyB64,
    algorithm: 'Ed25519',
    keyType:   'eok',
    validFrom:  now.toISOString(),
    validUntil: validUntil.toISOString(),
    ...(nodeLabel ? { label: nodeLabel } : {}),
  };

  // Export private key seed from PKCS8 DER (last 32 bytes)
  const rawPriv = privateKey.export({ type: 'pkcs8', format: 'der' }).slice(-32);

  return {
    eok,
    privateKey: rawPriv.toString('base64url'),
  };
}

/**
 * Create a signed EMERGENCY_OVERRIDE bundle.
 *
 * @param planId            Plan identifier
 * @param action            Action to override (e.g. 'ABORT', 'EXTEND')
 * @param eokPrivateKeyB64  Base64url-encoded raw 32-byte Ed25519 private seed
 * @param eokId             ID of the EOK (from createEOK)
 * @returns                 EMERGENCY_OVERRIDE bundle with overrideSig
 */
export function createEmergencyOverride(
  planId: string,
  action: string,
  eokPrivateKeyB64: string,
  eokId: string,
): EmergencyOverride {
  const timestamp = new Date().toISOString();
  const payload = {
    type:      'EMERGENCY_OVERRIDE' as const,
    planId,
    action,
    timestamp,
    eokId,
  };
  const payloadBytes = Buffer.from(canonicalJSON(payload), 'utf8');

  const rawSeed  = Buffer.from(eokPrivateKeyB64, 'base64url');
  const pkcs8Der = Buffer.concat([PKCS8_HEADER, rawSeed]);
  const privKey  = nodeCrypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
  const sigBytes = nodeCrypto.sign(null, payloadBytes, privKey);

  return {
    ...payload,
    overrideSig: sigBytes.toString('base64url'),
  };
}

/**
 * Verify an EMERGENCY_OVERRIDE bundle against an EOK cache.
 *
 * @param overrideBundle  Output from createEmergencyOverride()
 * @param eokCache        Map or plain object of eokId → EOKRecord
 * @returns               { valid, reason? }
 */
export function verifyEmergencyOverride(
  overrideBundle: EmergencyOverride,
  eokCache: Map<string, EOKRecord> | Record<string, EOKRecord>,
): { valid: boolean; reason?: string } {
  const { eokId, overrideSig } = overrideBundle;

  // Look up EOK in cache (Map or plain object)
  let eok: EOKRecord | undefined;
  if (eokCache instanceof Map) {
    eok = eokCache.get(eokId);
  } else if (eokCache && typeof eokCache === 'object') {
    eok = (eokCache as Record<string, EOKRecord>)[eokId];
  }

  if (!eok) return { valid: false, reason: 'key_not_in_cache' };

  // Check expiry
  if (Date.now() > new Date(eok.validUntil).getTime()) {
    return { valid: false, reason: 'key_expired' };
  }

  // Reconstruct payload (sign-over fields only, without overrideSig)
  const payload = {
    type:      overrideBundle.type,
    planId:    overrideBundle.planId,
    action:    overrideBundle.action,
    timestamp: overrideBundle.timestamp,
    eokId:     overrideBundle.eokId,
  };
  const payloadBytes = Buffer.from(canonicalJSON(payload), 'utf8');

  // Reconstruct Ed25519 public key from raw 32 bytes via SPKI DER
  const rawPub   = Buffer.from(eok.publicKey, 'base64url');
  const spkiDer  = Buffer.concat([SPKI_HEADER, rawPub]);
  const pubKey   = nodeCrypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });
  const sigBytes = Buffer.from(overrideSig, 'base64url');
  const valid    = nodeCrypto.verify(null, payloadBytes, pubKey, sigBytes);

  if (!valid) return { valid: false, reason: 'invalid_signature' };
  return { valid: true };
}

/**
 * Create an ACTION_COSIG bundle for multi-person authorisation.
 *
 * @param entryId            Entry identifier to co-sign
 * @param planId             Plan identifier
 * @param cosigNodeId        Node ID of the co-signer (fallback if cosigNIK not provided)
 * @param cosigPrivateKeyB64 Base64url-encoded raw 32-byte Ed25519 private seed
 * @param cosigNIK           NIK of the co-signer (nodeId is used for cosigNodeId)
 * @returns                  ACTION_COSIG bundle with cosigSig
 */
export function createCoSig(
  entryId: string,
  planId: string,
  cosigNodeId: string,
  cosigPrivateKeyB64: string,
  cosigNIK: NIK,
): CoSigBundle {
  const cosigTime = new Date().toISOString();
  const nodeId    = cosigNIK ? cosigNIK.nodeId : cosigNodeId;

  const payload = {
    type:        'ACTION_COSIG' as const,
    entryId,
    planId,
    cosigNodeId: nodeId,
    cosigTime,
  };
  const payloadBytes = Buffer.from(canonicalJSON(payload), 'utf8');

  const rawSeed  = Buffer.from(cosigPrivateKeyB64, 'base64url');
  const pkcs8Der = Buffer.concat([PKCS8_HEADER, rawSeed]);
  const privKey  = nodeCrypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
  const sigBytes = nodeCrypto.sign(null, payloadBytes, privKey);

  return {
    ...payload,
    cosigSig: sigBytes.toString('base64url'),
  };
}

/**
 * Check multi-person authorisation by verifying co-signature bundles.
 *
 * @param cosigBundles   Array of ACTION_COSIG bundles
 * @param entryId        Entry identifier to match
 * @param planId         Plan identifier to match
 * @param keyCache       Map or plain object of nodeId → NIK
 * @param requiredCount  Minimum valid signatures required
 * @returns              { authorised, validSigCount, invalidCount }
 */
export function checkMultiAuth(
  cosigBundles: CoSigBundle[],
  entryId: string,
  planId: string,
  keyCache: Map<string, NIK> | Record<string, NIK>,
  requiredCount: number,
): MultiAuthResult {
  let validSigCount = 0;
  let invalidCount  = 0;

  for (const bundle of cosigBundles) {
    // Must match entryId and planId
    if (bundle.entryId !== entryId || bundle.planId !== planId) {
      invalidCount++;
      continue;
    }

    // Look up signer NIK in keyCache
    const nodeId = bundle.cosigNodeId;
    let nik: NIK | undefined;
    if (keyCache instanceof Map) {
      nik = keyCache.get(nodeId);
    } else if (keyCache && typeof keyCache === 'object') {
      nik = (keyCache as Record<string, NIK>)[nodeId];
    }

    if (!nik) {
      invalidCount++;
      continue;
    }

    // Verify signature
    const payload = {
      type:        bundle.type,
      entryId:     bundle.entryId,
      planId:      bundle.planId,
      cosigNodeId: bundle.cosigNodeId,
      cosigTime:   bundle.cosigTime,
    };
    const payloadBytes = Buffer.from(canonicalJSON(payload), 'utf8');

    try {
      const rawPub   = Buffer.from(nik.publicKey, 'base64url');
      const spkiDer  = Buffer.concat([SPKI_HEADER, rawPub]);
      const pubKey   = nodeCrypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });
      const sigBytes = Buffer.from(bundle.cosigSig, 'base64url');
      const valid    = nodeCrypto.verify(null, payloadBytes, pubKey, sigBytes);
      if (valid) {
        validSigCount++;
      } else {
        invalidCount++;
      }
    } catch (_) {
      invalidCount++;
    }
  }

  return {
    authorised:   validSigCount >= requiredCount,
    validSigCount,
    invalidCount,
  };
}
