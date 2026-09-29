/**
 * @interplanet/ltx — Sequence Tracking
 * Story 28.4 — Sequence-number freshness and replay protection
 * Story 70.4 — Global freshness scope for session-independent bundles
 *              (LTX-SECURITY.md §11.1)
 *
 * createSequenceTracker: session scope — per-(sessionRootPlanId, nodeId).
 * createGlobalSequenceTracker: global scope — per-(senderNodeId, msgType),
 *   for KEY_BUNDLE / KEY_REVOCATION / release manifests, with a mandatory
 *   issuedAt max-age window (checkIssuedAt).
 * addSeq / checkSeq: bundle stamping and verification helpers.
 */

// ── Types ─────────────────────────────────────────────────────────────────────

/** Result returned by recordSeq() and checkSeq(). */
export interface SeqCheckResult {
  accepted: boolean;
  gap: boolean;
  gapSize: number;
  /**
   * Session-scope trackers only: true when seq is below the high-water mark,
   * inside the reorder window and never seen before (accepted late arrival).
   */
  late?: boolean;
  /** 'replay' | 'invalid_seq' | 'missing_seq' when not accepted. */
  reason?: string;
}

/** Optional external storage adapter (e.g. SQLite, localStorage). */
export interface SequenceTrackerStorage {
  get(key: string): number | undefined;
  set(key: string, value: number): void;
  /** Optional; when absent, cleared entries are overwritten with 0. */
  delete?(key: string): void;
}

/** Options for createSequenceTracker(). */
export interface SequenceTrackerOptions {
  /** Reorder window size (default SEQ_REORDER_WINDOW); 0 disables late acceptance. */
  reorderWindow?: number;
}

/**
 * Default reorder window for inbound seqs (LTX-SECURITY.md §11.2): a seq up to
 * this far below the highest seen, never seen before, is accepted as late.
 */
export const SEQ_REORDER_WINDOW = 64;

/** Sequence tracker instance returned by createSequenceTracker(). */
export interface SequenceTracker {
  /** Increment and return the next outbound sequence number for this node. */
  nextSeq(nodeId: string): number;
  /** Record an inbound seq; returns acceptance result (late / replay / gap). */
  recordSeq(nodeId: string, seq: number): SeqCheckResult;
  /** Seqs below the high-water mark still missing inside the reorder window, ascending. */
  missingSeqs(nodeId: string): number[];
  /** Last accepted inbound seq for nodeId (0 if none seen). */
  lastSeenSeq(nodeId: string): number;
  /** Current outbound seq counter for nodeId (0 if none sent). */
  currentSeq(nodeId: string): number;
  /** Export in-memory state snapshot (for persistence). */
  snapshot(): Record<string, number>;
}

// ── createSequenceTracker ─────────────────────────────────────────────────────

/**
 * Create a sequence tracker for a given plan.
 * Tracks both outbound (nextSeq) and inbound (recordSeq) sequence numbers
 * per nodeId, enabling monotonic-increment enforcement and replay rejection.
 *
 * Inbound seqs are checked against a sliding reorder window below the
 * highest seq seen (the high-water mark). Seqs skipped by a gap are
 * remembered while they remain inside the window, so a delayed but genuine
 * bundle that arrives after a higher seq is accepted and flagged late, while
 * an exact duplicate of an already-accepted (nodeId, seq) is rejected as a
 * replay. Seqs below the window are rejected as replays. Missing-seq markers
 * live in the storage adapter, so the window survives restarts.
 *
 * @param planId   Plan identifier used to namespace storage keys
 * @param storage  Optional storage adapter with get(key)/set(key,val)[/delete(key)]
 * @param options  { reorderWindow } (default SEQ_REORDER_WINDOW)
 * @returns        Sequence tracker instance
 */
