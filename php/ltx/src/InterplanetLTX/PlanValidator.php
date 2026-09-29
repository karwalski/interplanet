<?php
/**
 * PlanValidator.php — Plan validation
 * LTX-SPECIFICATION.md §4 (wire format, spec/ltx-schema.json), §3.5 (reserved
 * streams) and §7 (reserved branching). Mirrors validatePlan() in
 * javascript/ltx/ltx-sdk.js and typescript/ltx/src/validate.ts.
 */

namespace InterplanetLTX;

final class PlanValidator
{
    const SEG_TYPES = ['PLAN_CONFIRM', 'TX', 'RX', 'CAUCUS', 'BUFFER', 'MERGE'];
    /** Every segment type the reference SDKs handle (core §3.4 + auxiliary). */
    const PLAN_SEGMENT_TYPES = [...self::SEG_TYPES, 'SPEAK', 'REST', 'PAD', 'OPEN', 'RELAY'];
    const PLAN_MODES = ['LTX', 'LTX-LIVE', 'LTX-RELAY', 'LTX-ASYNC'];
    /** Fields that exist only in v3 plans (§4.4); MUST NOT appear in v2 (§4.3). */
    const V3_ONLY_FIELDS = ['delays', 'planVersion', 'prevPlanHash', 'questions', 'actions', 'streams'];
    /** Reserved branching identifiers (§7): MUST be absent from plans and segments. */
    const RESERVED_BRANCH_PLAN_FIELDS = ['branches', 'branching'];
    const RESERVED_BRANCH_SEGMENT_FIELDS = ['branch'];
    /** Reserved streams identifiers (§3.5): plan streams[] empty, no segment stream. */
    const RESERVED_STREAM_SEGMENT_FIELDS = ['stream'];

    private function __construct() {}

    /**
     * Validate a v2 or v3 plan (associative array or stdClass, as decoded from
     * JSON). Pure; never throws.
     *
     * Error codes: not_an_object, invalid_version, missing_field, invalid_field,
     * invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
     * duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
     * invalid_delays, reserved_streams, reserved_branching.
     *
     * @return array{valid: bool, errors: list<array{code: string, path: string, message: string}>}
     */
    public static function validate(mixed $plan): array
    {
        $errors = [];
        $err = function (string $code, string $path, string $message) use (&$errors): void {
            $errors[] = ['code' => $code, 'path' => $path, 'message' => $message];
        };
        $plan = self::normalize($plan);
        if (!self::isObj($plan)) {
            $err('not_an_object', '', 'plan must be an object');
            return ['valid' => false, 'errors' => $errors];
        }
        $has = fn(string $k) => array_key_exists($k, $plan);

        $v = $plan['v'] ?? null;
        $version = (self::isNum($v) && ($v == 2 || $v == 3)) ? (int)$v : null;
        if ($version === null) $err('invalid_version', 'v', 'v must be 2 or 3');
        foreach (['title', 'start', 'quantum', 'mode', 'nodes', 'segments'] as $f) {
            if (!$has($f)) $err('missing_field', $f, "$f is required");
        }
        if ($has('title') && !is_string($plan['title'])) $err('invalid_field', 'title', 'title must be a string');
        if ($has('start') && !self::validStart($plan['start'])) {
            $err('invalid_field', 'start', 'start must be an ISO 8601 UTC timestamp');
        }
        $q = $plan['quantum'] ?? null;
        if ($has('quantum') && !(self::isInteger($q) && $q >= 1 && $q <= 60)) {
            $err('invalid_quantum', 'quantum', 'quantum must be an integer 1..60 minutes (§3.2)');
        }
        if ($has('mode') && !in_array($plan['mode'], self::PLAN_MODES, true)) {
            $err('invalid_mode', 'mode', 'mode must be one of ' . implode(', ', self::PLAN_MODES));
        }

        $ids = [];
        if ($has('nodes')) {
            $nodes = $plan['nodes'];
            if (!is_array($nodes) || !array_is_list($nodes) || count($nodes) === 0) {
                $err('invalid_nodes', 'nodes', 'nodes must be a non-empty array');
            } else {
                $hosts = 0;
                foreach ($nodes as $i => $n) {
                    if (!self::isObj($n) || !is_string($n['id'] ?? null) || $n['id'] === '' ||
                        str_contains($n['id'], '|') || !is_string($n['name'] ?? null) ||
                        !in_array($n['role'] ?? null, ['HOST', 'PARTICIPANT', 'OBSERVER'], true) ||
                        !self::isNum($n['delay'] ?? null) || !($n['delay'] >= 0)) {
                        $err('invalid_nodes', "nodes[$i]", 'node needs id (no "|"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0');
                        continue;
                    }
                    if (isset($ids[$n['id']])) $err('duplicate_node_id', "nodes[$i].id", "duplicate node id {$n['id']}");
                    $ids[$n['id']] = true;
                    if ($n['role'] === 'HOST') $hosts++;
                }
                $h = $nodes[0];
                if ($hosts !== 1 || !self::isObj($h) || ($h['role'] ?? null) !== 'HOST' ||
                    !self::isNum($h['delay'] ?? null) || $h['delay'] != 0) {
                    $err('invalid_host', 'nodes[0]', 'exactly one HOST, first in nodes[], with delay 0 (§3.1)');
                }
            }
        }

        if ($has('segments')) {
            $segments = $plan['segments'];
            if (!is_array($segments) || !array_is_list($segments)) {
                $err('invalid_segment', 'segments', 'segments must be an array');
            } else {
                foreach ($segments as $i => $s) {
                    if (!self::isObj($s) || !in_array($s['type'] ?? null, self::PLAN_SEGMENT_TYPES, true) ||
                        !(self::isInteger($s['q'] ?? null) && $s['q'] >= 1)) {
                        $err('invalid_segment', "segments[$i]", 'segment needs a known type and integer q >= 1');
                        continue;
                    }
                    if (array_key_exists('speaker', $s) &&
                        !(is_string($s['speaker']) && isset($ids[$s['speaker']]))) {
                        $sp = $s['speaker'] === null ? 'null' : (string)(is_scalar($s['speaker']) ? $s['speaker'] : 'object');
                        $err('unknown_speaker', "segments[$i].speaker", "speaker $sp is not a node id");
                    }
                }
            }
        }

        if ($version === 2) {
            foreach (self::V3_ONLY_FIELDS as $f) {
                if ($has($f)) $err('v3_field_in_v2', $f, "$f is a v3 field and MUST NOT appear in a v2 plan (§4.3)");
            }
        } elseif ($version === 3) {
            if ($has('delays')) {
                $d = $plan['delays'];
                if (!(self::isObj($d) || $d === [])) {
                    $err('invalid_delays', 'delays', 'delays must be an object');
                } else {
                    foreach ($d as $k => $val) {
                        $parts = explode('|', (string)$k);
                        if (count($parts) !== 2 || !(strcmp($parts[0], $parts[1]) < 0) ||
                            ($ids && (!isset($ids[$parts[0]]) || !isset($ids[$parts[1]]))) ||
                            !self::isNum($val) || !($val >= 0)) {
                            $err('invalid_delays', "delays.$k", 'key must be two known node ids joined by "|" in sorted order; value >= 0 (§3.7.2)');
                        }
                    }
                }
            }
            $pv = $plan['planVersion'] ?? null;
            if ($has('planVersion') && !(self::isInteger($pv) && $pv >= 1)) {
                $err('invalid_field', 'planVersion', 'planVersion must be an integer >= 1');
            }
            $ph = $plan['prevPlanHash'] ?? null;
            if ($has('prevPlanHash') && !(is_string($ph) && preg_match('/\A[0-9a-f]{64}\z/', $ph))) {
                $err('invalid_field', 'prevPlanHash', 'prevPlanHash must be 64 lowercase hex characters');
            }
            foreach (['questions', 'actions'] as $f) {
                if ($has($f) && !(is_array($plan[$f]) && array_is_list($plan[$f]))) {
                    $err('invalid_field', $f, "$f must be an array");
                }
            }
        }

        foreach (self::reservedFieldErrors($plan) as $e) $errors[] = $e;
        return ['valid' => count($errors) === 0, 'errors' => $errors];
    }

