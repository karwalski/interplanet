<?php
/**
 * LTX REST API — api/ltx.php
 *
 * POST ?action=session          body: SessionPlan JSON
 *   → {"plan_id":"LTX-...","segments":[...],"total_min":N,"stored":true}
 *
 * GET  ?action=session&plan_id=LTX-...
 *   → {"plan_id":"LTX-...","plan":{...},"created_at":"...","views":N}
 *
 * POST ?action=ics&plan_id=LTX-...   body: {"start":"ISO","duration_min":N}
 *   → ICS file download (LTX-extended iCalendar)
 *
 * POST ?action=feedback          body: FeedbackPayload JSON
 *   → {"ok":true,"feedback_id":N}
 *
 * All timestamps are ISO 8601 UTC.
 * ICS extension properties follow the LTX v1.0 draft spec (ltx.html).
 */

declare(strict_types=1);

require_once __DIR__ . '/../db-config.php';

// ── CORS + helpers ─────────────────────────────────────────────────────────────

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

function jsonOk(array $data): never {
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
    exit;
}

function jsonError(string $msg, int $code = 400): never {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => $msg]);
    exit;
}

function rawBody(): string {
    static $raw = null;
    if ($raw === null) $raw = (string)file_get_contents('php://input');
    return $raw;
}

function parsedBody(): array {
    $raw = rawBody();
    if (!$raw) jsonError('Empty body');
    $data = json_decode($raw, true);
    if (!is_array($data)) jsonError('Invalid JSON body');
    return $data;
}

// ── Plan ID ─────────────────────────────────────────────────────────────────────
//
// The spec planId (docs/LTX-SPECIFICATION.md sections 4.3 and 4.5) of the plan
// exactly as the client sent it: key order preserved, hashed before any
// sanitising, so it equals makePlanId() in every SDK and in ltx.html.

require_once __DIR__ . '/ltx-planid.php';

/** planId of the raw JSON request body (the plan as received). */
function makePlanIdFromJson(string $raw): string {
    $plan = ltx_plan_decode($raw);
    if (!($plan instanceof stdClass)) jsonError('Invalid JSON body');
    try {
        return ltx_plan_id_utf8(ltx_make_plan_id($plan));
    } catch (Throwable) {
        jsonError('Invalid plan: cannot compute plan_id');
    }
}

/**
 * Clamp the fields the API derives values from (segments, ICS). Never used
 * for the planId or the stored plan_json.
 */
function sanitizePlan(array $plan): array {
    $plan['title']   = substr(trim(is_scalar($plan['title'] ?? null) ? (string)$plan['title'] : 'LTX Meeting'), 0, 200);
    $plan['quantum'] = max(1, min(60, (int)($plan['quantum'] ?? 5)));
    // "LTX" (the spec alias of LTX-LIVE, section 3.6) and unknown modes -> LTX-LIVE
    $plan['mode']    = in_array($plan['mode'] ?? '', ['LTX-LIVE','LTX-RELAY','LTX-ASYNC'], true)
                       ? $plan['mode'] : 'LTX-LIVE';
    return $plan;
}

// ── Segment helpers ────────────────────────────────────────────────────────────

/** Expand segment template into timed array of {type, start_ms, dur_min} */
function expandSegments(array $cfg, int $startMs): array {
    $quantum  = max(1, (int)($cfg['quantum'] ?? 5));
    $segments = $cfg['segments'] ?? [];
    $result   = [];
    $cursor   = $startMs;
    foreach ($segments as $s) {
        $type  = $s['type'] ?? 'BUFFER';
        $q     = max(1, (int)($s['q'] ?? 1));
        $durMs = $q * $quantum * 60000;
        $result[] = [
            'type'      => $type,
            'start_utc' => gmdate('Y-m-d\TH:i:s\Z', intdiv($cursor, 1000)),
            'dur_min'   => $q * $quantum,
        ];
        $cursor += $durMs;
    }
    return $result;
}

function totalMin(array $cfg): int {
    $quantum = max(1, (int)($cfg['quantum'] ?? 5));
    $total   = 0;
    foreach ($cfg['segments'] ?? [] as $s) {
        $total += max(1, (int)($s['q'] ?? 1)) * $quantum;
    }
    return $total;
}

// ── ICS generation (LTX-extended iCalendar) ───────────────────────────────────

function fmtDT(int $ms): string {
    return gmdate('Ymd\THis\Z', intdiv($ms, 1000));
}

/** RFC 5545 section 3.3.11 TEXT escaping (backslash, semicolon, comma, newline). */
function icsText(string $s): string {
    return str_replace(["\\", ';', ',', "\r\n", "\r", "\n"], ["\\\\", '\\;', '\\,', '\\n', '\\n', '\\n'], $s);
}

