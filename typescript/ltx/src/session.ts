/**
 * @interplanet/ltx — Session state machine
 * Stories 68.1 / 68.2 — LTX-SPECIFICATION.md §5 (plan lock, DEGRADED, quorum)
 * and §5.4 (delay-matrix violations).
 *
 * Pure and time-injected: every event carries `nowMs`, transition() never reads
 * a clock, and all side-effects are returned as SessionEffect values. This keeps
 * the machine deterministic, portable to every language port, and testable
 * without timers.
 */

import {
  DELAY_VIOLATION_WARN_S,
  DELAY_VIOLATION_DEGRADE_S,
  LOCK_TIMEOUT_FACTOR,
} from './constants.js';
import type { AnyLtxPlan, LtxNode } from './types.js';

// ── States and events ────────────────────────────────────────────────────────

export type SessionState =
  | 'DRAFT'
  | 'LOCKING'
  | 'LOCKED'
  | 'ACTIVE'
  | 'DEGRADED'
  | 'EMERGENCY_HOLD'
  | 'COMPLETE'
  | 'ABORTED';

export type LockKind = 'FULL' | 'QUORUM' | null;

export type SessionEvent =
  | { type: 'START_LOCK'; nowMs: number }
  | { type: 'PLAN_CONFIRM'; nowMs: number; nodeId: string; planId: string }
  | { type: 'TICK'; nowMs: number }
  | { type: 'SESSION_START'; nowMs: number }
  | { type: 'DELAY_MEASURED'; nowMs: number; nodeId: string; measuredDelayS: number }
  | { type: 'EOK_OVERRIDE'; nowMs: number; verified: boolean; reason?: string }
  | { type: 'AMENDMENT_PROPOSED'; nowMs: number; planId: string; planVersion: number; affectedNodeIds: string[] }
  | { type: 'AMENDMENT_CONFIRMED'; nowMs: number; nodeId: string; planId: string }
  | { type: 'HOST_DECISION'; nowMs: number; decision: 'continue' | 'abort' | 'resume' }
  | { type: 'SESSION_END'; nowMs: number };

/** Side-effect commands returned by transition(); the caller executes them. */
export type SessionEffect =
  | { kind: 'audit'; entry: StateTransitionEntry }
  | { kind: 'notify'; level: 'info' | 'warn' | 'error'; code: string; detail: string }
  | { kind: 'escalate'; code: string; detail: string };

/** Audit-log payload for a state change (LTX-SECURITY.md §9.6, type state_transition). */
export interface StateTransitionEntry {
  type: 'state_transition';
  from: SessionState;
  to: SessionState;
  event: SessionEvent['type'];
  atMs: number;
  detail?: string;
}

// ── Session context ──────────────────────────────────────────────────────────

export interface SessionOptions {
  /**
   * Quorum threshold for QUORUM-LOCK (LTX-SPECIFICATION.md §5.6):
   * 'all' (default) or 'majority' of PARTICIPANT nodes, or an absolute count.
   */
  quorum?: 'all' | 'majority' | number;
}

export interface PendingAmendment {
  planId: string;
  planVersion: number;
  affectedNodeIds: string[];
  confirmed: string[];
  proposedAtMs: number;
  timeoutMs: number;
}

