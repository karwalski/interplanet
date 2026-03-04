"""Core LTX plan operations — Python port of ltx-sdk.js."""

import json
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional

from ._models import LtxNode, LtxPlan, LtxSegment, LtxSegmentSpec, LtxNodeUrl

# ── Constants ──────────────────────────────────────────────────────────────────

VERSION = '1.0.0'

SEG_TYPES = ['PLAN_CONFIRM', 'TX', 'RX', 'CAUCUS', 'BUFFER', 'MERGE']

DEFAULT_QUANTUM = 3  # minutes per quantum

DEFAULT_SEGMENTS: List[Dict] = [
    {'type': 'PLAN_CONFIRM', 'q': 2},
    {'type': 'TX',           'q': 2},
    {'type': 'RX',           'q': 2},
    {'type': 'CAUCUS',       'q': 2},
    {'type': 'TX',           'q': 2},
    {'type': 'RX',           'q': 2},
    {'type': 'BUFFER',       'q': 1},
]

DEFAULT_API_BASE = 'https://interplanet.live/api/ltx.php'

# ── Internal helpers ───────────────────────────────────────────────────────────

def _pad(n: int) -> str:
    return str(n).zfill(2)


def _now_rounded() -> datetime:
    """Return current UTC time rounded to the minute, plus 5 minutes."""
    now = datetime.now(timezone.utc).replace(second=0, microsecond=0)
    return now + timedelta(minutes=5)


def _to_iso(dt: datetime) -> str:
    return dt.strftime('%Y-%m-%dT%H:%M:%SZ')


def _plan_as_dict(plan: LtxPlan) -> dict:
    return {
        'v': plan.v,
        'title': plan.title,
        'start': plan.start,
        'quantum': plan.quantum,
        'mode': plan.mode,
        'nodes': [
            {'id': n.id, 'name': n.name, 'role': n.role,
             'delay': n.delay, 'location': n.location}
            for n in plan.nodes
        ],
        'segments': [{'type': s.type, 'q': s.q} for s in plan.segments],
    }


def _imul32(a: int, b: int) -> int:
    """32-bit integer multiplication (matches JS Math.imul)."""
    return (a * b) & 0xFFFFFFFF


def _djb2_hash(s: str) -> int:
    """djb2-style hash matching ltx-sdk.js makePlanId hash."""
    h = 0
    for ch in s:
        h = (_imul32(31, h) + ord(ch)) & 0xFFFFFFFF
    return h

# ── Config management ──────────────────────────────────────────────────────────

def upgrade_config(cfg: dict) -> dict:
    """Upgrade a v1 config dict (txName/rxName/delay) to v2 schema (nodes[]).
    v2 configs are returned unchanged."""
    if cfg.get('v', 1) >= 2 and cfg.get('nodes'):
        return cfg
    rx = (cfg.get('rxName') or '').lower()
    remote_loc = 'mars' if 'mars' in rx else ('moon' if 'moon' in rx else 'earth')
    return {
        **cfg,
        'v': 2,
        'nodes': [
            {'id': 'N0', 'name': cfg.get('txName', 'Earth HQ'),
             'role': 'HOST', 'delay': 0, 'location': 'earth'},
            {'id': 'N1', 'name': cfg.get('rxName', 'Mars Hab-01'),
             'role': 'PARTICIPANT', 'delay': cfg.get('delay', 0),
             'location': remote_loc},
        ],
    }


def create_plan(
    title: str = 'LTX Session',
    start: Optional[str] = None,
    quantum: int = DEFAULT_QUANTUM,
    mode: str = 'LTX',
    nodes: Optional[List[dict]] = None,
    host_name: str = 'Earth HQ',
    host_location: str = 'earth',
    remote_name: str = 'Mars Hab-01',
    remote_location: str = 'mars',
    delay: float = 0.0,
    segments: Optional[List[dict]] = None,
) -> LtxPlan:
    """Create a new LTX session plan.

    Returns an LtxPlan dataclass.  All numeric delays are in seconds.
    """
    if start is None:
        start = _to_iso(_now_rounded())

    if nodes is None:
        nodes = [
            {'id': 'N0', 'name': host_name,   'role': 'HOST',        'delay': 0.0,  'location': host_location},
            {'id': 'N1', 'name': remote_name, 'role': 'PARTICIPANT', 'delay': delay, 'location': remote_location},
        ]

    seg_dicts = segments if segments is not None else [dict(s) for s in DEFAULT_SEGMENTS]

    return LtxPlan(
        v=2,
        title=title,
        start=start,
        quantum=quantum,
        mode=mode,
        segments=[LtxSegmentSpec(type=s['type'], q=s['q']) for s in seg_dicts],
        nodes=[LtxNode(id=n['id'], name=n['name'], role=n['role'],
                       delay=n.get('delay', 0.0), location=n.get('location', 'earth'))
               for n in nodes],
    )

