"""
_merkle.py — RFC 9162-style Merkle Audit Log
Story 28.5 — LTX Python SDK Merkle tree implementation

Leaf hash:  SHA-256(0x00 || entry_bytes)
Node hash:  SHA-256(0x01 || left || right)
Empty root: 32 zero bytes (64 hex zeros)
"""

from __future__ import annotations

import base64
import hashlib
from datetime import datetime, timezone
from typing import Any, Dict, List

from ._security import canonical_json

# ── Constants ─────────────────────────────────────────────────────────────────

EMPTY_ROOT = bytes(32)


# ── Internal hash helpers ─────────────────────────────────────────────────────


def _leaf_hash(entry_bytes: bytes) -> bytes:
    """SHA-256(0x00 || entry_bytes) — prevents second-preimage attacks."""
    return hashlib.sha256(b'\x00' + entry_bytes).digest()


def _node_hash(left: bytes, right: bytes) -> bytes:
    """SHA-256(0x01 || left || right) — prevents second-preimage attacks."""
    return hashlib.sha256(b'\x01' + left + right).digest()


def _largest_power_of_2_less_than(n: int) -> int:
    """Return the largest power of 2 strictly less than n (n >= 2)."""
    # (n-1).bit_length() - 1 gives floor(log2(n-1)), so 2**(that) is the result.
    return 1 << ((n - 1).bit_length() - 1)


def _root(leaves: List[bytes]) -> bytes:
    """Recursively compute the Merkle root of a slice of leaf hashes."""
    if not leaves:
        return EMPTY_ROOT
    if len(leaves) == 1:
        return leaves[0]
    mid = _largest_power_of_2_less_than(len(leaves))
    return _node_hash(_root(leaves[:mid]), _root(leaves[mid:]))


# ── MerkleLog ────────────────────────────────────────────────────────────────


