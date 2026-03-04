<?php
/**
 * mcp-server.php — InterPlanet MCP HTTP endpoint (PHP)
 *
 * JSON-RPC 2.0 over HTTP POST (MCP Streamable-HTTP transport).
 * Protocol version: 2024-11-05
 *
 * Usage:
 *   POST /mcp-server.php
 *   Content-Type: application/json
 *   Body: { "jsonrpc":"2.0","id":1,"method":"tools/call","params":{...} }
 */

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

// ── Load PHP planet-time library ─────────────────────────────────────────────

$autoload = __DIR__ . '/../php/planet-time/src/autoload.php';
if (!file_exists($autoload)) {
    http_response_code(500);
    echo json_encode(['jsonrpc' => '2.0', 'id' => null,
        'error' => ['code' => -32000, 'message' => 'PHP planet-time library not found at ' . $autoload]]);
    exit;
}
require_once $autoload;
use InterplanetTime\InterplanetTime;

// ── Constants ─────────────────────────────────────────────────────────────────

const AU_KM        = 149597870.7;
const AU_SECONDS   = 499.004785;
const PLANET_KEYS  = ['mercury','venus','earth','mars','jupiter','saturn','uranus','neptune','moon'];

function toPlanetKey(string $name): ?string {
    $lower = strtolower(trim($name));
    return in_array($lower, PLANET_KEYS, true) ? $lower : null;
}

// ── Output helpers ────────────────────────────────────────────────────────────

