"""
interplanet_ltx._registers — Question and Action registers
Story 69.4 — LTX-SPECIFICATION.md §9/§10, LTX-SECURITY.md §9.5/§9.6.
Mirrors typescript/ltx/src/registers.ts.

Registers are deterministic reductions over the signed, append-only audit
log: entries ordered by (timestamp, nodeId, seq); object-level conflicts
resolve by highest object version, then lexicographically lowest editor
nodeId (§8.2). Entries are plain dicts using the same camelCase field names
as the wire format.
"""

import base64
from typing import Any, Dict, List, Optional

from ._security import canonical_json

ENTRY_PREFIX = {
    'question': 'QST', 'question_response': 'QST',
    'action': 'ACT', 'action_update': 'ACT',
    'amendment': 'AMD', 'state_transition': 'STA',
    'merge_snapshot': 'MRG', 'decision': 'DEC',
}

_ACTION_STATUSES = ('PROPOSED', 'ACCEPTED', 'REJECTED', 'DONE')

# Ed25519 DER wrapping constants (same idiom as _merkle.py / _security.py)
_PKCS8_HEADER = bytes.fromhex('302e020100300506032b657004220420')
_SPKI_HEADER = bytes.fromhex('302a300506032b6570032100')


def _b64u_decode(s: str) -> bytes:
    pad = 4 - len(s) % 4
    if pad != 4:
        s = s + '=' * pad
    return base64.urlsafe_b64decode(s)


def _sign(data: bytes, private_key_b64: str) -> str:
    from cryptography.hazmat.primitives.serialization import load_der_private_key
    raw_seed = _b64u_decode(private_key_b64)
    priv = load_der_private_key(_PKCS8_HEADER + raw_seed, password=None)
    sig = priv.sign(data)
    return base64.urlsafe_b64encode(sig).rstrip(b'=').decode()


def _verify(data: bytes, sig_b64: str, nik: Dict[str, Any]) -> bool:
    from cryptography.hazmat.primitives.serialization import load_der_public_key
    try:
        raw_pub = _b64u_decode(nik['publicKey'])
        pub = load_der_public_key(_SPKI_HEADER + raw_pub)
        pub.verify(_b64u_decode(sig_b64), data)
        return True
    except Exception:
        return False


def create_register_entry(entry_type: str, content: Dict[str, Any],
                          session_id: str, node_id: str, seq: int,
                          timestamp: str, private_key_b64: str,
                          entry_id: Optional[str] = None) -> Dict[str, Any]:
    """Create a signed register entry (LTX-SECURITY.md §9.5)."""
    eid = entry_id or f"{ENTRY_PREFIX[entry_type]}-{node_id}-{seq}"
    unsigned = {
        'entryId': eid,
        'sessionId': session_id,
        'nodeId': node_id,
        'seq': seq,
        'type': entry_type,
        'content': content,
        'timestamp': timestamp,
    }
    sig = _sign(canonical_json(unsigned).encode('utf-8'), private_key_b64)
    entry = dict(unsigned)
    entry['sig'] = sig
    return entry


def verify_register_entry(entry: Dict[str, Any],
                          key_cache: Dict[str, Any]) -> Dict[str, Any]:
    """Verify entry signature against key_cache[entry['nodeId']] -> NIK."""
    if not entry or not entry.get('sig'):
        return {'valid': False, 'reason': 'missing_sig'}
    nik = key_cache.get(entry.get('nodeId'))
    if not nik:
        return {'valid': False, 'reason': 'key_not_in_cache'}
    unsigned = {k: v for k, v in entry.items() if k != 'sig'}
    ok = _verify(canonical_json(unsigned).encode('utf-8'), entry['sig'], nik)
    return {'valid': True} if ok else {'valid': False, 'reason': 'signature_invalid'}


