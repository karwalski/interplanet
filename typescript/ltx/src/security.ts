/**
 * @interplanet/ltx — Security primitives
 * Story 28.1 — Cryptographic Identity and Canonical JSON
 *
 * canonicalJSON: RFC 8785 / JCS compliant serialisation.
 * NIK: Node Identity Key — Ed25519 key pair, nodeId derivation, expiry checks.
 */

import * as nodeCrypto from 'node:crypto';

// ── NIK types ────────────────────────────────────────────────────────────────

/** Node Identity Key record. */
export interface NIK {
  nodeId: string;
  publicKey: string;
  algorithm: 'Ed25519' | 'P-384';
  validFrom: string;
  validUntil: string;
  keyVersion: number;
  label?: string;
}

export interface GenerateNIKResult {
  nik: NIK;
  privateKeyB64: string;
}

export interface GenerateNIKOptions {
  validDays?: number;
  nodeLabel?: string;
}

// ── Canonical JSON ───────────────────────────────────────────────────────────

/**
 * Canonical JSON serialisation (RFC 8785 / JCS).
 * Recursively sorts object keys lexicographically (Unicode code-point order).
 * Arrays preserve element order. No optional whitespace.
 *
 * @param obj  Any JSON-serialisable value
 * @returns    Canonical JSON string
 */
export function canonicalJSON(obj: unknown): string {
  if (obj === null || typeof obj !== 'object') return JSON.stringify(obj);
  if (Array.isArray(obj)) {
    return '[' + (obj as unknown[]).map(canonicalJSON).join(',') + ']';
  }
  const keys = Object.keys(obj as Record<string, unknown>).sort();
  return (
    '{' +
    keys
      .map(k => JSON.stringify(k) + ':' + canonicalJSON((obj as Record<string, unknown>)[k]))
      .join(',') +
    '}'
  );
}

// ── NIK functions ────────────────────────────────────────────────────────────

/**
 * Generate a new Node Identity Key (NIK) record.
 * Uses Ed25519 via Node.js built-in node:crypto.
 *
 * @param options  Optional configuration
 * @returns        NIK record and base64url-encoded private key seed
 */
export function generateNIK(options: GenerateNIKOptions = {}): GenerateNIKResult {
  const validDays = options.validDays !== undefined ? options.validDays : 365;
  const nodeLabel = options.nodeLabel !== undefined ? options.nodeLabel : '';

  const { privateKey, publicKey } = nodeCrypto.generateKeyPairSync('ed25519');

  // Export raw 32-byte public key from SPKI DER (last 32 bytes)
  const rawPub    = publicKey.export({ type: 'spki', format: 'der' }).slice(-32);
  const pubKeyB64 = rawPub.toString('base64url');

  // Derive nodeId: base64url of first 16 bytes of SHA-256(raw public key)
  const hash   = nodeCrypto.createHash('sha256').update(rawPub).digest();
  const nodeId = hash.slice(0, 16).toString('base64url');

  const now        = new Date();
  const validUntil = new Date(now.getTime() + validDays * 86400000);

  const nik: NIK = {
    nodeId,
    publicKey: pubKeyB64,
    algorithm: 'Ed25519',
    validFrom:  now.toISOString(),
    validUntil: validUntil.toISOString(),
    keyVersion: 1,
    ...(nodeLabel ? { label: nodeLabel } : {}),
  };

  // Export private key seed from PKCS8 DER (last 32 bytes)
  const rawPriv = privateKey.export({ type: 'pkcs8', format: 'der' }).slice(-32);

  return {
    nik,
    privateKeyB64: rawPriv.toString('base64url'),
  };
}

/**
 * Return the full SHA-256 hex fingerprint of a NIK's public key.
 *
 * @param nik  A NIK record
 * @returns    64-character lowercase hex string
 */
export function nikFingerprint(nik: NIK): string {
  const rawPub = Buffer.from(nik.publicKey, 'base64url');
  return nodeCrypto.createHash('sha256').update(rawPub).digest('hex');
}

/**
 * Returns true if the NIK's validUntil timestamp is in the past.
 *
 * @param nik  A NIK record
 * @returns    true if the key has expired
 */
export function isNIKExpired(nik: NIK): boolean {
  return Date.now() > new Date(nik.validUntil).getTime();
}

// ── COSE_Sign1 types ─────────────────────────────────────────────────────────

/** Simplified COSE_Sign1 envelope (JSON+base64url, upgradeable to full CBOR). */
export interface CoseSign1 {
  protected: string;
  unprotected: { kid: string };
  payload: string;
  signature: string;
}

/** Signed session plan envelope returned by signPlan(). */
export interface SignedPlan {
  plan: unknown;
  coseSign1: CoseSign1;
}

/** Result returned by verifyPlan(). */
export interface VerifyResult {
  valid: boolean;
  reason?: string;
}

// ── COSE_Sign1 functions ─────────────────────────────────────────────────────

/**
 * Sign an LTX session plan using a simplified COSE_Sign1-compatible structure.
 * Uses Ed25519 via Node.js node:crypto.
 *
 * @param plan           LTX plan config (any JSON-serialisable object)
 * @param privateKeyB64  Base64url-encoded raw 32-byte Ed25519 private seed
 * @returns              Signed envelope { plan, coseSign1 }
 */
