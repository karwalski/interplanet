/**
 * @interplanet/ltx — Merkle Audit Log
 * Story 28.5 — RFC 9162-style Merkle tree audit log
 *
 * Leaf hash:  SHA-256(0x00 || entry_bytes)
 * Node hash:  SHA-256(0x01 || left || right)
 * Empty root: 32 zero bytes (64 hex zeros)
 */

import * as nodeCrypto from 'node:crypto';
import { canonicalJSON } from './security.js';
import type { NIK } from './security.js';

// ── Public interfaces ─────────────────────────────────────────────────────

export interface MerkleAppendResult {
  treeSize: number;
  root: string;
}

export interface InclusionProofStep {
  side: 'left' | 'right';
  hash: string;
}

export interface SignedTreeHead {
  treeSize: number;
  sha256RootHash: string;
  timestamp: string;
  signerNodeId: string;
  treeHeadSig: string;
}

export interface MerkleLog {
  append(entry: unknown): MerkleAppendResult;
  treeSize(): number;
  rootHex(): string;
  inclusionProof(leafIndex: number): InclusionProofStep[];
  verifyInclusion(
    entry: unknown,
    leafIndex: number,
    proof: InclusionProofStep[],
    knownRoot: string,
  ): boolean;
  consistencyProof(oldSize: number): string[];
  signTreeHead(privateKeyB64: string, nodeId: string): SignedTreeHead;
}

// ── Internal hash helpers ─────────────────────────────────────────────────

function _leafHash(entryBytes: Buffer): Buffer {
  const buf = Buffer.alloc(1 + entryBytes.length);
  buf[0] = 0x00;
  entryBytes.copy(buf, 1);
  return nodeCrypto.createHash('sha256').update(buf).digest() as Buffer;
}

function _nodeHash(left: Buffer, right: Buffer): Buffer {
  const buf = Buffer.alloc(1 + 32 + 32);
  buf[0] = 0x01;
  left.copy(buf, 1);
  right.copy(buf, 33);
  return nodeCrypto.createHash('sha256').update(buf).digest() as Buffer;
}

function _rootOf(leavesSlice: Buffer[]): Buffer {
  if (leavesSlice.length === 0) return Buffer.alloc(32);
  if (leavesSlice.length === 1) return leavesSlice[0];
  const mid = Math.pow(2, Math.floor(Math.log2(leavesSlice.length - 1)));
  return _nodeHash(
    _rootOf(leavesSlice.slice(0, mid)),
    _rootOf(leavesSlice.slice(mid)),
  );
}

// ── createMerkleLog ───────────────────────────────────────────────────────

/**
 * Create an RFC 9162-compatible Merkle audit log.
 *
 * @returns MerkleLog instance
 */
