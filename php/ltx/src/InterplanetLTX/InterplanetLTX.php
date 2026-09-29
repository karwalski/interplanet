<?php
/**
 * InterplanetLTX.php — PHP LTX library static facade
 * Story 33.4 — PHP 8.1+ · No external dependencies
 *
 * Pure port of ltx-sdk.js (js/ltx-sdk.js).
 */

namespace InterplanetLTX;

class InterplanetLTX
{
    const VERSION         = '1.0.0';
    const DEFAULT_QUANTUM = 5;
    const DEFAULT_SEG_COUNT = 7;
    const DEFAULT_API_BASE  = 'https://interplanet.live/api/ltx.php';

    const DEFAULT_SEGMENTS = [
        ['type' => 'PLAN_CONFIRM', 'q' => 2],
        ['type' => 'TX',           'q' => 2],
        ['type' => 'RX',           'q' => 2],
        ['type' => 'CAUCUS',       'q' => 2],
        ['type' => 'TX',           'q' => 2],
        ['type' => 'RX',           'q' => 2],
        ['type' => 'BUFFER',       'q' => 1],
    ];

    /* ── Plan creation ──────────────────────────────────────────────────── */

    /**
     * Create a plan with default Earth HQ → Mars Hab-01 nodes and segments.
     *
     * @param string|null $title     Session title (null → "LTX Session")
     * @param string      $start     ISO-8601 UTC start time
     * @param int         $delaySec  One-way light-travel delay in seconds
     */
    public static function createPlan(
        ?string $title    = null,
        string  $start    = '',
        int     $delaySec = 0
    ): LtxPlan {
        $plan           = new LtxPlan();
        $plan->v        = 2;
        $plan->title    = $title ?: 'LTX Session';
        $plan->start    = $start;
        $plan->quantum  = self::DEFAULT_QUANTUM;
        $plan->mode     = 'LTX';
        $plan->nodes    = [
            new LtxNode(id: 'N0', name: 'Earth HQ',    role: 'HOST',        delay: 0,         location: 'earth'),
            new LtxNode(id: 'N1', name: 'Mars Hab-01', role: 'PARTICIPANT', delay: $delaySec, location: 'mars'),
        ];
        $plan->segments = array_map(
            fn(array $s) => new LtxSegmentTemplate(type: $s['type'], q: $s['q']),
            self::DEFAULT_SEGMENTS
        );
        return $plan;
    }

    /**
     * Merge a partial config array into a full LtxPlan with defaults filled in.
     * Accepts any associative array; merges with createPlan defaults.
     */
    public static function upgradeConfig(array $config): LtxPlan
    {
        $plan = self::createPlan(
            $config['title'] ?? null,
            $config['start'] ?? '',
            0
        );
        if (isset($config['quantum']))  $plan->quantum = (int)$config['quantum'];
        if (isset($config['mode']))     $plan->mode    = (string)$config['mode'];

        if (isset($config['nodes']) && is_array($config['nodes'])) {
            $plan->nodes = array_map(fn(array $n) => new LtxNode(
                id:       (string)($n['id']       ?? 'N0'),
                name:     (string)($n['name']     ?? 'Unknown'),
                role:     (string)($n['role']     ?? 'HOST'),
                delay:    (int)($n['delay']    ?? 0),
                location: (string)($n['location'] ?? 'earth'),
            ), $config['nodes']);
        }

        if (isset($config['segments']) && is_array($config['segments'])) {
            $plan->segments = array_map(
                fn(array $s) => LtxSegmentTemplate::fromArray($s),
                $config['segments']
            );
        }

        return $plan;
    }

    /* ── Segment computation ────────────────────────────────────────────── */

