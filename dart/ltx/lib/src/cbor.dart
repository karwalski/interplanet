// cbor.dart — Minimal deterministic CBOR (RFC 8949) for COSE_Sign1
// LTX v1.1 (Epic 72 cascade). Zero-dependency subset.
//
// Supported: unsigned/negative integers, byte strings, text strings, arrays,
// maps, booleans, null, and tags. Encoding follows the RFC 8949 §4.2.1 core
// deterministic profile: definite lengths only, shortest-form integer heads,
// map keys sorted bytewise by their encoded form. Floats, indefinite lengths
// and trailing bytes are rejected on decode.

import 'dart:convert';
import 'dart:typed_data';

import 'security.dart' show b64UrlEncode;

/// Tagged value wrapper (major type 6).
class CborTag {
  final int tag;
  final dynamic value;
  const CborTag(this.tag, this.value);
}

// ── Encoding ────────────────────────────────────────────────────────────────

Uint8List _encodeHead(int major, int arg) {
  if (arg < 0) throw const FormatException('cbor: invalid length/argument');
  if (arg < 24) return Uint8List.fromList([(major << 5) | arg]);
  if (arg < 0x100) return Uint8List.fromList([(major << 5) | 24, arg]);
  if (arg < 0x10000) {
    return Uint8List.fromList([(major << 5) | 25, arg >> 8, arg & 0xff]);
  }
  if (arg < 0x100000000) {
    return Uint8List.fromList([
      (major << 5) | 26,
      (arg >> 24) & 0xff,
      (arg >> 16) & 0xff,
      (arg >> 8) & 0xff,
      arg & 0xff,
    ]);
  }
  final b = Uint8List(9);
  b[0] = (major << 5) | 27;
  for (int i = 0; i < 8; i++) {
    b[8 - i] = (arg >> (8 * i)) & 0xff;
  }
  return b;
}

/// Encode a value to deterministic CBOR bytes.
/// Uint8List ⇄ bstr, String ⇄ tstr, int ⇄ major 0/1, List ⇄ array,
/// Map ⇄ map (int or String keys), CborTag ⇄ tag, bool/null ⇄ simple.
Uint8List encodeCbor(dynamic value) {
  final out = BytesBuilder();
  _encodeInto(value, out);
  return out.toBytes();
}

void _encodeInto(dynamic value, BytesBuilder out) {
  if (value == null) {
    out.addByte(0xf6);
    return;
  }
  if (value is bool) {
    out.addByte(value ? 0xf5 : 0xf4);
    return;
  }
  if (value is int) {
    out.add(value >= 0 ? _encodeHead(0, value) : _encodeHead(1, -value - 1));
    return;
  }
  if (value is String) {
    final bytes = utf8.encode(value);
    out.add(_encodeHead(3, bytes.length));
    out.add(bytes);
    return;
  }
  if (value is Uint8List) {
    out.add(_encodeHead(2, value.length));
    out.add(value);
    return;
  }
  if (value is CborTag) {
    out.add(_encodeHead(6, value.tag));
    _encodeInto(value.value, out);
    return;
  }
  if (value is List) {
    out.add(_encodeHead(4, value.length));
    for (final v in value) {
      _encodeInto(v, out);
    }
    return;
  }
  if (value is Map) {
    // Deterministic: sort entries by encoded key bytes (RFC 8949 §4.2.1).
    final encoded = <List<Uint8List>>[];
    value.forEach((k, v) {
      encoded.add([encodeCbor(k), encodeCbor(v)]);
    });
    encoded.sort((a, b) => _compareBytes(a[0], b[0]));
    out.add(_encodeHead(5, encoded.length));
    for (final e in encoded) {
      out.add(e[0]);
      out.add(e[1]);
    }
    return;
  }
  throw FormatException('cbor: unsupported type ${value.runtimeType}');
}

int _compareBytes(Uint8List a, Uint8List b) {
  final n = a.length < b.length ? a.length : b.length;
  for (int i = 0; i < n; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

// ── Decoding ────────────────────────────────────────────────────────────────

class _DecodeState {
  final Uint8List buf;
  int pos = 0;
  _DecodeState(this.buf);
}

List<int> _readHead(_DecodeState s) {
  if (s.pos >= s.buf.length) throw const FormatException('cbor: truncated');
  final initial = s.buf[s.pos];
  s.pos += 1;
  final major = initial >> 5;
  final info = initial & 0x1f;
  if (info < 24) return [major, info];
  if (info == 24) {
    if (s.pos + 1 > s.buf.length) throw const FormatException('cbor: truncated');
    final v = s.buf[s.pos];
    s.pos += 1;
    return [major, v];
  }
  if (info == 25) {
    if (s.pos + 2 > s.buf.length) throw const FormatException('cbor: truncated');
    final v = (s.buf[s.pos] << 8) | s.buf[s.pos + 1];
    s.pos += 2;
    return [major, v];
  }
  if (info == 26) {
    if (s.pos + 4 > s.buf.length) throw const FormatException('cbor: truncated');
    int v = 0;
    for (int i = 0; i < 4; i++) {
      v = (v << 8) | s.buf[s.pos + i];
    }
    s.pos += 4;
    return [major, v];
  }
  if (info == 27) {
    if (s.pos + 8 > s.buf.length) throw const FormatException('cbor: truncated');
    int v = 0;
    for (int i = 0; i < 8; i++) {
      v = (v << 8) | s.buf[s.pos + i];
    }
    s.pos += 8;
    if (v < 0) throw const FormatException('cbor: integer too large');
    return [major, v];
  }
  throw const FormatException('cbor: indefinite lengths not supported');
}

dynamic _decodeItem(_DecodeState s) {
  if (s.pos >= s.buf.length) throw const FormatException('cbor: truncated');
  final first = s.buf[s.pos];
  if (first == 0xf6) {
    s.pos += 1;
    return null;
  }
  if (first == 0xf5) {
    s.pos += 1;
    return true;
  }
  if (first == 0xf4) {
    s.pos += 1;
    return false;
  }

  final head = _readHead(s);
  final major = head[0];
  final arg = head[1];
  switch (major) {
    case 0:
      return arg;
    case 1:
      return -arg - 1;
    case 2:
      if (s.pos + arg > s.buf.length) {
        throw const FormatException('cbor: truncated bstr');
      }
      final bytes = Uint8List.sublistView(s.buf, s.pos, s.pos + arg);
      s.pos += arg;
      return Uint8List.fromList(bytes);
    case 3:
      if (s.pos + arg > s.buf.length) {
        throw const FormatException('cbor: truncated tstr');
      }
      final str = utf8.decode(s.buf.sublist(s.pos, s.pos + arg));
      s.pos += arg;
      return str;
    case 4:
      final out = <dynamic>[];
      for (int i = 0; i < arg; i++) {
        out.add(_decodeItem(s));
      }
      return out;
    case 5:
      final map = <dynamic, dynamic>{};
      for (int i = 0; i < arg; i++) {
        final k = _decodeItem(s);
        map[k is Uint8List ? b64UrlEncode(k) : k] = _decodeItem(s);
      }
      return map;
    case 6:
      return CborTag(arg, _decodeItem(s));
    default:
      throw FormatException('cbor: unsupported major type $major / simple value');
  }
}

/// Decode deterministic CBOR bytes to a value (maps decode to Map).
/// Rejects floats, indefinite lengths and trailing bytes.
dynamic decodeCbor(Uint8List bytes) {
  final s = _DecodeState(bytes);
  final value = _decodeItem(s);
  if (s.pos != s.buf.length) throw const FormatException('cbor: trailing bytes');
  return value;
}
