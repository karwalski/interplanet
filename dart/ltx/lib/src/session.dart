// session.dart — LTX v1.1 session state machine (Epic 72 cascade)
// LTX-SPECIFICATION.md §5 (plan lock, DEGRADED, quorum) and §5.4
// (delay-matrix violations).
//
// Pure and time-injected: every event carries 'nowMs', transition() never
// reads a clock, and all side-effects are returned as effect maps. Same
// (ctx, event) always yields the same result.

import 'models.dart';
import 'constants.dart';

/// Session states (LTX-SPECIFICATION.md §5).
const List<String> kV11SessionStates = [
  'DRAFT',
  'LOCKING',
  'LOCKED',
  'ACTIVE',
  'DEGRADED',
  'EMERGENCY_HOLD',
  'COMPLETE',
  'ABORTED',
];

/// Pending amendment awaiting delta re-lock confirmations (§6.4).
class PendingAmendment {
  final String planId;
  final int planVersion;
  final List<String> affectedNodeIds;
  List<String> confirmed;
  final int proposedAtMs;
  final num timeoutMs;

  PendingAmendment({
    required this.planId,
    required this.planVersion,
    required this.affectedNodeIds,
    required this.confirmed,
    required this.proposedAtMs,
    required this.timeoutMs,
  });
}

/// Session context advanced by [transition].
class SessionContext {
  String state;
  final LtxPlan plan;
  String planId;

  /// planId of the first (unamended) plan — freshness scope key.
  final String sessionRootPlanId;
  int planVersion;

  /// 'FULL' | 'QUORUM' | null.
  String? lock;
  int? lockStartedAtMs;
  num lockTimeoutMs;

  /// nodeId → planId confirmed by that node.
  final Map<String, String> confirmations;

  /// nodeIds that confirmed a planId different from ours (§5.5).
  List<String> mismatched;
  final int quorumThreshold;

  /// Participating subset when quorum-locked (§5.3); null = all nodes.
  List<String>? subset;
  List<String> degradedReasons;

  /// State to return to when leaving EMERGENCY_HOLD via HOST 'resume'.
  String? resumeState;
  PendingAmendment? pendingAmendment;

  SessionContext({
    required this.state,
    required this.plan,
    required this.planId,
    required this.sessionRootPlanId,
    required this.planVersion,
    required this.lock,
    required this.lockStartedAtMs,
    required this.lockTimeoutMs,
    required this.confirmations,
    required this.mismatched,
    required this.quorumThreshold,
    required this.subset,
    required this.degradedReasons,
    required this.resumeState,
    required this.pendingAmendment,
  });
}

/// Result of a [transition] call: the (updated) context plus effect maps
/// ({'kind': 'audit'|'notify'|'escalate', ...}) for the caller to execute.
class TransitionResult {
  final SessionContext ctx;
  final List<Map<String, dynamic>> effects;
  const TransitionResult({required this.ctx, required this.effects});
}

List<LtxNode> _participants(LtxPlan plan) =>
    plan.nodes.where((n) => n.role == 'PARTICIPANT').toList();

/// 2 × one-way delay to the furthest node, in ms (§5.1).
num lockTimeoutMs(LtxPlan plan) {
  num maxDelayS = 0;
  for (final n in plan.nodes) {
    if (n.delay > maxDelayS) maxDelayS = n.delay;
  }
  return kDefaultPlanLockTimeoutFactor * maxDelayS * 1000;
}

int _quorumCount(LtxPlan plan, dynamic quorum) {
  final total = _participants(plan).length;
  if (quorum == 'majority') return total ~/ 2 + 1;
  if (quorum is int) return quorum.clamp(1, total);
  return total; // 'all' (default)
}

/// Ascending-delay fallback ordering over confirmed participants (§5.3).
List<String> _confirmedSubset(SessionContext ctx) {
  final host = ctx.plan.nodes[0];
  final confirmed = _participants(ctx.plan)
      .where((n) => ctx.confirmations[n.id] == ctx.planId)
      .toList();
  // Stable ascending-delay sort (index tiebreak keeps declaration order).
  final indexed = confirmed.asMap().entries.toList()
    ..sort((a, b) {
      final d = a.value.delay.compareTo(b.value.delay);
      return d != 0 ? d : a.key.compareTo(b.key);
    });
  return [host.id, ...indexed.map((e) => e.value.id)];
}

bool _fullLockReached(SessionContext ctx) => _participants(ctx.plan)
    .every((n) => ctx.confirmations[n.id] == ctx.planId);

bool _quorumReached(SessionContext ctx) {
  final confirmed = _participants(ctx.plan)
      .where((n) => ctx.confirmations[n.id] == ctx.planId)
      .length;
  return confirmed >= ctx.quorumThreshold;
}

