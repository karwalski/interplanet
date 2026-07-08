/**
 * @interplanet/ltx — Type definitions
 * LTX (Light-Time eXchange) meeting protocol types.
 */

/** Valid segment type identifiers. */
export type SegmentType = 'PLAN_CONFIRM' | 'TX' | 'RX' | 'CAUCUS' | 'BUFFER' | 'MERGE';

/** Node role within a session. */
export type NodeRole = 'HOST' | 'PARTICIPANT' | 'OBSERVER';

/** Location key — planet name or 'earth'. */
export type LocationKey = string;

/** A segment template entry in the plan config. */
export interface SegmentTemplate {
  type: SegmentType;
  /** Number of quanta. */
  q: number;
  /** Presenting node id for attributed TX segments (LTX-SPECIFICATION.md §3.4.1). */
  speaker?: string;
  /** Agenda title for this segment (LTX-SPECIFICATION.md §3.4.1). */
  label?: string;
}

/** A single node (party) in a session. */
export interface LtxNode {
  id: string;
  name: string;
  role: NodeRole;
  /** One-way signal delay in seconds (0 for host). */
  delay: number;
  location: LocationKey;
}

/** v2 plan configuration — the canonical on-wire format. */
export interface LtxPlan {
  v: 2;
  title: string;
  /** ISO 8601 UTC start time. */
  start: string;
  /** Minutes per quantum. */
  quantum: number;
  mode: string;
  nodes: LtxNode[];
  segments: SegmentTemplate[];
}

/**
 * v3 plan — strictly additive extension of v2 (LTX-SPECIFICATION.md §4.4).
 * v3 fields MUST NOT be injected into a v2 plan (the frozen v2 planId hash is
 * insertion-order-sensitive); use upgradePlanToV3() / createAmendment().
 */
export interface LtxPlanV3 extends Omit<LtxPlan, 'v'> {
  v: 3;
  /** Pair-wise one-way delays in seconds, keyed "A|B" with A < B lexicographically. */
  delays?: Record<string, number>;
  /** Amendment counter; 1 for a root plan (LTX-SPECIFICATION.md §6.4). */
  planVersion?: number;
  /** SHA-256 hex of canonicalJSON of the predecessor plan in an amendment chain. */
  prevPlanHash?: string;
  /** Pre-polled question seeds (LTX-SPECIFICATION.md §9.2). */
  questions?: unknown[];
  /** Action register seeds (LTX-SPECIFICATION.md §10). */
  actions?: unknown[];
  /** Reserved (LTX-SPECIFICATION.md §3.5). MUST be absent or empty. */
  streams?: unknown[];
}

/** Any current plan version accepted by session-level APIs. */
export type AnyLtxPlan = LtxPlan | LtxPlanV3;

/** A v1 plan config (legacy two-party format). */
export interface LtxPlanV1 {
  v?: 1;
  title?: string;
  start?: string;
  quantum?: number;
  mode?: string;
  txName?: string;
  rxName?: string;
  delay?: number;
  segments?: SegmentTemplate[];
}

/** A computed, timed segment. */
export interface LtxSegment {
  type: SegmentType;
  q: number;
  start: Date;
  end: Date;
  /** Duration in minutes. */
  durMin: number;
}

/** Options for createPlan(). */
export interface CreatePlanOptions {
  title?: string;
  /** ISO 8601 UTC start time. */
  start?: string;
  quantum?: number;
  mode?: string;
  /** Explicit node list (overrides hostName / remoteName). */
  nodes?: LtxNode[];
  hostName?: string;
  hostLocation?: LocationKey;
  remoteName?: string;
  remoteLocation?: LocationKey;
  /** One-way signal delay in seconds. */
  delay?: number;
  segments?: SegmentTemplate[];
}

/** A node perspective URL entry. */
export interface NodeUrl {
  nodeId: string;
  name: string;
  role: NodeRole;
  url: string;
}
