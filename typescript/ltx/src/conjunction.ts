/**
 * @interplanet/ltx — Conjunction-safe Security Checkpoints
 * Story 28.9 — CONJUNCTION_CHECKPOINT and POST_CONJUNCTION_CLEAR bundles
 *
 * Provides signed checkpoint bundles for capturing Merkle log state and
 * sequence numbers at the start of a conjunction (communication blackout)
 * period, plus a post-conjunction queue and clear mechanism.
 */

import * as nodeCrypto from 'node:crypto';
import type { NIK } from './security.js';
import { canonicalJSON, isNIKExpired } from './security.js';

// ── Types ─────────────────────────────────────────────────────────────────────

/** Conjunction window timing information. */
export interface ConjunctionInfo {
  conjunctionStart: string;
  conjunctionEnd: string;
}

/** Signed checkpoint created at the start of a conjunction period. */
export interface ConjunctionCheckpoint {
  type: 'CONJUNCTION_CHECKPOINT';
  planId: string;
  checkpointSignerNodeId: string;
  checkpointTime: string;
  conjunctionStart: string;
  conjunctionEnd: string;
  merkleRoot: string;
  treeSize: number;
  lastSeqPerNode: Record<string, number>;
  checkpointSig: string;
}

/** Result of a drain operation on the post-conjunction queue. */
export interface DrainResult {
  cleared: number;
  rejected: number;
  rejectedBundles: unknown[];
}

/** Post-conjunction queue for holding bundles during blackout. */
export interface PostConjunctionQueue {
  enqueue(bundle: unknown): number;
  size(): number;
  drain(verifyFn: (bundle: unknown) => { valid: boolean; reason?: string }): DrainResult;
  getQueue(): unknown[];
}

/** Signed clear bundle issued after conjunction ends. */
export interface PostConjunctionClear {
  type: 'POST_CONJUNCTION_CLEAR';
  planId: string;
  clearedAt: string;
  queueProcessed: number;
  clearSig: string;
}

// ── Helper: build Ed25519 private key from base64url seed ─────────────────────

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

// ── createConjunctionCheckpoint ───────────────────────────────────────────────

/**
 * Create a signed CONJUNCTION_CHECKPOINT bundle.
 * Captures Merkle root, tree size, and last sequence numbers at the start
 * of a communication blackout (conjunction) period.
 *
 * @param planId           Plan identifier
 * @param signerNodeId     Node ID of the signer (from nik.nodeId)
 * @param conjunctionInfo  { conjunctionStart, conjunctionEnd } ISO-8601 strings
 * @param merkleRoot       Hex string from merkleLog.rootHex()
 * @param treeSize         Number from merkleLog.treeSize()
 * @param lastSeqPerNode   Plain object { nodeId: lastSeenSeq, ... }
 * @param privateKeyB64    Base64url raw 32-byte Ed25519 seed
 * @returns                Complete CONJUNCTION_CHECKPOINT bundle
 */
export function createConjunctionCheckpoint(
  planId: string,
  signerNodeId: string,
  conjunctionInfo: ConjunctionInfo,
  merkleRoot: string,
  treeSize: number,
  lastSeqPerNode: Record<string, number>,
  privateKeyB64: string,
): ConjunctionCheckpoint {
  const checkpointWithoutSig = {
    type: 'CONJUNCTION_CHECKPOINT' as const,
    planId,
    checkpointSignerNodeId: signerNodeId,
    checkpointTime: new Date().toISOString(),
    conjunctionStart: conjunctionInfo.conjunctionStart,
    conjunctionEnd: conjunctionInfo.conjunctionEnd,
    merkleRoot,
    treeSize,
    lastSeqPerNode,
  };

  const msgBytes = Buffer.from(canonicalJSON(checkpointWithoutSig), 'utf8');
  const privKey = _buildPrivKey(privateKeyB64);
  const sigBytes = nodeCrypto.sign(null, msgBytes, privKey);

  return { ...checkpointWithoutSig, checkpointSig: sigBytes.toString('base64url') };
}

// ── verifyConjunctionCheckpoint ───────────────────────────────────────────────

/**
 * Verify a CONJUNCTION_CHECKPOINT bundle.
 *
 * @param checkpoint  CONJUNCTION_CHECKPOINT bundle
 * @param keyCache    Map or plain object of nodeId → NIK
 * @returns           { valid, reason? }
 */