class MerkleLog:
    """
    RFC 9162-compatible Merkle audit log.

    Maintains an append-only list of leaf hashes and supports
    inclusion proofs, consistency proofs, and signed tree heads.
    """

    def __init__(self) -> None:
        self._leaves: List[bytes] = []

    def append(self, entry: Any) -> Dict[str, Any]:
        """
        Append an entry to the log.

        Parameters
        ----------
        entry : Any
            Any JSON-serialisable object.

        Returns
        -------
        dict
            ``{'tree_size': int, 'root': str}``
        """
        entry_bytes = canonical_json(entry).encode('utf-8')
        self._leaves.append(_leaf_hash(entry_bytes))
        return {'tree_size': len(self._leaves), 'root': _root(self._leaves).hex()}

    def tree_size(self) -> int:
        """Return the current number of log entries."""
        return len(self._leaves)

    def root_hex(self) -> str:
        """Return the current Merkle root as a 64-character hex string."""
        return _root(self._leaves).hex()

    def inclusion_proof(self, leaf_index: int) -> List[Dict[str, str]]:
        """
        Compute an inclusion proof for the leaf at ``leaf_index`` (0-based).

        Parameters
        ----------
        leaf_index : int
            Zero-based index of the leaf.

        Returns
        -------
        list of dict
            Each element has ``{'side': 'left'|'right', 'hash': str}``.

        Raises
        ------
        IndexError
            If ``leaf_index`` is out of range.
        """
        if leaf_index >= len(self._leaves):
            raise IndexError('leaf index out of range')
        proof: List[Dict[str, str]] = []

        def build(lo: int, hi: int, idx: int) -> None:
            if hi - lo == 1:
                return
            mid = _largest_power_of_2_less_than(hi - lo)
            if idx < lo + mid:
                build(lo, lo + mid, idx)
                proof.append({'side': 'right', 'hash': _root(self._leaves[lo + mid:hi]).hex()})
            else:
                build(lo + mid, hi, idx)
                proof.append({'side': 'left', 'hash': _root(self._leaves[lo:lo + mid]).hex()})

        build(0, len(self._leaves), leaf_index)
        return proof

    def verify_inclusion(
        self,
        entry: Any,
        leaf_index: int,
        proof: List[Dict[str, str]],
        known_root: str,
    ) -> bool:
        """
        Verify an inclusion proof for ``entry`` against ``known_root``.

        Parameters
        ----------
        entry : Any
            The original entry (must produce the same canonical JSON).
        leaf_index : int
            Zero-based index (unused in computation, kept for API symmetry).
        proof : list of dict
            Output from :meth:`inclusion_proof`.
        known_root : str
            The trusted Merkle root (hex string).

        Returns
        -------
        bool
            ``True`` if the proof is valid.
        """
        h = _leaf_hash(canonical_json(entry).encode())
        for step in proof:
            sibling = bytes.fromhex(step['hash'])
            if step['side'] == 'right':
                h = _node_hash(h, sibling)
            else:
                h = _node_hash(sibling, h)
        return h.hex() == known_root

    def consistency_proof(self, old_size: int) -> List[str]:
        """
        Compute a consistency proof showing the current tree is an
        extension of a tree that had ``old_size`` entries.

        Parameters
        ----------
        old_size : int
            The size of the smaller (older) tree.

        Returns
        -------
        list of str
            List of hex-encoded hash strings forming the proof.

        Raises
        ------
        ValueError
            If ``old_size`` exceeds the current tree size.
        """
        new_size = len(self._leaves)
        if old_size > new_size:
            raise ValueError('old_size > new_size')
        if old_size == new_size:
            return []
        proof: List[str] = []

        def build(lo: int, hi: int, old_hi: int, first: bool) -> None:
            if lo == hi:
                return
            if lo + 1 == hi:
                if not first:
                    proof.append(self._leaves[lo].hex())
                return
            mid = _largest_power_of_2_less_than(hi - lo)
            if old_hi - lo <= mid:
                proof.append(_root(self._leaves[lo + mid:hi]).hex())
                build(lo, lo + mid, old_hi, first)
            else:
                if not first:
                    proof.append(_root(self._leaves[lo:lo + mid]).hex())
                build(lo + mid, hi, old_hi, False)

        build(0, new_size, old_size, True)
        return proof

    def sign_tree_head(self, private_key_b64: str, node_id: str) -> Dict[str, Any]:
        """
        Sign the current tree head with an Ed25519 private key.

        Parameters
        ----------
        private_key_b64 : str
            Base64url-encoded raw 32-byte Ed25519 private seed (no padding).
        node_id : str
            The signer's node ID (stored in the signed head).

        Returns
        -------
        dict
            Signed tree head with keys:
            ``sha256RootHash``, ``signerNodeId``, ``timestamp``,
            ``treeSize``, ``treeHeadSig``.

        Raises
        ------
        RuntimeError
            If the ``cryptography`` library is not installed.
        """
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        except ImportError:
            raise RuntimeError(
                'cryptography library required for signing; install: pip install cryptography'
            )

        head: Dict[str, Any] = {
            'sha256RootHash': self.root_hex(),
            'signerNodeId': node_id,
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'treeSize': len(self._leaves),
        }
        head_str = canonical_json(head)

        raw_seed = base64.urlsafe_b64decode(private_key_b64 + '==')
        priv_key = Ed25519PrivateKey.from_private_bytes(raw_seed)
        sig = priv_key.sign(head_str.encode('utf-8'))
        sig_b64 = base64.urlsafe_b64encode(sig).rstrip(b'=').decode()

        return {**head, 'treeHeadSig': sig_b64}


# ── verify_tree_head ──────────────────────────────────────────────────────────


def verify_tree_head(signed_head: Dict[str, Any], nik: Dict[str, Any]) -> bool:
    """
    Verify a signed tree head produced by :meth:`MerkleLog.sign_tree_head`.

    Parameters
    ----------
    signed_head : dict
        Output from :meth:`MerkleLog.sign_tree_head`.
    nik : dict
        NIK record of the signer (must have ``publicKey``).

    Returns
    -------
    bool
        ``True`` if the signature is valid, ``False`` otherwise.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        from cryptography.exceptions import InvalidSignature
    except ImportError:
        return False

    sig_b64 = signed_head.get('treeHeadSig', '')
    head = {k: v for k, v in signed_head.items() if k != 'treeHeadSig'}
    head_str = canonical_json(head)

    raw_pub = base64.urlsafe_b64decode(nik['publicKey'] + '==')
    pub_key = Ed25519PublicKey.from_public_bytes(raw_pub)

    sig_bytes = base64.urlsafe_b64decode(sig_b64 + '==')
    try:
        pub_key.verify(sig_bytes, head_str.encode('utf-8'))
        return True
    except InvalidSignature:
        return False
