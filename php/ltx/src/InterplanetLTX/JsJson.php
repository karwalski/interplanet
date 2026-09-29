<?php
/**
 * JsJson.php — JSON serialisation byte-compatible with JavaScript.
 *
 * The frozen v2 planId (LTX-SPECIFICATION.md §4.3) hashes the UTF-16 code
 * units of JSON.stringify(plan), and canonical JSON (§4.5) serialises scalars
 * with JSON.stringify. PHP's json_encode prints integral floats as "840.0",
 * escapes U+2028/U+2029 and uses a different exponent format, so these
 * helpers follow ECMAScript (Number::toString and JSON.stringify) instead.
 *
 * JSON objects may be given as stdClass (json_decode without assoc, which
 * keeps {} and [] apart) or as associative arrays; list arrays are arrays.
 */

namespace InterplanetLTX;

final class JsJson
{
    private function __construct() {}

    /**
     * One or more characters of ECMAScript \s (WhiteSpace and LineTerminator,
     * ES2024 §12.2 and §12.3), as a PCRE pattern for UTF-8 strings.
     */
    public const WHITESPACE = '/[\x{0009}-\x{000D}\x{0020}\x{00A0}\x{1680}\x{2000}-\x{200A}'
        . '\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]+/u';

    /** Format a number exactly as JavaScript's JSON.stringify does. */
    public static function number(int|float $x): string
    {
        if (is_int($x)) return (string)$x;
        if (!is_finite($x)) return 'null';
        if ($x == 0.0) return '0';

        $sign = $x < 0 ? '-' : '';
        $a = abs($x);
        // Shortest round-tripping digits, as ECMAScript requires.
        for ($p = 1; $p <= 17; $p++) {
            $s = sprintf('%.' . ($p - 1) . 'e', $a);
            if ((float)$s === $a) break;
        }
        [$mant, $exp] = explode('e', $s);
        $digits = str_replace('.', '', $mant);
        $n = 1 + (int)$exp; // decimal point position
        $digits = rtrim($digits, '0');
        if ($digits === '') $digits = '0';
        $k = strlen($digits);

        if ($k <= $n && $n <= 21) return $sign . $digits . str_repeat('0', $n - $k);
        if ($n > 0 && $n <= 21) return $sign . substr($digits, 0, $n) . '.' . substr($digits, $n);
        if ($n > -6 && $n <= 0) return $sign . '0.' . str_repeat('0', -$n) . $digits;

        $e = $n - 1;
        $es = ($e >= 0 ? '+' : '-') . abs($e);
        if ($k === 1) return $sign . $digits . 'e' . $es;
        return $sign . $digits[0] . '.' . substr($digits, 1) . 'e' . $es;
    }

    /**
     * Quote a string exactly as JavaScript's JSON.stringify does.
     *
     * With these flags json_encode escapes as JSON.stringify does (\b \t \n
     * \f \r, other C0 controls as lowercase \u00xx, no escaping of "/", DEL
     * or U+2028/U+2029). A UTF-8 string cannot hold a lone UTF-16 surrogate,
     * but a WTF-8 string can (bytes ED A0..BF xx); JSON.stringify writes a lone
     * surrogate as a lowercase \udxxx escape, and so does this.
     */
    public static function string(string $s): string
    {
        if (mb_check_encoding($s, 'UTF-8')) {
            return json_encode($s, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
                | JSON_UNESCAPED_LINE_TERMINATORS | JSON_THROW_ON_ERROR);
        }
        return self::wtf8String($s);
    }

    /**
     * JSON.stringify of a string that is not valid UTF-8: decode it as WTF-8
     * (lone surrogates escaped, a CESU-8 surrogate pair joined into one code
     * point); any other invalid byte throws.
     */
    private static function wtf8String(string $s): string
    {
        $out = '"';
        $text = '';
        $len = strlen($s);
        for ($i = 0; $i < $len; $i += $n) {
            $b = ord($s[$i]);
            $n = $b < 0x80 ? 1 : ($b >= 0xF0 ? 4 : ($b >= 0xE0 ? 3 : 2));
            $chunk = substr($s, $i, $n);
            if (strlen($chunk) === $n && mb_check_encoding($chunk, 'UTF-8')) {
                $text .= $chunk;
            } elseif ($n === 3 && strlen($chunk) === 3 && $b === 0xED
                && (ord($chunk[1]) & 0xE0) === 0xA0 && (ord($chunk[2]) & 0xC0) === 0x80) {
                $unit = 0xD000 | ((ord($chunk[1]) & 0x3F) << 6) | (ord($chunk[2]) & 0x3F);
                $next = substr($s, $i + 3, 3);
                if ($unit < 0xDC00 && strlen($next) === 3 && ord($next[0]) === 0xED
                    && (ord($next[1]) & 0xF0) === 0xB0 && (ord($next[2]) & 0xC0) === 0x80) {
                    $low = 0xD000 | ((ord($next[1]) & 0x3F) << 6) | (ord($next[2]) & 0x3F);
                    $text .= mb_chr(0x10000 + (($unit - 0xD800) << 10) + ($low - 0xDC00), 'UTF-8');
                    $n = 6;
                } else {
                    $out .= substr(self::string($text), 1, -1) . sprintf('\\u%04x', $unit);
                    $text = '';
                }
            } else {
                throw new \JsonException('Malformed UTF-8 characters, possibly incorrectly encoded');
            }
        }
        return $out . substr(self::string($text), 1, -1) . '"';
    }

