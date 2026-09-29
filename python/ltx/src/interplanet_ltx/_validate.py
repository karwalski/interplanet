"""
interplanet_ltx._validate — Plan validation
LTX-SPECIFICATION.md §4 (wire format, spec/ltx-schema.json), §3.5 (reserved
streams) and §7 (reserved branching). Mirrors validatePlan() in
javascript/ltx/ltx-sdk.js and typescript/ltx/src/validate.ts.
"""

import math
import re
from datetime import datetime
from typing import Any, Dict, List

from ._core import SEG_TYPES

#: Every segment type the reference SDKs handle (core §3.4 + auxiliary).
PLAN_SEGMENT_TYPES = SEG_TYPES + ['SPEAK', 'REST', 'PAD', 'OPEN', 'RELAY']
PLAN_MODES = ['LTX', 'LTX-LIVE', 'LTX-RELAY', 'LTX-ASYNC']
#: Fields that exist only in v3 plans (§4.4); MUST NOT appear in v2 (§4.3).
V3_ONLY_FIELDS = ['delays', 'planVersion', 'prevPlanHash', 'questions', 'actions', 'streams']
#: Reserved branching identifiers (§7): MUST be absent from plans and segments.
RESERVED_BRANCH_PLAN_FIELDS = ['branches', 'branching']
RESERVED_BRANCH_SEGMENT_FIELDS = ['branch']
#: Reserved streams identifiers (§3.5): plan streams[] empty, no segment stream.
RESERVED_STREAM_SEGMENT_FIELDS = ['stream']

_HEX64 = re.compile(r'[0-9a-f]{64}')


class ReservedFieldError(ValueError):
    """Raised by plan-constructing APIs when a plan uses reserved fields.

    ``code`` is 'reserved_streams' or 'reserved_branching' (the first error);
    ``errors`` lists every reserved-field violation as {code, path, message}.
    """

    def __init__(self, message: str, code: str, errors: List[Dict[str, str]]):
        super().__init__(message)
        self.code = code
        self.errors = errors


def _is_num(v: Any) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _is_integer(v: Any) -> bool:
    """JavaScript Number.isInteger."""
    return _is_num(v) and math.isfinite(v) and float(v).is_integer()


def _valid_start(v: Any) -> bool:
    if not isinstance(v, str):
        return False
    try:
        datetime.fromisoformat(v.replace('Z', '+00:00'))
        return True
    except ValueError:
        return False


def _reserved_field_errors(plan: Any) -> List[Dict[str, str]]:
    """Reserved-field violations only (§3.5 streams, §7 branching)."""
    errors: List[Dict[str, str]] = []
    if not isinstance(plan, dict):
        return errors
    if 'streams' in plan and not (isinstance(plan['streams'], list) and len(plan['streams']) == 0):
        errors.append({'code': 'reserved_streams', 'path': 'streams',
                       'message': 'streams[] is reserved (§3.5) and MUST be absent or empty'})
    for f in RESERVED_BRANCH_PLAN_FIELDS:
        if f in plan:
            errors.append({'code': 'reserved_branching', 'path': f,
                           'message': f'{f} is reserved for branching (§7, not yet implemented) '
                                      'and MUST be absent'})
    segments = plan.get('segments') if isinstance(plan.get('segments'), list) else []
    for i, s in enumerate(segments):
        if not isinstance(s, dict):
            continue
        for f in RESERVED_STREAM_SEGMENT_FIELDS:
            if f in s:
                errors.append({'code': 'reserved_streams', 'path': f'segments[{i}].{f}',
                               'message': f'segment {f} is reserved (§3.5) and MUST be absent'})
        for f in RESERVED_BRANCH_SEGMENT_FIELDS:
            if f in s:
                errors.append({'code': 'reserved_branching', 'path': f'segments[{i}].{f}',
                               'message': f'segment {f} is reserved for branching (§7) '
                                          'and MUST be absent'})
    return errors


def assert_no_reserved_fields(plan: Any, fn_name: str) -> None:
    """Raise ReservedFieldError if a plan uses reserved stream/branch fields."""
    errors = _reserved_field_errors(plan)
    if errors:
        raise ReservedFieldError(f"{fn_name}: {errors[0]['message']}",
                                 errors[0]['code'], errors)