export function createSequenceTracker(
  planId: string,
  storage?: SequenceTrackerStorage,
  options: SequenceTrackerOptions = {},
): SequenceTracker {
  const mem = new Map<string, number>();
  const store: SequenceTrackerStorage = storage ?? {
    get: (k: string) => mem.get(k),
    set: (k: string, v: number) => { mem.set(k, v); },
    delete: (k: string) => { mem.delete(k); },
  };
  const reorderWindow = options.reorderWindow ?? SEQ_REORDER_WINDOW;
  if (!Number.isSafeInteger(reorderWindow) || reorderWindow < 0) {
    throw new Error('createSequenceTracker: reorderWindow must be a non-negative integer');
  }

  const prefix = `ltx_seq_${planId}_`;
  const rxKey = (nodeId: string) => prefix + nodeId + '_rx';
  const missKey = (nodeId: string, seq: number) => `${rxKey(nodeId)}_miss_${seq}`;
  const clear = (k: string) => {
    if (store.delete) store.delete(k); else store.set(k, 0);
  };

  return {
    nextSeq(nodeId: string): number {
      const key = prefix + nodeId;
      const current = store.get(key) ?? 0;
      const next = current + 1;
      store.set(key, next);
      return next;
    },

    recordSeq(nodeId: string, seq: number): SeqCheckResult {
      if (!Number.isSafeInteger(seq)) {
        return { accepted: false, gap: false, gapSize: 0, late: false, reason: 'invalid_seq' };
      }
      const key = rxKey(nodeId);
      const last = store.get(key) ?? 0;

      if (seq <= last) {
        const mk = missKey(nodeId, seq);
        if (seq > last - reorderWindow && store.get(mk) === 1) {
          clear(mk);
          return { accepted: true, gap: false, gapSize: 0, late: true };
        }
        return { accepted: false, gap: false, gapSize: 0, late: false, reason: 'replay' };
      }

      const gap = seq > last + 1;
      const gapSize = gap ? seq - last - 1 : 0;
      // Remember skipped seqs that stay inside the new window (seq - W, seq].
      for (let s = Math.max(last + 1, seq - reorderWindow + 1); s < seq; s++) {
        store.set(missKey(nodeId, s), 1);
      }
      // Forget markers that slide out of the window.
      for (let s = Math.max(1, last - reorderWindow + 1); s <= Math.min(last, seq - reorderWindow); s++) {
        if (store.get(missKey(nodeId, s)) === 1) clear(missKey(nodeId, s));
      }
      store.set(key, seq);
      return { accepted: true, gap, gapSize, late: false };
    },

    missingSeqs(nodeId: string): number[] {
      const last = store.get(rxKey(nodeId)) ?? 0;
      const out: number[] = [];
      for (let s = Math.max(1, last - reorderWindow + 1); s < last; s++) {
        if (store.get(missKey(nodeId, s)) === 1) out.push(s);
      }
      return out;
    },

    lastSeenSeq(nodeId: string): number {
      return store.get(prefix + nodeId + '_rx') ?? 0;
    },

    currentSeq(nodeId: string): number {
      return store.get(prefix + nodeId) ?? 0;
    },

    snapshot(): Record<string, number> {
      const out: Record<string, number> = {};
      if (mem.size > 0) {
        for (const [k, v] of mem) out[k] = v;
      }
      return out;
    },
  };
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// ── Global freshness scope (Story 70.4 · LTX-SECURITY.md §11.1) ──────────────

/** Global-scope tracker for session-independent bundle types. */
export interface GlobalSequenceTracker {
  nextSeq(senderNodeId: string, msgType: string): number;
  recordSeq(senderNodeId: string, msgType: string, seq: number): SeqCheckResult;
  lastSeenSeq(senderNodeId: string, msgType: string): number;
  snapshot(): Record<string, number>;
}

/** Default issuedAt max age: 30 days (exceeds the longest conjunction blackout). */
export const ISSUED_AT_MAX_AGE_DAYS = 30;

/**
 * Create a global-scope sequence tracker keyed (senderNodeId, msgType).
 * Session-independent bundles (KEY_BUNDLE, KEY_REVOCATION, release manifests)
 * exist outside any planId; this scope closes cross-session replay.
 */
export function createGlobalSequenceTracker(
  storage?: SequenceTrackerStorage,
): GlobalSequenceTracker {
  const mem = new Map<string, number>();
  const store: SequenceTrackerStorage = storage ?? {
    get: (k: string) => mem.get(k),
    set: (k: string, v: number) => { mem.set(k, v); },
  };
  const key = (senderNodeId: string, msgType: string) =>
    `ltx_gseq_${senderNodeId}_${msgType}`;

  return {
    nextSeq(senderNodeId: string, msgType: string): number {
      const k = key(senderNodeId, msgType);
      const next = (store.get(k) ?? 0) + 1;
      store.set(k, next);
      return next;
    },
    recordSeq(senderNodeId: string, msgType: string, seq: number): SeqCheckResult {
      const k = key(senderNodeId, msgType) + '_rx';
      const last = store.get(k) ?? 0;
      if (seq <= last) return { accepted: false, gap: false, gapSize: 0, reason: 'replay' };
      const gap = seq > last + 1;
      store.set(k, seq);
      return { accepted: true, gap, gapSize: gap ? seq - last - 1 : 0 };
    },
    lastSeenSeq(senderNodeId: string, msgType: string): number {
      return store.get(key(senderNodeId, msgType) + '_rx') ?? 0;
    },
    snapshot(): Record<string, number> {
      const out: Record<string, number> = {};
      for (const [k, v] of mem) out[k] = v;
      return out;
    },
  };
}

/**
 * Enforce the issuedAt max-age window for global-scope bundles
 * (LTX-SECURITY.md §11.2). `nowMs` is injected for determinism.
 */
export function checkIssuedAt(
  issuedAt: string,
  opts: { nowMs: number; maxAgeDays?: number },
): { accepted: boolean; reason?: string } {
  const issued = Date.parse(issuedAt);
  if (Number.isNaN(issued)) return { accepted: false, reason: 'invalid_issued_at' };
  const maxAgeMs = (opts.maxAgeDays ?? ISSUED_AT_MAX_AGE_DAYS) * 86400000;
  if (opts.nowMs - issued > maxAgeMs) return { accepted: false, reason: 'expired' };
  if (issued - opts.nowMs > 86400000) return { accepted: false, reason: 'future_dated' };
  return { accepted: true };
}

/**
 * Add a seq field to a bundle object using the tracker's next sequence number.
 *
 * @param bundle   Bundle object to stamp
 * @param tracker  Sequence tracker (from createSequenceTracker)
 * @param nodeId   Sending node ID
 * @returns        New bundle with seq field added
 */
export function addSeq(
  bundle: Record<string, unknown>,
  tracker: SequenceTracker,
  nodeId: string,
): Record<string, unknown> {
  return { ...bundle, seq: tracker.nextSeq(nodeId) };
}

/**
 * Check an incoming bundle's seq field against the tracker.
 *
 * @param bundle         Incoming bundle (should have .seq)
 * @param tracker        Sequence tracker (from createSequenceTracker)
 * @param senderNodeId   Node ID of the sender
 * @returns              Acceptance result
 */
export function checkSeq(
  bundle: Record<string, unknown>,
  tracker: SequenceTracker,
  senderNodeId: string,
): SeqCheckResult {
  if (typeof bundle.seq !== 'number') {
    return { accepted: false, gap: false, gapSize: 0, reason: 'missing_seq' };
  }
  return tracker.recordSeq(senderNodeId, bundle.seq as number);
}
