<?php
/**
 * ltx-planid.php: spec planId for plans received as JSON (no dependencies).
 *
 * Implements docs/LTX-SPECIFICATION.md sections 4.3 (frozen v2) and 4.5 (v3):
 *
 *   v2: "LTX-" YYYYMMDD "-" HOSTSTR "-" NODESTR "-v2-"
 *       hex8(imul31 over the UTF-16 code units of JSON.stringify(plan)),
 *       with the plan in key insertion order.
 *   v3: same prefix, "-v3-" + first 8 hex of SHA-256(canonical JSON, RFC 8785).
 *
 * Reference: makePlanId in javascript/ltx/ltx-sdk.js. Golden vectors:
 * spec/golden/plan-ids.json.
 *
 * The serialiser is a standalone port of php/ltx/src/InterplanetLTX/JsJson.php
 * (the web API is deployed without the php/ltx library). PHP's json_encode
 * differs from JavaScript's JSON.stringify (integral floats print as "840.0",
 * U+2028/U+2029 are escaped) and PHP strings are UTF-8 bytes, so neither can be
 * used for the hash directly.
 *
 * Plans must be decoded with ltx_plan_decode() so that key order and the
 * {} / [] distinction survive exactly as JSON.parse would keep them.
 *
 * Used by api/ltx.php and demo/relay-server.php (demo/api/ltx-planid.php is a
 * symlink to this file, like demo/api/ltx.php).
 */

declare(strict_types=1);

/**
 * Decode a JSON plan preserving key insertion order (objects as stdClass).
 * Returns null when the text is not valid JSON.
 */
