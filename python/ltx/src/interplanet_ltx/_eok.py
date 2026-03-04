"""
_eok.py — Emergency Override Keys (EOK) and Multi-Person Authorisation
Story 28.7 — LTX Python SDK EOK / MULTI-AUTH primitives

create_eok:                  Generate an Emergency Override Key
create_emergency_override:   Create a signed EMERGENCY_OVERRIDE bundle
verify_emergency_override:   Verify an EMERGENCY_OVERRIDE bundle
create_co_sig:               Create an ACTION_COSIG bundle
check_multi_auth:            Verify multi-person authorisation

Requires the `cryptography` package for Ed25519 signing/verification.
"""

from __future__ import annotations

import base64
import hashlib
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Union


from ._security import canonical_json, is_nik_expired


# ── EOK functions ──────────────────────────────────────────────────────────────


def create_eok(valid_days: int = 30, node_label: str = '') -> Dict[str, Any]:
    """
    Create an Emergency Override Key (EOK).

    Same structure as a NIK but with keyType 'eok'.

    Parameters
    ----------
    valid_days : int
        Validity period in days (default 30).
    node_label : str
        Optional human-readable label.

    Returns
    -------
    dict with keys:
        ``eok``         — EOK record dict
        ``private_key`` — base64url-encoded raw private seed (32 bytes)
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        from cryptography.hazmat.primitives.serialization import (
            Encoding, NoEncryption, PrivateFormat, PublicFormat,
        )
    except ImportError:
        raise ImportError(
            'create_eok requires the `cryptography` package. '
            'Install it: pip install cryptography'
        )

    private_key = Ed25519PrivateKey.generate()

    raw_priv = private_key.private_bytes(
        encoding=Encoding.Raw,
        format=PrivateFormat.Raw,
        encryption_algorithm=NoEncryption(),
    )
    raw_pub = private_key.public_key().public_bytes(
        encoding=Encoding.Raw,
        format=PublicFormat.Raw,
    )

    pub_b64 = base64.urlsafe_b64encode(raw_pub).rstrip(b'=').decode()

    # eokId: base64url of first 16 bytes of SHA-256(raw public key)
    digest = hashlib.sha256(raw_pub).digest()
    eok_id = base64.urlsafe_b64encode(digest[:16]).rstrip(b'=').decode()

    now         = datetime.now(timezone.utc)
    valid_until = now + timedelta(days=valid_days)

    eok: Dict[str, Any] = {
        'eokId':     eok_id,
        'publicKey': pub_b64,
        'algorithm': 'Ed25519',
        'keyType':   'eok',
        'validFrom':  now.strftime('%Y-%m-%dT%H:%M:%S.') + f'{now.microsecond // 1000:03d}Z',
        'validUntil': valid_until.strftime('%Y-%m-%dT%H:%M:%S.') + f'{valid_until.microsecond // 1000:03d}Z',
    }
    if node_label:
        eok['label'] = node_label

    priv_b64 = base64.urlsafe_b64encode(raw_priv).rstrip(b'=').decode()

    return {
        'eok':        eok,
        'private_key': priv_b64,
    }


def create_emergency_override(
    plan_id: str,
    action: str,
    eok_private_key_b64: str,
    eok_id: str,
) -> Dict[str, Any]:
    """
    Create a signed EMERGENCY_OVERRIDE bundle.

    Parameters
    ----------
    plan_id : str
        Plan identifier.
    action : str
        Action to override (e.g. 'ABORT', 'EXTEND').
    eok_private_key_b64 : str
        Base64url-encoded raw 32-byte Ed25519 private seed.
    eok_id : str
        ID of the EOK (from create_eok).

    Returns
    -------
    dict
        EMERGENCY_OVERRIDE bundle with ``overrideSig`` field.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    except ImportError:
        raise ImportError(
            'create_emergency_override requires the `cryptography` package. '
            'Install it: pip install cryptography'
        )

    timestamp = datetime.now(timezone.utc).isoformat()
    payload = {
        'action':    action,
        'eokId':     eok_id,
        'planId':    plan_id,
        'timestamp': timestamp,
        'type':      'EMERGENCY_OVERRIDE',
    }
    payload_bytes = canonical_json(payload).encode()

    raw_seed = base64.urlsafe_b64decode(eok_private_key_b64 + '==')
    priv_key = Ed25519PrivateKey.from_private_bytes(raw_seed)
    sig = priv_key.sign(payload_bytes)
    override_sig = base64.urlsafe_b64encode(sig).rstrip(b'=').decode()

    # Return with original (non-canonical) key order for convenience
    return {
        'type':        'EMERGENCY_OVERRIDE',
        'planId':      plan_id,
        'action':      action,
        'timestamp':   timestamp,
        'eokId':       eok_id,
        'overrideSig': override_sig,
    }


