/**
 * @interplanet/ltx: Plan validation
 * LTX-SPECIFICATION.md §4 (wire format, spec/ltx-schema.json),
 * §3.5 (reserved streams) and §7 (reserved branching).
 * Mirrors validatePlan() in javascript/ltx/ltx-sdk.js.
 */

import { SEG_TYPES } from './constants.js';

/** Error codes reported by validatePlan(). */
export type PlanValidationCode =
  | 'not_an_object'
  | 'invalid_version'
  | 'missing_field'
  | 'invalid_field'
  | 'invalid_quantum'
  | 'invalid_mode'
  | 'invalid_nodes'
  | 'invalid_host'
  | 'duplicate_node_id'
  | 'invalid_segment'
  | 'unknown_speaker'
  | 'v3_field_in_v2'
  | 'invalid_delays'
  | 'reserved_streams'
  | 'reserved_branching';

/** One validation failure. */
export interface PlanValidationError {
  code: PlanValidationCode;
  /** Location in the plan, e.g. "streams" or "segments[2].branch". */
  path: string;
  message: string;
}

/** Result of validatePlan(). */
export interface PlanValidationResult {
  valid: boolean;
  errors: PlanValidationError[];
}

/** Error thrown by plan-constructing APIs that reject reserved fields. */
export interface ReservedFieldError extends Error {
  code: 'reserved_streams' | 'reserved_branching';
  errors: PlanValidationError[];
}

/** Every segment type the reference SDKs handle (core §3.4 + auxiliary). */
const PLAN_SEGMENT_TYPES: readonly string[] = [...SEG_TYPES, 'SPEAK', 'REST', 'PAD', 'OPEN', 'RELAY'];
const PLAN_MODES: readonly string[] = ['LTX', 'LTX-LIVE', 'LTX-RELAY', 'LTX-ASYNC'];
/** Fields that exist only in v3 plans (§4.4); MUST NOT appear in v2 (§4.3). */
const V3_ONLY_FIELDS = ['delays', 'planVersion', 'prevPlanHash', 'questions', 'actions', 'streams'];
/** Reserved branching identifiers (§7): MUST be absent from plans and segments. */
const RESERVED_BRANCH_PLAN_FIELDS = ['branches', 'branching'];
const RESERVED_BRANCH_SEGMENT_FIELDS = ['branch'];
/** Reserved streams identifiers (§3.5): plan streams[] empty, no segment stream. */
const RESERVED_STREAM_SEGMENT_FIELDS = ['stream'];

type Rec = Record<string, unknown>;

function has(obj: object, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(obj, key);
}

function isRec(v: unknown): v is Rec {
  return !!v && typeof v === 'object' && !Array.isArray(v);
}

/** Reserved-field violations only (§3.5 streams, §7 branching). */
function reservedFieldErrors(plan: unknown): PlanValidationError[] {
  const errors: PlanValidationError[] = [];
  if (!isRec(plan)) return errors;
  if (has(plan, 'streams') && !(Array.isArray(plan.streams) && plan.streams.length === 0)) {
    errors.push({ code: 'reserved_streams', path: 'streams',
      message: 'streams[] is reserved (§3.5) and MUST be absent or empty' });
  }
  for (const f of RESERVED_BRANCH_PLAN_FIELDS) {
    if (has(plan, f)) {
      errors.push({ code: 'reserved_branching', path: f,
        message: `${f} is reserved for branching (§7, not yet implemented) and MUST be absent` });
    }
  }
  const segments = Array.isArray(plan.segments) ? plan.segments : [];
  segments.forEach((s: unknown, i: number) => {
    if (!isRec(s)) return;
    for (const f of RESERVED_STREAM_SEGMENT_FIELDS) {
      if (has(s, f)) {
        errors.push({ code: 'reserved_streams', path: `segments[${i}].${f}`,
          message: `segment ${f} is reserved (§3.5) and MUST be absent` });
      }
    }
    for (const f of RESERVED_BRANCH_SEGMENT_FIELDS) {
      if (has(s, f)) {
        errors.push({ code: 'reserved_branching', path: `segments[${i}].${f}`,
          message: `segment ${f} is reserved for branching (§7) and MUST be absent` });
      }
    }
  });
  return errors;
}

/**
 * Throw a ReservedFieldError if a plan uses reserved stream/branch fields.
 * err.code is the first error code. Internal helper for plan-constructing APIs.
 */
export function assertNoReservedFields(plan: unknown, fnName: string): void {
  const errors = reservedFieldErrors(plan);
  if (errors.length === 0) return;
  const err = new Error(`${fnName}: ${errors[0].message}`) as ReservedFieldError;
  err.code = errors[0].code as ReservedFieldError['code'];
  err.errors = errors;
  throw err;
}

/**
 * Validate a v2 or v3 plan against the wire format (spec/ltx-schema.json,
 * LTX-SPECIFICATION.md §4) and the reserved-field rules (§3.5 streams,
 * §7 branching). v1 configs must be upgraded (upgradeConfig) first.
 * Pure; never throws.
 */
