"""
_conjunction.py — Conjunction-safe Security Checkpoints
Story 28.9 — CONJUNCTION_CHECKPOINT and POST_CONJUNCTION_CLEAR bundles

Provides signed checkpoint bundles for capturing Merkle log state and
sequence numbers at the start of a conjunction (communication blackout)
period, plus a post-conjunction queue and clear mechanism.

Uses the `cryptography` package for Ed25519 signing/verification.
"""

from __future__ import annotations

import base64
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional

from ._security import canonical_json, is_nik_expired


# ── Private helpers ────────────────────────────────────────────────────────────


def _sign_bytes(msg: bytes, private_key_b64: str) -> str:
    """Sign msg with an Ed25519 private key seed; return base64url signature."""
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    except ImportError:
        raise ImportError(
            'Conjunction checkpoint functions require the `cryptography` package. '
            'Install it: pip install cryptography'
        )
    raw_seed = base64.urlsafe_b64decode(private_key_b64 + '==')
    priv_key = Ed25519PrivateKey.from_private_bytes(raw_seed)
    sig_bytes = priv_key.sign(msg)
    return base64.urlsafe_b64encode(sig_bytes).rstrip(b'=').decode()


def _verify_bytes(msg: bytes, sig_b64: str, public_key_b64: str) -> bool:
    """Verify an Ed25519 signature; returns True if valid, False otherwise."""
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        from cryptography.exceptions import InvalidSignature
    except ImportError:
        raise ImportError(
            'Conjunction checkpoint verification requires the `cryptography` package. '
            'Install it: pip install cryptography'
        )
    raw_pub = base64.urlsafe_b64decode(public_key_b64 + '==')
    pub_key = Ed25519PublicKey.from_public_bytes(raw_pub)
    sig_bytes = base64.urlsafe_b64decode(sig_b64 + '==')
    try:
        pub_key.verify(sig_bytes, msg)
        return True
    except InvalidSignature:
        return False


def _now_iso() -> str:
    now = datetime.now(timezone.utc)
    return now.strftime('%Y-%m-%dT%H:%M:%S.') + f'{now.microsecond // 1000:03d}Z'


# ── create_conjunction_checkpoint ─────────────────────────────────────────────


def create_conjunction_checkpoint(
    plan_id: str,
    signer_node_id: str,
    conjunction_info: Dict[str, str],
    merkle_root: str,
    tree_size: int,
    last_seq_per_node: Dict[str, int],
    private_key_b64: str,
) -> Dict[str, Any]:
    """
    Create a signed CONJUNCTION_CHECKPOINT bundle.

    Captures Merkle root, tree size, and last sequence numbers at the start
    of a communication blackout (conjunction) period.

    Parameters
    ----------
    plan_id : str
        Plan identifier.
    signer_node_id : str
        Node ID of the signer (from nik['nodeId']).
    conjunction_info : dict
        {'conjunctionStart': '<ISO-8601>', 'conjunctionEnd': '<ISO-8601>'}.
    merkle_root : str
        Hex string from MerkleLog.root_hex().
    tree_size : int
        Integer from MerkleLog.tree_size().
    last_seq_per_node : dict
        Plain dict { node_id: last_seen_seq, ... }.
    private_key_b64 : str
        Base64url raw 32-byte Ed25519 private seed.

    Returns
    -------
    dict
        Complete CONJUNCTION_CHECKPOINT bundle.
    """
    checkpoint_without_sig = {
        'type': 'CONJUNCTION_CHECKPOINT',
        'planId': plan_id,
        'checkpointSignerNodeId': signer_node_id,
        'checkpointTime': _now_iso(),
        'conjunctionStart': conjunction_info['conjunctionStart'],
        'conjunctionEnd': conjunction_info['conjunctionEnd'],
        'merkleRoot': merkle_root,
        'treeSize': tree_size,
        'lastSeqPerNode': last_seq_per_node,
    }

    msg = canonical_json(checkpoint_without_sig).encode()
    sig = _sign_bytes(msg, private_key_b64)

    return {**checkpoint_without_sig, 'checkpointSig': sig}


# ── verify_conjunction_checkpoint ─────────────────────────────────────────────


