/**
 * @interplanet/ltx — Constants
 */

import type { SegmentTemplate } from './types.js';

export const VERSION = '1.1.0';

export const SEG_TYPES = ['PLAN_CONFIRM', 'TX', 'RX', 'CAUCUS', 'BUFFER', 'MERGE'] as const;

export const DEFAULT_QUANTUM = 5; // minutes per quantum (LTX SPECIFICATION.md §3.2)

export const DEFAULT_SEGMENTS: SegmentTemplate[] = [
  { type: 'PLAN_CONFIRM', q: 2 },
  { type: 'TX',           q: 2 },
  { type: 'RX',           q: 2 },
  { type: 'CAUCUS',       q: 2 },
  { type: 'TX',           q: 2 },
  { type: 'RX',           q: 2 },
  { type: 'BUFFER',       q: 1 },
];

export const DEFAULT_API_BASE = 'https://interplanet.live/api/ltx.php';

// Delay-matrix violation thresholds in seconds (LTX-SPECIFICATION.md §5.4)
export const DELAY_VIOLATION_WARN_S    = 120;
export const DELAY_VIOLATION_DEGRADE_S = 300;

// Plan-lock timeout factor (LTX-SPECIFICATION.md §5.1): 2 × one-way delay
export const LOCK_TIMEOUT_FACTOR = 2;
