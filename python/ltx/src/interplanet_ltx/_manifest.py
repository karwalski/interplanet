"""
_manifest.py — Per-window artefact manifests and hedged EdDSA
Story 28.8 — LTX Python SDK window manifests

artefact_sha256: SHA-256 helper for computing artefact hashes.
create_window_manifest: Build a signed WINDOW_MANIFEST with hedged EdDSA.
verify_window_manifest: Verify a WINDOW_MANIFEST signature against a key cache.
hedged_sign / hedged_verify: Standalone hedged EdDSA signing.

Uses the `cryptography` package for Ed25519. Raises ImportError with a clear
message if it is not installed.
"""

from __future__ import annotations

import base64
import hashlib
import secrets
from typing import Any, Dict, List, Union

from ._security import canonical_json, is_nik_expired


def artefact_sha256(data: Union[str, bytes]) -> str:
    """
    Compute the SHA-256 hex digest of a string or bytes value.
    Strings are encoded as UTF-8 before hashing.

    Parameters
    ----------
    data : str or bytes
        Input data to hash.

    Returns
    -------
    str
        64-character lowercase hex string.
    """
    if isinstance(data, str):
        data = data.encode('utf-8')
    return hashlib.sha256(data).hexdigest()


def _sign_ed25519(data_bytes: bytes, private_key_b64: str) -> str:
    """Sign data_bytes with an Ed25519 private key seed. Returns base64url signature."""
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    except ImportError:
        raise ImportError(
            'Window manifest functions require the `cryptography` package. '
            'Install it: pip install cryptography'
        )
    raw_seed = base64.urlsafe_b64decode(private_key_b64 + '==')
    priv_key = Ed25519PrivateKey.from_private_bytes(raw_seed)
    sig_bytes = priv_key.sign(data_bytes)
    return base64.urlsafe_b64encode(sig_bytes).rstrip(b'=').decode()


def _verify_ed25519(data_bytes: bytes, signature_b64: str, public_key_b64: str) -> bool:
    """Verify an Ed25519 signature. Returns True if valid, False otherwise."""
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        from cryptography.exceptions import InvalidSignature
    except ImportError:
        raise ImportError(
            'Window manifest functions require the `cryptography` package. '
            'Install it: pip install cryptography'
        )
    raw_pub = base64.urlsafe_b64decode(public_key_b64 + '==')
    pub_key = Ed25519PublicKey.from_public_bytes(raw_pub)
    sig_bytes = base64.urlsafe_b64decode(signature_b64 + '==')
    try:
        pub_key.verify(sig_bytes, data_bytes)
        return True
    except InvalidSignature:
        return False


def create_window_manifest(
    plan_id: str,
    window_seq: int,
    artefacts: List[Dict[str, Any]],
    tree_head: Dict[str, Any],
    private_key_b64: str,
) -> Dict[str, Any]:
    """
    Create a signed WINDOW_MANIFEST for a set of artefacts.

    Uses hedged EdDSA: a random 32-byte nonce_salt is bound into the signed
    payload, ensuring each call produces a unique signature even for identical
    inputs.

    Parameters
    ----------
    plan_id : str
        Plan identifier.
    window_seq : int
        Window sequence number.
    artefacts : list of dict
        Each element: ``{ "name": str, "sha256": str, "sizeBytes": int }``.
        Caller pre-computes sha256 using ``artefact_sha256()``.
    tree_head : dict
        Signed tree head from ``merkle_log.sign_tree_head()``. Must contain
        ``sha256RootHash``, ``treeSize``, ``signerNodeId``, ``timestamp``,
        and ``treeHeadSig`` fields.
    private_key_b64 : str
        Base64url-encoded raw 32-byte Ed25519 private seed.

    Returns
    -------
    dict
        Complete WINDOW_MANIFEST including ``manifestSig``.
    """
    # Generate random 32-byte nonce_salt (hedged EdDSA)
    nonce_salt = base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b'=').decode()

    tree_head_ref = {
        'sha256RootHash': tree_head['sha256RootHash'],
        'signerNodeId':   tree_head['signerNodeId'],
        'timestamp':      tree_head['timestamp'],
        'treeHeadSig':    tree_head['treeHeadSig'],
        'treeSize':       tree_head['treeSize'],
    }

    manifest_without_sig = {
        'artefacts':   artefacts,
        'nonceSalt':   nonce_salt,
        'planId':      plan_id,
        'treeHeadRef': tree_head_ref,
        'type':        'WINDOW_MANIFEST',
        'windowSeq':   window_seq,
    }

    data_to_sign = canonical_json(manifest_without_sig).encode('utf-8')
    manifest_sig = _sign_ed25519(data_to_sign, private_key_b64)

    return {**manifest_without_sig, 'manifestSig': manifest_sig}