    /**
     * Compute the timed segment array for a plan.
     *
     * @return LtxSegment[]
     */
    public static function computeSegments(LtxPlan $plan): array
    {
        $qMs  = $plan->quantum * 60 * 1000;
        $t    = self::parseIsoMs($plan->start);
        $segs = [];

        foreach ($plan->segments as $tmpl) {
            $dur    = $tmpl->q * $qMs;
            $segs[] = new LtxSegment(
                type:   $tmpl->type,
                q:      $tmpl->q,
                startMs: $t,
                endMs:   $t + $dur,
                durMin:  $tmpl->q * $plan->quantum,
            );
            $t += $dur;
        }

        return $segs;
    }

    /** Total session duration in minutes. */
    public static function totalMin(LtxPlan $plan): int
    {
        return array_sum(array_map(fn($s) => $s->q * $plan->quantum, $plan->segments));
    }

    /* ── Plan ID ────────────────────────────────────────────────────────── */

    /**
     * Compute the deterministic plan ID string (matches makePlanId in ltx-sdk.js).
     * Format: "LTX-YYYYMMDD-HOST-NODE-v2-XXXXXXXX" or "...-v3-XXXXXXXX"
     *
     * Accepts an LtxPlan (v2, serialised by LtxPlan::toJson) or a plan decoded
     * from JSON (stdClass from json_decode($json), or an associative array),
     * v2 or v3, key insertion order preserved. v2 uses the FROZEN imul31 hash
     * over the UTF-16 code units of JSON.stringify(plan) (LTX-SPECIFICATION.md
     * §4.3); v3 uses SHA-256 over canonical JSON (§4.5). Reproduces every
     * vector in spec/golden/plan-ids.json.
     */
    public static function makePlanId(LtxPlan|array|\stdClass $plan): string
    {
        if ($plan instanceof LtxPlan) {
            $c     = $plan;
            $names = array_map(fn(LtxNode $n) => $n->name, $plan->nodes);
            $start = $plan->start;
            $v     = 2;
        } else {
            $c     = self::upgradeConfigData($plan);
            $arr   = (array)$c;
            $names = array_map(fn($n) => ((array)$n)['name'] ?? null, (array)($arr['nodes'] ?? []));
            $start = (string)($arr['start'] ?? '');
            $v     = $arr['v'] ?? 1;
        }
        $date = gmdate('Ymd', intdiv(self::parseIsoMs($start), 1000));

        /* Host string: remove whitespace, uppercase, max 8 UTF-16 units */
        $hostStr = self::idPart($names[0] ?? null, 8, 'HOST');

        /* Node string: first 4 of each remote node name, joined, max 16 */
        $nodeStr = 'RX';
        if (count($names) > 1) {
            $parts = array_map(fn($nm) => self::idPart($nm, 4, ''), array_slice($names, 1));
            $nodeStr = JsJson::utf16Slice(implode('-', $parts), 16);
        }

        if (is_numeric($v) && $v >= 3) {
            $digest = hash('sha256', JsJson::canonical($c));
            return sprintf('LTX-%s-%s-%s-v3-%s', $date, $hostStr, $nodeStr, substr($digest, 0, 8));
        }

        /* FROZEN v2 path: imul31 over UTF-16 code units of JSON.stringify */
        $json = $c instanceof LtxPlan ? $c->toJson() : JsJson::stringify($c);
        $h    = 0;
        foreach (JsJson::utf16Units($json) as $u) {
            $h = ($h * 31 + $u) & 0xFFFFFFFF;
        }

        return sprintf('LTX-%s-%s-%s-v2-%08x', $date, $hostStr, $nodeStr, $h);
    }

    /** SHA-256 hex of the canonical JSON of a plan (prevPlanHash, §6.4). */
    public static function planHash(array|\stdClass $plan): string
    {
        return hash('sha256', JsJson::canonical($plan));
    }

    /* ── Plan validation (§3.5, §4, §7) ─────────────────────────────────── */

    /**
     * Validate a v2 or v3 plan (stdClass or associative array, as decoded from
     * JSON) against spec/ltx-schema.json and the reserved-field rules:
     * reserved_streams (non-empty or non-array streams, segment stream) and
     * reserved_branching (branches, branching, segment branch). Pure.
     *
     * @return array{valid: bool, errors: list<array{code: string, path: string, message: string}>}
     */
    public static function validatePlan(mixed $plan): array
    {
        return PlanValidator::validate($plan);
    }

