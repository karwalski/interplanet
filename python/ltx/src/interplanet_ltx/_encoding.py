"""Base64 URL-safe encode/decode helpers matching ltx-sdk.js."""

import base64
from typing import Optional


def b64enc(s: str) -> str:
    """URL-safe base64 encode a string (no padding)."""
    return base64.urlsafe_b64encode(s.encode('utf-8')).rstrip(b'=').decode('ascii')


def b64dec(token: str) -> Optional[str]:
    """Decode a URL-safe base64 token back to a string.  Returns None on error."""
    # Re-add padding
    pad = 4 - len(token) % 4
    if pad != 4:
        token = token + '=' * pad
    try:
        return base64.urlsafe_b64decode(token).decode('utf-8')
    except Exception:
        return None
