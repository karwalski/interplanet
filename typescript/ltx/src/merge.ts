/**
 * @interplanet/ltx — Deterministic merge and partition recovery
 * Story 69.2 — LTX-SPECIFICATION.md §8, LTX-SECURITY.md §9.4
 *
 * mergeLogs(): verified union of two divergent logs in the §8.2 total order.
 * runMergeSegment(): HOST-signed merge_snapshot for the MERGE segment (§8.4).
 * recoverPartition(): §8.3 flow — verify the remote tree head, accept a
 * verified prefix extension, else deterministic merge, else flag divergence.
 */

import { createMerkleLog, verifyTreeHead } from './merkle.js';
import type { SignedTreeHead } from './merkle.js';
import {
  createRegisterEntry,
  verifyRegisterEntry,
  orderEntries,
  reduceQuestions,
  reduceActions,
} from './registers.js';
import type { CreateEntryOptions, RegisterEntry } from './registers.js';
import { canonicalJSON } from './security.js';
import type { NIK } from './security.js';

export interface MergeResult {
  /** Verified union in (timestamp, nodeId, seq) order. */
  entries: RegisterEntry[];
  /** Entries dropped because their signature failed or key was unknown. */
  rejected: Array<{ entry: RegisterEntry; reason: string }>;
}

/**
 * Deterministic merge of two entry logs (LTX-SPECIFICATION.md §8.2):
 * verify every entry, union de-duplicated by (nodeId, seq), order totally.
 * Both sides of a partition compute the identical result.
 */
export function mergeLogs(
  entriesA: RegisterEntry[],
  entriesB: RegisterEntry[],
  keyCache: Map<string, NIK> | Record<string, NIK>,
): MergeResult {
  const rejected: MergeResult['rejected'] = [];
  const verified: RegisterEntry[] = [];
  for (const entry of [...entriesA, ...entriesB]) {
    const v = verifyRegisterEntry(entry, keyCache);
    if (v.valid) verified.push(entry);
    else rejected.push({ entry, reason: v.reason || 'invalid' });
  }
  return { entries: orderEntries(verified), rejected };
}

/** Merkle root over an ordered entry list (leaves in log order). */
export function entriesRoot(entries: RegisterEntry[]): string {
  const log = createMerkleLog();
  for (const e of entries) log.append(e);
  return log.rootHex();
}

/**
 * Run the MERGE segment (LTX-SPECIFICATION.md §8.4): merge all received logs
 * and append a HOST-signed merge_snapshot entry recording the merged tree
 * root and the reduced register states.
 */
export function runMergeSegment(
  localEntries: RegisterEntry[],
  remoteEntries: RegisterEntry[],
  keyCache: Map<string, NIK> | Record<string, NIK>,
  opts: CreateEntryOptions,
): { merged: MergeResult; snapshot: RegisterEntry } {
  const merged = mergeLogs(localEntries, remoteEntries, keyCache);
  const questions = reduceQuestions(merged.entries);
  const actions = reduceActions(merged.entries);
  const snapshot = createRegisterEntry('merge_snapshot', {
    mergedRoot: entriesRoot(merged.entries),
    entryCount: merged.entries.length,
    rejectedCount: merged.rejected.length,
    questionRegister: questions.byId,
    actionRegister: actions.byId,
    superseded: [...questions.superseded, ...actions.superseded],
  }, opts);
  return { merged, snapshot };
}

export type PartitionOutcome =
  | { action: 'accept_extension'; entries: RegisterEntry[] }
  | { action: 'merged'; entries: RegisterEntry[]; rejected: MergeResult['rejected'] }
  | { action: 'divergent'; reason: string };

/**
 * Partition recovery (LTX-SPECIFICATION.md §8.3, LTX-SECURITY.md §9.4):
 * 1. Verify the remote signed tree head against the remote node's NIK.
 * 2. Verify the remote entry list actually reproduces that tree head.
 * 3. If the local log is a byte-identical prefix of the remote log, accept
 *    the extension. Otherwise fall back to the deterministic §8.2 merge.
 */
export function recoverPartition(
  localEntries: RegisterEntry[],
  remoteEntries: RegisterEntry[],
  remoteHead: SignedTreeHead,
  remoteNik: NIK,
  keyCache: Map<string, NIK> | Record<string, NIK>,
): PartitionOutcome {
  if (!verifyTreeHead(remoteHead, remoteNik)) {
    return { action: 'divergent', reason: 'tree_head_signature_invalid' };
  }
  if (remoteHead.treeSize !== remoteEntries.length ||
      entriesRoot(remoteEntries) !== remoteHead.sha256RootHash) {
    return { action: 'divergent', reason: 'remote_entries_do_not_match_head' };
  }
  if (localEntries.length <= remoteEntries.length) {
    const isPrefix = localEntries.every(
      (e, i) => canonicalJSON(e) === canonicalJSON(remoteEntries[i]),
    );
    if (isPrefix) {
      return { action: 'accept_extension', entries: remoteEntries.slice() };
    }
  }
  const merged = mergeLogs(localEntries, remoteEntries, keyCache);
  return { action: 'merged', entries: merged.entries, rejected: merged.rejected };
}
