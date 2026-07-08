"""
_cbor.py — Minimal deterministic CBOR (RFC 8949)
Story 70.5 — Python port of typescript/ltx/src/cbor.ts (Story 70.1):
zero-dependency subset for COSE_Sign1 (RFC 9052).

Supported: unsigned/negative integers, byte strings, text strings, arrays,
maps, booleans, null, and tags. Encoding follows the RFC 8949 §4.2.1 core
deterministic profile: definite lengths only, shortest-form integer heads,
map keys sorted bytewise by their encoded form.

Values map Python ⇄ CBOR: int ⇄ major 0/1 (bool is checked BEFORE int —
Python bool is an int subclass), bytes/bytearray ⇄ major 2, str ⇄ major 3,
list/tuple ⇄ major 4, dict ⇄ major 5, CborTag ⇄ major 6,
True/False/None ⇄ major 7. Floats are rejected (integers only).

Uses only the Python standard library.
"""

from __future__ import annotations

import base64
from typing import Any


# ── Tagged value wrapper (major type 6) ───────────────────────────────────────


class CborTag:
    """Tagged value wrapper (CBOR major type 6)."""

    def __init__(self, tag: int, value: Any) -> None:
        self.tag = tag
        self.value = value

    def __eq__(self, other: object) -> bool:
        return (
            isinstance(other, CborTag)
            and self.tag == other.tag
            and self.value == other.value
        )

    def __repr__(self) -> str:
        return f'CborTag({self.tag!r}, {self.value!r})'


# ── Encoding ─────────────────────────────────────────────────────────────────


def _encode_head(major: int, arg: int) -> bytes:
    """Encode a shortest-form head byte(s) for the given major type/argument."""
    if not isinstance(arg, int) or isinstance(arg, bool) or arg < 0 or arg > 0xFFFFFFFFFFFFFFFF:
        raise ValueError('cbor: invalid length/argument')
    if arg < 24:
        return bytes([(major << 5) | arg])
    if arg < 0x100:
        return bytes([(major << 5) | 24, arg])
    if arg < 0x10000:
        return bytes([(major << 5) | 25]) + arg.to_bytes(2, 'big')
    if arg < 0x100000000:
        return bytes([(major << 5) | 26]) + arg.to_bytes(4, 'big')
    return bytes([(major << 5) | 27]) + arg.to_bytes(8, 'big')


def encode_cbor(value: Any) -> bytes:
    """Encode a value to deterministic CBOR bytes (RFC 8949 §4.2.1 profile)."""
    if value is None:
        return b'\xf6'
    # bool must be checked BEFORE int: Python bool is an int subclass.
    if isinstance(value, bool):
        return b'\xf5' if value else b'\xf4'

    if isinstance(value, int):
        return _encode_head(0, value) if value >= 0 else _encode_head(1, -value - 1)

    if isinstance(value, float):
        raise ValueError('cbor: only integers supported')

    if isinstance(value, str):
        encoded = value.encode('utf-8')
        return _encode_head(3, len(encoded)) + encoded

    if isinstance(value, (bytes, bytearray)):
        raw = bytes(value)
        return _encode_head(2, len(raw)) + raw

    if isinstance(value, CborTag):
        return _encode_head(6, value.tag) + encode_cbor(value.value)

    if isinstance(value, (list, tuple)):
        parts = [encode_cbor(v) for v in value]
        return _encode_head(4, len(parts)) + b''.join(parts)

    if isinstance(value, dict):
        entries = []
        for k, v in value.items():
            key = k
            # COSE header labels are integers; encode numeric-looking string
            # keys as ints (matches the TS Object.entries behaviour). Dicts
            # that already carry int keys keep them as ints.
            if isinstance(k, str):
                try:
                    n = int(k)
                    if str(n) == k:
                        key = n
                except ValueError:
                    pass
            entries.append((encode_cbor(key), encode_cbor(v)))
        # Deterministic: sort by encoded key bytes (RFC 8949 §4.2.1).
        entries.sort(key=lambda kv: kv[0])
        return _encode_head(5, len(entries)) + b''.join(k + v for k, v in entries)

    raise TypeError(f'cbor: unsupported type {type(value).__name__!r}')


# ── Decoding ─────────────────────────────────────────────────────────────────


class _DecodeState:
    __slots__ = ('buf', 'pos')

    def __init__(self, buf: bytes) -> None:
        self.buf = buf
        self.pos = 0


_HEAD_EXTRA = {24: 1, 25: 2, 26: 4, 27: 8}


def _read_head(state: _DecodeState) -> tuple:
    if state.pos >= len(state.buf):
        raise ValueError('cbor: truncated')
    initial = state.buf[state.pos]
    state.pos += 1
    major = initial >> 5
    info = initial & 0x1F
    if info < 24:
        return major, info
    n = _HEAD_EXTRA.get(info)
    if n is None:
        raise ValueError('cbor: indefinite lengths not supported')
    chunk = state.buf[state.pos:state.pos + n]
    if len(chunk) != n:
        raise ValueError('cbor: truncated')
    state.pos += n
    return major, int.from_bytes(chunk, 'big')


def _decode_item(state: _DecodeState) -> Any:
    if state.pos >= len(state.buf):
        raise ValueError('cbor: truncated')
    first = state.buf[state.pos]
    if first == 0xF6:
        state.pos += 1
        return None
    if first == 0xF5:
        state.pos += 1
        return True
    if first == 0xF4:
        state.pos += 1
        return False

    major, arg = _read_head(state)
    if major == 0:
        return arg
    if major == 1:
        return -arg - 1
    if major == 2:
        raw = state.buf[state.pos:state.pos + arg]
        if len(raw) != arg:
            raise ValueError('cbor: truncated bstr')
        state.pos += arg
        return raw
    if major == 3:
        raw = state.buf[state.pos:state.pos + arg]
        if len(raw) != arg:
            raise ValueError('cbor: truncated tstr')
        state.pos += arg
        return raw.decode('utf-8')
    if major == 4:
        return [_decode_item(state) for _ in range(arg)]
    if major == 5:
        out = {}
        for _ in range(arg):
            key = _decode_item(state)
            if isinstance(key, (bytes, bytearray)):
                # Byte-string keys become base64url text keys (matches TS).
                key = base64.urlsafe_b64encode(bytes(key)).rstrip(b'=').decode()
            out[key] = _decode_item(state)
        return out
    if major == 6:
        return CborTag(arg, _decode_item(state))
    raise ValueError(f'cbor: unsupported major type {major} / simple value')


def decode_cbor(data: bytes) -> Any:
    """Decode deterministic CBOR bytes to a value (maps decode to dict)."""
    state = _DecodeState(bytes(data))
    value = _decode_item(state)
    if state.pos != len(state.buf):
        raise ValueError('cbor: trailing bytes')
    return value