# ── Segment computation ────────────────────────────────────────────────────────

def compute_segments(plan: LtxPlan) -> List[LtxSegment]:
    """Compute the timed segment list for a plan."""
    q_sec = plan.quantum * 60
    t = datetime.fromisoformat(plan.start.replace('Z', '+00:00'))
    result = []
    for s in plan.segments:
        dur_sec = s.q * q_sec
        end = t + timedelta(seconds=dur_sec)
        result.append(LtxSegment(
            type=s.type, q=s.q,
            start=_to_iso(t), end=_to_iso(end),
            dur_min=s.q * plan.quantum,
        ))
        t = end
    return result


def total_min(plan: LtxPlan) -> int:
    """Total session duration in minutes."""
    return sum(s.q * plan.quantum for s in plan.segments)

# ── Plan ID ────────────────────────────────────────────────────────────────────

def make_plan_id(plan: LtxPlan) -> str:
    """Compute the deterministic plan ID.  Matches ltx-sdk.js and ltx.html."""
    c = _plan_as_dict(plan)
    date = plan.start[:10].replace('-', '')
    nodes = plan.nodes
    host_str = nodes[0].name.replace(' ', '').upper()[:8] if nodes else 'HOST'
    if len(nodes) > 1:
        node_str = '-'.join(n.name.replace(' ', '').upper()[:4]
                            for n in nodes[1:])[:16]
    else:
        node_str = 'RX'
    raw = json.dumps(c, separators=(',', ':'))
    h = _djb2_hash(raw)
    return f'LTX-{date}-{host_str}-{node_str}-v2-{h:08x}'

# ── URL hash encoding ──────────────────────────────────────────────────────────

def encode_hash(plan: LtxPlan) -> str:
    """Encode a plan to a URL hash fragment (#l=…)."""
    from ._encoding import b64enc
    return '#l=' + b64enc(json.dumps(_plan_as_dict(plan), separators=(',', ':')))


def decode_hash(fragment: str) -> Optional[LtxPlan]:
    """Decode a plan from a URL hash fragment.  Returns None if invalid."""
    from ._encoding import b64dec
    token = fragment.lstrip('#')
    if token.startswith('l='):
        token = token[2:]
    raw = b64dec(token)
    if not raw:
        return None
    try:
        d = json.loads(raw)
    except (ValueError, TypeError):
        return None
    try:
        return LtxPlan(
            v=d.get('v', 2),
            title=d.get('title', ''),
            start=d.get('start', ''),
            quantum=d.get('quantum', DEFAULT_QUANTUM),
            mode=d.get('mode', 'LTX'),
            segments=[LtxSegmentSpec(**s) for s in d.get('segments', [])],
            nodes=[LtxNode(id=n['id'], name=n['name'], role=n['role'],
                           delay=n.get('delay', 0.0), location=n.get('location', 'earth'))
                   for n in d.get('nodes', [])],
        )
    except (KeyError, TypeError):
        return None

# ── Node URLs ──────────────────────────────────────────────────────────────────

def build_node_urls(plan: LtxPlan, base_url: str = '') -> List[LtxNodeUrl]:
    """Build perspective URLs for all nodes in a plan."""
    from ._encoding import b64enc
    c = _plan_as_dict(plan)
    token = '#l=' + b64enc(json.dumps(c, separators=(',', ':')))
    clean_base = base_url.split('#')[0].split('?')[0]
    return [
        LtxNodeUrl(
            node_id=n.id,
            name=n.name,
            role=n.role,
            url=f'{clean_base}?node={n.id}{token}',
        )
        for n in plan.nodes
    ]

# ── Integration helper ─────────────────────────────────────────────────────────

def delay_from_planets(planet_a: str, planet_b: str, utc_ms: int) -> float:
    """Return the one-way light travel time in seconds between two planets.

    Requires the *interplanet_time* package (story 18.1) to be installed.
    planet_a / planet_b are case-insensitive planet name strings.

    Raises ImportError if interplanet_time is not available.
    """
    import interplanet_time as ipt
    a = ipt.Planet[planet_a.upper()]
    b = ipt.Planet[planet_b.upper()]
    return ipt.light_travel_seconds(a, b, utc_ms)