export function signPlan(plan: unknown, privateKeyB64: string): SignedPlan {
  // Use require to get full crypto API (avoids @types/node dependency)
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const crypto = require('node:crypto') as {
    createPrivateKey: (opts: { key: Buffer; format: string; type: string }) => unknown;
    createPublicKey: (key: unknown) => { export: (opts: { type: string; format: string }) => Buffer };
    sign: (alg: null, data: Buffer, key: unknown) => Buffer;
    createHash: (alg: string) => { update: (d: Buffer) => { digest: () => Buffer } };
  };

  // Build protected header: canonical JSON of { alg: -19 } (-19 = EdDSA in COSE)
  const protectedHeader = canonicalJSON({ alg: -19 });
  const protectedB64 = Buffer.from(protectedHeader, 'utf8').toString('base64url');

  // Build payload: canonical JSON of the plan
  const payloadStr = canonicalJSON(plan);
  const payloadB64 = Buffer.from(payloadStr, 'utf8').toString('base64url');

  // Build Sig_Structure: canonical JSON of the array
  const sigStructure = canonicalJSON(['Signature1', protectedB64, '', payloadB64]);

  // Reconstruct Ed25519 private key from raw 32-byte seed via PKCS8 DER wrapping
  // Ed25519 PKCS8 DER header (RFC 8410): 302e020100300506032b657004220420 (16 bytes) + 32-byte seed
  const rawSeed = Buffer.from(privateKeyB64, 'base64url');
  const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
  const pkcs8Der = (Buffer as unknown as { concat: (bufs: Buffer[]) => Buffer }).concat([pkcs8Header, rawSeed]);
  const privKey = crypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });

  // Sign using Ed25519 one-shot API (null = use algorithm from key type)
  const sigBytes = crypto.sign(null, Buffer.from(sigStructure, 'utf8'), privKey);
  const sigB64 = sigBytes.toString('base64url');

  // Derive NIK nodeId from public key to use as kid.
  // nodeId = base64url of first 16 bytes of SHA-256(raw public key), same as generateNIK.
  const pubKeyObj = crypto.createPublicKey(privKey);
  const rawPubForKid = pubKeyObj.export({ type: 'spki', format: 'der' }).slice(-32);
  const kidHash = crypto.createHash('sha256').update(rawPubForKid).digest();
  const kid = kidHash.slice(0, 16).toString('base64url');

  return {
    plan,
    coseSign1: {
      protected: protectedB64,
      unprotected: { kid },
      payload: payloadB64,
      signature: sigB64,
    },
  };
}

/**
 * Verify a COSE_Sign1-signed session plan envelope.
 *
 * @param coseEnvelope  Output from signPlan()
 * @param keyCache      Map or plain object of nodeId → NIK
 * @returns             { valid, reason? }
 */
export function verifyPlan(
  coseEnvelope: SignedPlan,
  keyCache: Map<string, NIK> | Record<string, NIK>,
): VerifyResult {
  const { coseSign1, plan } = coseEnvelope;
  if (!coseSign1) return { valid: false, reason: 'missing_cose_sign1' };

  const kid = coseSign1.unprotected && coseSign1.unprotected.kid;

  // Look up signer's NIK in keyCache (Map or plain object)
  let signerNIK: NIK | undefined;
  if (keyCache instanceof Map) {
    signerNIK = keyCache.get(kid) ||
      [...keyCache.values()].find(n => n.nodeId && n.nodeId.startsWith(kid));
  } else if (keyCache && typeof keyCache === 'object') {
    signerNIK = (keyCache as Record<string, NIK>)[kid] ||
      Object.values(keyCache as Record<string, NIK>).find(
        n => n.nodeId && n.nodeId.startsWith(kid),
      );
  }

  if (!signerNIK) return { valid: false, reason: 'key_not_in_cache' };
  if (isNIKExpired(signerNIK)) return { valid: false, reason: 'key_expired' };

  // Use require to get full crypto API (avoids @types/node dependency)
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const crypto = require('node:crypto') as {
    createPublicKey: (opts: { key: Buffer; format: string; type: string }) => unknown;
    verify: (alg: null, data: Buffer, key: unknown, sig: Buffer) => boolean;
  };

  // Reconstruct Sig_Structure
  const sigStructure = canonicalJSON(['Signature1', coseSign1.protected, '', coseSign1.payload]);

  // Reconstruct Ed25519 public key from raw 32 bytes via SubjectPublicKeyInfo DER wrapping
  // Ed25519 SPKI DER header: 302a300506032b6570032100 (12 bytes) + 32-byte key
  const rawPub = Buffer.from(signerNIK.publicKey, 'base64url');
  const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');
  const spkiDer = (Buffer as unknown as { concat: (bufs: Buffer[]) => Buffer }).concat([spkiHeader, rawPub]);
  const pubKey = crypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });

  // Verify signature
  const sigBytes = Buffer.from(coseSign1.signature, 'base64url');
  const valid = crypto.verify(null, Buffer.from(sigStructure, 'utf8'), pubKey, sigBytes);

  if (!valid) return { valid: false, reason: 'signature_invalid' };

  // Also verify that the embedded payload matches the plan
  const payloadStr = Buffer.from(coseSign1.payload, 'base64url').toString('utf8');
  const planStr = canonicalJSON(plan);
  if (payloadStr !== planStr) return { valid: false, reason: 'payload_mismatch' };

  return { valid: true };
}