    /**
     * (name || default).replace(/\s+/g, '').toUpperCase().slice(0, n), with
     * JavaScript's \s (PCRE's /\s/u also strips U+0085 and keeps U+FEFF).
     */
    /** ICS node id: name.replace(/\s+/g, '-').toUpperCase() (ltx-sdk.js toId). */
    private static function icsNodeId(string $name): string
    {
        return mb_strtoupper(preg_replace(JsJson::WHITESPACE, '-', $name), 'UTF-8');
    }

    private static function idPart(mixed $name, int $n, string $default): string
    {
        $s = (is_string($name) && $name !== '') ? $name : $default;
        return JsJson::utf16Slice(mb_strtoupper(preg_replace(JsJson::WHITESPACE, '', $s), 'UTF-8'), $n);
    }

    /**
     * upgradeConfig for decoded plans: v1 (txName/rxName/delay) to v2 nodes[];
     * v2+ plans with nodes are returned unchanged (same key order).
     */
    private static function upgradeConfigData(array|\stdClass $cfg): array|\stdClass
    {
        $a = (array)$cfg;
        $v = $a['v'] ?? null;
        if (is_numeric($v) && $v >= 2 && !empty($a['nodes'])) return $cfg;
        $rx = strtolower((string)($a['rxName'] ?? ''));
        $remoteLoc = str_contains($rx, 'mars') ? 'mars' : (str_contains($rx, 'moon') ? 'moon' : 'earth');
        $a['v'] = 2;
        $a['nodes'] = [
            ['id' => 'N0', 'name' => $a['txName'] ?? 'Earth HQ', 'role' => 'HOST',
             'delay' => 0, 'location' => 'earth'],
            ['id' => 'N1', 'name' => $a['rxName'] ?? 'Mars Hab-01', 'role' => 'PARTICIPANT',
             'delay' => $a['delay'] ?? 0, 'location' => $remoteLoc],
        ];
        return $a;
    }

    /* ── Encoding ───────────────────────────────────────────────────────── */

    /**
     * Encode a plan to a URL-safe base64 hash fragment ("#l=…").
     */
    public static function encodeHash(LtxPlan $plan): string
    {
        $json    = $plan->toJson();
        $payload = rtrim(strtr(base64_encode($json), '+/', '-_'), '=');
        return '#l=' . $payload;
    }

    /**
     * Decode a plan from a URL hash fragment ("#l=…", "l=…", or raw base64).
     *
     * @return LtxPlan|null  null on failure
     */
    public static function decodeHash(string $hash): ?LtxPlan
    {
        /* Strip leading "#l=" or "l=" */
        $token = $hash;
        if (str_starts_with($token, '#')) $token = substr($token, 1);
        if (str_starts_with($token, 'l=')) $token = substr($token, 2);

        /* Restore standard base64 and decode */
        $b64  = strtr($token, '-_', '+/');
        $json = base64_decode($b64, strict: false);
        if ($json === false || $json === '') {
            return null;
        }

        $plan = LtxPlan::fromJson($json);
        if ($plan === null || empty($plan->segments)) {
            return null;
        }
        return $plan;
    }

    /* ── Node URLs ──────────────────────────────────────────────────────── */

    /**
     * Build perspective URLs for all nodes in a plan.
     *
     * @return NodeUrl[]
     */
    public static function buildNodeUrls(LtxPlan $plan, string $baseUrl): array
    {
        $hash = self::encodeHash($plan);
        $hashPart = ltrim($hash, '#'); /* strip leading "#" */

        /* Strip query and fragment from base URL */
        $base = preg_replace('/[?#].*$/', '', $baseUrl);

        $urls = [];
        foreach ($plan->nodes as $node) {
            $urls[] = new NodeUrl(
                nodeId: $node->id,
                name:   $node->name,
                role:   $node->role,
                url:    "{$base}?node={$node->id}#{$hashPart}",
            );
        }
        return $urls;
    }

