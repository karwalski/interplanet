/**
 * @interplanet/ltx — COSE_Sign1 (RFC 9052) plan signing
 * Story 70.2 — real CBOR COSE_Sign1 alongside the frozen TRANSITIONAL JSON
 * envelope (LTX-SECURITY.md §7.2/§7.5).
 *
 * Algorithm: Ed25519, COSE algorithm ID -19 (RFC 9864; the polymorphic EdDSA
 * id -8 is deprecated and rejected). Payload: RFC 8785 canonical JSON bytes of
 * the plan. Structure: COSE_Sign1 = tag 18 of
 *   [ protected: bstr .cbor { 1: -19 },
 *     unprotected: { 4: kid-bytes },
 *     payload: bstr,
 *     signature: bstr ]
 * Sig_structure = ["Signature1", protected, external_aad = h'', payload].
 */

import * as nodeCrypto from 'node:crypto';

import { CborTag, decodeCbor, encodeCbor } from './cbor.js';
import { canonicalJSON, isNIKExpired, verifyPlan } from './security.js';
import type { NIK, SignedPlan, VerifyResult } from './security.js';

export const COSE_SIGN1_TAG = 18;
export const COSE_ALG_ED25519 = -19;

/** Signed plan carrying the CBOR COSE_Sign1 envelope (base64url bytes). */
export interface CoseSignedPlan {
  plan: unknown;
  coseSign1CborB64: string;
}

const PKCS8_HEADER = Buffer.from('302e020100300506032b657004220420', 'hex');
const SPKI_HEADER = Buffer.from('302a300506032b6570032100', 'hex');

function privKeyFromSeed(privateKeyB64: string): ReturnType<typeof nodeCrypto.createPrivateKey> {
  const rawSeed = Buffer.from(privateKeyB64, 'base64url');
  return nodeCrypto.createPrivateKey({
    key: Buffer.concat([PKCS8_HEADER, rawSeed]), format: 'der', type: 'pkcs8',
  });
}

function pubKeyFromNik(nik: NIK): ReturnType<typeof nodeCrypto.createPublicKey> {
  const rawPub = Buffer.from(nik.publicKey, 'base64url');
  return nodeCrypto.createPublicKey({
    key: Buffer.concat([SPKI_HEADER, rawPub]), format: 'der', type: 'spki',
  });
}

function sigStructureBytes(protectedBytes: Buffer, payload: Buffer): Buffer {
  return encodeCbor(['Signature1', protectedBytes, Buffer.alloc(0), payload]);
}

/**
 * Sign a plan as a real CBOR COSE_Sign1 (tag 18). The kid (header label 4)
 * is the signer's NIK nodeId — base64url of the first 16 bytes of
 * SHA-256(raw public key), matching generateNIK()/signPlan().
 */
export function signPlanCose(plan: unknown, privateKeyB64: string): CoseSignedPlan {
  const privKey = privKeyFromSeed(privateKeyB64);

  const protectedBytes = encodeCbor(new Map<number, number>([[1, COSE_ALG_ED25519]]));
  const payload = Buffer.from(canonicalJSON(plan), 'utf8');
  const signature = nodeCrypto.sign(null, sigStructureBytes(protectedBytes, payload), privKey) as Buffer;

  const pubKeyObj = nodeCrypto.createPublicKey(privKey);
  const rawPub = (pubKeyObj.export({ type: 'spki', format: 'der' }) as Buffer).slice(-32);
  const kid = (nodeCrypto.createHash('sha256').update(rawPub).digest() as Buffer)
    .slice(0, 16);

  const coseSign1 = new CborTag(COSE_SIGN1_TAG, [
    protectedBytes,
    new Map<number, Buffer>([[4, kid]]),
    payload,
    signature,
  ]);
  return { plan, coseSign1CborB64: encodeCbor(coseSign1).toString('base64url') };
}

