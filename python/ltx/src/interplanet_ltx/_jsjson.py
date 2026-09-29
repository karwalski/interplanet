"""
interplanet_ltx._jsjson — JSON serialisation byte-compatible with JavaScript.

The frozen v2 planId (LTX-SPECIFICATION.md §4.3) hashes the UTF-16 code units
of ``JSON.stringify(plan)``, and canonical JSON (§4.5) serialises scalars with
``JSON.stringify``. Python's ``json.dumps`` differs in three ways that change
hashes: it escapes non-ASCII by default, prints integral floats as ``840.0``
and uses a different exponent format. The helpers here follow ECMAScript
(Number::toString and JSON.stringify's QuoteJSONString) instead.
"""

import json
import math
import re
from decimal import Decimal
from typing import Any

_LONE_SURROGATE = re.compile('[\ud800-\udfff]')


def js_number(x: Any) -> str:
    """Format a number exactly as JavaScript's JSON.stringify does."""
    if isinstance(x, bool):
        return 'true' if x else 'false'
    if isinstance(x, int):
        return str(x)
    if not math.isfinite(x):
        return 'null'
    if x == 0:
        return '0'
    sign = '-' if x < 0 else ''
    # repr() gives the shortest round-tripping digits, like ECMAScript.
    _, digits_t, exp = Decimal(repr(abs(x))).as_tuple()
    digits = ''.join(str(d) for d in digits_t).rstrip('0') or '0'
    exp += len(digits_t) - len(digits)
    k = len(digits)
    n = exp + k  # decimal point position (ECMAScript Number::toString "n")
    if k <= n <= 21:
        return sign + digits + '0' * (n - k)
    if 0 < n <= 21:
        return sign + digits[:n] + '.' + digits[n:]
    if -6 < n <= 0:
        return sign + '0.' + '0' * (-n) + digits
    e = n - 1
    es = ('+' if e >= 0 else '-') + str(abs(e))
    if k == 1:
        return sign + digits + 'e' + es
    return sign + digits[0] + '.' + digits[1:] + 'e' + es


def js_string(s: str) -> str:
    """Quote a string exactly as JavaScript's JSON.stringify does."""
    out = json.dumps(s, ensure_ascii=False)
    # Well-formed JSON.stringify escapes lone surrogates as \\udXXX.
    return _LONE_SURROGATE.sub(lambda m: '\\u%04x' % ord(m.group(0)), out)


def js_stringify(obj: Any) -> str:
    """JSON.stringify(obj) with no whitespace, preserving dict insertion order."""
    if obj is None:
        return 'null'
    if isinstance(obj, (bool, int, float)):
        return js_number(obj)
    if isinstance(obj, str):
        return js_string(obj)
    if isinstance(obj, (list, tuple)):
        return '[' + ','.join(js_stringify(v) for v in obj) + ']'
    if isinstance(obj, dict):
        return '{' + ','.join(js_string(str(k)) + ':' + js_stringify(v)
                              for k, v in obj.items()) + '}'
    raise TypeError(f'js_stringify: unsupported type {type(obj).__name__!r}')


def utf16_units(s: str) -> list:
    """UTF-16 code units of s (what JavaScript's charCodeAt iterates)."""
    b = s.encode('utf-16-le', 'surrogatepass')
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


def utf16_sort_key(s: str) -> list:
    """Sort key matching JavaScript's default Array.prototype.sort on strings."""
    return utf16_units(s)


def utf16_slice(s: str, end: int) -> str:
    """s.slice(0, end) with JavaScript (UTF-16 code unit) semantics."""
    b = s.encode('utf-16-le', 'surrogatepass')[:2 * end]
    return b.decode('utf-16-le', 'surrogatepass')
