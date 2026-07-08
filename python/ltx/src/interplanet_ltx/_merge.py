"""
interplanet_ltx._merge — Deterministic merge and partition recovery
Story 69.4 — LTX-SPECIFICATION.md §8, LTX-SECURITY.md §9.4.
Mirrors typescript/ltx/src/merge.ts.
"""

from typing import Any, Dict, List

from ._merkle import MerkleLog, verify_tree_head
from ._registers import (
    create_register_entry,
    order_entries,
    reduce_actions,
    reduce_questions,
    verify_register_entry,
)
from ._security import canonical_json


def merge_logs(entries_a: List[Dict[str, Any]], entries_b: List[Dict[str, Any]],
               key_cache: Dict[str, Any]) -> Dict[str, Any]:
    """Deterministic merge (§8.2): verify, union de-dup by (nodeId, seq), order."""
    rejected = []
    verified = []
    for entry in list(entries_a) + list(entries_b):
        v = verify_register_entry(entry, key_cache)
        if v['valid']:
            verified.append(entry)
        else:
            rejected.append({'entry': entry, 'reason': v.get('reason', 'invalid')})
    return {'entries': order_entries(verified), 'rejected': rejected}


def entries_root(entries: List[Dict[str, Any]]) -> str:
    """Merkle root over an ordered entry list (leaves in log order)."""
    log = MerkleLog()
    for e in entries:
        log.append(e)
    return log.root_hex()


def run_merge_segment(local_entries: List[Dict[str, Any]],
                      remote_entries: List[Dict[str, Any]],
                      key_cache: Dict[str, Any],
                      session_id: str, node_id: str, seq: int,
                      timestamp: str, private_key_b64: str) -> Dict[str, Any]:
    """MERGE segment (§8.4): merge + HOST-signed merge_snapshot entry."""
    merged = merge_logs(local_entries, remote_entries, key_cache)
    questions = reduce_questions(merged['entries'])
    actions = reduce_actions(merged['entries'])
    snapshot = create_register_entry('merge_snapshot', {
        'mergedRoot': entries_root(merged['entries']),
        'entryCount': len(merged['entries']),
        'rejectedCount': len(merged['rejected']),
        'questionRegister': questions['byId'],
        'actionRegister': actions['byId'],
        'superseded': questions['superseded'] + actions['superseded'],
    }, session_id, node_id, seq, timestamp, private_key_b64)
    return {'merged': merged, 'snapshot': snapshot}


def recover_partition(local_entries: List[Dict[str, Any]],
                      remote_entries: List[Dict[str, Any]],
                      remote_head: Dict[str, Any], remote_nik: Dict[str, Any],
                      key_cache: Dict[str, Any]) -> Dict[str, Any]:
    """
    Partition recovery (§8.3 / LTX-SECURITY §9.4): verify remote tree head,
    accept verified prefix extension, else deterministic merge, else flag
    divergence.
    """
    if not verify_tree_head(remote_head, remote_nik):
        return {'action': 'divergent', 'reason': 'tree_head_signature_invalid'}
    if (remote_head.get('treeSize') != len(remote_entries)
            or entries_root(remote_entries) != remote_head.get('sha256RootHash')):
        return {'action': 'divergent', 'reason': 'remote_entries_do_not_match_head'}
    if len(local_entries) <= len(remote_entries):
        is_prefix = all(
            canonical_json(e) == canonical_json(remote_entries[i])
            for i, e in enumerate(local_entries)
        )
        if is_prefix:
            return {'action': 'accept_extension', 'entries': list(remote_entries)}
    merged = merge_logs(local_entries, remote_entries, key_cache)
    return {'action': 'merged', 'entries': merged['entries'],
            'rejected': merged['rejected']}
