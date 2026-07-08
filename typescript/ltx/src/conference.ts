/**
 * @interplanet/ltx — Conference agenda builder
 * Story 71.2 — LTX-SPECIFICATION.md §14 (Blocks, Cycles, prime-time fairness)
 *
 * A conference agenda is an ordered list of attributed TX Blocks. Across N
 * cycles with N presenting nodes, fair rotation gives each node the opening
 * Block exactly once (§14.4).
 */

import { upgradeConfig } from './plan.js';
import type { LtxNode, LtxPlan, LtxPlanV1, SegmentTemplate } from './types.js';

export interface ConferenceAgendaOptions {
  /** Number of full cycles (each node presents once per cycle). Default 1. */
  cycles?: number;
  /** Quanta per presenting Block. Default 3. */
  blockQ?: number;
  /** Quanta for the PLAN_CONFIRM opener. Default 2. */
  confirmQ?: number;
  /** Quanta for the closing MERGE. Default 2 (0 to omit). */
  mergeQ?: number;
  /** Quanta for the trailing BUFFER. Default 1 (0 to omit). */
  bufferQ?: number;
  /** Insert a CAUCUS of this many quanta between cycles. Default 0 (none). */
  caucusQ?: number;
  /** 'rotate' (default): cycle c opens with node index c mod N. 'fixed': plan order. */
  fairness?: 'rotate' | 'fixed';
  /** Optional label per node id, e.g. { N1: 'Mars Field Report' }. */
  labels?: Record<string, string>;
}

/**
 * Build a conference segment template over the presenting nodes (§14.2).
 * Presenting nodes = every node that is not an OBSERVER.
 * Rotation invariant ('rotate'): across N cycles, each node opens exactly once.
 */
export function buildConferenceAgenda(
  nodes: LtxNode[],
  options: ConferenceAgendaOptions = {},
): SegmentTemplate[] {
  const presenting = nodes.filter(n => n.role !== 'OBSERVER');
  if (presenting.length === 0) throw new Error('buildConferenceAgenda: no presenting nodes');
  const cycles = options.cycles ?? 1;
  const blockQ = options.blockQ ?? 3;
  const confirmQ = options.confirmQ ?? 2;
  const mergeQ = options.mergeQ ?? 2;
  const bufferQ = options.bufferQ ?? 1;
  const caucusQ = options.caucusQ ?? 0;
  const fairness = options.fairness ?? 'rotate';
  const labels = options.labels ?? {};

  const segments: SegmentTemplate[] = [];
  if (confirmQ > 0) segments.push({ type: 'PLAN_CONFIRM', q: confirmQ });

  const n = presenting.length;
  for (let c = 0; c < cycles; c++) {
    if (c > 0 && caucusQ > 0) segments.push({ type: 'CAUCUS', q: caucusQ });
    const offset = fairness === 'rotate' ? c % n : 0;
    for (let i = 0; i < n; i++) {
      const node = presenting[(offset + i) % n];
      segments.push({
        type: 'TX',
        q: blockQ,
        speaker: node.id,
        ...(labels[node.id] ? { label: labels[node.id] } : {}),
      });
    }
  }

  if (mergeQ > 0) segments.push({ type: 'MERGE', q: mergeQ });
  if (bufferQ > 0) segments.push({ type: 'BUFFER', q: bufferQ });
  return segments;
}

export interface PrimeTimeEntry {
  nodeId: string;
  /** Zero-based indices of this node's attributed slots among all attributed slots. */
  slots: number[];
  /** Number of times this node holds the opening Block of a cycle-equivalent. */
  openings: number;
  /** Mean slot desirability in [0, 1]; earlier slots score higher. */
  score: number;
}

/**
 * Score per-node slot desirability over a plan's attributed segments (§14.4).
 * Desirability of attributed slot i (of k) = (k - i) / k, so the opening slot
 * scores 1 and the final slot 1/k. Organisers use the report to spot
 * imbalances when deviating from fair rotation.
 */
export function primeTimeReport(cfg: LtxPlan | LtxPlanV1): PrimeTimeEntry[] {
  const c = upgradeConfig(cfg);
  const attributed = c.segments.filter(s => s.speaker);
  const k = attributed.length;
  const byNode = new Map<string, { slots: number[]; scoreSum: number }>();
  attributed.forEach((seg, i) => {
    const rec = byNode.get(seg.speaker as string) || { slots: [], scoreSum: 0 };
    rec.slots.push(i);
    rec.scoreSum += (k - i) / k;
    byNode.set(seg.speaker as string, rec);
  });
  const n = Math.max(1, byNode.size);
  return [...byNode.entries()]
    .map(([nodeId, rec]) => ({
      nodeId,
      slots: rec.slots,
      // An "opening" is the first slot of each cycle: attributed index ≡ 0 (mod N).
      openings: rec.slots.filter(s => s % n === 0).length,
      score: rec.slots.length ? rec.scoreSum / rec.slots.length : 0,
    }))
    .sort((a, b) => b.score - a.score || (a.nodeId < b.nodeId ? -1 : 1));
}
