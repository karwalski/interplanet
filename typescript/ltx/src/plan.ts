/**
 * @interplanet/ltx — Plan creation and config management
 */

import { DEFAULT_QUANTUM, DEFAULT_SEGMENTS } from './constants.js';
import type { CreatePlanOptions, LtxNode, LtxPlan, LtxPlanV1, LtxPlanV3 } from './types.js';

/**
 * Upgrade a v1 config (`txName` / `rxName` / `delay`) to the v2 schema (`nodes[]`).
 * v2 configs are returned unchanged.
 */
export function upgradeConfig(cfg: LtxPlan | LtxPlanV1): LtxPlan {
  const c = cfg as LtxPlan;
  if (c.v >= 2 && Array.isArray(c.nodes) && c.nodes.length) return c;

  const v1 = cfg as LtxPlanV1;
  const remoteLoc = (v1.rxName || '').toLowerCase().includes('mars') ? 'mars'
    : (v1.rxName || '').toLowerCase().includes('moon') ? 'moon' : 'earth';

  return {
    ...v1,
    v: 2,
    title:    v1.title    || 'LTX Session',
    start:    v1.start    || new Date().toISOString(),
    quantum:  v1.quantum  || DEFAULT_QUANTUM,
    mode:     v1.mode     || 'LTX',
    segments: v1.segments || DEFAULT_SEGMENTS.slice(),
    nodes: [
      { id: 'N0', name: v1.txName || 'Earth HQ',    role: 'HOST',        delay: 0,             location: 'earth'     },
      { id: 'N1', name: v1.rxName || 'Mars Hab-01', role: 'PARTICIPANT',  delay: v1.delay || 0, location: remoteLoc   },
    ],
  };
}

/**
 * Explicitly upgrade a plan to v3 (LTX-SPECIFICATION.md §4.4).
 * NEVER automatic: v3 fields must not be injected into a v2 plan, because the
 * frozen v2 planId hash is insertion-order-sensitive — the upgraded plan is a
 * NEW plan with a new (v3) planId. The input is not mutated.
 */
export function upgradePlanToV3(
  cfg: LtxPlan | LtxPlanV1,
  extras: Partial<Omit<LtxPlanV3, 'v'>> = {},
): LtxPlanV3 {
  const c = upgradeConfig(cfg);
  return {
    ...c,
    ...extras,
    v: 3,
    planVersion: extras.planVersion ?? 1,
  };
}

/**
 * Create a new LTX session plan config (v2).
 */
export function createPlan(opts: CreatePlanOptions = {}): LtxPlan {
  const now = new Date();
  now.setSeconds(0, 0);
  now.setMinutes(now.getMinutes() + 5);

  const nodes: LtxNode[] = opts.nodes || [
    { id: 'N0', name: opts.hostName   || 'Earth HQ',    role: 'HOST',        delay: 0,             location: opts.hostLocation   || 'earth' },
    { id: 'N1', name: opts.remoteName || 'Mars Hab-01', role: 'PARTICIPANT',  delay: opts.delay || 0, location: opts.remoteLocation || 'mars'  },
  ];

  return {
    v:        2,
    title:    opts.title    || 'LTX Session',
    start:    opts.start    || now.toISOString(),
    quantum:  opts.quantum  || DEFAULT_QUANTUM,
    mode:     opts.mode     || 'LTX',
    segments: opts.segments ? opts.segments.slice() : DEFAULT_SEGMENTS.slice(),
    nodes,
  };
}
