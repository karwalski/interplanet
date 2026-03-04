/**
 * @interplanet/ltx — Node URL building
 */

import { upgradeConfig } from './plan.js';
import { encodeHash }    from './encoding.js';
import type { LtxPlan, LtxPlanV1, NodeUrl } from './types.js';

/**
 * Build perspective URLs for all nodes in a plan.
 *
 * @param cfg     LTX plan config
 * @param baseUrl Base page URL, e.g. `"https://interplanet.live/ltx.html"`
 */
export function buildNodeUrls(cfg: LtxPlan | LtxPlanV1, baseUrl: string): NodeUrl[] {
  const c    = upgradeConfig(cfg);
  const hash = encodeHash(c).replace(/^#/, '');   // "l=eyJ2IjoyLC..."
  const base = (baseUrl || '').replace(/#.*$/, '').replace(/\?.*$/, '');
  return (c.nodes || []).map(node => ({
    nodeId: node.id,
    name:   node.name,
    role:   node.role,
    url:    `${base}?node=${encodeURIComponent(node.id)}#${hash}`,
  }));
}
