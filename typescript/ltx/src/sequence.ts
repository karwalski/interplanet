/**
 * @interplanet/ltx — Sequence Tracking
 * Story 28.4 — Sequence-number freshness and replay protection
 *
 * createSequenceTracker: per-(planId, nodeId) monotonic sequence tracking.
 * addSeq / checkSeq: bundle stamping and verification helpers.
 */

// ── Types ─────────────────────────────────────────────────────────────────────

/** Result returned by recordSeq() and checkSeq(). */
export interface SeqCheckResult {
  accepted: boolean;
  gap: boolean;
  gapSize: number;
  reason?: string;
}

/** Optional external storage adapter (e.g. SQLite, localStorage). */
export interface SequenceTrackerStorage {
  get(key: string): number | undefined;
  set(key: string, value: number): void;
}

/** Sequence tracker instance returned by createSequenceTracker(). */
export interface SequenceTracker {
  /** Increment and return the next outbound sequence number for this node. */
  nextSeq(nodeId: string): number;
  /** Record an inbound seq; returns acceptance result. */
  recordSeq(nodeId: string, seq: number): SeqCheckResult;
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
 * @param planId   Plan identifier used to namespace storage keys
 * @param storage  Optional storage adapter with get(key)/set(key,val)
 * @returns        Sequence tracker instance
 */
export function createSequenceTracker(
  planId: string,
  storage?: SequenceTrackerStorage,
): SequenceTracker {
  const mem = new Map<string, number>();
  const store: SequenceTrackerStorage = storage ?? {
    get: (k: string) => mem.get(k),
    set: (k: string, v: number) => { mem.set(k, v); },
  };

  const prefix = `ltx_seq_${planId}_`;

  return {
    nextSeq(nodeId: string): number {
      const key = prefix + nodeId;
      const current = store.get(key) ?? 0;
      const next = current + 1;
      store.set(key, next);
      return next;
    },

    recordSeq(nodeId: string, seq: number): SeqCheckResult {
      const key = prefix + nodeId + '_rx';
      const last = store.get(key) ?? 0;

      if (seq <= last) {
        return { accepted: false, gap: false, gapSize: 0, reason: 'replay' };
      }

      const gap = seq > last + 1;
      const gapSize = gap ? seq - last - 1 : 0;
      store.set(key, seq);
      return { accepted: true, gap, gapSize };
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
