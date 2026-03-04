"""
_security.py — Cryptographic Identity and Canonical JSON
Story 28.1 — LTX Python SDK security primitives

canonical_json: RFC 8785 / JCS compliant serialisation.
NIK: Node Identity Key — Ed25519 key pair, nodeId derivation, expiry checks.

Uses the Python standard library only (hashlib, secrets) plus the
`cryptography` package for Ed25519 key generation. If `cryptography` is not
available, falls back to `PyNaCl` (nacl). A clear ImportError is raised if
neither is installed.
"""

from __future__ import annotations

import base64
import hashlib
import json
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional


# ── Canonical JSON (RFC 8785 / JCS) ──────────────────────────────────────────


def canonical_json(obj: Any) -> str:
    """
    Produce RFC 8785 / JCS canonical JSON.

    - Object keys are sorted lexicographically (Unicode code-point order).
    - Array element order is preserved.
    - No optional whitespace.

    Returns a str (UTF-8 content — encode to bytes if a bytes payload is needed).
    """
    if obj is None:
        return 'null'
    if isinstance(obj, bool):
        return 'true' if obj else 'false'
    if isinstance(obj, (int, float)):
        return json.dumps(obj)
    if isinstance(obj, str):
        return json.dumps(obj)
    if isinstance(obj, list):
        return '[' + ','.join(canonical_json(v) for v in obj) + ']'
    if isinstance(obj, dict):
        keys = sorted(obj.keys())
        return '{' + ','.join(json.dumps(k) + ':' + canonical_json(obj[k]) for k in keys) + '}'
    raise TypeError(f'canonical_json: unsupported type {type(obj).__name__!r}')


# ── Ed25519 key generation helpers ────────────────────────────────────────────


