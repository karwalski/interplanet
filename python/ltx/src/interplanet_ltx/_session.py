"""
interplanet_ltx._session — Session state machine
Story 68.5 — LTX-SPECIFICATION.md §5 (plan lock, DEGRADED, quorum) and §5.4
(delay-matrix violations). Mirrors typescript/ltx/src/session.ts.

Pure and time-injected: every event carries `now_ms`, transition() never reads
a clock, and all side-effects are returned as effect dicts. Plans are plain
dicts (the same shape sign_plan()/verify_plan() take).

States: DRAFT -> LOCKING -> LOCKED -> ACTIVE <-> DEGRADED -> COMPLETE,
plus EMERGENCY_HOLD (verified EOK override) and ABORTED.
"""

from typing import Any, Dict, List, Optional, Tuple

# Delay-matrix violation thresholds in seconds (LTX-SPECIFICATION.md §5.4)
DELAY_VIOLATION_WARN_S = 120
DELAY_VIOLATION_DEGRADE_S = 300

# Plan-lock timeout factor (LTX-SPECIFICATION.md §5.1)
LOCK_TIMEOUT_FACTOR = 2


def _participants(plan: Dict[str, Any]) -> List[Dict[str, Any]]:
    return [n for n in plan.get('nodes', []) if n.get('role') == 'PARTICIPANT']


def lock_timeout_ms(plan: Dict[str, Any]) -> int:
    """2 x one-way delay to the furthest node, in ms (§5.1)."""
    max_delay_s = max([n.get('delay', 0) for n in plan.get('nodes', [])] or [0])
    return int(LOCK_TIMEOUT_FACTOR * max_delay_s * 1000)


def _quorum_count(plan: Dict[str, Any], quorum: Any) -> int:
    total = len(_participants(plan))
    if quorum == 'majority':
        return total // 2 + 1
    if isinstance(quorum, int) and not isinstance(quorum, bool):
        return min(max(quorum, 1), total)
    return total  # 'all' (default)


def _confirmed_subset(ctx: Dict[str, Any]) -> List[str]:
    host = ctx['plan']['nodes'][0]
    confirmed = sorted(
        (n for n in _participants(ctx['plan'])
         if ctx['confirmations'].get(n['id']) == ctx['planId']),
        key=lambda n: n.get('delay', 0),
    )
    return [host['id']] + [n['id'] for n in confirmed]


def _full_lock_reached(ctx: Dict[str, Any]) -> bool:
    return all(ctx['confirmations'].get(n['id']) == ctx['planId']
               for n in _participants(ctx['plan']))


def _quorum_reached(ctx: Dict[str, Any]) -> bool:
    confirmed = sum(1 for n in _participants(ctx['plan'])
                    if ctx['confirmations'].get(n['id']) == ctx['planId'])
    return confirmed >= ctx['quorumThreshold']


def _declared_delay_s(plan: Dict[str, Any], node_id: str) -> Optional[float]:
    node = next((n for n in plan.get('nodes', []) if n.get('id') == node_id), None)
    if node is None:
        return None
    delays = plan.get('delays')
    if isinstance(delays, dict):
        host_id = plan['nodes'][0]['id']
        key = '|'.join(sorted([host_id, node_id]))
        if isinstance(delays.get(key), (int, float)):
            return delays[key]
    return node.get('delay', 0)


def create_session(plan: Dict[str, Any], plan_id: str,
                   quorum: Any = 'all') -> Dict[str, Any]:
    """Create a session context in DRAFT state. plan_id from make_plan_id()."""
    return {
        'state': 'DRAFT',
        'plan': plan,
        'planId': plan_id,
        'sessionRootPlanId': plan_id,
        'planVersion': plan.get('planVersion', 1),
        'lock': None,
        'lockStartedAtMs': None,
        'lockTimeoutMs': lock_timeout_ms(plan),
        'confirmations': {},
        'mismatched': [],
        'quorumThreshold': _quorum_count(plan, quorum),
        'subset': None,
        'degradedReasons': [],
        'resumeState': None,
        'pendingAmendment': None,
    }


def _moved(ctx: Dict[str, Any], to: str, event: Dict[str, Any],
           effects: List[Dict[str, Any]], detail: str = '') -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    entry: Dict[str, Any] = {
        'type': 'state_transition',
        'from': ctx['state'],
        'to': to,
        'event': event['type'],
        'atMs': event['nowMs'],
    }
    if detail:
        entry['detail'] = detail
    next_ctx = dict(ctx)
    next_ctx['state'] = to
    return next_ctx, [{'kind': 'audit', 'entry': entry}] + effects


