"""Conference agenda builder — Story 71.2 (LTX-SPECIFICATION.md §14).

A conference agenda is an ordered list of attributed TX Blocks.  Across N
cycles with N presenting nodes, fair rotation gives each node the opening
Block exactly once (§14.4).
"""

from typing import Dict, List, Optional

from ._core import _as_plan_dict
from ._models import LtxNode


def _node_dict(node) -> dict:
    if isinstance(node, LtxNode):
        return {'id': node.id, 'role': node.role}
    return node


def build_conference_agenda(
    nodes,
    cycles: int = 1,
    block_q: int = 3,
    confirm_q: int = 2,
    merge_q: int = 2,
    buffer_q: int = 1,
    caucus_q: int = 0,
    fairness: str = 'rotate',
    labels: Optional[Dict[str, str]] = None,
) -> List[dict]:
    """Build a conference segment template over the presenting nodes (§14.2).

    Presenting nodes = every node that is not an OBSERVER.  Rotation invariant
    ('rotate', default): cycle c opens with presenting-node index c mod N, so
    across N cycles each node opens exactly once.  'fixed' keeps plan order.

    ``nodes`` may be a list of node dicts or LtxNode dataclasses.  Returns a
    list of segment dicts ``{type, q, speaker?, label?}``.
    """
    presenting = [_node_dict(n) for n in nodes]
    presenting = [n for n in presenting if n.get('role') != 'OBSERVER']
    if not presenting:
        raise ValueError('build_conference_agenda: no presenting nodes')
    labels = labels or {}

    segments: List[dict] = []
    if confirm_q > 0:
        segments.append({'type': 'PLAN_CONFIRM', 'q': confirm_q})

    n = len(presenting)
    for c in range(cycles):
        if c > 0 and caucus_q > 0:
            segments.append({'type': 'CAUCUS', 'q': caucus_q})
        offset = c % n if fairness == 'rotate' else 0
        for i in range(n):
            node = presenting[(offset + i) % n]
            seg = {'type': 'TX', 'q': block_q, 'speaker': node['id']}
            if labels.get(node['id']):
                seg['label'] = labels[node['id']]
            segments.append(seg)

    if merge_q > 0:
        segments.append({'type': 'MERGE', 'q': merge_q})
    if buffer_q > 0:
        segments.append({'type': 'BUFFER', 'q': buffer_q})
    return segments


def prime_time_report(plan) -> List[dict]:
    """Score per-node slot desirability over a plan's attributed segments (§14.4).

    Desirability of attributed slot i (of k) = (k - i) / k, so the opening
    slot scores 1 and the final slot 1/k.  An "opening" is the first slot of
    each cycle: attributed index ≡ 0 (mod N).  Organisers use the report to
    spot imbalances when deviating from fair rotation.

    Accepts an LtxPlan dataclass or a plan dict (v1/v2/v3).  Returns a list of
    dicts ``{nodeId, slots, openings, score}`` sorted by score descending,
    then nodeId ascending.
    """
    c = _as_plan_dict(plan)
    attributed = [s for s in c.get('segments', []) if s.get('speaker')]
    k = len(attributed)
    by_node: Dict[str, dict] = {}
    for i, seg in enumerate(attributed):
        rec = by_node.setdefault(seg['speaker'], {'slots': [], 'score_sum': 0.0})
        rec['slots'].append(i)
        rec['score_sum'] += (k - i) / k
    n = max(1, len(by_node))
    entries = [
        {
            'nodeId': node_id,
            'slots': rec['slots'],
            'openings': sum(1 for s in rec['slots'] if s % n == 0),
            'score': rec['score_sum'] / len(rec['slots']) if rec['slots'] else 0.0,
        }
        for node_id, rec in by_node.items()
    ]
    entries.sort(key=lambda e: (-e['score'], e['nodeId']))
    return entries
