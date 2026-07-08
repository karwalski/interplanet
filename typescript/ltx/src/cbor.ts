/**
 * @interplanet/ltx — Minimal deterministic CBOR (RFC 8949)
 * Story 70.1 — zero-dependency subset for COSE_Sign1 (RFC 9052)
 *
 * Supported: unsigned/negative integers, byte strings, text strings, arrays,
 * maps, booleans, null, and tags. Encoding follows the RFC 8949 §4.2.1 core
 * deterministic profile: definite lengths only, shortest-form integer heads,
 * map keys sorted bytewise by their encoded form.
 *
 * Values map JS ⇄ CBOR: number (integer only) ⇄ major 0/1, Uint8Array/Buffer
 * ⇄ major 2, string ⇄ major 3, Array ⇄ major 4, plain object or Map ⇄ major 5,
 * { tag, value } via CborTag ⇄ major 6, true/false/null ⇄ major 7.
 */

/** Tagged value wrapper (major type 6). */
export class CborTag {
  constructor(public tag: number, public value: unknown) {}
}

// ── Encoding ─────────────────────────────────────────────────────────────────

function encodeHead(major: number, arg: number): Buffer {
  if (!Number.isSafeInteger(arg) || arg < 0) throw new Error('cbor: invalid length/argument');
  if (arg < 24) return Buffer.from([(major << 5) | arg]);
  if (arg < 0x100) return Buffer.from([(major << 5) | 24, arg]);
  if (arg < 0x10000) {
    const b = Buffer.alloc(3);
    b[0] = (major << 5) | 25;
    b.writeUInt16BE(arg, 1);
    return b;
  }
  if (arg < 0x100000000) {
    const b = Buffer.alloc(5);
    b[0] = (major << 5) | 26;
    b.writeUInt32BE(arg, 1);
    return b;
  }
  const b = Buffer.alloc(9);
  b[0] = (major << 5) | 27;
  b.writeBigUInt64BE(BigInt(arg), 1);
  return b;
}

/** Encode a value to deterministic CBOR bytes. */
export function encodeCbor(value: unknown): Buffer {
  if (value === null) return Buffer.from([0xf6]);
  if (value === true) return Buffer.from([0xf5]);
  if (value === false) return Buffer.from([0xf4]);

  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value)) throw new Error('cbor: only integers supported');
    return value >= 0 ? encodeHead(0, value) : encodeHead(1, -value - 1);
  }

  if (typeof value === 'string') {
    const bytes = Buffer.from(value, 'utf8');
    return Buffer.concat([encodeHead(3, bytes.length), bytes]);
  }

  if (value instanceof Uint8Array) {
    const bytes = Buffer.from(value);
    return Buffer.concat([encodeHead(2, bytes.length), bytes]);
  }

  if (value instanceof CborTag) {
    return Buffer.concat([encodeHead(6, value.tag), encodeCbor(value.value)]);
  }

  if (Array.isArray(value)) {
    const parts = value.map(encodeCbor);
    return Buffer.concat([encodeHead(4, value.length), ...parts]);
  }

  if (value instanceof Map || (typeof value === 'object' && value !== null)) {
    const entries: Array<[unknown, unknown]> = value instanceof Map
      ? [...value.entries()]
      : Object.entries(value as Record<string, unknown>).map(([k, v]) => {
          // COSE header labels are integers; encode numeric-looking keys as ints.
          const n = Number(k);
          return [Number.isSafeInteger(n) && String(n) === k ? n : k, v] as [unknown, unknown];
        });
    // Deterministic: sort by encoded key bytes (RFC 8949 §4.2.1).
    const encoded = entries.map(([k, v]) => [encodeCbor(k), encodeCbor(v)] as [Buffer, Buffer]);
    encoded.sort((a, b) => Buffer.compare(a[0], b[0]));
    return Buffer.concat([encodeHead(5, encoded.length), ...encoded.flat()]);
  }

  throw new Error(`cbor: unsupported type ${typeof value}`);
}

// ── Decoding ─────────────────────────────────────────────────────────────────

interface DecodeState { buf: Buffer; pos: number }

function readHead(s: DecodeState): { major: number; arg: number } {
  const initial = s.buf[s.pos];
  if (initial === undefined) throw new Error('cbor: truncated');
  s.pos += 1;
  const major = initial >> 5;
  const info = initial & 0x1f;
  if (info < 24) return { major, arg: info };
  if (info === 24) { const v = s.buf[s.pos]; s.pos += 1; return { major, arg: v }; }
  if (info === 25) { const v = s.buf.readUInt16BE(s.pos); s.pos += 2; return { major, arg: v }; }
  if (info === 26) { const v = s.buf.readUInt32BE(s.pos); s.pos += 4; return { major, arg: v }; }
  if (info === 27) {
    const v = s.buf.readBigUInt64BE(s.pos);
    s.pos += 8;
    if (v > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error('cbor: integer too large');
    return { major, arg: Number(v) };
  }
  throw new Error('cbor: indefinite lengths not supported');
}

function decodeItem(s: DecodeState): unknown {
  const first = s.buf[s.pos];
  if (first === 0xf6) { s.pos += 1; return null; }
  if (first === 0xf5) { s.pos += 1; return true; }
  if (first === 0xf4) { s.pos += 1; return false; }

  const { major, arg } = readHead(s);
  switch (major) {
    case 0: return arg;
    case 1: return -arg - 1;
    case 2: {
      const bytes = s.buf.slice(s.pos, s.pos + arg);
      if (bytes.length !== arg) throw new Error('cbor: truncated bstr');
      s.pos += arg;
      return bytes;
    }
    case 3: {
      const bytes = s.buf.slice(s.pos, s.pos + arg);
      if (bytes.length !== arg) throw new Error('cbor: truncated tstr');
      s.pos += arg;
      return bytes.toString('utf8');
    }
    case 4: {
      const out: unknown[] = [];
      for (let i = 0; i < arg; i++) out.push(decodeItem(s));
      return out;
    }
    case 5: {
      const map = new Map<unknown, unknown>();
      for (let i = 0; i < arg; i++) {
        const k = decodeItem(s);
        map.set(k instanceof Uint8Array ? Buffer.from(k).toString('base64url') : k, decodeItem(s));
      }
      return map;
    }
    case 6: return new CborTag(arg, decodeItem(s));
    default: throw new Error(`cbor: unsupported major type ${major} / simple value`);
  }
}

/** Decode deterministic CBOR bytes to a value (maps decode to Map). */
export function decodeCbor(bytes: Uint8Array | Buffer): unknown {
  const s: DecodeState = { buf: Buffer.from(bytes as Uint8Array), pos: 0 };
  const value = decodeItem(s);
  if (s.pos !== s.buf.length) throw new Error('cbor: trailing bytes');
  return value;
}
