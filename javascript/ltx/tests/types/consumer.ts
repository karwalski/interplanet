// Type-check smoke test for ltx-sdk.d.ts. Compiled with `tsc --noEmit` by
// `make check-types`; never executed.
import * as ltx from '../../ltx-sdk';
import ltxCjs = require('../../ltx-sdk');

const version: string = ltx.VERSION;
const plan: object = ltx.createPlan({ hostName: 'Earth HQ', delay: 860 });

const check: { valid: boolean; errors: Array<{ code: string; path: string; message: string }> } =
  ltx.validatePlan(plan);
const segs = ltx.computeSegments(plan);
const firstStart: Date | undefined = segs[0]?.start;
const matrix = ltx.buildDelayMatrix(plan);
const seconds: number = matrix.length ? matrix[0].delaySeconds : ltx.pairDelay(plan, 'N0', 'N1');
const hash: string = ltx.encodeHash(plan);
const ics: string = ltx.generateICS(plan);
const decisions = ltx.reduceDecisions([]);
const superseded: unknown[] = decisions.superseded;
const hms: string = ltxCjs.formatHMS(seconds);

// @ts-expect-error computeSegments requires a plan argument
ltx.computeSegments();

void [version, check, firstStart, hash, ics, superseded, hms];
