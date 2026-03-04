"""
_bib.py — BPSec Bundle Integrity Block (BIB)
Story 28.3 — BPSec BIB (RFC 9173, Context ID 1) using HMAC-SHA-256

add_bib:          Attach a BIB HMAC-SHA-256 integrity tag to any LTX bundle.
verify_bib:       Verify the BIB tag on a bundle.
generate_bib_key: Generate a fresh 32-byte base64url-encoded HMAC key.

Uses only the Python standard library (base64, hashlib, hmac, os).
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
    if not bib or not isinstance(bib, dict) or 'hmac' not in bib:
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
