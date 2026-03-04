/**
 * @interplanet/ltx — Window Manifests and Hedged EdDSA
 * Story 28.8 — Per-window artefact manifests and hedged signing
 *
 * createWindowManifest: Build a signed WINDOW_MANIFEST with hedged EdDSA (random nonceSalt).
 * verifyWindowManifest: Verify a WINDOW_MANIFEST signature against a key cache.
 * hedgedSign / hedgedVerify: Standalone hedged EdDSA signing.
 * artefactSha256: SHA-256 helper for computing artefact hashes.
 */

import * as nodeCrypto from 'node:crypto';
import { canonicalJSON, isNIKExpired } from './security.js';
import type { NIK } from './security.js';
import type { SignedTreeHead } from './merkle.js';

// ── Types ─────────────────────────────────────────────────────────────────────

/** A single artefact entry in a WINDOW_MANIFEST. */
export interface Artefact {
  name: string;
  sha256: string;
  sizeBytes: number;
}

/** Reference to a signed tree head embedded in a WINDOW_MANIFEST. */
export interface TreeHeadRef {
  treeSize: number;
  sha256RootHash: string;
  signerNodeId: string;
  timestamp: string;
  treeHeadSig: string;
}

/** Signed per-window artefact manifest. */
export interface WindowManifest {
  type: 'WINDOW_MANIFEST';
  planId: string;
  windowSeq: number;
  treeHeadRef: TreeHeadRef;
  artefacts: Artefact[];
  nonceSalt: string;
  manifestSig: string;
}

/** Result of hedgedSign(). */
export interface HedgedSignResult {
  signature: string;
  nonceSalt: string;
}

// ── Private key reconstruction helpers ────────────────────────────────────────

const PKCS8_HEADER = Buffer.from('302e020100300506032b657004220420', 'hex');
const SPKI_HEADER  = Buffer.from('302a300506032b6570032100', 'hex');

function _buildPrivKey(privateKeyB64: string): ReturnType<typeof nodeCrypto.createPrivateKey> {
  const rawSeed = Buffer.from(privateKeyB64, 'base64url');
  const pkcs8Der = Buffer.concat([PKCS8_HEADER, rawSeed]);
  return nodeCrypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });
}

function _buildPubKey(publicKeyB64: string): ReturnType<typeof nodeCrypto.createPublicKey> {
  const rawPub = Buffer.from(publicKeyB64, 'base64url');
  const spkiDer = Buffer.concat([SPKI_HEADER, rawPub]);
  return nodeCrypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });
}

// ── Public functions ──────────────────────────────────────────────────────────

/**
 * Compute the SHA-256 hex digest of a string or Buffer.
 * Helper for computing artefact hashes before including in a manifest.
 *
 * @param data  String (encoded as UTF-8) or Buffer
 * @returns     64-character lowercase hex string
 */
export function artefactSha256(data: string | Buffer): string {
  const buf = typeof data === 'string' ? Buffer.from(data, 'utf8') : data;
  return nodeCrypto.createHash('sha256').update(buf).digest('hex');
}

/**
 * Create a signed WINDOW_MANIFEST for a set of artefacts.
 * Uses hedged EdDSA: a random nonceSalt is bound into the signed payload,
 * ensuring each call produces a unique signature even for identical inputs.
 *
 * @param planId         Plan identifier
 * @param windowSeq      Window sequence number
 * @param artefacts      Array of { name, sha256, sizeBytes }
 * @param treeHead       Signed tree head from merkleLog.signTreeHead()
 * @param privateKeyB64  Base64url-encoded raw 32-byte Ed25519 private seed
 * @returns              Complete WINDOW_MANIFEST with manifestSig
 */