/** Node id as the SDKs write it (whitespace runs to "-", upper case), TEXT-escaped. */
function toIcsId(string $name): string {
    return icsText(mb_strtoupper((string)preg_replace('/\s+/u', '-', $name), 'UTF-8'));
}

/** Fold a content line at 75 octets (RFC 5545 section 3.1) without splitting a UTF-8 character. */
function icsFold(string $line): string {
    $out = '';
    $cur = '';
    $limit = 75;
    foreach (mb_str_split($line, 1, 'UTF-8') as $ch) {
        if (strlen($cur) + strlen($ch) > $limit) {
            $out  .= $cur . "\r\n ";
            $cur   = '';
            $limit = 74;   // continuation lines start with one space
        }
        $cur .= $ch;
    }
    return $out . $cur;
}

function generateIcs(string $planId, array $cfg, int $startMs): string {
    $endMs   = $startMs + totalMin($cfg) * 60000;
    $nodes   = $cfg['nodes'] ?? [];
    $quantum = max(1, (int)($cfg['quantum'] ?? 5));
    $mode    = $cfg['mode'] ?? 'LTX-LIVE';
    $title   = $cfg['title'] ?? 'LTX Meeting';

    $segTpl = implode(',', array_map(fn($s) => $s['type'], $cfg['segments'] ?? []));

    $nodeName  = fn($n) => is_array($n) && is_scalar($n['name'] ?? null) ? (string)$n['name'] : 'NODE';
    $nodes     = array_values(array_filter($nodes, 'is_array'));
    $hostName  = isset($nodes[0]) ? $nodeName($nodes[0]) : 'HOST';
    $partNames = implode(', ', array_map($nodeName, array_slice($nodes, 1))) ?: 'remote nodes';

    // LTX-NODE lines
    $nodeLines = array_map(
        fn($n) => 'LTX-NODE:ID=' . toIcsId($nodeName($n)) . ';ROLE=' . icsText((string)($n['role'] ?? 'PARTICIPANT')),
        $nodes
    );

    // LTX-DELAY lines (skip host at index 0)
    $delayLines = [];
    foreach (array_slice($nodes, 1) as $n) {
        $d = (int)($n['delay'] ?? 0);
        $delayLines[] = sprintf(
            'LTX-DELAY;NODEID=%s:ONEWAY-MIN=%d;ONEWAY-MAX=%d;ONEWAY-ASSUMED=%d',
            toIcsId($nodeName($n)), $d, $d + 120, $d
        );
    }

    // LTX-LOCALTIME for Mars nodes (LMST is a Mars scheme; as in the SDKs)
    $localTimeLines = [];
    foreach ($nodes as $n) {
        if (($n['location'] ?? 'earth') === 'mars') {
            $localTimeLines[] = sprintf(
                'LTX-LOCALTIME:NODE=%s;SCHEME=LMST;PARAMS=LONGITUDE:0E',
                toIcsId($nodeName($n))
            );
        }
    }

    $desc = icsText("LTX session — {$hostName} with {$partNames}\nMode: {$mode}\nGenerated by InterPlanet");

    $lines = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//InterPlanet//LTX v1.0//EN',
        'CALSCALE:GREGORIAN',
        'BEGIN:VEVENT',
        'UID:' . $planId . '@interplanet.live',
        'DTSTAMP:' . fmtDT((int)(microtime(true) * 1000)),
        'DTSTART:' . fmtDT($startMs),
        'DTEND:' . fmtDT($endMs),
        'SUMMARY:' . icsText($title),
        'DESCRIPTION:' . $desc,
        'LTX:1',
        'LTX-PLANID:' . $planId,
        'LTX-QUANTUM:PT' . $quantum . 'M',
        'LTX-SEGMENT-TEMPLATE:' . $segTpl,
        'LTX-MODE:' . $mode,
        ...$nodeLines,
        ...$delayLines,
        ...$localTimeLines,
        'LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY',
        'END:VEVENT',
        'END:VCALENDAR',
    ];

    return implode("\r\n", array_map('icsFold', $lines)) . "\r\n";
}

// ── Route handlers ─────────────────────────────────────────────────────────────

/**
 * POST ?action=session
 * body: SessionPlan (v:2, title, start, quantum, mode, nodes, segments)
 *
 * Returns plan_id, expanded segments, total_min, and whether it was stored in DB.
 */
