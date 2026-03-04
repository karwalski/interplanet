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
    const DEFAULT_QUANTUM = 3;
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
            $plan->segments = array_map(fn(array $s) => new LtxSegmentTemplate(
                type: (string)($s['type'] ?? 'TX'),
                q:    (int)($s['q']    ?? 2),
            ), $config['segments']);
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
     * Compute the deterministic plan ID string.
     * Format: "LTX-YYYYMMDD-HOST-NODE-v2-XXXXXXXX"
     */
    public static function makePlanId(LtxPlan $plan): string
    {
        $startMs = self::parseIsoMs($plan->start);
        $date    = gmdate('Ymd', intdiv($startMs, 1000));

        /* Host string: remove spaces, uppercase, max 8 chars */
        $hostStr = 'HOST';
        if (!empty($plan->nodes)) {
            $nm = $plan->nodes[0]->name;
            $tmp = strtoupper(str_replace([' ', "\t"], '', $nm));
            $hostStr = substr($tmp, 0, 8);
        }

        /* Node string: first 4 non-space chars of each remote node name */
        $nodeStr = 'RX';
        if (count($plan->nodes) > 1) {
            $parts = [];
            foreach (array_slice($plan->nodes, 1) as $n) {
                $nm   = $n->name;
                $part = '';
                foreach (str_split($nm) as $c) {
                    if ($c === ' ' || $c === "\t") continue;
                    $part .= strtoupper($c);
                    if (strlen($part) >= 4) break;
                }
                $parts[] = $part;
            }
            $nodeStr = implode('-', $parts);
        }

        /* Polynomial hash matching Math.imul(31, h) in ltx-sdk.js */
        $json = $plan->toJson();
        $h    = 0;
        foreach (str_split($json) as $c) {
            $h = ($h * 31 + ord($c)) & 0xFFFFFFFF;
        }

        return sprintf('LTX-%s-%s-%s-v2-%08x', $date, $hostStr, $nodeStr, $h);
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
            $nid     = strtoupper(str_replace([' ', "\t"], '-', $node->name));
            $lines[] = "LTX-NODE:ID={$nid};ROLE={$node->role}";
        }

        foreach (array_slice($plan->nodes, 1) as $node) {
            $nid     = strtoupper(str_replace([' ', "\t"], '-', $node->name));
            $d       = $node->delay;
            $lines[] = "LTX-DELAY;NODEID={$nid}:ONEWAY-MIN={$d};ONEWAY-MAX=" . ($d + 120) . ";ONEWAY-ASSUMED={$d}";
        }

        $lines[] = 'LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY';

        foreach ($plan->nodes as $node) {
            if ($node->location === 'mars') {
                $nid     = strtoupper(str_replace([' ', "\t"], '-', $node->name));
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
