"""
_keydist.py — Pre-session key distribution (KEY_BUNDLE protocol)
Story 28.6 — LTX Python SDK key distribution primitives
Story 70.5 — Global-scope freshness fields (port of TS Story 70.4,
             LTX-SECURITY.md §11.1): issuedAt/seq/senderNodeId covered
             by bundleSig, enforced via GlobalSequenceTracker.

The HOST creates a KEY_BUNDLE message containing all node NIKs, signs it,
and distributes to participants. Receivers verify and cache the keys.
Supports KEY_REVOCATION.

Requires the `cryptography` package for Ed25519 signing/verification.
"""

from __future__ import annotations

import base64
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from ._security import canonical_json, check_issued_at, is_nik_expired


# ── Key Distribution functions ─────────────────────────────────────────────────


def create_key_bundle(
    plan_id: str,
    nik_array: List[Dict[str, Any]],
    host_private_key_b64: str,
    sender_node_id: Optional[str] = None,
    seq: Optional[int] = None,
    issued_at: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Create a signed KEY_BUNDLE message containing all node NIKs.

    Legacy form (no freshness kwargs): the host signs the canonical JSON of
    the keys array only. Global-scope form (Story 70.5, LTX-SECURITY.md
    §11.1): when ``sender_node_id`` and ``seq`` are given, ``bundleSig``
    covers canonical JSON of {issuedAt, keys, planId, senderNodeId, seq} and
    the bundle carries issuedAt/seq/senderNodeId (timestamp = issuedAt).

    Parameters
    ----------
    plan_id : str
        Plan identifier.
    nik_array : list of dict
        Array of NIK records to bundle.
    host_private_key_b64 : str
        Base64url-encoded raw 32-byte Ed25519 private seed.
    sender_node_id : str, optional
        Sending node's nodeId (freshness form).
    seq : int, optional
        Global-scope sequence number, from GlobalSequenceTracker.next_seq
        (freshness form).
    issued_at : str, optional
        ISO 8601 issue timestamp (defaults to now, freshness form only).

    Returns
    -------
    dict
        Signed KEY_BUNDLE message with ``bundleSig`` field.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    except ImportError:
        raise RuntimeError('cryptography library required for key bundle creation')

    raw_seed = base64.urlsafe_b64decode(host_private_key_b64 + '==')
    priv_key = Ed25519PrivateKey.from_private_bytes(raw_seed)

    if sender_node_id is not None and seq is not None:
        # Global-scope form (Story 70.5): issuedAt and seq are signature-covered.
        issued = issued_at or datetime.now(timezone.utc).isoformat()
        signed_payload = canonical_json({
            'issuedAt': issued,
            'keys': nik_array,
            'planId': plan_id,
            'senderNodeId': sender_node_id,
            'seq': seq,
        })
        sig = priv_key.sign(signed_payload.encode())
        return {
            'keys': nik_array,
            'planId': plan_id,
            'timestamp': issued,
            'type': 'KEY_BUNDLE',
            'issuedAt': issued,
            'seq': seq,
            'senderNodeId': sender_node_id,
            'bundleSig': base64.urlsafe_b64encode(sig).rstrip(b'=').decode(),
        }

    # Legacy form: signature covers the keys array only.
    bundle = {
        'keys': nik_array,
        'planId': plan_id,
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'type': 'KEY_BUNDLE',
    }
    keys_str = canonical_json(nik_array)
    sig = priv_key.sign(keys_str.encode())
    bundle['bundleSig'] = base64.urlsafe_b64encode(sig).rstrip(b'=').decode()
    return bundle


def verify_and_cache_keys(
    key_bundle: Dict[str, Any],
    bootstrap_nik: Dict[str, Any],
    tracker=None,
    now_ms: Optional[int] = None,
    max_age_days: int = 30,
) -> Optional[Dict[str, Any]]:
    """
    Verify a KEY_BUNDLE signature against a bootstrap NIK and return a populated key cache.

    Expired NIKs are excluded from the returned cache. When ``tracker`` and
    ``now_ms`` are given, global-scope freshness (Story 70.5, LTX-SECURITY.md
    §11) is enforced: bundles lacking the signature-covered issuedAt/seq/
    senderNodeId fields are rejected, issuedAt must be within the max-age
    window (check_issued_at), and seq must advance per
    tracker.record_seq(senderNodeId, 'KEY_BUNDLE', seq).

    Parameters
    ----------
    key_bundle : dict
        KEY_BUNDLE message (from create_key_bundle).
    bootstrap_nik : dict
        NIK used to verify the bundle signature (typically the host's NIK).
    tracker : GlobalSequenceTracker, optional
        Global-scope sequence tracker (freshness enforcement).
    now_ms : int, optional
        Current time in epoch milliseconds (freshness enforcement).
    max_age_days : int
        Maximum accepted issuedAt age in days (default 30).

    Returns
    -------
    dict or None
        Dict of nodeId → NIK, or None on any verification/freshness failure.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        from cryptography.exceptions import InvalidSignature
    except ImportError:
        return None

    if key_bundle.get('type') != 'KEY_BUNDLE':
        return None

    if 'issuedAt' in key_bundle:
        # Global-scope form: signature covers the freshness fields too.
        signed_payload = canonical_json({
            'issuedAt': key_bundle.get('issuedAt'),
            'keys': key_bundle['keys'],
            'planId': key_bundle.get('planId'),
            'senderNodeId': key_bundle.get('senderNodeId'),
            'seq': key_bundle.get('seq'),
        })
    else:
        signed_payload = canonical_json(key_bundle['keys'])  # legacy form
    raw_pub = base64.urlsafe_b64decode(bootstrap_nik['publicKey'] + '==')
    pub_key = Ed25519PublicKey.from_public_bytes(raw_pub)
    sig_bytes = base64.urlsafe_b64decode(key_bundle['bundleSig'] + '==')

    try:
        pub_key.verify(sig_bytes, signed_payload.encode())
    except InvalidSignature:
        return None

    # Global-scope freshness enforcement (Story 70.5, LTX-SECURITY.md §11).
    if tracker is not None and now_ms is not None:
        if ('issuedAt' not in key_bundle or 'seq' not in key_bundle
                or 'senderNodeId' not in key_bundle):
            return None  # freshness demanded but bundle lacks the covered fields
        age = check_issued_at(key_bundle['issuedAt'], now_ms, max_age_days)
        if not age['accepted']:
            return None
        seq_res = tracker.record_seq(
            key_bundle['senderNodeId'], 'KEY_BUNDLE', key_bundle['seq'])
        if not seq_res['accepted']:
            return None

    cache: Dict[str, Any] = {}
    for nik in key_bundle['keys']:
        if not is_nik_expired(nik):
            cache[nik['nodeId']] = nik
    return cache


def create_revocation(
    plan_id: str,
    revoked_node_id: str,
    reason: str,
    host_private_key_b64: str,
) -> Dict[str, Any]:
    """
    Create a signed KEY_REVOCATION message.

    Parameters
    ----------
    plan_id : str
        Plan identifier.
    revoked_node_id : str
        nodeId of the key to revoke.
    reason : str
        Human-readable reason for revocation.
    host_private_key_b64 : str
        Base64url-encoded raw 32-byte Ed25519 private seed.

    Returns
    -------
    dict
        Signed KEY_REVOCATION message with ``revocationSig`` field.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    except ImportError:
        raise RuntimeError('cryptography library required for revocation creation')

    payload = {
        'nodeId': revoked_node_id,
        'planId': plan_id,
        'reason': reason,
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'type': 'KEY_REVOCATION',
    }
    payload_str = canonical_json(payload)
    raw_seed = base64.urlsafe_b64decode(host_private_key_b64 + '==')
    priv_key = Ed25519PrivateKey.from_private_bytes(raw_seed)
    sig = priv_key.sign(payload_str.encode())
    return {**payload, 'revocationSig': base64.urlsafe_b64encode(sig).rstrip(b'=').decode()}


def apply_revocation(
    cache: Dict[str, Any],
    revocation: Dict[str, Any],
) -> bool:
    """
    Apply a KEY_REVOCATION to a key cache, removing the revoked entry.

    Parameters
    ----------
    cache : dict
        Key cache (dict of nodeId → NIK, from verify_and_cache_keys).
    revocation : dict
        KEY_REVOCATION message.

    Returns
    -------
    bool
        True if revocation was applied, False if type mismatch.
    """
    if revocation.get('type') != 'KEY_REVOCATION':
        return False
    cache.pop(revocation['nodeId'], None)
    return True