    /* ── ICS generation ─────────────────────────────────────────────────── */

    /** Generate LTX-extended iCalendar (.ics) content for a plan. */
    public static function generateICS(LtxPlan $plan): string
    {
        $segs    = self::computeSegments($plan);
        $startMs = self::parseIsoMs($plan->start);
        $endMs   = !empty($segs) ? end($segs)->endMs : $startMs;
        $planId  = self::makePlanId($plan);

        $dtStart = gmdate('Ymd\THis\Z', intdiv($startMs, 1000));
        $dtEnd   = gmdate('Ymd\THis\Z', intdiv($endMs, 1000));
        $dtStamp = gmdate('Ymd\THis\Z');

        $segTpl    = implode(',', array_map(fn($s) => $s->type, $plan->segments));
        $hostName  = !empty($plan->nodes) ? $plan->nodes[0]->name : 'Earth HQ';
        $partNames = count($plan->nodes) > 1
            ? implode(', ', array_map(fn($n) => $n->name, array_slice($plan->nodes, 1)))
            : 'remote nodes';

        $delayParts = [];
        foreach (array_slice($plan->nodes, 1) as $n) {
            $delayParts[] = sprintf('%s: %d min one-way', $n->name, intdiv($n->delay, 60));
        }
        $delayDesc = $delayParts ? implode(' . ', $delayParts) : 'no participant delay configured';

        $lines   = [];
        $lines[] = 'BEGIN:VCALENDAR';
        $lines[] = 'VERSION:2.0';
        $lines[] = 'PRODID:-//InterPlanet//LTX v1.1//EN';
        $lines[] = 'CALSCALE:GREGORIAN';
        $lines[] = 'METHOD:PUBLISH';
        $lines[] = 'BEGIN:VEVENT';
        $lines[] = "UID:{$planId}@interplanet.live";
        $lines[] = "DTSTAMP:{$dtStamp}";
        $lines[] = "DTSTART:{$dtStart}";
        $lines[] = "DTEND:{$dtEnd}";
        $lines[] = "SUMMARY:{$plan->title}";
        $lines[] = "DESCRIPTION:LTX session -- {$hostName} with {$partNames}\\nSignal delays: {$delayDesc}\\nMode: {$plan->mode} . Segment plan: {$segTpl}\\nGenerated by InterPlanet (https://interplanet.live)";
        $lines[] = 'LTX:1';
        $lines[] = "LTX-PLANID:{$planId}";
        $lines[] = "LTX-QUANTUM:PT{$plan->quantum}M";
        $lines[] = "LTX-SEGMENT-TEMPLATE:{$segTpl}";
        $lines[] = "LTX-MODE:{$plan->mode}";

        foreach ($plan->nodes as $node) {
            $nid     = self::icsNodeId($node->name);
            $lines[] = "LTX-NODE:ID={$nid};ROLE={$node->role}";
        }

        foreach (array_slice($plan->nodes, 1) as $node) {
            $nid     = self::icsNodeId($node->name);
            $d       = $node->delay;
            $lines[] = "LTX-DELAY;NODEID={$nid}:ONEWAY-MIN={$d};ONEWAY-MAX=" . ($d + 120) . ";ONEWAY-ASSUMED={$d}";
        }

        $lines[] = 'LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY';

        foreach ($plan->nodes as $node) {
            if ($node->location === 'mars') {
                $nid     = self::icsNodeId($node->name);
                $lines[] = "LTX-LOCALTIME:NODE={$nid};SCHEME=LMST;PARAMS=LONGITUDE:0E";
            }
        }

        $lines[] = 'END:VEVENT';
        $lines[] = 'END:VCALENDAR';

        return implode("\r\n", $lines) . "\r\n";
    }