def _invalid(ctx: Dict[str, Any], event: Dict[str, Any]) -> Dict[str, Any]:
    return {'kind': 'notify', 'level': 'warn', 'code': 'INVALID_EVENT',
            'detail': f"{event['type']} ignored in state {ctx['state']}"}


def _degrade(ctx: Dict[str, Any], event: Dict[str, Any], reason: str,
             extra: Optional[List[Dict[str, Any]]] = None) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    next_ctx = dict(ctx)
    next_ctx['degradedReasons'] = ctx['degradedReasons'] + [reason]
    effects = [
        {'kind': 'notify', 'level': 'warn', 'code': 'DEGRADED', 'detail': reason},
        {'kind': 'escalate', 'code': 'DEGRADED', 'detail': reason},
    ] + (extra or [])
    if ctx['state'] == 'DEGRADED':
        return next_ctx, effects[:1]
    return _moved(next_ctx, 'DEGRADED', event, effects, reason)


def transition(ctx: Dict[str, Any], event: Dict[str, Any]) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    """Advance the session state machine (pure). Returns (next_ctx, effects)."""
    etype = event['type']

    if etype == 'START_LOCK':
        if ctx['state'] != 'DRAFT':
            return ctx, [_invalid(ctx, event)]
        host_id = ctx['plan']['nodes'][0]['id']
        next_ctx = dict(ctx)
        next_ctx['lockStartedAtMs'] = event['nowMs']
        next_ctx['confirmations'] = dict(ctx['confirmations'], **{host_id: ctx['planId']})
        return _moved(next_ctx, 'LOCKING', event, [])

    if etype == 'PLAN_CONFIRM':
        if ctx['state'] not in ('LOCKING', 'DEGRADED'):
            return ctx, [_invalid(ctx, event)]
        next_ctx = dict(ctx)
        next_ctx['confirmations'] = dict(ctx['confirmations'], **{event['nodeId']: event['planId']})
        if event['planId'] != ctx['planId']:
            next_ctx['mismatched'] = [i for i in ctx['mismatched'] if i != event['nodeId']] + [event['nodeId']]
            return next_ctx, [{
                'kind': 'notify', 'level': 'warn', 'code': 'PLANID_MISMATCH',
                'detail': f"{event['nodeId']} confirmed {event['planId']}, expected {ctx['planId']} (resolve per §5.5)",
            }]
        next_ctx['mismatched'] = [i for i in ctx['mismatched'] if i != event['nodeId']]
        if _full_lock_reached(next_ctx):
            next_ctx['lock'] = 'FULL'
            next_ctx['subset'] = None
            return _moved(next_ctx, 'LOCKED', event, [
                {'kind': 'notify', 'level': 'info', 'code': 'LOCKED', 'detail': 'full lock achieved'},
            ])
        return next_ctx, []

    if etype == 'TICK':
        if ctx['state'] != 'LOCKING' or ctx['lockStartedAtMs'] is None:
            return ctx, []
        if event['nowMs'] - ctx['lockStartedAtMs'] < ctx['lockTimeoutMs']:
            return ctx, []
        if _quorum_reached(ctx):
            subset = _confirmed_subset(ctx)
            next_ctx = dict(ctx)
            next_ctx['lock'] = 'QUORUM'
            next_ctx['subset'] = subset
            missing = [n['id'] for n in _participants(ctx['plan'])
                       if ctx['confirmations'].get(n['id']) != ctx['planId']]
            return _degrade(next_ctx, event,
                            f"quorum lock with subset [{','.join(subset)}]; unconfirmed: [{','.join(missing)}]")
        return _degrade(ctx, event, 'plan-lock timeout without quorum')

    if etype == 'SESSION_START':
        if ctx['state'] == 'LOCKED':
            return _moved(ctx, 'ACTIVE', event, [])
        if ctx['state'] == 'DEGRADED' and ctx['lock'] is not None:
            return ctx, [{
                'kind': 'escalate', 'code': 'DEGRADED_START',
                'detail': 'session start requested while DEGRADED; HOST decision required',
            }]
        return ctx, [_invalid(ctx, event)]

    if etype == 'DELAY_MEASURED':
        if ctx['state'] not in ('ACTIVE', 'LOCKED', 'DEGRADED'):
            return ctx, []
        declared = _declared_delay_s(ctx['plan'], event['nodeId'])
        if declared is None:
            return ctx, [_invalid(ctx, event)]
        deviation = abs(event['measuredDelayS'] - declared)
        if deviation > DELAY_VIOLATION_DEGRADE_S:
            return _degrade(ctx, event,
                            f"delay violation {event['nodeId']}: measured {event['measuredDelayS']}s "
                            f"vs declared {declared}s (>{DELAY_VIOLATION_DEGRADE_S}s)")
        if deviation > DELAY_VIOLATION_WARN_S:
            return ctx, [{
                'kind': 'notify', 'level': 'warn', 'code': 'DELAY_VIOLATION',
                'detail': f"{event['nodeId']}: measured {event['measuredDelayS']}s vs declared {declared}s",
            }]
        return ctx, []

    if etype == 'EOK_OVERRIDE':
        if ctx['state'] in ('COMPLETE', 'ABORTED'):
            return ctx, []
        if not event.get('verified'):
            return ctx, [{
                'kind': 'notify', 'level': 'error', 'code': 'OVERRIDE_REJECTED',
                'detail': event.get('reason', 'override failed verification'),
            }]
        if ctx['state'] == 'EMERGENCY_HOLD':
            return ctx, []
        next_ctx = dict(ctx)
        next_ctx['resumeState'] = ctx['state']
        return _moved(next_ctx, 'EMERGENCY_HOLD', event, [
            {'kind': 'notify', 'level': 'error', 'code': 'EMERGENCY_HOLD',
             'detail': event.get('reason', 'verified EOK override')},
        ])

    if etype == 'AMENDMENT_PROPOSED':
        if ctx['state'] not in ('ACTIVE', 'LOCKED', 'DEGRADED'):
            return ctx, [_invalid(ctx, event)]
        if event['planVersion'] != ctx['planVersion'] + 1:
            return ctx, [{
                'kind': 'notify', 'level': 'error', 'code': 'AMENDMENT_REJECTED',
                'detail': f"planVersion {event['planVersion']} != {ctx['planVersion']} + 1",
            }]
        affected = [n for n in ctx['plan']['nodes'] if n['id'] in event['affectedNodeIds']]
        max_delay_s = max([n.get('delay', 0) for n in affected] or [0])
        next_ctx = dict(ctx)
        next_ctx['pendingAmendment'] = {
            'planId': event['planId'],
            'planVersion': event['planVersion'],
            'affectedNodeIds': list(event['affectedNodeIds']),
            'confirmed': [],
            'proposedAtMs': event['nowMs'],
            'timeoutMs': int(LOCK_TIMEOUT_FACTOR * max_delay_s * 1000),
        }
        return next_ctx, [{
            'kind': 'notify', 'level': 'info', 'code': 'AMENDMENT_PROPOSED',
            'detail': f"plan {event['planId']} v{event['planVersion']}; "
                      f"awaiting [{','.join(event['affectedNodeIds'])}]",
        }]

    if etype == 'AMENDMENT_CONFIRMED':
        pa = ctx['pendingAmendment']
        if not pa or event['planId'] != pa['planId']:
            return ctx, [_invalid(ctx, event)]
        if event['nodeId'] not in pa['affectedNodeIds']:
            return ctx, []
        confirmed = [i for i in pa['confirmed'] if i != event['nodeId']] + [event['nodeId']]
        if len(confirmed) < len(pa['affectedNodeIds']):
            next_ctx = dict(ctx)
            next_ctx['pendingAmendment'] = dict(pa, confirmed=confirmed)
            return next_ctx, []
        next_ctx = dict(ctx)
        next_ctx['planId'] = pa['planId']
        next_ctx['planVersion'] = pa['planVersion']
        next_ctx['pendingAmendment'] = None
        return next_ctx, [{
            'kind': 'notify', 'level': 'info', 'code': 'AMENDMENT_APPLIED',
            'detail': f"plan {pa['planId']} v{pa['planVersion']} in effect "
                      f"(root {ctx['sessionRootPlanId']})",
        }]

    if etype == 'HOST_DECISION':
        decision = event['decision']
        if decision == 'abort':
            if ctx['state'] in ('COMPLETE', 'ABORTED'):
                return ctx, []
            return _moved(ctx, 'ABORTED', event, [])
        if decision == 'resume' and ctx['state'] == 'EMERGENCY_HOLD':
            next_ctx = dict(ctx)
            back = ctx['resumeState'] or 'ACTIVE'
            next_ctx['resumeState'] = None
            return _moved(next_ctx, back, event, [])
        if decision == 'continue' and ctx['state'] == 'DEGRADED':
            detail = (f"continuing with subset [{','.join(ctx['subset'])}]"
                      if ctx['subset'] else 'continuing despite degraded condition')
            return _moved(ctx, 'ACTIVE', event, [
                {'kind': 'notify', 'level': 'warn', 'code': 'CONTINUE_DEGRADED', 'detail': detail},
            ])
        return ctx, [_invalid(ctx, event)]

    if etype == 'SESSION_END':
        if ctx['state'] in ('ACTIVE', 'DEGRADED'):
            return _moved(ctx, 'COMPLETE', event, [])
        return ctx, [_invalid(ctx, event)]

    return ctx, [_invalid(ctx, event)]
