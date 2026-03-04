"""
_keydist.py — Pre-session key distribution (KEY_BUNDLE protocol)
Story 28.6 — LTX Python SDK key distribution primitives

The HOST creates a KEY_BUNDLE message containing all node NIKs, signs it,
and distributes to participants. Receivers verify and cache the keys.
Supports KEY_REVOCATION.

Requires the `cryptography` package for Ed25519 signing/verification.
"""

from __future__ import annotations

import base64
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from ._security import canonical_json, is_nik_expired


# ── Key Distribution functions ─────────────────────────────────────────────────


def create_key_bundle(
    plan_id: str,
    nik_array: List[Dict[str, Any]],
    host_private_key_b64: str,
) -> Dict[str, Any]:
    """
    Create a signed KEY_BUNDLE message containing all node NIKs.

    The host signs the canonical JSON of the keys array with their private key.

    Parameters
    ----------
    plan_id : str
        Plan identifier.
    nik_array : list of dict
        Array of NIK records to bundle.
    host_private_key_b64 : str
        Base64url-encoded raw 32-byte Ed25519 private seed.

    Returns
    -------
    dict
        Signed KEY_BUNDLE message with ``bundleSig`` field.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    except ImportError:
        raise RuntimeError('cryptography library required for key bundle creation')

    bundle = {
        'keys': nik_array,
        'planId': plan_id,
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'type': 'KEY_BUNDLE',
    }
    keys_str = canonical_json(nik_array)
    raw_seed = base64.urlsafe_b64decode(host_private_key_b64 + '==')
    priv_key = Ed25519PrivateKey.from_private_bytes(raw_seed)
    sig = priv_key.sign(keys_str.encode())
    bundle['bundleSig'] = base64.urlsafe_b64encode(sig).rstrip(b'=').decode()
    return bundle


def verify_and_cache_keys(
    key_bundle: Dict[str, Any],
    bootstrap_nik: Dict[str, Any],
) -> Optional[Dict[str, Any]]:
    """
    Verify a KEY_BUNDLE signature against a bootstrap NIK and return a populated key cache.

    Expired NIKs are excluded from the returned cache.

    Parameters
    ----------
    key_bundle : dict
        KEY_BUNDLE message (from create_key_bundle).
    bootstrap_nik : dict
        NIK used to verify the bundle signature (typically the host's NIK).

    Returns
    -------
    dict or None
        Dict of nodeId → NIK, or None if the signature is invalid.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        from cryptography.exceptions import InvalidSignature
    except ImportError:
        return None

    if key_bundle.get('type') != 'KEY_BUNDLE':
        return None

    keys_str = canonical_json(key_bundle['keys'])
    raw_pub = base64.urlsafe_b64decode(bootstrap_nik['publicKey'] + '==')
    pub_key = Ed25519PublicKey.from_public_bytes(raw_pub)
    sig_bytes = base64.urlsafe_b64decode(key_bundle['bundleSig'] + '==')

    try:
        pub_key.verify(sig_bytes, keys_str.encode())
    except InvalidSignature:
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