def _generate_ed25519() -> tuple[bytes, bytes]:
    """
    Generate an Ed25519 key pair.
    Returns (raw_private_seed_32_bytes, raw_public_key_32_bytes).

    Tries `cryptography` first, then `PyNaCl`, raises ImportError if neither.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        private_key = Ed25519PrivateKey.generate()
        # Raw private seed (32 bytes)
        from cryptography.hazmat.primitives.serialization import (
            Encoding, NoEncryption, PrivateFormat, PublicFormat,
        )
        raw_priv = private_key.private_bytes(
            encoding=Encoding.Raw,
            format=PrivateFormat.Raw,
            encryption_algorithm=NoEncryption(),
        )
        raw_pub = private_key.public_key().public_bytes(
            encoding=Encoding.Raw,
            format=PublicFormat.Raw,
        )
        return raw_priv, raw_pub
    except ImportError:
        pass

    try:
        import nacl.signing  # type: ignore[import]
        signing_key = nacl.signing.SigningKey.generate()
        raw_priv = bytes(signing_key)
        raw_pub  = bytes(signing_key.verify_key)
        return raw_priv, raw_pub
    except ImportError:
        pass

    raise ImportError(
        'NIK key generation requires either the `cryptography` or `PyNaCl` package. '
        'Install one: pip install cryptography'
    )


# ── NIK functions ─────────────────────────────────────────────────────────────


def generate_nik(valid_days: int = 365, node_label: str = '') -> Dict[str, Any]:
    """
    Generate a new Node Identity Key (NIK) record.

    Parameters
    ----------
    valid_days : int
        Validity period in days (default 365).
    node_label : str
        Optional human-readable label stored in the NIK record.

    Returns
    -------
    dict with keys:
        ``nik``            — NIK record dict
        ``private_key_b64`` — base64url-encoded raw private seed (32 bytes)
    """
    raw_priv, raw_pub = _generate_ed25519()

    pub_b64 = base64.urlsafe_b64encode(raw_pub).rstrip(b'=').decode()

    # nodeId: base64url of first 16 bytes of SHA-256(raw public key)
    digest  = hashlib.sha256(raw_pub).digest()
    node_id = base64.urlsafe_b64encode(digest[:16]).rstrip(b'=').decode()

    now         = datetime.now(timezone.utc)
    valid_until = now + timedelta(days=valid_days)

    nik: Dict[str, Any] = {
        'nodeId':     node_id,
        'publicKey':  pub_b64,
        'algorithm':  'Ed25519',
        'validFrom':  now.strftime('%Y-%m-%dT%H:%M:%S.') + f'{now.microsecond // 1000:03d}Z',
        'validUntil': valid_until.strftime('%Y-%m-%dT%H:%M:%S.') + f'{valid_until.microsecond // 1000:03d}Z',
        'keyVersion': 1,
    }
    if node_label:
        nik['label'] = node_label

    priv_b64 = base64.urlsafe_b64encode(raw_priv).rstrip(b'=').decode()

    return {
        'nik':             nik,
        'private_key_b64': priv_b64,
    }


def nik_fingerprint(nik: Dict[str, Any]) -> str:
    """
    Return the SHA-256 hex fingerprint of a NIK's public key.

    Parameters
    ----------
    nik : dict
        A NIK record with a ``publicKey`` field (base64url, 43 chars / 32 bytes).

    Returns
    -------
    str
        64-character lowercase hex string.
    """
    raw_pub = base64.urlsafe_b64decode(nik['publicKey'] + '==')
    return hashlib.sha256(raw_pub).hexdigest()


def is_nik_expired(nik: Dict[str, Any]) -> bool:
    """
    Return True if the NIK's ``validUntil`` timestamp is in the past.

    Parameters
    ----------
    nik : dict
        A NIK record with a ``validUntil`` ISO 8601 UTC string.
    """
    valid_until = datetime.fromisoformat(nik['validUntil'].replace('Z', '+00:00'))
    return datetime.now(timezone.utc) > valid_until


# ── COSE_Sign1 SessionPlan signing ────────────────────────────────────────────


def sign_plan(plan: Dict[str, Any], private_key_b64: str) -> Dict[str, Any]:
    """
    Sign an LTX session plan using a simplified COSE_Sign1-compatible structure.

    Wire format (JSON envelope)::

        {
            "plan": <plan dict>,
            "coseSign1": {
                "protected": "<base64url of canonical JSON of {\"alg\": -19}>",
                "unprotected": {"kid": "<first 8 chars of first node id>"},
                "payload": "<base64url of canonical JSON of plan>",
                "signature": "<base64url of Ed25519 signature over Sig_Structure>"
            }
        }

    The Sig_Structure signed is the canonical JSON (RFC 8785) of::

        ["Signature1", "<protected-b64>", "", "<payload-b64>"]

    Parameters
    ----------
    plan : dict
        LTX plan config (any JSON-serialisable dict).
    private_key_b64 : str
        Base64url-encoded raw 32-byte Ed25519 private seed (from generate_nik).

    Returns
    -------
    dict
        Signed envelope ``{"plan": plan, "coseSign1": {...}}``.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    except ImportError:
        raise ImportError(
            'sign_plan requires the `cryptography` package. '
            'Install it: pip install cryptography'
        )

    # Decode private seed
    raw_seed = base64.urlsafe_b64decode(private_key_b64 + '==')
    priv_key = Ed25519PrivateKey.from_private_bytes(raw_seed)

    # Protected header: canonical JSON of { alg: -19 } (-19 = EdDSA in COSE)
    protected_header = canonical_json({'alg': -19})
    protected_b64 = base64.urlsafe_b64encode(protected_header.encode()).rstrip(b'=').decode()

    # Payload: canonical JSON of the plan
    payload_str = canonical_json(plan)
    payload_b64 = base64.urlsafe_b64encode(payload_str.encode()).rstrip(b'=').decode()

    # Sig_Structure: canonical JSON of the array
    sig_structure = canonical_json(['Signature1', protected_b64, '', payload_b64])
    sig_bytes = priv_key.sign(sig_structure.encode())
    sig_b64 = base64.urlsafe_b64encode(sig_bytes).rstrip(b'=').decode()

    # Derive NIK nodeId from public key to use as kid.
    # nodeId = base64url of first 16 bytes of SHA-256(raw public key), same as generate_nik.
    from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
    raw_pub_for_kid = priv_key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    kid_hash = hashlib.sha256(raw_pub_for_kid).digest()
    kid = base64.urlsafe_b64encode(kid_hash[:16]).rstrip(b'=').decode()

    return {
        'plan': plan,
        'coseSign1': {
            'protected': protected_b64,
            'unprotected': {'kid': kid},
            'payload': payload_b64,
            'signature': sig_b64,
        },
    }


