"""
interplanet_ltx._amend — Plan amendment chains
Story 68.5 — LTX-SPECIFICATION.md §6.4, LTX-SECURITY.md §7.6.
Mirrors typescript/ltx/src/amend.ts.

An amendment replaces a locked plan with a re-signed successor:
planVersion + 1 and prevPlanHash = SHA-256(canonical_json(predecessor)).
The canonical-JSON hash is order-insensitive and collision-resistant —
never the legacy v2 polynomial planId hash. Plans are plain dicts.
"""

import hashlib
from typing import Any, Dict, List, Union

from ._security import canonical_json, sign_plan, verify_plan


def plan_hash(plan: Dict[str, Any]) -> str:
    """SHA-256 hex of the RFC 8785 canonical JSON of a plan dict."""
    return hashlib.sha256(canonical_json(plan).encode('utf-8')).hexdigest()


def create_amendment(signed_plan: Dict[str, Any], changes: Dict[str, Any],
                     private_key_b64: str) -> Dict[str, Any]:
    """
    Create a signed amendment of `signed_plan` with `changes` applied.
    The successor is always a v3 plan; the original dict is not mutated.
    Managed fields (v, planVersion, prevPlanHash) cannot be overridden.
    """
    prev = signed_plan['plan']
    prev_version = prev.get('planVersion', 1)
    successor = dict(prev)
    successor.update(changes)
    successor['v'] = 3
    successor['planVersion'] = prev_version + 1
    successor['prevPlanHash'] = plan_hash(prev)
    return sign_plan(successor, private_key_b64)


def verify_amendment_chain(chain: List[Dict[str, Any]],
                           key_cache: Union[Dict[str, Any], Any]) -> Dict[str, Any]:
    """
    Verify an amendment chain: chain[0] is the root plan, each later element a
    successive amendment. Per link: HOST signature against key_cache,
    planVersion increment of exactly 1, prevPlanHash equality with the
    recomputed predecessor hash (LTX-SECURITY.md §7.6).
    """
    if not isinstance(chain, list) or not chain:
        return {'valid': False, 'reason': 'empty_chain'}
    for i, link in enumerate(chain):
        sig = verify_plan(link, key_cache)
        if not sig.get('valid'):
            return {'valid': False, 'reason': f"link_{i}_{sig.get('reason')}"}
    root = chain[0]['plan']
    if 'prevPlanHash' in root:
        return {'valid': False, 'reason': 'root_has_prev_hash'}
    prev_plan = root
    prev_version = root.get('planVersion', 1)
    for i in range(1, len(chain)):
        p = chain[i]['plan']
        if p.get('v') != 3:
            return {'valid': False, 'reason': f'link_{i}_not_v3'}
        if p.get('planVersion', 0) != prev_version + 1:
            return {'valid': False, 'reason': f'link_{i}_version_gap'}
        if p.get('prevPlanHash') != plan_hash(prev_plan):
            return {'valid': False, 'reason': f'link_{i}_prev_hash_mismatch'}
        prev_plan = p
        prev_version = p['planVersion']
    return {'valid': True}


def insert_buffer_via_amendment(signed_plan: Dict[str, Any], after_index: int,
                                q: int, private_key_b64: str) -> Dict[str, Any]:
    """
    §6.2 drift response: amend the plan by inserting a BUFFER segment after
    segment index `after_index` (append with -1). Elapsed segments must not be
    touched — the caller chooses an index at or beyond the current segment.
    """
    prev = signed_plan['plan']
    segments = list(prev.get('segments', []))
    at = len(segments) if after_index < 0 else after_index + 1
    segments.insert(at, {'type': 'BUFFER', 'q': q})
    return create_amendment(signed_plan, {'segments': segments}, private_key_b64)