/// Declared one-way delay: v3 pair-matrix HOST row, else node.delay.
num? _declaredDelayS(LtxPlan plan, String nodeId) {
  LtxNode? node;
  for (final n in plan.nodes) {
    if (n.id == nodeId) node = n;
  }
  if (node == null) return null;
  final delays = plan.delays;
  if (delays != null) {
    final hostId = plan.nodes[0].id;
    final key = ([hostId, nodeId]..sort()).join('|');
    if (delays[key] != null) return delays[key];
  }
  return node.delay;
}

/// Create a session context in DRAFT state.
/// [planId] is supplied by the caller (makePlanId) so this module stays pure.
/// [quorum]: 'all' (default) or 'majority' of PARTICIPANT nodes, or an int.
SessionContext createSession(LtxPlan plan, String planId, {dynamic quorum}) {
  return SessionContext(
    state: 'DRAFT',
    plan: plan,
    planId: planId,
    sessionRootPlanId: planId,
    planVersion: plan.planVersion ?? 1,
    lock: null,
    lockStartedAtMs: null,
    lockTimeoutMs: lockTimeoutMs(plan),
    confirmations: {},
    mismatched: [],
    quorumThreshold: _quorumCount(plan, quorum),
    subset: null,
    degradedReasons: [],
    resumeState: null,
    pendingAmendment: null,
  );
}

SessionContext _copy(SessionContext c) => SessionContext(
      state: c.state,
      plan: c.plan,
      planId: c.planId,
      sessionRootPlanId: c.sessionRootPlanId,
      planVersion: c.planVersion,
      lock: c.lock,
      lockStartedAtMs: c.lockStartedAtMs,
      lockTimeoutMs: c.lockTimeoutMs,
      confirmations: Map.of(c.confirmations),
      mismatched: List.of(c.mismatched),
      quorumThreshold: c.quorumThreshold,
      subset: c.subset == null ? null : List.of(c.subset!),
      degradedReasons: List.of(c.degradedReasons),
      resumeState: c.resumeState,
      pendingAmendment: c.pendingAmendment,
    );

Map<String, dynamic> _invalid(SessionContext ctx, Map<String, dynamic> event) => {
      'kind': 'notify',
      'level': 'warn',
      'code': 'INVALID_EVENT',
      'detail': '${event['type']} ignored in state ${ctx.state}',
    };

TransitionResult _moved(
  SessionContext ctx,
  String to,
  Map<String, dynamic> event,
  List<Map<String, dynamic>> effects, [
  String? detail,
]) {
  final entry = <String, dynamic>{
    'type': 'state_transition',
    'from': ctx.state,
    'to': to,
    'event': event['type'],
    'atMs': event['nowMs'],
    if (detail != null) 'detail': detail,
  };
  final next = _copy(ctx)..state = to;
  return TransitionResult(
    ctx: next,
    effects: [
      {'kind': 'audit', 'entry': entry},
      ...effects,
    ],
  );
}

TransitionResult _unchanged(SessionContext ctx,
        [List<Map<String, dynamic>> effects = const []]) =>
    TransitionResult(ctx: ctx, effects: effects);

TransitionResult _degrade(
  SessionContext ctx,
  Map<String, dynamic> event,
  String reason, [
  List<Map<String, dynamic>> extra = const [],
]) {
  final next = _copy(ctx)..degradedReasons = [...ctx.degradedReasons, reason];
  final effects = <Map<String, dynamic>>[
    {'kind': 'notify', 'level': 'warn', 'code': 'DEGRADED', 'detail': reason},
    {'kind': 'escalate', 'code': 'DEGRADED', 'detail': reason},
    ...extra,
  ];
  if (ctx.state == 'DEGRADED') {
    return _unchanged(next, effects.sublist(0, 1)); // already degraded
  }
  return _moved(next, 'DEGRADED', event, effects, reason);
}