export interface SessionContext {
  state: SessionState;
  plan: AnyLtxPlan;
  planId: string;
  /** planId of the first (unamended) plan — freshness scope key (LTX-SECURITY §11). */
  sessionRootPlanId: string;
  planVersion: number;
  lock: LockKind;
  lockStartedAtMs: number | null;
  lockTimeoutMs: number;
  /** nodeId → planId confirmed by that node. */
  confirmations: Record<string, string>;
  /** nodeIds that confirmed a planId different from ours (§5.5). */
  mismatched: string[];
  quorumThreshold: number;
  /** Participating subset when quorum-locked (§5.3); null = all nodes. */
  subset: string[] | null;
  degradedReasons: string[];
  /** State to return to when leaving EMERGENCY_HOLD via HOST 'resume'. */
  resumeState: SessionState | null;
  pendingAmendment: PendingAmendment | null;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function participants(plan: AnyLtxPlan): LtxNode[] {
  return plan.nodes.filter(n => n.role === 'PARTICIPANT');
}

/** 2 × one-way delay to the furthest node, in ms (LTX-SPECIFICATION.md §5.1). */
export function lockTimeoutMs(plan: AnyLtxPlan): number {
  const maxDelayS = plan.nodes.reduce((m, n) => Math.max(m, n.delay || 0), 0);
  return LOCK_TIMEOUT_FACTOR * maxDelayS * 1000;
}

function quorumCount(plan: AnyLtxPlan, quorum: SessionOptions['quorum']): number {
  const total = participants(plan).length;
  if (quorum === 'majority') return Math.floor(total / 2) + 1;
  if (typeof quorum === 'number') return Math.min(Math.max(quorum, 1), total);
  return total; // 'all' (default)
}

/** Ascending-delay fallback ordering over confirmed participants (§5.3). */
function confirmedSubset(ctx: SessionContext): string[] {
  const host = ctx.plan.nodes[0];
  const confirmed = participants(ctx.plan)
    .filter(n => ctx.confirmations[n.id] === ctx.planId)
    .sort((a, b) => (a.delay || 0) - (b.delay || 0))
    .map(n => n.id);
  return [host.id, ...confirmed];
}

function fullLockReached(ctx: SessionContext): boolean {
  return participants(ctx.plan).every(n => ctx.confirmations[n.id] === ctx.planId);
}

function quorumReached(ctx: SessionContext): boolean {
  const confirmed = participants(ctx.plan)
    .filter(n => ctx.confirmations[n.id] === ctx.planId).length;
  return confirmed >= ctx.quorumThreshold;
}

/** Declared one-way delay for a node: v3 pair matrix HOST row, else node.delay. */
function declaredDelayS(plan: AnyLtxPlan, nodeId: string): number | null {
  const node = plan.nodes.find(n => n.id === nodeId);
  if (!node) return null;
  const v3 = plan as { delays?: Record<string, number> };
  if (v3.delays) {
    const hostId = plan.nodes[0].id;
    const key = [hostId, nodeId].sort().join('|');
    if (typeof v3.delays[key] === 'number') return v3.delays[key];
  }
  return node.delay || 0;
}

// ── Session construction ─────────────────────────────────────────────────────

/**
 * Create a session context in DRAFT state.
 * `planId` is supplied by the caller (makePlanId) so this module stays pure.
 */
export function createSession(
  plan: AnyLtxPlan,
  planId: string,
  options: SessionOptions = {},
): SessionContext {
  const v3 = plan as { planVersion?: number };
  return {
    state: 'DRAFT',
    plan,
    planId,
    sessionRootPlanId: planId,
    planVersion: v3.planVersion || 1,
    lock: null,
    lockStartedAtMs: null,
    lockTimeoutMs: lockTimeoutMs(plan),
    confirmations: {},
    mismatched: [],
    quorumThreshold: quorumCount(plan, options.quorum),
    subset: null,
    degradedReasons: [],
    resumeState: null,
    pendingAmendment: null,
  };
}

// ── Transition function ──────────────────────────────────────────────────────

export interface TransitionResult {
  ctx: SessionContext;
  effects: SessionEffect[];
}

function moved(
  ctx: SessionContext,
  to: SessionState,
  event: SessionEvent,
  effects: SessionEffect[],
  detail?: string,
): TransitionResult {
  const entry: StateTransitionEntry = {
    type: 'state_transition',
    from: ctx.state,
    to,
    event: event.type,
    atMs: event.nowMs,
    ...(detail ? { detail } : {}),
  };
  return {
    ctx: { ...ctx, state: to },
    effects: [{ kind: 'audit', entry }, ...effects],
  };
}

function unchanged(ctx: SessionContext, effects: SessionEffect[] = []): TransitionResult {
  return { ctx, effects };
}

function degrade(
  ctx: SessionContext,
  event: SessionEvent,
  reason: string,
  extra: SessionEffect[] = [],
): TransitionResult {
  const next = { ...ctx, degradedReasons: [...ctx.degradedReasons, reason] };
  const effects: SessionEffect[] = [
    { kind: 'notify', level: 'warn', code: 'DEGRADED', detail: reason },
    { kind: 'escalate', code: 'DEGRADED', detail: reason },
    ...extra,
  ];
  if (ctx.state === 'DEGRADED') {
    return unchanged(next, effects.slice(0, 1)); // already degraded: notify only
  }
  return moved(next, 'DEGRADED', event, effects, reason);
}

/**
 * Advance the session state machine.
 * Pure: same (ctx, event) always yields the same result.
 */
export function transition(ctx: SessionContext, event: SessionEvent): TransitionResult {
  switch (event.type) {
    case 'START_LOCK': {
      if (ctx.state !== 'DRAFT') return unchanged(ctx, [invalid(ctx, event)]);
      const hostId = ctx.plan.nodes[0].id;
      const next: SessionContext = {
        ...ctx,
        lockStartedAtMs: event.nowMs,
        confirmations: { ...ctx.confirmations, [hostId]: ctx.planId },
      };
      return moved(next, 'LOCKING', event, []);
    }

    case 'PLAN_CONFIRM': {
      if (ctx.state !== 'LOCKING' && ctx.state !== 'DEGRADED') {
        return unchanged(ctx, [invalid(ctx, event)]);
      }
      const next: SessionContext = {
        ...ctx,
        confirmations: { ...ctx.confirmations, [event.nodeId]: event.planId },
      };
      if (event.planId !== ctx.planId) {
        next.mismatched = [...ctx.mismatched.filter(id => id !== event.nodeId), event.nodeId];
        return unchanged(next, [{
          kind: 'notify', level: 'warn', code: 'PLANID_MISMATCH',
          detail: `${event.nodeId} confirmed ${event.planId}, expected ${ctx.planId} (resolve per §5.5)`,
        }]);
      }
      next.mismatched = ctx.mismatched.filter(id => id !== event.nodeId);
      if (fullLockReached(next)) {
        const locked = { ...next, lock: 'FULL' as LockKind, subset: null };
        // Late full confirmation recovers a DEGRADED quorum lock (§5.2).
        return moved(locked, 'LOCKED', event, [
          { kind: 'notify', level: 'info', code: 'LOCKED', detail: 'full lock achieved' },
        ]);
      }
      return unchanged(next);
    }

    case 'TICK': {
      if (ctx.state !== 'LOCKING') return unchanged(ctx);
      if (ctx.lockStartedAtMs === null) return unchanged(ctx);
      if (event.nowMs - ctx.lockStartedAtMs < ctx.lockTimeoutMs) return unchanged(ctx);
      // Lock timeout expired (§5.1).
      if (quorumReached(ctx)) {
        const subset = confirmedSubset(ctx);
        const next = { ...ctx, lock: 'QUORUM' as LockKind, subset };
        const missing = participants(ctx.plan)
          .filter(n => ctx.confirmations[n.id] !== ctx.planId).map(n => n.id);
        return degrade(next, event,
          `quorum lock with subset [${subset.join(',')}]; unconfirmed: [${missing.join(',')}]`);
      }
      return degrade(ctx, event, 'plan-lock timeout without quorum');
    }

    case 'SESSION_START': {
      if (ctx.state === 'LOCKED') return moved(ctx, 'ACTIVE', event, []);
      if (ctx.state === 'DEGRADED' && ctx.lock !== null) {
        // §5.2: escalation to HOST required before TX; HOST_DECISION continue does that.
        return unchanged(ctx, [{
          kind: 'escalate', code: 'DEGRADED_START',
          detail: 'session start requested while DEGRADED; HOST decision required',
        }]);
      }
      return unchanged(ctx, [invalid(ctx, event)]);
    }

    case 'DELAY_MEASURED': {
      if (ctx.state !== 'ACTIVE' && ctx.state !== 'LOCKED' && ctx.state !== 'DEGRADED') {
        return unchanged(ctx);
      }
      const declared = declaredDelayS(ctx.plan, event.nodeId);
      if (declared === null) return unchanged(ctx, [invalid(ctx, event)]);
      const deviation = Math.abs(event.measuredDelayS - declared);
      if (deviation > DELAY_VIOLATION_DEGRADE_S) {
        return degrade(ctx, event,
          `delay violation ${event.nodeId}: measured ${event.measuredDelayS}s vs declared ${declared}s (>${DELAY_VIOLATION_DEGRADE_S}s)`);
      }
      if (deviation > DELAY_VIOLATION_WARN_S) {
        return unchanged(ctx, [{
          kind: 'notify', level: 'warn', code: 'DELAY_VIOLATION',
          detail: `${event.nodeId}: measured ${event.measuredDelayS}s vs declared ${declared}s`,
        }]);
      }
      return unchanged(ctx);
    }

    case 'EOK_OVERRIDE': {
      if (ctx.state === 'COMPLETE' || ctx.state === 'ABORTED') return unchanged(ctx);
      if (!event.verified) {
        return unchanged(ctx, [{
          kind: 'notify', level: 'error', code: 'OVERRIDE_REJECTED',
          detail: event.reason || 'override failed verification',
        }]);
      }
      if (ctx.state === 'EMERGENCY_HOLD') return unchanged(ctx);
      const next = { ...ctx, resumeState: ctx.state };
      return moved(next, 'EMERGENCY_HOLD', event, [
        { kind: 'notify', level: 'error', code: 'EMERGENCY_HOLD', detail: event.reason || 'verified EOK override' },
      ]);
    }

    case 'AMENDMENT_PROPOSED': {
      if (ctx.state !== 'ACTIVE' && ctx.state !== 'LOCKED' && ctx.state !== 'DEGRADED') {
        return unchanged(ctx, [invalid(ctx, event)]);
      }
      if (event.planVersion !== ctx.planVersion + 1) {
        return unchanged(ctx, [{
          kind: 'notify', level: 'error', code: 'AMENDMENT_REJECTED',
          detail: `planVersion ${event.planVersion} != ${ctx.planVersion} + 1`,
        }]);
      }
      // Delta re-lock (§6.4): timeout scoped to the furthest affected node.
      const affected = ctx.plan.nodes.filter(n => event.affectedNodeIds.includes(n.id));
      const maxDelayS = affected.reduce((m, n) => Math.max(m, n.delay || 0), 0);
      const pending: PendingAmendment = {
        planId: event.planId,
        planVersion: event.planVersion,
        affectedNodeIds: event.affectedNodeIds,
        confirmed: [],
        proposedAtMs: event.nowMs,
        timeoutMs: LOCK_TIMEOUT_FACTOR * maxDelayS * 1000,
      };
      return unchanged({ ...ctx, pendingAmendment: pending }, [{
        kind: 'notify', level: 'info', code: 'AMENDMENT_PROPOSED',
        detail: `plan ${event.planId} v${event.planVersion}; awaiting [${event.affectedNodeIds.join(',')}]`,
      }]);
    }

    case 'AMENDMENT_CONFIRMED': {
      const pa = ctx.pendingAmendment;
      if (!pa || event.planId !== pa.planId) return unchanged(ctx, [invalid(ctx, event)]);
      if (!pa.affectedNodeIds.includes(event.nodeId)) return unchanged(ctx);
      const confirmed = [...pa.confirmed.filter(id => id !== event.nodeId), event.nodeId];
      if (confirmed.length < pa.affectedNodeIds.length) {
        return unchanged({ ...ctx, pendingAmendment: { ...pa, confirmed } });
      }
      // All affected nodes confirmed — the amendment applies. The caller swaps
      // ctx.plan for the verified successor plan (transition() only tracks ids).
      const next: SessionContext = {
        ...ctx,
        planId: pa.planId,
        planVersion: pa.planVersion,
        pendingAmendment: null,
      };
      return unchanged(next, [{
        kind: 'notify', level: 'info', code: 'AMENDMENT_APPLIED',
        detail: `plan ${pa.planId} v${pa.planVersion} in effect (root ${ctx.sessionRootPlanId})`,
      }]);
    }

    case 'HOST_DECISION': {
      if (event.decision === 'abort') {
        if (ctx.state === 'COMPLETE' || ctx.state === 'ABORTED') return unchanged(ctx);
        return moved(ctx, 'ABORTED', event, []);
      }
      if (event.decision === 'resume' && ctx.state === 'EMERGENCY_HOLD') {
        const back = ctx.resumeState || 'ACTIVE';
        return moved({ ...ctx, resumeState: null }, back, event, []);
      }
      if (event.decision === 'continue' && ctx.state === 'DEGRADED') {
        // §5.2: HOST elects to continue with the confirmed subset.
        return moved(ctx, 'ACTIVE', event, [{
          kind: 'notify', level: 'warn', code: 'CONTINUE_DEGRADED',
          detail: ctx.subset
            ? `continuing with subset [${ctx.subset.join(',')}]`
            : 'continuing despite degraded condition',
        }]);
      }
      return unchanged(ctx, [invalid(ctx, event)]);
    }

    case 'SESSION_END': {
      if (ctx.state === 'ACTIVE' || ctx.state === 'DEGRADED') {
        return moved(ctx, 'COMPLETE', event, []);
      }
      return unchanged(ctx, [invalid(ctx, event)]);
    }
  }
}

function invalid(ctx: SessionContext, event: SessionEvent): SessionEffect {
  return {
    kind: 'notify', level: 'warn', code: 'INVALID_EVENT',
    detail: `${event.type} ignored in state ${ctx.state}`,
  };
}