function handleSession(): void {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        jsonError('POST required', 405);
    }

    $plan = parsedBody();

    // Basic validation
    if (empty($plan['segments']) || !is_array($plan['segments'])) {
        jsonError('segments array is required');
    }
    if (empty($plan['start'])) {
        jsonError('start (ISO 8601 UTC) is required');
    }

    // Parse start time
    try {
        $dt      = new DateTimeImmutable((string)$plan['start'], new DateTimeZone('UTC'));
        $startMs = $dt->getTimestamp() * 1000;
    } catch (Throwable) {
        jsonError('Invalid start timestamp: ' . (is_scalar($plan['start']) ? (string)$plan['start'] : gettype($plan['start'])));
    }

    // planId of the plan as received, hashed before sanitising (sanitising
    // must not change the id: mode "LTX" is the spec alias of "LTX-LIVE").
    $planId = makePlanIdFromJson(rawBody());

    // Sanitised copy for derived values only; the stored plan is as received.
    $plan = sanitizePlan($plan);

    $segments = expandSegments($plan, $startMs);
    $totalM   = totalMin($plan);

    $stored = false;
    try {
        $db       = getDB();
        // Store the plan as received, re-serialised like JSON.stringify, so the
        // stored plan_json hashes back to plan_id.
        $planJson = ltx_js_stringify(ltx_plan_decode(rawBody()));
        // Upsert — ignore duplicate plan_id (idempotent)
        $db->prepare(
            'INSERT IGNORE INTO ltx_sessions (plan_id, plan_json, total_min)
             VALUES (?, ?, ?)'
        )->execute([$planId, $planJson, $totalM]);
        $stored = true;
    } catch (Throwable $e) {
        error_log('ltx session store error: ' . $e->getMessage());
        // Non-fatal — still return plan_id to caller
    }

    jsonOk([
        'plan_id'    => $planId,
        'segments'   => $segments,
        'total_min'  => $totalM,
        'mode'       => $plan['mode'],
        'stored'     => $stored,
    ]);
}

/**
 * GET ?action=session&plan_id=LTX-...
 *
 * Returns stored session plan and metadata.
 */
function handleGetSession(): void {
    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        jsonError('GET required', 405);
    }

    $planId = is_string($_GET['plan_id'] ?? null) ? trim($_GET['plan_id']) : '';
    if (!ltx_is_plan_id($planId)) {
        jsonError('Invalid or missing plan_id');
    }

    try {
        $db  = getDB();
        $st  = $db->prepare(
            'SELECT plan_json, total_min, created_at, views
             FROM ltx_sessions WHERE plan_id = ? LIMIT 1'
        );
        $st->execute([$planId]);
        $row = $st->fetch();
        if (!$row) {
            jsonError('Session not found', 404);
        }

        // Increment view counter (best-effort)
        try {
            $db->prepare('UPDATE ltx_sessions SET views = views + 1 WHERE plan_id = ?')
               ->execute([$planId]);
        } catch (Throwable) {}

        jsonOk([
            'plan_id'    => $planId,
            // stdClass decode keeps {} distinct from [] (plan as stored)
            'plan'       => json_decode($row['plan_json']),
            'total_min'  => (int)$row['total_min'],
            'created_at' => $row['created_at'],
            'views'      => (int)$row['views'] + 1,
        ]);
    } catch (Throwable $e) {
        error_log('ltx session get error: ' . $e->getMessage());
        jsonError('Database error', 500);
    }
}

/**
 * POST ?action=ics&plan_id=LTX-...
 * body: {"start":"ISO","duration_min":N}   (optional override of stored plan timing)
 *
 * Returns a downloadable LTX-extended ICS file.
 */
function handleIcs(): void {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        jsonError('POST required', 405);
    }

    $planId = is_string($_GET['plan_id'] ?? null) ? trim($_GET['plan_id']) : '';
    if (!ltx_is_plan_id($planId)) {
        jsonError('Invalid or missing plan_id');
    }

    // Optional body may provide a start override (e.g., for rescheduled meetings)
    $body  = trim(rawBody()) === '' ? [] : parsedBody();
    $startOverride = $body['start'] ?? null;

    // Load plan from DB
    try {
        $db  = getDB();
        $st  = $db->prepare('SELECT plan_json FROM ltx_sessions WHERE plan_id = ? LIMIT 1');
        $st->execute([$planId]);
        $row = $st->fetch();
        if (!$row) {
            jsonError('Session not found', 404);
        }
        $plan = sanitizePlan((array)json_decode($row['plan_json'], true));
    } catch (Throwable $e) {
        error_log('ltx ics db error: ' . $e->getMessage());
        jsonError('Database error', 500);
    }

    $startIso = $startOverride ?? ($plan['start'] ?? null);
    if (!is_string($startIso) || $startIso === '') {
        jsonError('No start time available (pass {"start":"ISO"} in body)');
    }

    try {
        $dt      = new DateTimeImmutable($startIso, new DateTimeZone('UTC'));
        $startMs = $dt->getTimestamp() * 1000;
    } catch (Throwable) {
        jsonError("Invalid start timestamp: {$startIso}");
    }

    $ics      = generateIcs($planId, $plan, $startMs);
    $filename = 'ltx-' . gmdate('Y-m-d', intdiv($startMs, 1000)) . '.ics';

    header('Content-Type: text/calendar; charset=utf-8');
    header('Content-Disposition: attachment; filename="' . $filename . '"');
    header('Content-Length: ' . strlen($ics));
    echo $ics;
    exit;
}

