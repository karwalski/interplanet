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