/**
 * Verify a CBOR COSE_Sign1 plan envelope against the key cache.
 * Rejects non-Ed25519 algorithms (including the deprecated -8) and payloads
 * that do not match the accompanying plan object.
 */
export function verifyPlanCose(
  envelope: CoseSignedPlan,
  keyCache: Map<string, NIK> | Record<string, NIK>,
): VerifyResult {
  if (!envelope || typeof envelope.coseSign1CborB64 !== 'string') {
    return { valid: false, reason: 'missing_cose_sign1' };
  }

  let decoded: unknown;
  try {
    decoded = decodeCbor(Buffer.from(envelope.coseSign1CborB64, 'base64url'));
  } catch (_) {
    return { valid: false, reason: 'cbor_decode_failed' };
  }
  if (!(decoded instanceof CborTag) || decoded.tag !== COSE_SIGN1_TAG) {
    return { valid: false, reason: 'not_cose_sign1' };
  }
  const arr = decoded.value as unknown[];
  if (!Array.isArray(arr) || arr.length !== 4) {
    return { valid: false, reason: 'malformed_cose_sign1' };
  }
  const [protectedBytes, unprotected, payload, signature] = arr as
    [Buffer, Map<unknown, unknown>, Buffer, Buffer];

  let protectedMap: Map<unknown, unknown>;
  try {
    protectedMap = decodeCbor(protectedBytes) as Map<unknown, unknown>;
  } catch (_) {
    return { valid: false, reason: 'protected_decode_failed' };
  }
  if (protectedMap.get(1) !== COSE_ALG_ED25519) {
    return { valid: false, reason: 'unsupported_alg' };
  }

  const kidRaw = unprotected instanceof Map ? unprotected.get(4) : undefined;
  const kid = kidRaw instanceof Uint8Array
    ? Buffer.from(kidRaw).toString('base64url')
    : typeof kidRaw === 'string' ? kidRaw : '';
  if (!kid) return { valid: false, reason: 'missing_kid' };

  let signerNIK: NIK | undefined;
  if (keyCache instanceof Map) {
    signerNIK = keyCache.get(kid) ||
      [...keyCache.values()].find(n => n.nodeId && n.nodeId.startsWith(kid));
  } else if (keyCache && typeof keyCache === 'object') {
    signerNIK = (keyCache as Record<string, NIK>)[kid] ||
      Object.values(keyCache as Record<string, NIK>).find(
        n => n.nodeId && n.nodeId.startsWith(kid));
  }
  if (!signerNIK) return { valid: false, reason: 'key_not_in_cache' };
  if (isNIKExpired(signerNIK)) return { valid: false, reason: 'key_expired' };

  const ok = nodeCrypto.verify(
    null,
    sigStructureBytes(Buffer.from(protectedBytes), Buffer.from(payload)),
    pubKeyFromNik(signerNIK),
    Buffer.from(signature),
  );
  if (!ok) return { valid: false, reason: 'signature_invalid' };

  if (envelope.plan !== undefined &&
      Buffer.from(payload).toString('utf8') !== canonicalJSON(envelope.plan)) {
    return { valid: false, reason: 'payload_mismatch' };
  }
  return { valid: true };
}

/**
 * Verify either envelope form: the CBOR COSE_Sign1 (coseSign1CborB64) or the
 * frozen TRANSITIONAL JSON envelope (coseSign1) — LTX-SECURITY.md §7.5.
 */
export function verifyPlanAny(
  envelope: CoseSignedPlan | SignedPlan,
  keyCache: Map<string, NIK> | Record<string, NIK>,
): VerifyResult {
  if ((envelope as CoseSignedPlan).coseSign1CborB64 !== undefined) {
    return verifyPlanCose(envelope as CoseSignedPlan, keyCache);
  }
  if ((envelope as SignedPlan).coseSign1 !== undefined) {
    return verifyPlan(envelope as SignedPlan, keyCache);
  }
  return { valid: false, reason: 'unknown_envelope' };
}