/**
 * POST ?action=feedback
 * body: FeedbackPayload — post-meeting telemetry for ML optimisation pipeline
 *
 * {
 *   "plan_id":       "LTX-...",          // optional (null if no stored plan)
 *   "session_title": "Q4 All-Hands",
 *   "mode":          "LTX-LIVE",
 *   "actual_start":  "2026-02-27T14:00:00Z",
 *   "actual_end":    "2026-02-27T15:20:00Z",
 *   "nodes": [
 *     { "name": "Earth HQ", "location": "earth", "delay_s": 0 },
 *     { "name": "Mars Crew", "location": "mars",  "delay_s": 1140 }
 *   ],
 *   "segments_run":  [ { "type": "READINESS", "completed": true },
 *                      { "type": "AGENDA",    "completed": true } ],
 *   "outcome":       "completed",       // "completed"|"partial"|"aborted"
 *   "satisfaction":  4,                 // 1–5 (optional)
 *   "relay_used":    false,             // true if fell back to LTX-RELAY
 *   "signal_issues": false,             // true if signal disruption reported
 *   "notes":         "Smooth session"   // free text, optional
 * }
 *
 * Stored as-is in ltx_feedback for future ML scheduling optimisation.
 * No PII is required — node names should be location labels, not personal names.
 */
function handleFeedback(): void {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        jsonError('POST required', 405);
    }

    $body = parsedBody();

    // Minimal validation
    $outcome = $body['outcome'] ?? 'unknown';
    if (!in_array($outcome, ['completed', 'partial', 'aborted', 'unknown'], true)) {
        $outcome = 'unknown';
    }

    $planId       = isset($body['plan_id']) && is_string($body['plan_id']) ? substr($body['plan_id'], 0, 100) : null;
    $sessionTitle = substr(trim((string)($body['session_title'] ?? '')), 0, 200);
    $mode         = in_array($body['mode'] ?? '', ['LTX-LIVE','LTX-RELAY','LTX-ASYNC'], true)
                    ? $body['mode'] : null;

    // Clamp satisfaction to 1–5 or null
    $satisfaction = isset($body['satisfaction']) ? max(1, min(5, (int)$body['satisfaction'])) : null;

    // Encode nodes and segments as JSON for storage
    $nodesJson    = json_encode($body['nodes']        ?? [], JSON_UNESCAPED_UNICODE);
    $segsJson     = json_encode($body['segments_run'] ?? [], JSON_UNESCAPED_UNICODE);

    // Parse actual_start / actual_end
    $actualStart = null;
    $actualEnd   = null;
    try {
        if (!empty($body['actual_start'])) {
            $actualStart = (new DateTimeImmutable($body['actual_start'], new DateTimeZone('UTC')))->format('Y-m-d H:i:s');
        }
        if (!empty($body['actual_end'])) {
            $actualEnd = (new DateTimeImmutable($body['actual_end'], new DateTimeZone('UTC')))->format('Y-m-d H:i:s');
        }
    } catch (Throwable) {
        // Non-fatal — store nulls
    }

    $relayUsed    = !empty($body['relay_used'])    ? 1 : 0;
    $signalIssues = !empty($body['signal_issues']) ? 1 : 0;
    $notes        = substr(trim((string)($body['notes'] ?? '')), 0, 1000);

    // Raw payload stored for ML pipeline ingestion
    $rawJson = json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

    try {
        $db = getDB();
        $st = $db->prepare(
            'INSERT INTO ltx_feedback
               (plan_id, session_title, mode, actual_start, actual_end,
                nodes_json, segments_json, outcome, satisfaction,
                relay_used, signal_issues, notes, raw_json)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $st->execute([
            $planId, $sessionTitle, $mode, $actualStart, $actualEnd,
            $nodesJson, $segsJson, $outcome, $satisfaction,
            $relayUsed, $signalIssues, $notes, $rawJson,
        ]);
        $feedbackId = (int)$db->lastInsertId();

        jsonOk(['ok' => true, 'feedback_id' => $feedbackId]);

    } catch (Throwable $e) {
        error_log('ltx feedback store error: ' . $e->getMessage());
        jsonError('Database error', 500);
    }
}

// ── Router ─────────────────────────────────────────────────────────────────────

$action = is_string($_GET['action'] ?? null) ? trim($_GET['action']) : '';
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

match (true) {
    $action === 'session' && $method === 'POST' => handleSession(),
    $action === 'session' && $method === 'GET'  => handleGetSession(),
    $action === 'ics'                           => handleIcs(),
    $action === 'feedback'                      => handleFeedback(),
    default                                     => jsonError("Unknown action: {$action}", 404),
};