def order_entries(entries: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """De-duplicate by (nodeId, seq); sort by (timestamp, nodeId, seq) (§8.2)."""
    seen: Dict[str, Dict[str, Any]] = {}
    for e in entries:
        key = f"{e.get('nodeId')} {e.get('seq')}"
        if key not in seen:
            seen[key] = e
    return sorted(seen.values(),
                  key=lambda e: (e.get('timestamp', ''), e.get('nodeId', ''), e.get('seq', 0)))


def _wins(inc_version: int, inc_editor: str, cur_version: int, cur_editor: str) -> bool:
    if inc_version != cur_version:
        return inc_version > cur_version
    return inc_editor < cur_editor


def reduce_questions(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Reduce question register state (LTX-SPECIFICATION.md §9.4). Pure."""
    by_id: Dict[str, Dict[str, Any]] = {}
    winners: Dict[str, Dict[str, Any]] = {}
    superseded: List[str] = []

    for e in order_entries(entries):
        c = e.get('content', {})
        if e.get('type') == 'question':
            qid = e['entryId']
            if qid in by_id:
                superseded.append(e['entryId'])
                continue
            winners[qid] = {'version': 1, 'editor': e['nodeId'], 'entryId': e['entryId']}
            q: Dict[str, Any] = {'qid': qid, 'text': str(c.get('text', '')),
                                 'submitter': e['nodeId']}
            if 'urgency' in c:
                q['urgency'] = str(c['urgency'])
            if 'intendedWindow' in c:
                q['intendedWindow'] = str(c['intendedWindow'])
            q['status'] = 'OPEN'
            q['version'] = 1
            by_id[qid] = q
        elif e.get('type') == 'question_response':
            qid = str(c.get('qid', ''))
            q = by_id.get(qid)
            if q is None:
                superseded.append(e['entryId'])
                continue
            version = int(c.get('version', q['version'] + 1))
            current = winners.get(qid)
            if current and not _wins(version, e['nodeId'], current['version'], current['editor']):
                superseded.append(e['entryId'])
                continue
            if current and current['entryId'] != q['qid']:
                superseded.append(current['entryId'])
            winners[qid] = {'version': version, 'editor': e['nodeId'], 'entryId': e['entryId']}
            q = dict(q)
            q['status'] = 'WITHDRAWN' if c.get('status') == 'WITHDRAWN' else 'ANSWERED'
            if 'response' in c:
                q['response'] = str(c['response'])
            q['responder'] = e['nodeId']
            q['version'] = version
            by_id[qid] = q
    return {'byId': by_id, 'superseded': superseded}


def reduce_actions(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Reduce action register state (LTX-SPECIFICATION.md §10.2). Pure."""
    by_id: Dict[str, Dict[str, Any]] = {}
    winners: Dict[str, Dict[str, Any]] = {}
    superseded: List[str] = []

    for e in order_entries(entries):
        c = e.get('content', {})
        if e.get('type') == 'action':
            aid = e['entryId']
            if aid in by_id:
                superseded.append(e['entryId'])
                continue
            winners[aid] = {'version': 1, 'editor': e['nodeId'], 'entryId': e['entryId']}
            a: Dict[str, Any] = {'aid': aid, 'description': str(c.get('description', ''))}
            if 'owner' in c:
                a['owner'] = str(c['owner'])
            if 'dueTimeUTC' in c:
                a['dueTimeUTC'] = str(c['dueTimeUTC'])
            if 'originWindow' in c:
                a['originWindow'] = str(c['originWindow'])
            a['status'] = 'PROPOSED'
            a['version'] = 1
            by_id[aid] = a
        elif e.get('type') == 'action_update':
            aid = str(c.get('aid', ''))
            a = by_id.get(aid)
            if a is None:
                superseded.append(e['entryId'])
                continue
            version = int(c.get('version', a['version'] + 1))
            current = winners.get(aid)
            if current and not _wins(version, e['nodeId'], current['version'], current['editor']):
                superseded.append(e['entryId'])
                continue
            if current and current['entryId'] != a['aid']:
                superseded.append(current['entryId'])
            winners[aid] = {'version': version, 'editor': e['nodeId'], 'entryId': e['entryId']}
            a = dict(a)
            a['status'] = c['status'] if c.get('status') in _ACTION_STATUSES else a['status']
            if 'description' in c:
                a['description'] = str(c['description'])
            if 'owner' in c:
                a['owner'] = str(c['owner'])
            if 'dueTimeUTC' in c:
                a['dueTimeUTC'] = str(c['dueTimeUTC'])
            a['version'] = version
            by_id[aid] = a
    return {'byId': by_id, 'superseded': superseded}


def emit_question_seeds(seeds: List[Dict[str, Any]], session_id: str,
                        node_id: str, start_seq: int, timestamp: str,
                        private_key_b64: str) -> List[Dict[str, Any]]:
    """Re-emit v3 plan question seeds as signed log entries at lock (§9.2)."""
    out = []
    seq = start_seq
    for seed in seeds:
        out.append(create_register_entry('question', seed, session_id,
                                         node_id, seq, timestamp, private_key_b64))
        seq += 1
    return out
