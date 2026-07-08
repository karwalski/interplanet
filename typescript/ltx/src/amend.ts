/**
 * @interplanet/ltx — Plan amendment chains
 * Story 68.3 — LTX-SPECIFICATION.md §6.4, LTX-SECURITY.md §7.6
 *
 * An amendment replaces a locked plan with a re-signed successor:
 * planVersion + 1 and prevPlanHash = SHA-256(canonicalJSON(predecessor)).
 * The canonical-JSON hash is order-insensitive and collision-resistant —
 * never the legacy v2 polynomial planId hash.
 */

import * as nodeCrypto from 'node:crypto';

import { canonicalJSON, signPlan, verifyPlan } from './security.js';
import type { NIK, SignedPlan, VerifyResult } from './security.js';
import type { AnyLtxPlan, LtxPlan, LtxPlanV3, SegmentTemplate } from './types.js';

/** SHA-256 hex of the RFC 8785 canonical JSON of a plan. */
export function planHash(plan: AnyLtxPlan): string {
  return nodeCrypto.createHash('sha256')
    .update(Buffer.from(canonicalJSON(plan), 'utf8'))
    .digest('hex');
}

/**
 * Create a signed amendment of `signedPlan` with `changes` applied.
 * The successor is always a v3 plan (LTX-SPECIFICATION.md §4.4); the original
 * plan object is not mutated. Fields managed here (`v`, `planVersion`,
 * `prevPlanHash`) cannot be overridden via `changes`.
 */
export function createAmendment(
  signedPlan: SignedPlan,
  changes: Partial<Omit<LtxPlanV3, 'v' | 'planVersion' | 'prevPlanHash'>>,
  privateKeyB64: string,
): SignedPlan {
  const prev = signedPlan.plan as AnyLtxPlan;
  const prevVersion = (prev as LtxPlanV3).planVersion || 1;
  const successor: LtxPlanV3 = {
    ...(prev as LtxPlan),
    ...changes,
    v: 3,
    planVersion: prevVersion + 1,
    prevPlanHash: planHash(prev),
  };
  return signPlan(successor, privateKeyB64);
}

/**
 * Verify an amendment chain: chain[0] is the root plan, each later element a
 * successive amendment. Checks, per link: HOST signature against `keyCache`,
 * planVersion increment of exactly 1, and prevPlanHash equality with the
 * recomputed predecessor hash (LTX-SECURITY.md §7.6).
 */
export function verifyAmendmentChain(
  chain: SignedPlan[],
  keyCache: Map<string, NIK> | Record<string, NIK>,
): VerifyResult {
  if (!Array.isArray(chain) || chain.length === 0) {
    return { valid: false, reason: 'empty_chain' };
  }
  for (let i = 0; i < chain.length; i++) {
    const sig = verifyPlan(chain[i], keyCache);
    if (!sig.valid) return { valid: false, reason: `link_${i}_${sig.reason}` };
  }
  const root = chain[0].plan as LtxPlanV3;
  if (root.prevPlanHash !== undefined) {
    return { valid: false, reason: 'root_has_prev_hash' };
  }
  let prevPlan = chain[0].plan as AnyLtxPlan;
  let prevVersion = (root as LtxPlanV3).planVersion || 1;
  for (let i = 1; i < chain.length; i++) {
    const p = chain[i].plan as LtxPlanV3;
    if (p.v !== 3) return { valid: false, reason: `link_${i}_not_v3` };
    if ((p.planVersion || 0) !== prevVersion + 1) {
      return { valid: false, reason: `link_${i}_version_gap` };
    }
    if (p.prevPlanHash !== planHash(prevPlan)) {
      return { valid: false, reason: `link_${i}_prev_hash_mismatch` };
    }
    prevPlan = p;
    prevVersion = p.planVersion as number;
  }
  return { valid: true };
}

/**
 * Convenience for the §6.2 drift response: amend the plan by inserting a
 * BUFFER segment after segment index `afterIndex` (append with -1).
 * Elapsed segments must not be touched — the caller is responsible for
 * choosing an index at or beyond the current segment.
 */
export function insertBufferViaAmendment(
  signedPlan: SignedPlan,
  options: { afterIndex: number; q: number },
  privateKeyB64: string,
): SignedPlan {
  const prev = signedPlan.plan as AnyLtxPlan;
  const segments: SegmentTemplate[] = prev.segments.slice();
  const buffer: SegmentTemplate = { type: 'BUFFER', q: options.q };
  const at = options.afterIndex < 0 ? segments.length : options.afterIndex + 1;
  segments.splice(at, 0, buffer);
  return createAmendment(signedPlan, { segments }, privateKeyB64);
}