    /** Reserved-field violations only (§3.5 streams, §7 branching). */
    public static function reservedFieldErrors(mixed $plan): array
    {
        $plan = self::normalize($plan);
        $errors = [];
        if (!self::isObj($plan)) return $errors;
        if (array_key_exists('streams', $plan) &&
            !(is_array($plan['streams']) && count($plan['streams']) === 0)) {
            $errors[] = ['code' => 'reserved_streams', 'path' => 'streams',
                'message' => 'streams[] is reserved (§3.5) and MUST be absent or empty'];
        }
        foreach (self::RESERVED_BRANCH_PLAN_FIELDS as $f) {
            if (array_key_exists($f, $plan)) {
                $errors[] = ['code' => 'reserved_branching', 'path' => $f,
                    'message' => "$f is reserved for branching (§7, not yet implemented) and MUST be absent"];
            }
        }
        $segments = (is_array($plan['segments'] ?? null) && array_is_list($plan['segments'])) ? $plan['segments'] : [];
        foreach ($segments as $i => $s) {
            if (!self::isObj($s)) continue;
            foreach (self::RESERVED_STREAM_SEGMENT_FIELDS as $f) {
                if (array_key_exists($f, $s)) {
                    $errors[] = ['code' => 'reserved_streams', 'path' => "segments[$i].$f",
                        'message' => "segment $f is reserved (§3.5) and MUST be absent"];
                }
            }
            foreach (self::RESERVED_BRANCH_SEGMENT_FIELDS as $f) {
                if (array_key_exists($f, $s)) {
                    $errors[] = ['code' => 'reserved_branching', 'path' => "segments[$i].$f",
                        'message' => "segment $f is reserved for branching (§7) and MUST be absent"];
                }
            }
        }
        return $errors;
    }

    /** stdClass trees become associative arrays (an empty {} becomes []). */
    private static function normalize(mixed $v): mixed
    {
        if ($v instanceof \stdClass) $v = (array)$v;
        if (is_array($v)) {
            foreach ($v as $k => $val) $v[$k] = self::normalize($val);
        }
        return $v;
    }

    /** A JSON object after normalize(): non-list array (or empty array). */
    private static function isObj(mixed $v): bool
    {
        return is_array($v) && (!array_is_list($v) || $v === []);
    }

    private static function isNum(mixed $v): bool
    {
        return (is_int($v) || is_float($v)) && !(is_float($v) && is_nan($v));
    }

    /** JavaScript Number.isInteger */
    private static function isInteger(mixed $v): bool
    {
        return is_int($v) || (is_float($v) && is_finite($v) && floor($v) == $v);
    }

    private static function validStart(mixed $v): bool
    {
        if (!is_string($v)) return false;
        return (bool)preg_match('/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})\z/', $v)
            && strtotime($v) !== false;
    }
}