function jsonOut(array $obj): void {
    echo json_encode($obj, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function jsonErr($id, int $code, string $message): void {
    jsonOut(['jsonrpc' => '2.0', 'id' => $id, 'error' => ['code' => $code, 'message' => $message]]);
}

function toolResult($id, $data): void {
    jsonOut([
        'jsonrpc' => '2.0',
        'id'      => $id,
        'result'  => [
            'content' => [['type' => 'text', 'text' => json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)]],
        ],
    ]);
}

function toolError($id, string $msg): void {
    jsonOut([
        'jsonrpc' => '2.0',
        'id'      => $id,
        'result'  => [
            'content' => [['type' => 'text', 'text' => 'Error: ' . $msg]],
            'isError' => true,
        ],
    ]);
}

// ── Tool definitions ──────────────────────────────────────────────────────────

const TOOLS = [
    [
        'name'        => 'get_planet_time',
        'description' => 'Get the current local time on a planet. Returns hour, minute, second and work-hour status.',
        'inputSchema' => [
            'type'       => 'object',
            'properties' => [
                'planet'      => ['type' => 'string',  'description' => 'Planet name (mercury, venus, earth, mars, jupiter, saturn, uranus, neptune, moon)'],
                'utc_ms'      => ['type' => 'number',  'description' => 'UTC timestamp in milliseconds'],
                'tz_offset_h' => ['type' => 'number',  'description' => 'Optional timezone offset in planet local hours (default 0)'],
            ],
            'required' => ['planet', 'utc_ms'],
        ],
    ],
    [
        'name'        => 'get_light_travel',
        'description' => 'Calculate one-way light travel time between two solar system bodies.',
        'inputSchema' => [
            'type'       => 'object',
            'properties' => [
                'from'   => ['type' => 'string', 'description' => 'Origin body (planet name)'],
                'to'     => ['type' => 'string', 'description' => 'Destination body (planet name)'],
                'utc_ms' => ['type' => 'number', 'description' => 'UTC timestamp in milliseconds'],
            ],
            'required' => ['from', 'to', 'utc_ms'],
        ],
    ],
    [
        'name'        => 'get_mtc',
        'description' => 'Get Mars Coordinated Time (MTC) — the prime-meridian clock time on Mars.',
        'inputSchema' => [
            'type'       => 'object',
            'properties' => ['utc_ms' => ['type' => 'number', 'description' => 'UTC timestamp in milliseconds']],
            'required'   => ['utc_ms'],
        ],
    ],
    [
        'name'        => 'get_planet_distance',
        'description' => 'Get the distance between two solar system bodies in AU and km.',
        'inputSchema' => [
            'type'       => 'object',
            'properties' => [
                'from'   => ['type' => 'string', 'description' => 'Origin body (planet name)'],
                'to'     => ['type' => 'string', 'description' => 'Destination body (planet name)'],
                'utc_ms' => ['type' => 'number', 'description' => 'UTC timestamp in milliseconds'],
            ],
            'required' => ['from', 'to', 'utc_ms'],
        ],
    ],
    [
        'name'        => 'find_meeting_windows',
        'description' => 'Find overlapping work-hour windows between two planets.',
        'inputSchema' => [
            'type'       => 'object',
            'properties' => [
                'planet_a' => ['type' => 'string', 'description' => 'First planet name'],
                'planet_b' => ['type' => 'string', 'description' => 'Second planet name'],
                'from_ms'  => ['type' => 'number', 'description' => 'UTC start timestamp in milliseconds'],
                'days'     => ['type' => 'number', 'description' => 'Number of Earth days to search (default 7)'],
            ],
            'required' => ['planet_a', 'planet_b', 'from_ms'],
        ],
    ],
    [
        'name'        => 'check_line_of_sight',
        'description' => 'Check whether the line of sight between two bodies is clear, degraded, or blocked by the Sun.',
        'inputSchema' => [
            'type'       => 'object',
            'properties' => [
                'from'   => ['type' => 'string', 'description' => 'Origin body (planet name)'],
                'to'     => ['type' => 'string', 'description' => 'Destination body (planet name)'],
                'utc_ms' => ['type' => 'number', 'description' => 'UTC timestamp in milliseconds'],
            ],
            'required' => ['from', 'to', 'utc_ms'],
        ],
    ],
];

// ── Tool handlers ─────────────────────────────────────────────────────────────

function handleGetPlanetTime($id, array $p): void {
    $key = toPlanetKey($p['planet'] ?? '');
    if (!$key) { toolError($id, 'Unknown planet: ' . ($p['planet'] ?? '')); return; }
    if (!isset($p['utc_ms'])) { toolError($id, 'utc_ms is required'); return; }
    $utcMs    = (int)$p['utc_ms'];
    $tzOffset = isset($p['tz_offset_h']) ? (float)$p['tz_offset_h'] : 0.0;
    $pt = InterplanetTime::getPlanetTime($key, $utcMs, $tzOffset);
    toolResult($id, [
        'planet'         => $key,
        'hour'           => $pt->hour,
        'minute'         => $pt->minute,
        'second'         => $pt->second,
        'time_str'       => $pt->timeStr,
        'time_str_full'  => $pt->timeStrFull,
        'is_work_hour'   => $pt->isWorkHour,
        'is_work_period' => $pt->isWorkPeriod,
        'day_number'     => $pt->dayNumber,
        'year_number'    => $pt->yearNumber,
    ]);
}

function handleGetLightTravel($id, array $p): void {
    $from = toPlanetKey($p['from'] ?? '');
    $to   = toPlanetKey($p['to']   ?? '');
    if (!$from) { toolError($id, 'Unknown origin: '      . ($p['from'] ?? '')); return; }
    if (!$to)   { toolError($id, 'Unknown destination: ' . ($p['to']   ?? '')); return; }
    if (!isset($p['utc_ms'])) { toolError($id, 'utc_ms is required'); return; }
    $secs = InterplanetTime::lightTravelSeconds($from, $to, (int)$p['utc_ms']);
    toolResult($id, [
        'seconds'   => $secs,
        'formatted' => InterplanetTime::formatLightTime($secs),
    ]);
}

function handleGetMTC($id, array $p): void {
    if (!isset($p['utc_ms'])) { toolError($id, 'utc_ms is required'); return; }
    $mtc = InterplanetTime::getMTC((int)$p['utc_ms']);
    toolResult($id, [
        'sol'      => $mtc->sol,
        'hour'     => $mtc->hour,
        'minute'   => $mtc->minute,
        'second'   => $mtc->second,
        'time_str' => $mtc->mtcStr,
    ]);
}

function handleGetPlanetDistance($id, array $p): void {
    $from = toPlanetKey($p['from'] ?? '');
    $to   = toPlanetKey($p['to']   ?? '');
    if (!$from) { toolError($id, 'Unknown origin: '      . ($p['from'] ?? '')); return; }
    if (!$to)   { toolError($id, 'Unknown destination: ' . ($p['to']   ?? '')); return; }
    if (!isset($p['utc_ms'])) { toolError($id, 'utc_ms is required'); return; }
    $au = InterplanetTime::bodyDistanceAu($from, $to, (int)$p['utc_ms']);
    toolResult($id, [
        'au' => $au,
        'km' => $au * AU_KM,
    ]);
}

function handleFindMeetingWindows($id, array $p): void {
    $keyA = toPlanetKey($p['planet_a'] ?? '');
    $keyB = toPlanetKey($p['planet_b'] ?? '');
    if (!$keyA) { toolError($id, 'Unknown planet_a: ' . ($p['planet_a'] ?? '')); return; }
    if (!$keyB) { toolError($id, 'Unknown planet_b: ' . ($p['planet_b'] ?? '')); return; }
    if (!isset($p['from_ms'])) { toolError($id, 'from_ms is required'); return; }
    $days = isset($p['days']) ? max(1, (int)$p['days']) : 7;
    $wins = InterplanetTime::findMeetingWindows($keyA, $keyB, (int)$p['from_ms'], $days);
    $result = array_map(fn($w) => [
        'start_ms'         => $w->startMs,
        'end_ms'           => $w->endMs,
        'duration_minutes' => $w->durationMinutes,
        'start_iso'        => gmdate('Y-m-d\TH:i:s\Z', (int)($w->startMs / 1000)),
        'end_iso'          => gmdate('Y-m-d\TH:i:s\Z', (int)($w->endMs   / 1000)),
    ], $wins);
    toolResult($id, $result);
}

function handleCheckLineOfSight($id, array $p): void {
    $from = toPlanetKey($p['from'] ?? '');
    $to   = toPlanetKey($p['to']   ?? '');
    if (!$from) { toolError($id, 'Unknown origin: '      . ($p['from'] ?? '')); return; }
    if (!$to)   { toolError($id, 'Unknown destination: ' . ($p['to']   ?? '')); return; }
    if (!isset($p['utc_ms'])) { toolError($id, 'utc_ms is required'); return; }
    $los = InterplanetTime::checkLineOfSight($from, $to, (int)$p['utc_ms']);
    toolResult($id, [
        'clear'          => $los->clear,
        'blocked'        => $los->blocked,
        'degraded'       => $los->degraded,
        'closest_sun_au' => $los->closestSunAu,
        'elong_deg'      => $los->elongDeg,
    ]);
}

// ── JSON-RPC dispatch ─────────────────────────────────────────────────────────

$raw = file_get_contents('php://input');
if (!$raw || !trim($raw)) {
    jsonErr(null, -32700, 'Empty request body');
}

$req = json_decode($raw, true);
if (json_last_error() !== JSON_ERROR_NONE) {
    jsonErr(null, -32700, 'Parse error: ' . json_last_error_msg());
}

$id     = $req['id']     ?? null;
$method = $req['method'] ?? '';
$params = $req['params'] ?? [];

switch ($method) {
    case 'initialize':
        jsonOut([
            'jsonrpc' => '2.0',
            'id'      => $id,
            'result'  => [
                'protocolVersion' => '2024-11-05',
                'capabilities'    => ['tools' => new stdClass()],
                'serverInfo'      => ['name' => 'interplanet-mcp-php', 'version' => '0.1.0'],
            ],
        ]);
        break;

    case 'notifications/initialized':
        http_response_code(204);
        exit;

    case 'tools/list':
        jsonOut(['jsonrpc' => '2.0', 'id' => $id, 'result' => ['tools' => TOOLS]]);
        break;

    case 'tools/call':
        $toolName   = $params['name']      ?? '';
        $toolParams = $params['arguments'] ?? [];
        switch ($toolName) {
            case 'get_planet_time':      handleGetPlanetTime($id, $toolParams);      break;
            case 'get_light_travel':     handleGetLightTravel($id, $toolParams);     break;
            case 'get_mtc':              handleGetMTC($id, $toolParams);             break;
            case 'get_planet_distance':  handleGetPlanetDistance($id, $toolParams);  break;
            case 'find_meeting_windows': handleFindMeetingWindows($id, $toolParams); break;
            case 'check_line_of_sight':  handleCheckLineOfSight($id, $toolParams);   break;
            default:
                jsonErr($id, -32601, 'Unknown tool: ' . $toolName);
        }
        break;

    default:
        jsonErr($id, -32601, 'Method not found: ' . $method);
}