export function createMerkleLog(): MerkleLog {
  const leaves: Buffer[] = [];

  function root(): Buffer {
    return _rootOf(leaves.slice());
  }

  return {
    append(entry: unknown): MerkleAppendResult {
      const entryBytes = Buffer.from(canonicalJSON(entry), 'utf8');
      leaves.push(_leafHash(entryBytes));
      return { treeSize: leaves.length, root: root().toString('hex') };
    },

    treeSize(): number {
      return leaves.length;
    },

    rootHex(): string {
      return root().toString('hex');
    },

    inclusionProof(leafIndex: number): InclusionProofStep[] {
      if (leafIndex >= leaves.length) throw new Error('leaf index out of range');
      const proof: InclusionProofStep[] = [];

      function buildProof(lo: number, hi: number, idx: number): void {
        if (hi - lo === 1) return;
        const mid = Math.pow(2, Math.floor(Math.log2((hi - lo) - 1)));
        if (idx < lo + mid) {
          buildProof(lo, lo + mid, idx);
          proof.push({ side: 'right', hash: _rootOf(leaves.slice(lo + mid, hi)).toString('hex') });
        } else {
          buildProof(lo + mid, hi, idx);
          proof.push({ side: 'left', hash: _rootOf(leaves.slice(lo, lo + mid)).toString('hex') });
        }
      }

      buildProof(0, leaves.length, leafIndex);
      return proof;
    },

    verifyInclusion(
      entry: unknown,
      _leafIndex: number,
      proof: InclusionProofStep[],
      knownRoot: string,
    ): boolean {
      let hash = _leafHash(Buffer.from(canonicalJSON(entry), 'utf8'));
      for (const step of proof) {
        const sibling = Buffer.from(step.hash, 'hex');
        hash = step.side === 'right'
          ? _nodeHash(hash, sibling)
          : _nodeHash(sibling, hash);
      }
      return hash.toString('hex') === knownRoot;
    },

    consistencyProof(oldSize: number): string[] {
      const newSize = leaves.length;
      if (oldSize > newSize) throw new Error('oldSize > newSize');
      if (oldSize === newSize) return [];
      const proof: string[] = [];

      function buildConsistency(lo: number, hi: number, oldHi: number, first: boolean): void {
        if (lo === hi) return;
        if (lo + 1 === hi) {
          if (!first) proof.push(leaves[lo].toString('hex'));
          return;
        }
        const mid = Math.pow(2, Math.floor(Math.log2((hi - lo) - 1)));
        if (oldHi - lo <= mid) {
          proof.push(_rootOf(leaves.slice(lo + mid, hi)).toString('hex'));
          buildConsistency(lo, lo + mid, oldHi, first);
        } else {
          if (!first) proof.push(_rootOf(leaves.slice(lo, lo + mid)).toString('hex'));
          buildConsistency(lo + mid, hi, oldHi, false);
        }
      }

      buildConsistency(0, newSize, oldSize, true);
      return proof;
    },

    signTreeHead(privateKeyB64: string, nodeId: string): SignedTreeHead {
      const head = {
        sha256RootHash: root().toString('hex'),
        signerNodeId: nodeId,
        timestamp: new Date().toISOString(),
        treeSize: leaves.length,
      };
      const headStr = canonicalJSON(head);

      // Reconstruct Ed25519 private key from raw 32-byte seed via PKCS8 DER wrapping
      const rawSeed = Buffer.from(privateKeyB64, 'base64url');
      const pkcs8Header = Buffer.from('302e020100300506032b657004220420', 'hex');
      const pkcs8Der = Buffer.concat([pkcs8Header, rawSeed]);
      const privKey = nodeCrypto.createPrivateKey({ key: pkcs8Der, format: 'der', type: 'pkcs8' });

      const sigBytes = nodeCrypto.sign(null, Buffer.from(headStr, 'utf8'), privKey);

      return { ...head, treeHeadSig: sigBytes.toString('base64url') };
    },
  };
}

// ── verifyTreeHead ────────────────────────────────────────────────────────

/**
 * Verify a signed tree head produced by log.signTreeHead().
 *
 * @param signedHead  Output from signTreeHead()
 * @param nik         NIK record of the signer
 * @returns           true if the signature is valid
 */
export function verifyTreeHead(signedHead: SignedTreeHead, nik: NIK): boolean {
  const { treeHeadSig, ...head } = signedHead;
  const headStr = canonicalJSON(head);

  // Reconstruct Ed25519 public key from raw 32 bytes via SPKI DER wrapping
  const rawPub = Buffer.from(nik.publicKey, 'base64url');
  const spkiHeader = Buffer.from('302a300506032b6570032100', 'hex');
  const spkiDer = Buffer.concat([spkiHeader, rawPub]);
  const pubKey = nodeCrypto.createPublicKey({ key: spkiDer, format: 'der', type: 'spki' });

  const sigBytes = Buffer.from(treeHeadSig, 'base64url');
  return nodeCrypto.verify(null, Buffer.from(headStr, 'utf8'), pubKey, sigBytes);
}
