"""
interplanet_ltx._bcb — BPSec Bundle Confidentiality Block (BCB)
Story 28.11 — AES-256-GCM confidentiality for LTX window payloads.

generate_session_key(): Generate a 32-byte AES-256 session key.
encrypt_window():       Encrypt a payload dict -> BCB bundle dict.
decrypt_window():       Decrypt a BCB bundle dict -> { valid, plaintext } or { valid, reason }.
"""

import os
import json
import base64

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


def generate_session_key() -> bytes:
    """Return 32 cryptographically random bytes for AES-256."""
    return os.urandom(32)


def _b64u_encode(b: bytes) -> str:
    """Base64url-encode without padding."""
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode()


def _b64u_decode(s: str) -> bytes:
    """Base64url-decode (adds padding as needed)."""
    pad = 4 - len(s) % 4
    if pad != 4:
        s = s + '=' * pad
    return base64.urlsafe_b64decode(s)


def encrypt_window(payload: dict, session_key: bytes) -> dict:
    """
    Encrypt payload with AES-256-GCM using session_key (32 bytes).

    Returns a BCB bundle:
        {
            'type':       'BCB',
            'nonce':      <base64url, 12 bytes>,
            'ciphertext': <base64url, len(payload_json) bytes>,
            'tag':        <base64url, 16 bytes>,
        }
    """
    nonce = os.urandom(12)
    aesgcm = AESGCM(session_key)
    plaintext_bytes = json.dumps(payload, separators=(',', ':')).encode('utf-8')
    # AESGCM.encrypt returns ciphertext + 16-byte auth tag concatenated
    ct_and_tag = aesgcm.encrypt(nonce, plaintext_bytes, None)
    ct = ct_and_tag[:-16]
    tag = ct_and_tag[-16:]
    return {
        'type': 'BCB',
        'nonce': _b64u_encode(nonce),
        'ciphertext': _b64u_encode(ct),
        'tag': _b64u_encode(tag),
    }


def decrypt_window(bundle: dict, session_key: bytes) -> dict:
    """
    Decrypt a BCB bundle with AES-256-GCM using session_key (32 bytes).

    Returns one of:
        { 'valid': True,  'plaintext': <dict> }
        { 'valid': False, 'reason': 'not_bcb' }
        { 'valid': False, 'reason': 'tag_mismatch' }
    """
    if bundle.get('type') != 'BCB':
        return {'valid': False, 'reason': 'not_bcb'}

    try:
        nonce = _b64u_decode(bundle['nonce'])
        ct    = _b64u_decode(bundle['ciphertext'])
        tag   = _b64u_decode(bundle['tag'])
        aesgcm = AESGCM(session_key)
        # AESGCM.decrypt expects ciphertext + tag concatenated
        plaintext_bytes = aesgcm.decrypt(nonce, ct + tag, None)
        return {'valid': True, 'plaintext': json.loads(plaintext_bytes)}
    except Exception:
        return {'valid': False, 'reason': 'tag_mismatch'}