function ltx_plan_decode(string $raw): mixed
{
    try {
        return json_decode($raw, false, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        return null;
    }
}

/** Format a number exactly as JavaScript's JSON.stringify does. */
function ltx_js_number(int|float $x): string
{
    if (is_int($x)) {
        // JSON.parse yields doubles: integers beyond 2^53 lose precision there.
        if (abs($x) <= 9007199254740992) return (string)$x;
        $x = (float)$x;
    }
    if (!is_finite($x)) return 'null';
    if ($x == 0.0) return '0';

    $sign = $x < 0 ? '-' : '';
    $a = abs($x);
    // Shortest round-tripping digits, as ECMAScript Number::toString requires.
    for ($p = 1; $p <= 17; $p++) {
        $s = sprintf('%.' . ($p - 1) . 'e', $a);
        if ((float)$s === $a) break;
    }
    [$mant, $exp] = explode('e', $s);
    $digits = rtrim(str_replace('.', '', $mant), '0');
    if ($digits === '') $digits = '0';
    $n = 1 + (int)$exp; // decimal point position
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
function ltx_js_string(string $s): string
{
    return json_encode($s, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
        | JSON_UNESCAPED_LINE_TERMINATORS | JSON_INVALID_UTF8_SUBSTITUTE | JSON_THROW_ON_ERROR);
}

/** True for a JSON object value (stdClass, or a non-list PHP array). */
function ltx_is_object(mixed $v): bool
{
    return $v instanceof stdClass || (is_array($v) && !array_is_list($v));
}

/**
 * Object entries in JavaScript property order: array-index keys ("0".."4294967294")
 * first in ascending numeric order, then all other keys in insertion order.
 */
function ltx_js_entries(array|stdClass $obj): array
{
    $idx = [];
    $str = [];
    foreach ((array)$obj as $k => $val) {
        $k = (string)$k;
        if (preg_match('/^(0|[1-9][0-9]*)$/', $k) && (float)$k < 4294967295) {
            $idx[] = [$k, $val];
        } else {
            $str[] = [$k, $val];
        }
    }
    usort($idx, fn($a, $b) => (float)$a[0] <=> (float)$b[0]);
    return array_merge($idx, $str);
}

/** JSON.stringify($v) with no whitespace, preserving key insertion order. */
function ltx_js_stringify(mixed $v): string
{
    if ($v === null) return 'null';
    if ($v === true) return 'true';
    if ($v === false) return 'false';
    if (is_int($v) || is_float($v)) return ltx_js_number($v);
    if (is_string($v)) return ltx_js_string($v);
    if (ltx_is_object($v)) {
        $parts = [];
        foreach (ltx_js_entries($v) as [$k, $val]) {
            $parts[] = ltx_js_string($k) . ':' . ltx_js_stringify($val);
        }
        return '{' . implode(',', $parts) . '}';
    }
    if (is_array($v)) {
        return '[' . implode(',', array_map('ltx_js_stringify', $v)) . ']';
    }
    throw new InvalidArgumentException('ltx_js_stringify: unsupported type ' . get_debug_type($v));
}

/** UTF-16 code units of a UTF-8 string (what JavaScript's charCodeAt iterates). */
function ltx_utf16_units(string $s): array
{
    if ($s === '') return [];
    return array_values(unpack('v*', mb_convert_encoding($s, 'UTF-16LE', 'UTF-8')));
}

/** $s.slice(0, $n) with JavaScript (UTF-16 code unit) semantics. */
function ltx_utf16_slice(string $s, int $n): string
{
    $units = array_slice(ltx_utf16_units($s), 0, $n);
    if (!$units) return '';
    return mb_convert_encoding(pack('v*', ...$units), 'UTF-8', 'UTF-16LE');
}

function ltx_utf16_compare(string $a, string $b): int
{
    $ua = ltx_utf16_units($a);
    $ub = ltx_utf16_units($b);
    $n = min(count($ua), count($ub));
    for ($i = 0; $i < $n; $i++) {
        if ($ua[$i] !== $ub[$i]) return $ua[$i] <=> $ub[$i];
    }
    return count($ua) <=> count($ub);
}

/**
 * Canonical JSON as canonicalJSON() in ltx-sdk.js produces it (RFC 8785 for
 * plan data): keys sorted by UTF-16 code units, scalars as JSON.stringify.
 */
function ltx_canonical_json(mixed $v): string
{
    if (ltx_is_object($v)) {
        $arr = [];
        foreach ((array)$v as $k => $val) $arr[(string)$k] = $val;
        $keys = array_map('strval', array_keys($arr));
        usort($keys, 'ltx_utf16_compare');
        $parts = [];
        foreach ($keys as $k) {
            $parts[] = ltx_js_string($k) . ':' . ltx_canonical_json($arr[$k]);
        }
        return '{' . implode(',', $parts) . '}';
    }
    if (is_array($v)) {
        return '[' . implode(',', array_map('ltx_canonical_json', $v)) . ']';
    }
    return ltx_js_stringify($v);
}

/**
 * upgradeConfig() from ltx-sdk.js: a v1 plan (txName/rxName/delay) gains v: 2
 * and a nodes[] pair; a v2+ plan with nodes is returned unchanged.
 * Existing keys keep their position, new keys are appended, as with {...cfg}.
 */
function ltx_upgrade_config(array|stdClass $cfg): array|stdClass
{
    $a = (array)$cfg;
    $v = $a['v'] ?? null;
    $nodes = $a['nodes'] ?? null;
    if (is_numeric($v) && $v >= 2 && is_array($nodes) && count($nodes) > 0) return $cfg;
    $rx = is_string($a['rxName'] ?? null) ? strtolower($a['rxName']) : '';
    $remoteLoc = str_contains($rx, 'mars') ? 'mars' : (str_contains($rx, 'moon') ? 'moon' : 'earth');
    $a['v'] = 2;
    $a['nodes'] = [
        (object)['id' => 'N0', 'name' => ($a['txName'] ?? null) ?: 'Earth HQ', 'role' => 'HOST',
                 'delay' => 0, 'location' => 'earth'],
        (object)['id' => 'N1', 'name' => ($a['rxName'] ?? null) ?: 'Mars Hab-01', 'role' => 'PARTICIPANT',
                 'delay' => ($a['delay'] ?? null) ?: 0, 'location' => $remoteLoc],
    ];
    return (object)$a;
}

/** Name part of a planId: whitespace removed, upper-cased, first $n UTF-16 units. */
function ltx_id_part(mixed $name, int $n, string $default): string
{
    $s = (is_string($name) && $name !== '') ? $name : $default;
    return ltx_utf16_slice(mb_strtoupper(preg_replace('/\s+/u', '', $s) ?? $s, 'UTF-8'), $n);
}

/**
 * Spec planId (sections 4.3 and 4.5) of a plan decoded by ltx_plan_decode().
 * Associative arrays are accepted too, but only a stdClass decode keeps an
 * empty object ({}) distinct from an empty array ([]).
 *
 * @throws InvalidArgumentException when start is not a parseable timestamp
 */
function ltx_make_plan_id(array|stdClass $plan): string
{
    $c = ltx_upgrade_config($plan);
    $a = (array)$c;

    try {
        $dt = new DateTimeImmutable((string)($a['start'] ?? ''), new DateTimeZone('UTC'));
    } catch (Throwable) {
        throw new InvalidArgumentException('Invalid start timestamp');
    }
    $date = $dt->setTimezone(new DateTimeZone('UTC'))->format('Ymd');

    $names = [];
    foreach ((array)($a['nodes'] ?? []) as $node) {
        $names[] = ((array)$node)['name'] ?? null;
    }
    $hostStr = ltx_id_part($names[0] ?? null, 8, 'HOST');
    $nodeStr = 'RX';
    if (count($names) > 1) {
        $parts = array_map(fn($nm) => ltx_id_part($nm, 4, ''), array_slice($names, 1));
        $nodeStr = ltx_utf16_slice(implode('-', $parts), 16);
    }

    $v = $a['v'] ?? null;
    if (is_numeric($v) && $v >= 3) {
        $digest = hash('sha256', ltx_canonical_json($c));
        return sprintf('LTX-%s-%s-%s-v3-%s', $date, $hostStr, $nodeStr, substr($digest, 0, 8));
    }

    // FROZEN v2 path: imul31 over the UTF-16 code units of JSON.stringify.
    $h = 0;
    foreach (ltx_utf16_units(ltx_js_stringify($c)) as $u) {
        $h = ($h * 31 + $u) & 0xFFFFFFFF;
    }
    return sprintf('LTX-%s-%s-%s-v2-%08x', $date, $hostStr, $nodeStr, $h);
}

/**
 * Shape check for a plan_id query parameter. Host and node parts are
 * upper-cased node names (any non-whitespace text) and the hash is lowercase
 * hex after "-v2-" or "-v3-". Queries use prepared statements.
 */
function ltx_is_plan_id(string $planId): bool {
    return strlen($planId) <= 100
        && preg_match('/^LTX-[0-9]{8}-\S+-v[23]-[0-9a-f]{8}$/u', $planId) === 1;
}