export function validatePlan(plan: unknown): PlanValidationResult {
  const errors: PlanValidationError[] = [];
  const err = (code: PlanValidationCode, path: string, message: string) =>
    errors.push({ code, path, message });
  if (!isRec(plan)) {
    err('not_an_object', '', 'plan must be an object');
    return { valid: false, errors };
  }
  if (plan.v !== 2 && plan.v !== 3) err('invalid_version', 'v', 'v must be 2 or 3');
  for (const f of ['title', 'start', 'quantum', 'mode', 'nodes', 'segments']) {
    if (!has(plan, f)) err('missing_field', f, `${f} is required`);
  }
  if (has(plan, 'title') && typeof plan.title !== 'string') err('invalid_field', 'title', 'title must be a string');
  if (has(plan, 'start') && (typeof plan.start !== 'string' || !Number.isFinite(Date.parse(plan.start)))) {
    err('invalid_field', 'start', 'start must be an ISO 8601 UTC timestamp');
  }
  const q = plan.quantum;
  if (has(plan, 'quantum') && !(typeof q === 'number' && Number.isInteger(q) && q >= 1 && q <= 60)) {
    err('invalid_quantum', 'quantum', 'quantum must be an integer 1..60 minutes (§3.2)');
  }
  if (has(plan, 'mode') && !PLAN_MODES.includes(plan.mode as string)) {
    err('invalid_mode', 'mode', `mode must be one of ${PLAN_MODES.join(', ')}`);
  }

  const ids = new Set<string>();
  if (has(plan, 'nodes')) {
    const nodes = plan.nodes;
    if (!Array.isArray(nodes) || nodes.length === 0) {
      err('invalid_nodes', 'nodes', 'nodes must be a non-empty array');
    } else {
      let hosts = 0;
      nodes.forEach((n: unknown, i: number) => {
        if (!isRec(n) || typeof n.id !== 'string' || !n.id || n.id.includes('|') ||
            typeof n.name !== 'string' || !['HOST', 'PARTICIPANT', 'OBSERVER'].includes(n.role as string) ||
            typeof n.delay !== 'number' || !(n.delay >= 0)) {
          err('invalid_nodes', `nodes[${i}]`, 'node needs id (no "|"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0');
          return;
        }
        if (ids.has(n.id)) err('duplicate_node_id', `nodes[${i}].id`, `duplicate node id ${n.id}`);
        ids.add(n.id);
        if (n.role === 'HOST') hosts++;
      });
      const h = nodes[0] as Rec | undefined;
      if (hosts !== 1 || !isRec(h) || h.role !== 'HOST' || h.delay !== 0) {
        err('invalid_host', 'nodes[0]', 'exactly one HOST, first in nodes[], with delay 0 (§3.1)');
      }
    }
  }

  if (has(plan, 'segments')) {
    if (!Array.isArray(plan.segments)) {
      err('invalid_segment', 'segments', 'segments must be an array');
    } else {
      plan.segments.forEach((s: unknown, i: number) => {
        if (!isRec(s) || !PLAN_SEGMENT_TYPES.includes(s.type as string) ||
            !(typeof s.q === 'number' && Number.isInteger(s.q) && s.q >= 1)) {
          err('invalid_segment', `segments[${i}]`, 'segment needs a known type and integer q >= 1');
          return;
        }
        if (s.speaker !== undefined && !ids.has(s.speaker as string)) {
          err('unknown_speaker', `segments[${i}].speaker`, `speaker ${String(s.speaker)} is not a node id`);
        }
      });
    }
  }

  if (plan.v === 2) {
    for (const f of V3_ONLY_FIELDS) {
      if (has(plan, f)) err('v3_field_in_v2', f, `${f} is a v3 field and MUST NOT appear in a v2 plan (§4.3)`);
    }
  } else if (plan.v === 3) {
    if (has(plan, 'delays')) {
      const d = plan.delays;
      if (!isRec(d)) {
        err('invalid_delays', 'delays', 'delays must be an object');
      } else {
        for (const k of Object.keys(d)) {
          const parts = k.split('|');
          const val = d[k];
          if (parts.length !== 2 || !(parts[0] < parts[1]) ||
              (ids.size > 0 && (!ids.has(parts[0]) || !ids.has(parts[1]))) ||
              typeof val !== 'number' || !(val >= 0)) {
            err('invalid_delays', `delays.${k}`, 'key must be two known node ids joined by "|" in sorted order; value >= 0 (§3.7.2)');
          }
        }
      }
    }
    const pv = plan.planVersion;
    if (has(plan, 'planVersion') && !(typeof pv === 'number' && Number.isInteger(pv) && pv >= 1)) {
      err('invalid_field', 'planVersion', 'planVersion must be an integer >= 1');
    }
    const ph = plan.prevPlanHash;
    if (has(plan, 'prevPlanHash') && !(typeof ph === 'string' && /^[0-9a-f]{64}$/.test(ph))) {
      err('invalid_field', 'prevPlanHash', 'prevPlanHash must be 64 lowercase hex characters');
    }
    for (const f of ['questions', 'actions']) {
      if (has(plan, f) && !Array.isArray(plan[f])) err('invalid_field', f, `${f} must be an array`);
    }
  }

  for (const e of reservedFieldErrors(plan)) errors.push(e);
  return { valid: errors.length === 0, errors };
}
