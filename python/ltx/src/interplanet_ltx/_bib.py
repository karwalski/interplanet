"""
_bib.py — BPSec Bundle Integrity Block (BIB)
Story 28.3 — BPSec BIB (RFC 9173, Context ID 1) using HMAC-SHA-256
Story 70.5 — LTX-native Ed25519 BIB (LTX-SECURITY.md §8.2, "ltx-ed25519"),
             port of the Story 70.3 TypeScript additions.

add_bib:            Attach a BIB HMAC-SHA-256 integrity tag to any LTX bundle.
verify_bib:         Verify the HMAC BIB tag on a bundle.
add_bib_ed25519:    Attach an Ed25519 NIK-signed BIB (non-repudiation, no
                    pre-shared pairwise key).
verify_bib_ed25519: Verify an Ed25519 BIB against the sender's NIK.
generate_bib_key:   Generate a fresh 32-byte base64url-encoded HMAC key.

Context-confusion defence: each verifier rejects a BIB whose declared
context does not match its verification method.

Uses only the Python standard library (base64, hashlib, hmac, os) for the
HMAC context; the Ed25519 context needs the `cryptography` package
(guarded imports).
"""

from __future__ import annotations

import base64
import hashlib
import hmac as _hmac
import os
from typing import Any, Dict


# ── Base64url helpers ─────────────────────────────────────────────────────────


def _urlsafe_b64decode(s: str) -> bytes:
    """Decode a base64url string (no-padding-required variant)."""
    # Add padding as needed before decoding
    return base64.urlsafe_b64decode(s + '==')


def _urlsafe_b64encode(b: bytes) -> str:
    """Encode bytes to base64url without padding."""
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode()


# ── BIB functions ─────────────────────────────────────────────────────────────


def generate_bib_key() -> str:
    """
    Generate a fresh base64url-encoded 32-byte random key for HMAC-SHA-256.

    Returns a 43-character base64url string (256 bits, no padding).
    """
    return _urlsafe_b64encode(os.urandom(32))


def add_bib(bundle: Dict[str, Any], hmac_key_b64: str) -> Dict[str, Any]:
    """
    Add a BPSec Bundle Integrity Block (Context ID 1, RFC 9173) to a bundle.

    Strips any existing 'bib' field from the bundle before computing the HMAC,
    then returns a new dict with the 'bib' field appended. The input bundle is
    NOT mutated.

    :param bundle:       Any LTX message bundle (plain Python dict)
    :param hmac_key_b64: Base64url-encoded raw 32-byte HMAC-SHA-256 key
    :returns:            New bundle dict: { ...bundleWithoutBib, bib: { contextId, targetBlockNumber, hmac } }
    """
    from ._security import canonical_json  # local import to avoid circular deps

    # Strip any existing bib field (do not mutate original)
    bundle_without_bib = {k: v for k, v in bundle.items() if k != 'bib'}

    raw_key = _urlsafe_b64decode(hmac_key_b64)
    msg = canonical_json(bundle_without_bib).encode('utf-8')
    hmac_bytes = _hmac.new(raw_key, msg, hashlib.sha256).digest()

    result = dict(bundle_without_bib)
    result['bib'] = {
        'contextId': 1,
        'targetBlockNumber': 0,
        'hmac': _urlsafe_b64encode(hmac_bytes),
    }
    return result