    /** True for a JSON object value (stdClass or non-list array). */
    public static function isObject(mixed $v): bool
    {
        return $v instanceof \stdClass || (is_array($v) && !array_is_list($v));
    }

    /** JSON.stringify($v) with no whitespace, preserving key insertion order. */
    public static function stringify(mixed $v): string
    {
        if ($v === null) return 'null';
        if ($v === true) return 'true';
        if ($v === false) return 'false';
        if (is_int($v) || is_float($v)) return self::number($v);
        if (is_string($v)) return self::string($v);
        if (self::isObject($v)) {
            $parts = [];
            foreach ((array)$v as $k => $val) {
                $parts[] = self::string((string)$k) . ':' . self::stringify($val);
            }
            return '{' . implode(',', $parts) . '}';
        }
        if (is_array($v)) {
            return '[' . implode(',', array_map([self::class, 'stringify'], $v)) . ']';
        }
        throw new \InvalidArgumentException('stringify: unsupported type ' . get_debug_type($v));
    }

    /**
     * RFC 8785 canonical JSON as produced by canonicalJSON() in ltx-sdk.js:
     * object keys sorted by UTF-16 code units, scalars as JSON.stringify.
     */
    public static function canonical(mixed $v): string
    {
        if (self::isObject($v)) {
            $arr = (array)$v;
            $keys = array_map('strval', array_keys($arr));
            usort($keys, fn($a, $b) => self::compareUtf16($a, $b));
            $parts = [];
            foreach ($keys as $k) {
                $parts[] = self::string($k) . ':' . self::canonical($arr[$k]);
            }
            return '{' . implode(',', $parts) . '}';
        }
        if (is_array($v)) {
            return '[' . implode(',', array_map([self::class, 'canonical'], $v)) . ']';
        }
        return self::stringify($v);
    }

    /** UTF-16 code units of a UTF-8 string (what JavaScript's charCodeAt iterates). */
    public static function utf16Units(string $s): array
    {
        if ($s === '') return [];
        return array_values(unpack('v*', mb_convert_encoding($s, 'UTF-16LE', 'UTF-8')));
    }

    /**
     * $s.slice(0, $n) with JavaScript (UTF-16 code unit) semantics, as UTF-8.
     * A cut that splits a surrogate pair leaves a lone surrogate, which UTF-8
     * cannot hold: it becomes U+FFFD, as when JavaScript encodes the string
     * to UTF-8 (spec/golden/plan-id-prefixes.json planIdUtf8).
     * mb_convert_encoding would substitute '?' instead.
     */
    public static function utf16Slice(string $s, int $n): string
    {
        $units = array_slice(self::utf16Units($s), 0, $n);
        $out = '';
        $count = count($units);
        for ($i = 0; $i < $count; $i++) {
            $u = $units[$i];
            if ($u >= 0xD800 && $u <= 0xDBFF && $i + 1 < $count
                && $units[$i + 1] >= 0xDC00 && $units[$i + 1] <= 0xDFFF) {
                $out .= mb_chr(0x10000 + (($u - 0xD800) << 10) + ($units[++$i] - 0xDC00), 'UTF-8');
            } elseif ($u >= 0xD800 && $u <= 0xDFFF) {
                $out .= "\u{FFFD}";
            } else {
                $out .= mb_chr($u, 'UTF-8');
            }
        }
        return $out;
    }

    private static function compareUtf16(string $a, string $b): int
    {
        $ua = self::utf16Units($a);
        $ub = self::utf16Units($b);
        $n = min(count($ua), count($ub));
        for ($i = 0; $i < $n; $i++) {
            if ($ua[$i] !== $ub[$i]) return $ua[$i] <=> $ub[$i];
        }
        return count($ua) <=> count($ub);
    }
}