export function verifyConjunctionCheckpoint(
  checkpoint: ConjunctionCheckpoint,
  keyCache: Map<string, NIK> | Record<string, NIK>,
): { valid: boolean; reason?: string } {
  const { checkpointSig, ...checkpointWithoutSig } = checkpoint;
  if (!checkpointSig) return { valid: false, reason: 'missing_signature' };

  const signerNodeId = checkpoint.checkpointSignerNodeId;
  let candidates: NIK[] = [];

  if (signerNodeId) {
    let signerNIK: NIK | undefined;
    if (keyCache instanceof Map) {
      signerNIK = keyCache.get(signerNodeId);
    } else {
      signerNIK = (keyCache as Record<string, NIK>)[signerNodeId];
    }
    if (signerNIK) {
      candidates = [signerNIK];
    } else {
      return { valid: false, reason: 'key_not_in_cache' };
    }
  } else {
    candidates = keyCache instanceof Map
      ? [...keyCache.values()]
      : Object.values(keyCache as Record<string, NIK>);
  }

  if (candidates.length === 0) return { valid: false, reason: 'key_not_in_cache' };

  const msgBytes = Buffer.from(canonicalJSON(checkpointWithoutSig), 'utf8');
  const sigBuf = Buffer.from(checkpointSig, 'base64url');

  for (const nik of candidates) {
    if (isNIKExpired(nik)) continue;
    try {
      const pubKey = _buildPubKey(nik.publicKey);
      const valid = nodeCrypto.verify(null, msgBytes, pubKey, sigBuf);
      if (valid) return { valid: true };
    } catch (_) {
      // continue to next candidate
    }
  }

  return { valid: false, reason: 'signature_invalid' };
}

// ── createPostConjunctionQueue ────────────────────────────────────────────────

/**
 * Create a post-conjunction queue for holding bundles during a blackout period.
 * Bundles queued during the conjunction are processed via drain() after contact resumes.
 *
 * @returns PostConjunctionQueue instance
 */
export function createPostConjunctionQueue(): PostConjunctionQueue {
  const queue: unknown[] = [];

  return {
    enqueue(bundle: unknown): number {
      queue.push(bundle);
      return queue.length;
    },

    size(): number {
      return queue.length;
    },

    drain(verifyFn: (bundle: unknown) => { valid: boolean; reason?: string }): DrainResult {
      let cleared = 0;
      let rejected = 0;
      const rejectedBundles: unknown[] = [];
      const items = queue.splice(0);
      for (const bundle of items) {
        const result = verifyFn(bundle);
        if (result && result.valid) {
          cleared++;
        } else {
          rejected++;
          rejectedBundles.push(bundle);
        }
      }
      return { cleared, rejected, rejectedBundles };
    },

    getQueue(): unknown[] {
      return queue.slice();
    },
  };
}

// ── createPostConjunctionClear ────────────────────────────────────────────────

/**
 * Create a signed POST_CONJUNCTION_CLEAR bundle.
 * Signals that the conjunction period has ended and queued bundles have been processed.
 *
 * @param planId          Plan identifier
 * @param queueProcessed  Number of queued bundles that were processed
 * @param privateKeyB64   Base64url raw 32-byte Ed25519 seed
 * @returns               Complete POST_CONJUNCTION_CLEAR bundle
 */
export function createPostConjunctionClear(
  planId: string,
  queueProcessed: number,
  privateKeyB64: string,
): PostConjunctionClear {
  const clearWithoutSig = {
    type: 'POST_CONJUNCTION_CLEAR' as const,
    planId,
    clearedAt: new Date().toISOString(),
    queueProcessed,
  };

  const msgBytes = Buffer.from(canonicalJSON(clearWithoutSig), 'utf8');
  const privKey = _buildPrivKey(privateKeyB64);
  const sigBytes = nodeCrypto.sign(null, msgBytes, privKey);

  return { ...clearWithoutSig, clearSig: sigBytes.toString('base64url') };
}

// ── verifyPostConjunctionClear ────────────────────────────────────────────────

/**
 * Verify a POST_CONJUNCTION_CLEAR bundle.
 * Since the clear bundle has no signer ID field, tries each NIK in the cache.
 *
 * @param clearBundle  POST_CONJUNCTION_CLEAR bundle
 * @param keyCache     Map or plain object of nodeId → NIK
 * @returns            { valid, signerNodeId?, reason? }
 */
export function verifyPostConjunctionClear(
  clearBundle: PostConjunctionClear,
  keyCache: Map<string, NIK> | Record<string, NIK>,
): { valid: boolean; signerNodeId?: string; reason?: string } {
  const { clearSig, ...clearWithoutSig } = clearBundle;
  if (!clearSig) return { valid: false, reason: 'missing_signature' };

  const msgBytes = Buffer.from(canonicalJSON(clearWithoutSig), 'utf8');
  const sigBuf = Buffer.from(clearSig, 'base64url');

  const niks: NIK[] = keyCache instanceof Map
    ? [...keyCache.values()]
    : Object.values(keyCache as Record<string, NIK>);

  if (niks.length === 0) return { valid: false, reason: 'key_not_in_cache' };

  for (const nik of niks) {
    if (isNIKExpired(nik)) continue;
    try {
      const pubKey = _buildPubKey(nik.publicKey);
      const valid = nodeCrypto.verify(null, msgBytes, pubKey, sigBuf);
      if (valid) return { valid: true, signerNodeId: nik.nodeId };
    } catch (_) {
      // continue to next candidate
    }
  }

  return { valid: false, reason: 'signature_invalid' };
}