    /* ── Formatting ─────────────────────────────────────────────────────── */

    /**
     * Format a duration in seconds as "MM:SS" (< 1 hour) or "HH:MM:SS".
     */
    public static function formatHMS(int $seconds): string
    {
        if ($seconds < 0) $seconds = 0;
        $h = intdiv($seconds, 3600);
        $m = intdiv($seconds % 3600, 60);
        $s = $seconds % 60;
        return $h > 0
            ? sprintf('%02d:%02d:%02d', $h, $m, $s)
            : sprintf('%02d:%02d', $m, $s);
    }

    /**
     * Format UTC epoch milliseconds as "HH:MM:SS UTC".
     */
    public static function formatUTC(int $epochMs): string
    {
        $secs = intdiv($epochMs, 1000);
        return gmdate('H:i:s', $secs) . ' UTC';
    }

    /* ── REST client ────────────────────────────────────────────────────── */

    /**
     * POST the plan to the LTX session store.
     * @return array  Decoded JSON response
     */
    public static function storeSession(LtxPlan $plan, ?string $apiBase = null): array
    {
        $url  = rtrim($apiBase ?? self::DEFAULT_API_BASE, '/') . '/session';
        $body = json_encode(['plan' => json_decode($plan->toJson(), true)]);
        return self::httpPost($url, $body) ?? [];
    }

    /**
     * GET a session plan by plan ID.
     * @return LtxPlan|null
     */
    public static function getSession(string $planId, ?string $apiBase = null): ?LtxPlan
    {
        $url  = rtrim($apiBase ?? self::DEFAULT_API_BASE, '/') . '/session/' . urlencode($planId);
        $json = self::httpGet($url);
        if ($json === null) return null;
        $data = json_decode($json, true);
        $planData = $data['plan'] ?? $data;
        return is_array($planData) ? LtxPlan::fromJson(json_encode($planData)) : null;
    }

    /**
     * Download ICS for a session by plan ID and optional node ID.
     */
    public static function downloadICS(string $planId, ?string $nodeId = null, ?string $apiBase = null): string
    {
        $base = rtrim($apiBase ?? self::DEFAULT_API_BASE, '/');
        $url  = $base . '/ics/' . urlencode($planId);
        if ($nodeId !== null) $url .= '?node=' . urlencode($nodeId);
        return self::httpGet($url) ?? '';
    }

    /**
     * Submit feedback for a session.
     * @param  array $payload  Feedback payload (associative array)
     * @return array           Decoded JSON response
     */
    public static function submitFeedback(string $planId, array $payload, ?string $apiBase = null): array
    {
        $url  = rtrim($apiBase ?? self::DEFAULT_API_BASE, '/') . '/feedback/' . urlencode($planId);
        $body = json_encode($payload);
        return self::httpPost($url, $body) ?? [];
    }

    /* ── Private helpers ────────────────────────────────────────────────── */

    /** Parse an ISO-8601 UTC string to epoch milliseconds. */
    private static function parseIsoMs(string $iso): int
    {
        if ($iso === '') return 0;
        try {
            $dt = new \DateTime($iso, new \DateTimeZone('UTC'));
            return (int)($dt->getTimestamp() * 1000);
        } catch (\Exception) {
            return 0;
        }
    }

    /** POST JSON body to URL; returns response body or null on error. */
    private static function httpPost(string $url, string $body): ?array
    {
        if (!function_exists('curl_init')) return null;
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $body,
            CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 10,
        ]);
        $result = curl_exec($ch);
        curl_close($ch);
        if ($result === false) return null;
        $data = json_decode((string)$result, true);
        return is_array($data) ? $data : null;
    }

    /** GET URL; returns response body string or null on error. */
    private static function httpGet(string $url): ?string
    {
        if (!function_exists('curl_init')) return null;
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 10,
        ]);
        $result = curl_exec($ch);
        curl_close($ch);
        return ($result !== false) ? (string)$result : null;
    }
}
