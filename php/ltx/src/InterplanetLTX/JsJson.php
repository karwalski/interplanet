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

    /** Quote a string exactly as JavaScript's JSON.stringify does. */
    public static function string(string $s): string
    {
        return json_encode($s, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
            | JSON_UNESCAPED_LINE_TERMINATORS | JSON_THROW_ON_ERROR);
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

    /** $s.slice(0, $n) with JavaScript (UTF-16 code unit) semantics. */
    public static function utf16Slice(string $s, int $n): string
    {
        $units = array_slice(self::utf16Units($s), 0, $n);
        if (!$units) return '';
        return mb_convert_encoding(pack('v*', ...$units), 'UTF-8', 'UTF-16LE');
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