def verify_window_manifest(
    manifest: Dict[str, Any],
    key_cache: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Verify a WINDOW_MANIFEST signature against a key cache.

    Parameters
    ----------
    manifest : dict
        WINDOW_MANIFEST (from ``create_window_manifest``).
    key_cache : dict
        Plain dict mapping nodeId → NIK record.

    Returns
    -------
    dict
        ``{"valid": True}`` on success, or
        ``{"valid": False, "reason": str}`` on failure.
    """
    tree_head_ref = manifest.get('treeHeadRef', {})
    signer_node_id = tree_head_ref.get('signerNodeId')
    if not signer_node_id:
        return {'valid': False, 'reason': 'missing_signer_node_id'}

    signer_nik = key_cache.get(signer_node_id)
    if not signer_nik:
        return {'valid': False, 'reason': 'key_not_in_cache'}
    if is_nik_expired(signer_nik):
        return {'valid': False, 'reason': 'key_expired'}

    manifest_sig = manifest.get('manifestSig')
    if not manifest_sig:
        return {'valid': False, 'reason': 'missing_manifest_sig'}

    # Build manifest without sig for verification
    manifest_without_sig = {k: v for k, v in manifest.items() if k != 'manifestSig'}
    data_to_verify = canonical_json(manifest_without_sig).encode('utf-8')

    valid = _verify_ed25519(data_to_verify, manifest_sig, signer_nik['publicKey'])
    if not valid:
        return {'valid': False, 'reason': 'signature_invalid'}
    return {'valid': True}


def hedged_sign(
    data_bytes: bytes,
    private_key_b64: str,
) -> Dict[str, str]:
    """
    Hedged EdDSA signing: signs data_bytes with a random nonce_salt included
    in the canonical payload. Produces a unique signature per call even for
    identical inputs.

    Parameters
    ----------
    data_bytes : bytes
        Data to sign.
    private_key_b64 : str
        Base64url-encoded raw 32-byte Ed25519 private seed.

    Returns
    -------
    dict
        ``{"signature": base64url_str, "nonceSalt": base64url_str}``
    """
    nonce_salt = base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b'=').decode()
    data_b64 = base64.urlsafe_b64encode(data_bytes).rstrip(b'=').decode()
    payload = canonical_json({'data': data_b64, 'nonceSalt': nonce_salt})
    signature = _sign_ed25519(payload.encode('utf-8'), private_key_b64)
    return {'signature': signature, 'nonceSalt': nonce_salt}


def hedged_verify(
    data_bytes: bytes,
    signature: str,
    nonce_salt: str,
    public_key_b64: str,
) -> bool:
    """
    Verify a hedged EdDSA signature produced by ``hedged_sign()``.

    Parameters
    ----------
    data_bytes : bytes
        Original data that was signed.
    signature : str
        Base64url-encoded Ed25519 signature.
    nonce_salt : str
        Base64url-encoded nonce salt (from ``hedged_sign`` result).
    public_key_b64 : str
        Base64url-encoded raw 32-byte Ed25519 public key.

    Returns
    -------
    bool
        True if the signature is valid, False otherwise.
    """
    data_b64 = base64.urlsafe_b64encode(data_bytes).rstrip(b'=').decode()
    payload = canonical_json({'data': data_b64, 'nonceSalt': nonce_salt})
    return _verify_ed25519(payload.encode('utf-8'), signature, public_key_b64)