/// Advance the session state machine. Pure.
TransitionResult transition(SessionContext ctx, Map<String, dynamic> event) {
  final type = event['type'] as String;
  final nowMs = event['nowMs'] as int;

  switch (type) {
    case 'START_LOCK':
      {
        if (ctx.state != 'DRAFT') return _unchanged(ctx, [_invalid(ctx, event)]);
        final hostId = ctx.plan.nodes[0].id;
        final next = _copy(ctx)..lockStartedAtMs = nowMs;
        next.confirmations[hostId] = ctx.planId;
        return _moved(next, 'LOCKING', event, []);
      }

    case 'PLAN_CONFIRM':
      {
        if (ctx.state != 'LOCKING' && ctx.state != 'DEGRADED') {
          return _unchanged(ctx, [_invalid(ctx, event)]);
        }
        final nodeId = event['nodeId'] as String;
        final planId = event['planId'] as String;
        final next = _copy(ctx);
        next.confirmations[nodeId] = planId;
        if (planId != ctx.planId) {
          next.mismatched = [
            ...ctx.mismatched.where((id) => id != nodeId),
            nodeId,
          ];
          return _unchanged(next, [
            {
              'kind': 'notify',
              'level': 'warn',
              'code': 'PLANID_MISMATCH',
              'detail':
                  '$nodeId confirmed $planId, expected ${ctx.planId} (resolve per §5.5)',
            }
          ]);
        }
        next.mismatched = ctx.mismatched.where((id) => id != nodeId).toList();
        if (_fullLockReached(next)) {
          final locked = _copy(next)
            ..lock = 'FULL'
            ..subset = null;
          // Late full confirmation recovers a DEGRADED quorum lock (§5.2).
          return _moved(locked, 'LOCKED', event, [
            {
              'kind': 'notify',
              'level': 'info',
              'code': 'LOCKED',
              'detail': 'full lock achieved',
            }
          ]);
        }
        return _unchanged(next);
      }

    case 'TICK':
      {
        if (ctx.state != 'LOCKING') return _unchanged(ctx);
        if (ctx.lockStartedAtMs == null) return _unchanged(ctx);
        if (nowMs - ctx.lockStartedAtMs! < ctx.lockTimeoutMs) {
          return _unchanged(ctx);
        }
        // Lock timeout expired (§5.1).
        if (_quorumReached(ctx)) {
          final subset = _confirmedSubset(ctx);
          final next = _copy(ctx)
            ..lock = 'QUORUM'
            ..subset = subset;
          final missing = _participants(ctx.plan)
              .where((n) => ctx.confirmations[n.id] != ctx.planId)
              .map((n) => n.id)
              .toList();
          return _degrade(next, event,
              'quorum lock with subset [${subset.join(',')}]; unconfirmed: [${missing.join(',')}]');
        }
        return _degrade(ctx, event, 'plan-lock timeout without quorum');
      }

    case 'SESSION_START':
      {
        if (ctx.state == 'LOCKED') return _moved(ctx, 'ACTIVE', event, []);
        if (ctx.state == 'DEGRADED' && ctx.lock != null) {
          // §5.2: escalation to HOST required before TX.
          return _unchanged(ctx, [
            {
              'kind': 'escalate',
              'code': 'DEGRADED_START',
              'detail':
                  'session start requested while DEGRADED; HOST decision required',
            }
          ]);
        }
        return _unchanged(ctx, [_invalid(ctx, event)]);
      }

    case 'DELAY_MEASURED':
      {
        if (ctx.state != 'ACTIVE' &&
            ctx.state != 'LOCKED' &&
            ctx.state != 'DEGRADED') {
          return _unchanged(ctx);
        }
        final nodeId = event['nodeId'] as String;
        final measuredDelayS = event['measuredDelayS'] as num;
        final declared = _declaredDelayS(ctx.plan, nodeId);
        if (declared == null) return _unchanged(ctx, [_invalid(ctx, event)]);
        final deviation = (measuredDelayS - declared).abs();
        if (deviation > kDelayViolationDegradedS) {
          return _degrade(ctx, event,
              'delay violation $nodeId: measured ${measuredDelayS}s vs declared ${declared}s (>${kDelayViolationDegradedS}s)');
        }
        if (deviation > kDelayViolationWarnS) {
          return _unchanged(ctx, [
            {
              'kind': 'notify',
              'level': 'warn',
              'code': 'DELAY_VIOLATION',
              'detail':
                  '$nodeId: measured ${measuredDelayS}s vs declared ${declared}s',
            }
          ]);
        }
        return _unchanged(ctx);
      }

    case 'EOK_OVERRIDE':
      {
        if (ctx.state == 'COMPLETE' || ctx.state == 'ABORTED') {
          return _unchanged(ctx);
        }
        final verified = event['verified'] == true;
        final reason = event['reason'] as String?;
        if (!verified) {
          return _unchanged(ctx, [
            {
              'kind': 'notify',
              'level': 'error',
              'code': 'OVERRIDE_REJECTED',
              'detail': reason ?? 'override failed verification',
            }
          ]);
        }
        if (ctx.state == 'EMERGENCY_HOLD') return _unchanged(ctx);
        final next = _copy(ctx)..resumeState = ctx.state;
        return _moved(next, 'EMERGENCY_HOLD', event, [
          {
            'kind': 'notify',
            'level': 'error',
            'code': 'EMERGENCY_HOLD',
            'detail': reason ?? 'verified EOK override',
          }
        ]);
      }

    case 'AMENDMENT_PROPOSED':
      {
        if (ctx.state != 'ACTIVE' &&
            ctx.state != 'LOCKED' &&
            ctx.state != 'DEGRADED') {
          return _unchanged(ctx, [_invalid(ctx, event)]);
        }
        final planId = event['planId'] as String;
        final planVersion = event['planVersion'] as int;
        final affectedNodeIds =
            (event['affectedNodeIds'] as List).cast<String>();
        if (planVersion != ctx.planVersion + 1) {
          return _unchanged(ctx, [
            {
              'kind': 'notify',
              'level': 'error',
              'code': 'AMENDMENT_REJECTED',
              'detail': 'planVersion $planVersion != ${ctx.planVersion} + 1',
            }
          ]);
        }
        // Delta re-lock (§6.4): timeout scoped to the furthest affected node.
        num maxDelayS = 0;
        for (final n in ctx.plan.nodes) {
          if (affectedNodeIds.contains(n.id) && n.delay > maxDelayS) {
            maxDelayS = n.delay;
          }
        }
        final pending = PendingAmendment(
          planId: planId,
          planVersion: planVersion,
          affectedNodeIds: affectedNodeIds,
          confirmed: [],
          proposedAtMs: nowMs,
          timeoutMs: kDefaultPlanLockTimeoutFactor * maxDelayS * 1000,
        );
        final next = _copy(ctx)..pendingAmendment = pending;
        return _unchanged(next, [
          {
            'kind': 'notify',
            'level': 'info',
            'code': 'AMENDMENT_PROPOSED',
            'detail':
                'plan $planId v$planVersion; awaiting [${affectedNodeIds.join(',')}]',
          }
        ]);
      }

    case 'AMENDMENT_CONFIRMED':
      {
        final pa = ctx.pendingAmendment;
        final planId = event['planId'] as String;
        final nodeId = event['nodeId'] as String;
        if (pa == null || planId != pa.planId) {
          return _unchanged(ctx, [_invalid(ctx, event)]);
        }
        if (!pa.affectedNodeIds.contains(nodeId)) return _unchanged(ctx);
        final confirmed = [
          ...pa.confirmed.where((id) => id != nodeId),
          nodeId,
        ];
        if (confirmed.length < pa.affectedNodeIds.length) {
          final next = _copy(ctx)
            ..pendingAmendment = PendingAmendment(
              planId: pa.planId,
              planVersion: pa.planVersion,
              affectedNodeIds: pa.affectedNodeIds,
              confirmed: confirmed,
              proposedAtMs: pa.proposedAtMs,
              timeoutMs: pa.timeoutMs,
            );
          return _unchanged(next);
        }
        // All affected nodes confirmed — the amendment applies. The caller
        // swaps ctx.plan for the verified successor plan.
        final next = _copy(ctx)
          ..planId = pa.planId
          ..planVersion = pa.planVersion
          ..pendingAmendment = null;
        return _unchanged(next, [
          {
            'kind': 'notify',
            'level': 'info',
            'code': 'AMENDMENT_APPLIED',
            'detail':
                'plan ${pa.planId} v${pa.planVersion} in effect (root ${ctx.sessionRootPlanId})',
          }
        ]);
      }

    case 'HOST_DECISION':
      {
        final decision = event['decision'] as String;
        if (decision == 'abort') {
          if (ctx.state == 'COMPLETE' || ctx.state == 'ABORTED') {
            return _unchanged(ctx);
          }
          return _moved(ctx, 'ABORTED', event, []);
        }
        if (decision == 'resume' && ctx.state == 'EMERGENCY_HOLD') {
          final back = ctx.resumeState ?? 'ACTIVE';
          final next = _copy(ctx)..resumeState = null;
          return _moved(next, back, event, []);
        }
        if (decision == 'continue' && ctx.state == 'DEGRADED') {
          // §5.2: HOST elects to continue with the confirmed subset.
          return _moved(ctx, 'ACTIVE', event, [
            {
              'kind': 'notify',
              'level': 'warn',
              'code': 'CONTINUE_DEGRADED',
              'detail': ctx.subset != null
                  ? 'continuing with subset [${ctx.subset!.join(',')}]'
                  : 'continuing despite degraded condition',
            }
          ]);
        }
        return _unchanged(ctx, [_invalid(ctx, event)]);
      }

    case 'SESSION_END':
      {
        if (ctx.state == 'ACTIVE' || ctx.state == 'DEGRADED') {
          return _moved(ctx, 'COMPLETE', event, []);
        }
        return _unchanged(ctx, [_invalid(ctx, event)]);
      }
  }
  return _unchanged(ctx, [_invalid(ctx, event)]);
}
