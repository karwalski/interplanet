"""
_cose.py — COSE_Sign1 (RFC 9052) plan signing
Story 70.5 — Python port of typescript/ltx/src/cose.ts (Story 70.2):
real CBOR COSE_Sign1 alongside the frozen TRANSITIONAL JSON envelope
(LTX-SECURITY.md §7.2/§7.5).

Algorithm: Ed25519, COSE algorithm ID -19 (RFC 9864; the polymorphic EdDSA
id -8 is deprecated and rejected). Payload: RFC 8785 canonical JSON bytes of
the plan. Structure: COSE_Sign1 = tag 18 of

    [ protected: bstr .cbor { 1: -19 },
      unprotected: { 4: kid-bytes },
      payload: bstr,
      signature: bstr ]

Sig_structure = ["Signature1", protected, external_aad = h'', payload].

Requires the `cryptography` package for Ed25519 signing/verification
(guarded imports — a clear ImportError is raised if missing).
"""

from __future__ import annotations

import base64
import hashlib
from typing import Any, Dict

from ._cbor import CborTag, decode_cbor, encode_cbor
from ._security import canonical_json, is_nik_expired, verify_plan

COSE_SIGN1_TAG = 18
COSE_ALG_ED25519 = -19


# ── Base64url helpers ─────────────────────────────────────────────────────────


def _b64u_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b'=').decode()


def _b64u_decode(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + '==')


def _sig_structure_bytes(protected_bytes: bytes, payload: bytes) -> bytes:
    return encode_cbor(['Signature1', protected_bytes, b'', payload])


# ── COSE_Sign1 functions ──────────────────────────────────────────────────────


def sign_plan_cose(plan: Dict[str, Any], private_key_b64: str) -> Dict[str, Any]:
    """
    Sign a plan as a real CBOR COSE_Sign1 (tag 18).

    The kid (header label 4) is the raw 16-byte prefix of
    SHA-256(raw public key) — its base64url form is the signer's NIK nodeId,
    matching generate_nik()/sign_plan().

    Parameters
    ----------
    plan : dict
        LTX plan config (any JSON-serialisable dict).
    private_key_b64 : str
        Base64url-encoded raw 32-byte Ed25519 private seed (from generate_nik).

    Returns
    -------
    dict
        ``{'plan': plan, 'coseSign1CborB64': <base64url str, no padding>}``.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
    except ImportError:
        raise ImportError(
            'sign_plan_cose requires the `cryptography` package. '
            'Install it: pip install cryptography'
        )

    raw_seed = _b64u_decode(private_key_b64)
    priv_key = Ed25519PrivateKey.from_private_bytes(raw_seed)

    protected_bytes = encode_cbor({1: COSE_ALG_ED25519})
    payload = canonical_json(plan).encode('utf-8')
    signature = priv_key.sign(_sig_structure_bytes(protected_bytes, payload))

    raw_pub = priv_key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    kid = hashlib.sha256(raw_pub).digest()[:16]

    cose_sign1 = CborTag(COSE_SIGN1_TAG, [
        protected_bytes,
        {4: kid},
        payload,
        signature,
    ])
    return {'plan': plan, 'coseSign1CborB64': _b64u_encode(encode_cbor(cose_sign1))}


def verify_plan_cose(
    envelope: Dict[str, Any],
    key_cache: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Verify a CBOR COSE_Sign1 plan envelope against the key cache.

    Rejects non-Ed25519 algorithms (including the deprecated -8) and payloads
    that do not match the accompanying plan object.

    Parameters
    ----------
    envelope : dict
        Output of ``sign_plan_cose()`` — ``{'plan', 'coseSign1CborB64'}``.
    key_cache : dict
        Plain dict mapping nodeId → NIK record.

    Returns
    -------
    dict
        ``{'valid': True}`` or ``{'valid': False, 'reason': <str>}``.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    except ImportError:
        raise ImportError(
            'verify_plan_cose requires the `cryptography` package. '
            'Install it: pip install cryptography'
        )

    if not isinstance(envelope, dict) or not isinstance(envelope.get('coseSign1CborB64'), str):
        return {'valid': False, 'reason': 'missing_cose_sign1'}

    try:
        decoded = decode_cbor(_b64u_decode(envelope['coseSign1CborB64']))
    except Exception:
        return {'valid': False, 'reason': 'cbor_decode_failed'}
    if not isinstance(decoded, CborTag) or decoded.tag != COSE_SIGN1_TAG:
        return {'valid': False, 'reason': 'not_cose_sign1'}
    arr = decoded.value
    if not isinstance(arr, list) or len(arr) != 4:
        return {'valid': False, 'reason': 'malformed_cose_sign1'}
    protected_bytes, unprotected, payload, signature = arr

    try:
        protected_map = decode_cbor(protected_bytes)
    except Exception:
        return {'valid': False, 'reason': 'protected_decode_failed'}
    if not isinstance(protected_map, dict) or protected_map.get(1) != COSE_ALG_ED25519:
        return {'valid': False, 'reason': 'unsupported_alg'}

    kid_raw = unprotected.get(4) if isinstance(unprotected, dict) else None
    if isinstance(kid_raw, (bytes, bytearray)):
        kid = _b64u_encode(bytes(kid_raw))
    elif isinstance(kid_raw, str):
        kid = kid_raw
    else:
        kid = ''
    if not kid:
        return {'valid': False, 'reason': 'missing_kid'}

    signer_nik = key_cache.get(kid)
    if not signer_nik:
        signer_nik = next(
            (n for n in key_cache.values()
             if str(n.get('nodeId', '')).startswith(kid)),
            None,
        )
    if not signer_nik:
        return {'valid': False, 'reason': 'key_not_in_cache'}
    if is_nik_expired(signer_nik):
        return {'valid': False, 'reason': 'key_expired'}

    try:
        raw_pub = _b64u_decode(signer_nik['publicKey'])
        pub_key = Ed25519PublicKey.from_public_bytes(raw_pub)
        pub_key.verify(
            bytes(signature),
            _sig_structure_bytes(bytes(protected_bytes), bytes(payload)),
        )
    except Exception:
        return {'valid': False, 'reason': 'signature_invalid'}

    if 'plan' in envelope:
        try:
            payload_str = bytes(payload).decode('utf-8')
        except UnicodeDecodeError:
            return {'valid': False, 'reason': 'payload_mismatch'}
        if payload_str != canonical_json(envelope['plan']):
            return {'valid': False, 'reason': 'payload_mismatch'}
    return {'valid': True}


def verify_plan_any(
    envelope: Dict[str, Any],
    key_cache: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Verify either envelope form: the CBOR COSE_Sign1 (``coseSign1CborB64``) or
    the frozen TRANSITIONAL JSON envelope (``coseSign1``) — LTX-SECURITY.md §7.5.
    """
    if isinstance(envelope, dict):
        if 'coseSign1CborB64' in envelope:
            return verify_plan_cose(envelope, key_cache)
        if 'coseSign1' in envelope:
            return verify_plan(envelope, key_cache)
    return {'valid': False, 'reason': 'unknown_envelope'}
