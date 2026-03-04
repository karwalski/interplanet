"""REST API client for the LTX server — Python port of ltx-sdk.js REST methods.

Uses only stdlib urllib (no external dependencies).
"""

import json
import urllib.request
from typing import Any, Dict, Optional

from ._models import LtxPlan
from ._core import _plan_as_dict, DEFAULT_API_BASE


def _post(url: str, payload: dict) -> dict:
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        url,
        data=data,
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode('utf-8'))


def _get(url: str) -> dict:
    with urllib.request.urlopen(url) as resp:
        return json.loads(resp.read().decode('utf-8'))


def store_session(plan: LtxPlan, api_base: Optional[str] = None) -> Dict[str, Any]:
    """Store a session plan on the LTX server.

    Returns: {'plan_id': str, 'segments': list, 'total_min': int, 'stored': bool}
    """
    url = (api_base or DEFAULT_API_BASE) + '?action=session'
    return _post(url, _plan_as_dict(plan))


def get_session(plan_id: str, api_base: Optional[str] = None) -> Dict[str, Any]:
    """Retrieve a stored session plan by plan ID.

    Returns: {'plan_id': str, 'plan': dict, 'created_at': str, 'views': int}
    """
    base = api_base or DEFAULT_API_BASE
    from urllib.parse import quote
    url = f'{base}?action=session&plan_id={quote(plan_id)}'
    return _get(url)


def download_ics(
    plan_id: str,
    start: str,
    duration_min: int,
    api_base: Optional[str] = None,
) -> str:
    """Download ICS content for a stored plan from the server.  Returns ICS text."""
    base = api_base or DEFAULT_API_BASE
    from urllib.parse import quote
    url = f'{base}?action=ics&plan_id={quote(plan_id)}'
    data = json.dumps({'start': start, 'duration_min': duration_min}).encode('utf-8')
    req = urllib.request.Request(
        url,
        data=data,
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    with urllib.request.urlopen(req) as resp:
        return resp.read().decode('utf-8')


def submit_feedback(payload: dict, api_base: Optional[str] = None) -> Dict[str, Any]:
    """Submit session feedback.  Returns: {'ok': bool, 'feedback_id': int}"""
    url = (api_base or DEFAULT_API_BASE) + '?action=feedback'
    return _post(url, payload)