export function createWindowManifest(
  planId: string,
  windowSeq: number,
  artefacts: Artefact[],
  treeHead: SignedTreeHead,
  privateKeyB64: string,
): WindowManifest {
  // Generate random 32-byte nonceSalt (hedged EdDSA)
  const nonceSalt = nodeCrypto.randomBytes(32).toString('base64url');

  const treeHeadRef: TreeHeadRef = {
    sha256RootHash: treeHead.sha256RootHash,
    signerNodeId:   treeHead.signerNodeId,
    timestamp:      treeHead.timestamp,
    treeHeadSig:    treeHead.treeHeadSig,
    treeSize:       treeHead.treeSize,
  };

  // Build manifest without sig (keys sorted by canonicalJSON)
  const manifestWithoutSig = {
    artefacts,
    nonceSalt,
    planId,
    treeHeadRef,
    type: 'WINDOW_MANIFEST' as const,
    windowSeq,
  };

  const dataToSign = Buffer.from(canonicalJSON(manifestWithoutSig), 'utf8');
  const privKey = _buildPrivKey(privateKeyB64);
  const sigBytes = nodeCrypto.sign(null, dataToSign, privKey);

  return {
    ...manifestWithoutSig,
    manifestSig: sigBytes.toString('base64url'),
  };
}

/**
 * Verify a WINDOW_MANIFEST signature against a key cache.
 *
 * @param manifest  WINDOW_MANIFEST (from createWindowManifest)
 * @param keyCache  Map or plain object of nodeId → NIK
 * @returns         { valid: true } or { valid: false, reason: string }
 */
export function verifyWindowManifest(
  manifest: WindowManifest,
  keyCache: Map<string, NIK> | Record<string, NIK>,
): { valid: boolean; reason?: string } {
  const signerNodeId = manifest.treeHeadRef && manifest.treeHeadRef.signerNodeId;
  if (!signerNodeId) return { valid: false, reason: 'missing_signer_node_id' };

  let signerNIK: NIK | undefined;
  if (keyCache instanceof Map) {
    signerNIK = keyCache.get(signerNodeId);
  } else if (keyCache && typeof keyCache === 'object') {
    signerNIK = (keyCache as Record<string, NIK>)[signerNodeId];
  }

  if (!signerNIK) return { valid: false, reason: 'key_not_in_cache' };
  if (isNIKExpired(signerNIK)) return { valid: false, reason: 'key_expired' };

  const { manifestSig, ...manifestWithoutSig } = manifest;
  if (!manifestSig) return { valid: false, reason: 'missing_manifest_sig' };

  const pubKey = _buildPubKey(signerNIK.publicKey);
  const sigBytes = Buffer.from(manifestSig, 'base64url');
  const dataToVerify = Buffer.from(canonicalJSON(manifestWithoutSig), 'utf8');
  const valid = nodeCrypto.verify(null, dataToVerify, pubKey, sigBytes);

  if (!valid) return { valid: false, reason: 'signature_invalid' };
  return { valid: true };
}

/**
 * Hedged EdDSA signing: signs dataBytes with a random nonceSalt included in the payload.
 * Produces a unique signature per call even for identical inputs.
 *
 * @param dataBytes      Data to sign (Buffer)
 * @param privateKeyB64  Base64url-encoded raw 32-byte Ed25519 private seed
 * @returns              { signature: base64url, nonceSalt: base64url }
 */
export function hedgedSign(dataBytes: Buffer, privateKeyB64: string): HedgedSignResult {
  const nonceSalt = nodeCrypto.randomBytes(32).toString('base64url');
  const dataB64 = dataBytes.toString('base64url');
  const payload = canonicalJSON({ data: dataB64, nonceSalt });
  const privKey = _buildPrivKey(privateKeyB64);
  const sigBytes = nodeCrypto.sign(null, Buffer.from(payload, 'utf8'), privKey);
  return {
    signature: sigBytes.toString('base64url'),
    nonceSalt,
  };
}

/**
 * Verify a hedged EdDSA signature produced by hedgedSign().
 *
 * @param dataBytes     Original data that was signed
 * @param signature     Base64url-encoded Ed25519 signature
 * @param nonceSalt     Base64url-encoded nonce salt (from hedgedSign result)
 * @param publicKeyB64  Base64url-encoded raw 32-byte Ed25519 public key
 * @returns             true if valid, false otherwise
 */
export function hedgedVerify(
  dataBytes: Buffer,
  signature: string,
  nonceSalt: string,
  publicKeyB64: string,
): boolean {
  const dataB64 = dataBytes.toString('base64url');
  const payload = canonicalJSON({ data: dataB64, nonceSalt });
  const pubKey = _buildPubKey(publicKeyB64);
  const sigBytes = Buffer.from(signature, 'base64url');
  return nodeCrypto.verify(null, Buffer.from(payload, 'utf8'), pubKey, sigBytes);
}