def verify_bib(bundle: Dict[str, Any], hmac_key_b64: str) -> Dict[str, Any]:
    """
    Verify a BPSec Bundle Integrity Block (Context ID 1, RFC 9173).

    Extracts the 'bib' field, recomputes HMAC-SHA-256 over canonicalJSON of the
    remaining bundle fields, and compares with bib['hmac'] using a constant-time
    comparison.

    :param bundle:       Bundle dict containing a 'bib' field
    :param hmac_key_b64: Base64url-encoded raw 32-byte HMAC-SHA-256 key
    :returns:            {'valid': True} or {'valid': False, 'reason': <str>}
    """
    from ._security import canonical_json  # local import to avoid circular deps

    bib = bundle.get('bib')
    if not bib or not isinstance(bib, dict):
        return {'valid': False, 'reason': 'missing_bib'}
    if bib.get('securityContext') == 'ltx-ed25519':
        # Context-confusion defence: an Ed25519 BIB must not pass HMAC verification.
        return {'valid': False, 'reason': 'context_mismatch'}
    if 'hmac' not in bib:
        return {'valid': False, 'reason': 'missing_bib'}

    bundle_without_bib = {k: v for k, v in bundle.items() if k != 'bib'}

    raw_key = _urlsafe_b64decode(hmac_key_b64)
    msg = canonical_json(bundle_without_bib).encode('utf-8')
    computed = _hmac.new(raw_key, msg, hashlib.sha256).digest()
    expected = _urlsafe_b64decode(bib['hmac'])

    # Constant-time comparison
    if not _hmac.compare_digest(computed, expected):
        return {'valid': False, 'reason': 'hmac_mismatch'}

    return {'valid': True}


# ── LTX-native Ed25519 BIB (Story 70.5, port of TS Story 70.3) ────────────────


def add_bib_ed25519(bundle: Dict[str, Any], private_key_b64: str) -> Dict[str, Any]:
    """
    Add an LTX-native Ed25519 BIB (LTX-SECURITY.md §8.2): the bundle is signed
    with the originating node's NIK, giving per-bundle non-repudiation without
    a pre-shared pairwise key. The input bundle is NOT mutated.

    :param bundle:          Any LTX message bundle (plain Python dict)
    :param private_key_b64: Base64url-encoded raw 32-byte Ed25519 private seed
    :returns:               New bundle dict: { ...bundleWithoutBib,
                            bib: { securityContext, targetBlockNumber, sig } }
    """
    from ._security import canonical_json  # local import to avoid circular deps
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    except ImportError:
        raise ImportError(
            'add_bib_ed25519 requires the `cryptography` package. '
            'Install it: pip install cryptography'
        )

    bundle_without_bib = {k: v for k, v in bundle.items() if k != 'bib'}
    raw_seed = _urlsafe_b64decode(private_key_b64)
    priv_key = Ed25519PrivateKey.from_private_bytes(raw_seed)
    msg = canonical_json(bundle_without_bib).encode('utf-8')
    sig = priv_key.sign(msg)

    result = dict(bundle_without_bib)
    result['bib'] = {
        'securityContext': 'ltx-ed25519',
        'targetBlockNumber': 0,
        'sig': _urlsafe_b64encode(sig),
    }
    return result


def verify_bib_ed25519(bundle: Dict[str, Any], nik: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify an LTX-native Ed25519 BIB against the sender's NIK.
    Rejects HMAC-context BIBs (context-confusion defence).

    :param bundle: Bundle dict containing a 'bib' field
    :param nik:    Sender's NIK record (with base64url 'publicKey')
    :returns:      {'valid': True} or {'valid': False, 'reason': <str>}
    """
    from ._security import canonical_json  # local import to avoid circular deps
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    except ImportError:
        raise ImportError(
            'verify_bib_ed25519 requires the `cryptography` package. '
            'Install it: pip install cryptography'
        )

    bib = bundle.get('bib')
    if not bib or not isinstance(bib, dict):
        return {'valid': False, 'reason': 'missing_bib'}
    if bib.get('securityContext') != 'ltx-ed25519' or not isinstance(bib.get('sig'), str):
        return {'valid': False, 'reason': 'context_mismatch'}

    bundle_without_bib = {k: v for k, v in bundle.items() if k != 'bib'}
    msg = canonical_json(bundle_without_bib).encode('utf-8')
    try:
        raw_pub = _urlsafe_b64decode(nik['publicKey'])
        pub_key = Ed25519PublicKey.from_public_bytes(raw_pub)
        pub_key.verify(_urlsafe_b64decode(bib['sig']), msg)
    except Exception:
        return {'valid': False, 'reason': 'signature_invalid'}
    return {'valid': True}