def verify_conjunction_checkpoint(
    checkpoint: Dict[str, Any],
    key_cache: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Verify a CONJUNCTION_CHECKPOINT bundle.

    Parameters
    ----------
    checkpoint : dict
        CONJUNCTION_CHECKPOINT bundle (from create_conjunction_checkpoint).
    key_cache : dict
        Plain dict mapping nodeId → NIK record.

    Returns
    -------
    dict
        ``{'valid': bool, 'reason': str | None}``
    """
    checkpoint_sig = checkpoint.get('checkpointSig')
    if not checkpoint_sig:
        return {'valid': False, 'reason': 'missing_signature'}

    # Build the signed payload (checkpoint without the sig field)
    checkpoint_without_sig = {k: v for k, v in checkpoint.items() if k != 'checkpointSig'}
    msg = canonical_json(checkpoint_without_sig).encode()

    # Identify candidates
    signer_node_id = checkpoint.get('checkpointSignerNodeId')
    candidates: List[Dict[str, Any]] = []

    if signer_node_id:
        signer_nik = key_cache.get(signer_node_id)
        if signer_nik:
            candidates = [signer_nik]
        else:
            return {'valid': False, 'reason': 'key_not_in_cache'}
    else:
        candidates = list(key_cache.values())

    if not candidates:
        return {'valid': False, 'reason': 'key_not_in_cache'}

    for nik in candidates:
        if is_nik_expired(nik):
            continue
        try:
            if _verify_bytes(msg, checkpoint_sig, nik['publicKey']):
                return {'valid': True, 'reason': None}
        except Exception:
            pass

    return {'valid': False, 'reason': 'signature_invalid'}


# ── PostConjunctionQueue ───────────────────────────────────────────────────────


class PostConjunctionQueue:
    """
    Post-conjunction queue for holding bundles during a blackout period.

    Bundles queued during the conjunction are processed via drain() after
    communication resumes.
    """

    def __init__(self) -> None:
        self._queue: List[Any] = []

    def enqueue(self, bundle: Any) -> int:
        """
        Add a bundle to the queue.

        Returns
        -------
        int
            New queue size.
        """
        self._queue.append(bundle)
        return len(self._queue)

    def size(self) -> int:
        """Return current queue size."""
        return len(self._queue)

    def drain(
        self,
        verify_fn: Callable[[Any], Dict[str, Any]],
    ) -> Dict[str, Any]:
        """
        Process all queued bundles through verify_fn.

        Parameters
        ----------
        verify_fn : callable
            Function that accepts a bundle and returns ``{'valid': bool, ...}``.

        Returns
        -------
        dict
            ``{'cleared': int, 'rejected': int, 'rejected_bundles': list}``
        """
        cleared = 0
        rejected = 0
        rejected_bundles: List[Any] = []
        items = list(self._queue)
        self._queue.clear()
        for bundle in items:
            result = verify_fn(bundle)
            if result and result.get('valid'):
                cleared += 1
            else:
                rejected += 1
                rejected_bundles.append(bundle)
        return {'cleared': cleared, 'rejected': rejected, 'rejected_bundles': rejected_bundles}

    def get_queue(self) -> List[Any]:
        """Return a copy of the current queue."""
        return list(self._queue)


def create_post_conjunction_queue() -> PostConjunctionQueue:
    """
    Factory function to create a new PostConjunctionQueue.

    Returns
    -------
    PostConjunctionQueue
    """
    return PostConjunctionQueue()


# ── create_post_conjunction_clear ─────────────────────────────────────────────


def create_post_conjunction_clear(
    plan_id: str,
    queue_processed: int,
    private_key_b64: str,
) -> Dict[str, Any]:
    """
    Create a signed POST_CONJUNCTION_CLEAR bundle.

    Signals that the conjunction period has ended and queued bundles have
    been processed.

    Parameters
    ----------
    plan_id : str
        Plan identifier.
    queue_processed : int
        Number of queued bundles that were processed.
    private_key_b64 : str
        Base64url raw 32-byte Ed25519 private seed.

    Returns
    -------
    dict
        Complete POST_CONJUNCTION_CLEAR bundle.
    """
    clear_without_sig = {
        'type': 'POST_CONJUNCTION_CLEAR',
        'planId': plan_id,
        'clearedAt': _now_iso(),
        'queueProcessed': queue_processed,
    }

    msg = canonical_json(clear_without_sig).encode()
    sig = _sign_bytes(msg, private_key_b64)

    return {**clear_without_sig, 'clearSig': sig}


# ── verify_post_conjunction_clear ─────────────────────────────────────────────


def verify_post_conjunction_clear(
    clear_bundle: Dict[str, Any],
    key_cache: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Verify a POST_CONJUNCTION_CLEAR bundle.

    Since the clear bundle has no signer ID field, tries each NIK in the cache.

    Parameters
    ----------
    clear_bundle : dict
        POST_CONJUNCTION_CLEAR bundle (from create_post_conjunction_clear).
    key_cache : dict
        Plain dict mapping nodeId → NIK record.

    Returns
    -------
    dict
        ``{'valid': bool, 'signer_node_id': str | None, 'reason': str | None}``
    """
    clear_sig = clear_bundle.get('clearSig')
    if not clear_sig:
        return {'valid': False, 'signer_node_id': None, 'reason': 'missing_signature'}

    clear_without_sig = {k: v for k, v in clear_bundle.items() if k != 'clearSig'}
    msg = canonical_json(clear_without_sig).encode()

    niks = list(key_cache.values())
    if not niks:
        return {'valid': False, 'signer_node_id': None, 'reason': 'key_not_in_cache'}

    for nik in niks:
        if is_nik_expired(nik):
            continue
        try:
            if _verify_bytes(msg, clear_sig, nik['publicKey']):
                return {'valid': True, 'signer_node_id': nik['nodeId'], 'reason': None}
        except Exception:
            pass

    return {'valid': False, 'signer_node_id': None, 'reason': 'signature_invalid'}