def verify_plan(
    signed_envelope: Dict[str, Any],
    key_cache: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Verify a COSE_Sign1-signed session plan envelope.

    Parameters
    ----------
    signed_envelope : dict
        Output from ``sign_plan()`` — a dict with ``plan`` and ``coseSign1`` keys.
    key_cache : dict
        Plain dict mapping nodeId → NIK record.

    Returns
    -------
    dict
        ``{"valid": bool, "reason": str|None}``
        ``reason`` is ``None`` when valid, otherwise a short error code.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        from cryptography.exceptions import InvalidSignature
    except ImportError:
        raise ImportError(
            'verify_plan requires the `cryptography` package. '
            'Install it: pip install cryptography'
        )

    cose = signed_envelope.get('coseSign1')
    if not cose:
        return {'valid': False, 'reason': 'missing_cose_sign1'}

    kid = cose.get('unprotected', {}).get('kid', '')

    # Look up signer's NIK in key_cache (dict nodeId → NIK)
    signer_nik = key_cache.get(kid)
    if not signer_nik:
        signer_nik = next(
            (n for n in key_cache.values() if n.get('nodeId', '').startswith(kid)),
            None,
        )
    if not signer_nik:
        return {'valid': False, 'reason': 'key_not_in_cache'}
    if is_nik_expired(signer_nik):
        return {'valid': False, 'reason': 'key_expired'}

    # Reconstruct Sig_Structure
    sig_structure = canonical_json(['Signature1', cose['protected'], '', cose['payload']])

    # Reconstruct public key from raw 32 bytes
    raw_pub = base64.urlsafe_b64decode(signer_nik['publicKey'] + '==')
    pub_key = Ed25519PublicKey.from_public_bytes(raw_pub)

    # Verify signature
    sig_bytes = base64.urlsafe_b64decode(cose['signature'] + '==')
    try:
        pub_key.verify(sig_bytes, sig_structure.encode())
        valid = True
    except InvalidSignature:
        valid = False

    if not valid:
        return {'valid': False, 'reason': 'signature_invalid'}

    # Also verify that the embedded payload matches the plan
    payload_str = base64.urlsafe_b64decode(cose['payload'] + '==').decode()
    plan = signed_envelope.get('plan', {})
    if payload_str != canonical_json(plan):
        return {'valid': False, 'reason': 'payload_mismatch'}

    return {'valid': True, 'reason': None}


# ── Sequence Tracking ─────────────────────────────────────────────────────────


class SequenceTracker:
    """
    Per-(plan_id, node_id) monotonic sequence tracker for replay protection.

    Tracks both outbound (next_seq) and inbound (record_seq) sequence numbers
    per node_id. Rejects bundles where seq <= last_seen_seq.

    Parameters
    ----------
    plan_id : str
        Plan identifier used to namespace storage keys.
    storage : optional
        Object with ``get(key, default)`` and ``set(key, val)`` methods.
        Defaults to an in-memory dict.
    """

    def __init__(self, plan_id: str, storage=None) -> None:
        self._prefix = f'ltx_seq_{plan_id}_'
        self._mem: Dict[str, int] = {}
        self._storage = storage

    def _get(self, key: str) -> int:
        if self._storage is not None:
            return self._storage.get(key, 0)
        return self._mem.get(key, 0)

    def _set(self, key: str, val: int) -> None:
        if self._storage is not None:
            self._storage.set(key, val)
        else:
            self._mem[key] = val

    def next_seq(self, node_id: str) -> int:
        """Increment and return the next outbound sequence number for this node."""
        key = self._prefix + node_id
        current = self._get(key)
        nxt = current + 1
        self._set(key, nxt)
        return nxt

    def record_seq(self, node_id: str, seq: int) -> Dict[str, Any]:
        """
        Record an inbound sequence number.

        Returns
        -------
        dict with keys: accepted (bool), gap (bool), gap_size (int), reason (str, optional)
        """
        key = self._prefix + node_id + '_rx'
        last = self._get(key)
        if seq <= last:
            return {'accepted': False, 'gap': False, 'gap_size': 0, 'reason': 'replay'}
        gap = seq > last + 1
        gap_size = seq - last - 1 if gap else 0
        self._set(key, seq)
        return {'accepted': True, 'gap': gap, 'gap_size': gap_size}

    def last_seen_seq(self, node_id: str) -> int:
        """Return the last accepted inbound seq for node_id (0 if none seen)."""
        return self._get(self._prefix + node_id + '_rx')

    def current_seq(self, node_id: str) -> int:
        """Return the current outbound seq counter for node_id (0 if none sent)."""
        return self._get(self._prefix + node_id)

    def snapshot(self) -> Dict[str, int]:
        """Export in-memory state snapshot for persistence."""
        return dict(self._mem)


def add_seq(bundle: Dict[str, Any], tracker: SequenceTracker, node_id: str) -> Dict[str, Any]:
    """
    Add a ``seq`` field to a bundle dict using the tracker's next sequence number.

    Parameters
    ----------
    bundle : dict
        Bundle object to stamp.
    tracker : SequenceTracker
        Sequence tracker instance.
    node_id : str
        Sending node ID.

    Returns
    -------
    dict
        New bundle with ``seq`` field added.
    """
    result = dict(bundle)
    result['seq'] = tracker.next_seq(node_id)
    return result


def check_seq(
    bundle: Dict[str, Any],
    tracker: SequenceTracker,
    sender_node_id: str,
) -> Dict[str, Any]:
    """
    Check an incoming bundle's ``seq`` field against the tracker.

    Parameters
    ----------
    bundle : dict
        Incoming bundle (should have a ``seq`` key).
    tracker : SequenceTracker
        Sequence tracker instance.
    sender_node_id : str
        Node ID of the sender.

    Returns
    -------
    dict
        Acceptance result with keys: accepted, gap, gap_size, reason (optional).
    """
    if 'seq' not in bundle:
        return {'accepted': False, 'gap': False, 'gap_size': 0, 'reason': 'missing_seq'}
    return tracker.record_seq(sender_node_id, bundle['seq'])