def verify_emergency_override(
    override_bundle: Dict[str, Any],
    eok_cache: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Verify an EMERGENCY_OVERRIDE bundle against an EOK cache.

    Parameters
    ----------
    override_bundle : dict
        Output from ``create_emergency_override()``.
    eok_cache : dict
        Plain dict mapping eokId → EOK record.

    Returns
    -------
    dict
        ``{"valid": bool, "reason": str|None}``
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        from cryptography.exceptions import InvalidSignature
    except ImportError:
        raise ImportError(
            'verify_emergency_override requires the `cryptography` package. '
            'Install it: pip install cryptography'
        )

    eok_id = override_bundle.get('eokId', '')

    # Look up EOK in cache
    eok = eok_cache.get(eok_id) if isinstance(eok_cache, dict) else None
    if not eok:
        return {'valid': False, 'reason': 'key_not_in_cache'}

    # Check expiry
    valid_until = datetime.fromisoformat(eok['validUntil'].replace('Z', '+00:00'))
    if datetime.now(timezone.utc) > valid_until:
        return {'valid': False, 'reason': 'key_expired'}

    # Reconstruct signed payload (sign-over fields only, without overrideSig)
    payload = {
        'action':    override_bundle['action'],
        'eokId':     override_bundle['eokId'],
        'planId':    override_bundle['planId'],
        'timestamp': override_bundle['timestamp'],
        'type':      override_bundle['type'],
    }
    payload_bytes = canonical_json(payload).encode()

    # Verify signature
    raw_pub = base64.urlsafe_b64decode(eok['publicKey'] + '==')
    pub_key = Ed25519PublicKey.from_public_bytes(raw_pub)
    sig_bytes = base64.urlsafe_b64decode(override_bundle['overrideSig'] + '==')

    try:
        pub_key.verify(sig_bytes, payload_bytes)
    except InvalidSignature:
        return {'valid': False, 'reason': 'invalid_signature'}

    return {'valid': True, 'reason': None}


def create_co_sig(
    entry_id: str,
    plan_id: str,
    cosig_node_id: str,
    cosig_private_key_b64: str,
    cosig_nik: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Create an ACTION_COSIG bundle for multi-person authorisation.

    Parameters
    ----------
    entry_id : str
        Entry identifier to co-sign.
    plan_id : str
        Plan identifier.
    cosig_node_id : str
        Node ID of the co-signer (fallback if cosig_nik not provided).
    cosig_private_key_b64 : str
        Base64url-encoded raw 32-byte Ed25519 private seed.
    cosig_nik : dict
        NIK of the co-signer (``nodeId`` is used for ``cosigNodeId``).

    Returns
    -------
    dict
        ACTION_COSIG bundle with ``cosigSig`` field.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    except ImportError:
        raise ImportError(
            'create_co_sig requires the `cryptography` package. '
            'Install it: pip install cryptography'
        )

    cosig_time = datetime.now(timezone.utc).isoformat()
    node_id    = cosig_nik['nodeId'] if cosig_nik else cosig_node_id

    payload = {
        'cosigNodeId': node_id,
        'cosigTime':   cosig_time,
        'entryId':     entry_id,
        'planId':      plan_id,
        'type':        'ACTION_COSIG',
    }
    payload_bytes = canonical_json(payload).encode()

    raw_seed = base64.urlsafe_b64decode(cosig_private_key_b64 + '==')
    priv_key = Ed25519PrivateKey.from_private_bytes(raw_seed)
    sig = priv_key.sign(payload_bytes)
    cosig_sig = base64.urlsafe_b64encode(sig).rstrip(b'=').decode()

    return {
        'type':        'ACTION_COSIG',
        'entryId':     entry_id,
        'planId':      plan_id,
        'cosigNodeId': node_id,
        'cosigTime':   cosig_time,
        'cosigSig':    cosig_sig,
    }


def check_multi_auth(
    cosig_bundles: List[Dict[str, Any]],
    entry_id: str,
    plan_id: str,
    key_cache: Dict[str, Any],
    required_count: int,
) -> Dict[str, Any]:
    """
    Check multi-person authorisation by verifying co-signature bundles.

    Parameters
    ----------
    cosig_bundles : list of dict
        Array of ACTION_COSIG bundles.
    entry_id : str
        Entry identifier to match.
    plan_id : str
        Plan identifier to match.
    key_cache : dict
        Plain dict mapping nodeId → NIK record.
    required_count : int
        Minimum number of valid signatures required for authorisation.

    Returns
    -------
    dict with keys:
        ``authorised``      — bool
        ``valid_sig_count`` — int
        ``invalid_count``   — int
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        from cryptography.exceptions import InvalidSignature
    except ImportError:
        raise ImportError(
            'check_multi_auth requires the `cryptography` package. '
            'Install it: pip install cryptography'
        )

    valid_sig_count = 0
    invalid_count   = 0

    for bundle in cosig_bundles:
        # Must match entry_id and plan_id
        if bundle.get('entryId') != entry_id or bundle.get('planId') != plan_id:
            invalid_count += 1
            continue

        # Look up signer NIK in key_cache
        node_id = bundle.get('cosigNodeId', '')
        nik = key_cache.get(node_id)
        if not nik:
            invalid_count += 1
            continue

        # Verify signature
        payload = {
            'cosigNodeId': bundle['cosigNodeId'],
            'cosigTime':   bundle['cosigTime'],
            'entryId':     bundle['entryId'],
            'planId':      bundle['planId'],
            'type':        bundle['type'],
        }
        payload_bytes = canonical_json(payload).encode()

        try:
            raw_pub = base64.urlsafe_b64decode(nik['publicKey'] + '==')
            pub_key = Ed25519PublicKey.from_public_bytes(raw_pub)
            sig_bytes = base64.urlsafe_b64decode(bundle['cosigSig'] + '==')
            pub_key.verify(sig_bytes, payload_bytes)
            valid_sig_count += 1
        except (InvalidSignature, Exception):
            invalid_count += 1

    return {
        'authorised':      valid_sig_count >= required_count,
        'valid_sig_count': valid_sig_count,
        'invalid_count':   invalid_count,
    }