def validate_plan(plan: Any) -> Dict[str, Any]:
    """Validate a v2 or v3 plan dict against the wire format
    (spec/ltx-schema.json, LTX-SPECIFICATION.md §4) and the reserved-field
    rules (§3.5 streams, §7 branching). v1 configs must be upgraded
    (upgrade_config) first. Pure; never raises.

    Returns ``{'valid': bool, 'errors': [{'code', 'path', 'message'}]}``.
    Error codes: not_an_object, invalid_version, missing_field, invalid_field,
    invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
    duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
    invalid_delays, reserved_streams, reserved_branching.
    """
    errors: List[Dict[str, str]] = []

    def err(code: str, path: str, message: str) -> None:
        errors.append({'code': code, 'path': path, 'message': message})

    if not isinstance(plan, dict):
        err('not_an_object', '', 'plan must be an object')
        return {'valid': False, 'errors': errors}
    v = plan.get('v')
    version = v if _is_num(v) and v in (2, 3) else None
    if version is None:
        err('invalid_version', 'v', 'v must be 2 or 3')
    for f in ('title', 'start', 'quantum', 'mode', 'nodes', 'segments'):
        if f not in plan:
            err('missing_field', f, f'{f} is required')
    if 'title' in plan and not isinstance(plan['title'], str):
        err('invalid_field', 'title', 'title must be a string')
    if 'start' in plan and not _valid_start(plan['start']):
        err('invalid_field', 'start', 'start must be an ISO 8601 UTC timestamp')
    q = plan.get('quantum')
    if 'quantum' in plan and not (_is_integer(q) and 1 <= q <= 60):
        err('invalid_quantum', 'quantum', 'quantum must be an integer 1..60 minutes (§3.2)')
    if 'mode' in plan and plan['mode'] not in PLAN_MODES:
        err('invalid_mode', 'mode', f"mode must be one of {', '.join(PLAN_MODES)}")

    ids = set()
    if 'nodes' in plan:
        nodes = plan['nodes']
        if not isinstance(nodes, list) or len(nodes) == 0:
            err('invalid_nodes', 'nodes', 'nodes must be a non-empty array')
        else:
            hosts = 0
            for i, n in enumerate(nodes):
                if (not isinstance(n, dict) or not isinstance(n.get('id'), str) or not n['id']
                        or '|' in n['id'] or not isinstance(n.get('name'), str)
                        or n.get('role') not in ('HOST', 'PARTICIPANT', 'OBSERVER')
                        or not _is_num(n.get('delay')) or not n['delay'] >= 0):
                    err('invalid_nodes', f'nodes[{i}]',
                        'node needs id (no "|"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0')
                    continue
                if n['id'] in ids:
                    err('duplicate_node_id', f'nodes[{i}].id', f"duplicate node id {n['id']}")
                ids.add(n['id'])
                if n['role'] == 'HOST':
                    hosts += 1
            h = nodes[0]
            if (hosts != 1 or not isinstance(h, dict) or h.get('role') != 'HOST'
                    or not _is_num(h.get('delay')) or h.get('delay') != 0):
                err('invalid_host', 'nodes[0]',
                    'exactly one HOST, first in nodes[], with delay 0 (§3.1)')

    if 'segments' in plan:
        segments = plan['segments']
        if not isinstance(segments, list):
            err('invalid_segment', 'segments', 'segments must be an array')
        else:
            for i, s in enumerate(segments):
                if (not isinstance(s, dict) or s.get('type') not in PLAN_SEGMENT_TYPES
                        or not (_is_integer(s.get('q')) and s['q'] >= 1)):
                    err('invalid_segment', f'segments[{i}]',
                        'segment needs a known type and integer q >= 1')
                    continue
                if 'speaker' in s and s['speaker'] not in ids:
                    sp = 'null' if s['speaker'] is None else s['speaker']
                    err('unknown_speaker', f'segments[{i}].speaker',
                        f'speaker {sp} is not a node id')

    if version == 2:
        for f in V3_ONLY_FIELDS:
            if f in plan:
                err('v3_field_in_v2', f,
                    f'{f} is a v3 field and MUST NOT appear in a v2 plan (§4.3)')
    elif version == 3:
        if 'delays' in plan:
            d = plan['delays']
            if not isinstance(d, dict):
                err('invalid_delays', 'delays', 'delays must be an object')
            else:
                for k, val in d.items():
                    parts = str(k).split('|')
                    if (len(parts) != 2 or not parts[0] < parts[1]
                            or (ids and (parts[0] not in ids or parts[1] not in ids))
                            or not _is_num(val) or not val >= 0):
                        err('invalid_delays', f'delays.{k}',
                            'key must be two known node ids joined by "|" in sorted order; '
                            'value >= 0 (§3.7.2)')
        pv = plan.get('planVersion')
        if 'planVersion' in plan and not (_is_integer(pv) and pv >= 1):
            err('invalid_field', 'planVersion', 'planVersion must be an integer >= 1')
        ph = plan.get('prevPlanHash')
        if 'prevPlanHash' in plan and not (isinstance(ph, str) and _HEX64.fullmatch(ph)):
            err('invalid_field', 'prevPlanHash', 'prevPlanHash must be 64 lowercase hex characters')
        for f in ('questions', 'actions'):
            if f in plan and not isinstance(plan[f], list):
                err('invalid_field', f, f'{f} must be an array')

    errors.extend(_reserved_field_errors(plan))
    return {'valid': len(errors) == 0, 'errors': errors}
