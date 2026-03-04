<?php
/**
 * relay-server.php — LTX DTN store-and-forward relay (PHP)
 *
 * Simulates light-time delays for interplanetary LTX meetings.
 * State is persisted in SQLite (no external dependencies required).
 *
 * Routes (via PATH_INFO or X-Relay-Path header):
 *   GET  /relay/health                   — server status
 *   POST /relay/session                  — register a session
 *   DELETE /relay/session/{id}           — remove a session
 *   POST /relay/{id}/send                — queue a frame
 *   GET  /relay/{id}/receive?node={n}    — dequeue ready frames
 *
 * For Apache: enable AllowEncodedSlashes and use PATH_INFO.
 * Direct URL: relay-server.php/relay/health
 */

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

// ── SQLite setup ──────────────────────────────────────────────────────────────

$dbPath = sys_get_temp_dir() . '/interplanet_relay.sqlite';

try {
    $db = new SQLite3($dbPath);
    $db->busyTimeout(3000);
    $db->exec('PRAGMA journal_mode=WAL');
    $db->exec('PRAGMA synchronous=NORMAL');
    $db->exec("
        CREATE TABLE IF NOT EXISTS relay_sessions (
            session_id      TEXT PRIMARY KEY,
            nodes           TEXT NOT NULL,
            delay_ms        INTEGER NOT NULL DEFAULT 0,
            tls_fingerprint TEXT NOT NULL,
            created_at      INTEGER NOT NULL,
            plan            TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS relay_frames (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id      TEXT NOT NULL,
            node_id         TEXT NOT NULL,
            target_node_id  TEXT,
            data            TEXT NOT NULL,
            timestamp_ms    INTEGER NOT NULL,
            deliver_at      INTEGER NOT NULL,
            delay_ms        INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_frames_session ON relay_frames(session_id);
    ");
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => 'DB error: ' . $e->getMessage()]);
    exit;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function sendJSON(int $status, array $body): void {
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function readBody(): ?array {
    $raw = file_get_contents('php://input');
    if (!$raw || !trim($raw)) return null;
    $data = json_decode($raw, true);
    return json_last_error() === JSON_ERROR_NONE ? $data : null;
}

function extractBearer(): ?string {
    $auth = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (preg_match('/^Bearer\s+(.+)$/i', $auth, $m)) return $m[1];
    return null;
}

/** Timing-safe string comparison */
function safeEqual(string $a, string $b): bool {
    if (strlen($a) !== strlen($b)) return false;
    return hash_equals($a, $b);
}

/**
 * Compute a deterministic session ID from a plan.
 * Uses CRC32 over canonical JSON, base64url-encoded — mirrors the Node.js logic.
 */
function makePlanId(array $plan): string {
    $canonical = json_encode([
        'v'        => $plan['v']        ?? null,
        'title'    => $plan['title']    ?? null,
        'start'    => $plan['start']    ?? null,
        'quantum'  => $plan['quantum']  ?? null,
        'mode'     => $plan['mode']     ?? null,
        'nodes'    => $plan['nodes']    ?? [],
        'segments' => $plan['segments'] ?? [],
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    $hash = sprintf('%08x', crc32($canonical));
    return rtrim(strtr(base64_encode(hex2bin($hash)), '+/', '-_'), '=');
}

// ── Route handlers ────────────────────────────────────────────────────────────

function handleHealth(): void {
    global $db;
    $sessions = (int)$db->querySingle('SELECT COUNT(*) FROM relay_sessions');
    $frames   = (int)$db->querySingle('SELECT COUNT(*) FROM relay_frames');
    sendJSON(200, [
        'status'        => 'ok',
        'sessions'      => $sessions,
        'queued_frames' => $frames,
    ]);
}

function handleRegisterSession(): void {
    global $db;
    $body = readBody();
    if (!$body || !isset($body['nodes']) || !is_array($body['nodes']) || !count($body['nodes'])) {
        sendJSON(400, ['error' => 'Plan must include nodes array']);
    }

    $sessionId = makePlanId($body);
    $nodes     = $body['nodes'];

    $participants = array_values(array_filter($nodes, fn($n) => ($n['role'] ?? '') !== 'HOST'));
    $delayS       = isset($participants[0]['delay']) ? (float)$participants[0]['delay'] : 0;
    $delay_ms     = (int)round($delayS * 1000);

    $tls_fingerprint = (isset($body['relay']['tls_fingerprint']) && $body['relay']['tls_fingerprint'])
        ? $body['relay']['tls_fingerprint']
        : bin2hex(random_bytes(16));

    $stmt = $db->prepare('
        INSERT OR REPLACE INTO relay_sessions (session_id, nodes, delay_ms, tls_fingerprint, created_at, plan)
        VALUES (:id, :nodes, :delay_ms, :fp, :created_at, :plan)
    ');
    $stmt->bindValue(':id',         $sessionId);
    $stmt->bindValue(':nodes',      json_encode($nodes));
    $stmt->bindValue(':delay_ms',   $delay_ms,      SQLITE3_INTEGER);
    $stmt->bindValue(':fp',         $tls_fingerprint);
    $stmt->bindValue(':created_at', (int)(microtime(true) * 1000), SQLITE3_INTEGER);
    $stmt->bindValue(':plan',       json_encode($body));
    $stmt->execute();

    sendJSON(200, ['sessionId' => $sessionId, 'status' => 'ready', 'delay_ms' => $delay_ms, 'tls_fingerprint' => $tls_fingerprint]);
}

function handleDeleteSession(string $sessionId): void {
    global $db;
    $row = $db->querySingle("SELECT session_id FROM relay_sessions WHERE session_id = '$sessionId'");
    if (!$row) sendJSON(404, ['error' => 'Session not found']);
    $db->exec("DELETE FROM relay_sessions WHERE session_id = " . SQLite3::escapeString($sessionId));
    $db->exec("DELETE FROM relay_frames WHERE session_id = "   . SQLite3::escapeString($sessionId));
    sendJSON(200, ['deleted' => true, 'sessionId' => $sessionId]);
}

function handleSend(string $sessionId): void {
    global $db;
    $row = $db->querySingle("SELECT delay_ms, tls_fingerprint, nodes FROM relay_sessions WHERE session_id = '" . SQLite3::escapeString($sessionId) . "'", true);
    if (!$row) sendJSON(404, ['error' => 'Session not found']);

    $token = extractBearer();
    if (!$token || !safeEqual($token, $row['tls_fingerprint'])) {
        sendJSON(401, ['error' => 'Invalid or missing Authorization token']);
    }

    $body = readBody();
    if (!$body) sendJSON(400, ['error' => 'Invalid JSON body']);

    $nodeId       = $body['nodeId']       ?? null;
    $targetNodeId = $body['targetNodeId'] ?? null;
    $data         = $body['data']         ?? null;
    $timestamp_ms = isset($body['timestamp_ms']) ? (int)$body['timestamp_ms'] : (int)(microtime(true) * 1000);

    if (!$nodeId || $data === null) sendJSON(400, ['error' => 'nodeId and data are required']);

    $nodes   = json_decode($row['nodes'], true);
    $nodeIds = array_column($nodes, 'id');
    if (!in_array($nodeId, $nodeIds, true)) sendJSON(400, ['error' => "nodeId '$nodeId' not in session"]);

    $delay_ms  = (int)$row['delay_ms'];
    $deliverAt = $timestamp_ms + $delay_ms;

    $stmt = $db->prepare('
        INSERT INTO relay_frames (session_id, node_id, target_node_id, data, timestamp_ms, deliver_at, delay_ms)
        VALUES (:sid, :nid, :tnid, :data, :ts, :da, :dm)
    ');
    $stmt->bindValue(':sid',  $sessionId);
    $stmt->bindValue(':nid',  $nodeId);
    $stmt->bindValue(':tnid', $targetNodeId);
    $stmt->bindValue(':data', json_encode($data));
    $stmt->bindValue(':ts',   $timestamp_ms, SQLITE3_INTEGER);
    $stmt->bindValue(':da',   $deliverAt,    SQLITE3_INTEGER);
    $stmt->bindValue(':dm',   $delay_ms,     SQLITE3_INTEGER);
    $stmt->execute();

    sendJSON(200, ['queued' => true, 'deliver_at' => $deliverAt]);
}

function handleReceive(string $sessionId): void {
    global $db;
    $row = $db->querySingle("SELECT tls_fingerprint, nodes FROM relay_sessions WHERE session_id = '" . SQLite3::escapeString($sessionId) . "'", true);
    if (!$row) sendJSON(404, ['error' => 'Session not found']);

    $token = extractBearer();
    if (!$token || !safeEqual($token, $row['tls_fingerprint'])) {
        sendJSON(401, ['error' => 'Invalid or missing Authorization token']);
    }

    $nodeId = $_GET['node'] ?? null;
    if (!$nodeId) sendJSON(400, ['error' => 'node query param required']);

    $nodes   = json_decode($row['nodes'], true);
    $nodeIds = array_column($nodes, 'id');
    if (!in_array($nodeId, $nodeIds, true)) sendJSON(400, ['error' => "nodeId '$nodeId' not in session"]);

    $now     = (int)(microtime(true) * 1000);
    $sid_esc = SQLite3::escapeString($sessionId);
    $nid_esc = SQLite3::escapeString($nodeId);

    // Fetch frames that are ready for this node (sent by others, targeted to this node or broadcast)
    $result = $db->query("
        SELECT id, node_id, target_node_id, data, timestamp_ms, delay_ms
        FROM relay_frames
        WHERE session_id = '$sid_esc'
          AND node_id != '$nid_esc'
          AND (target_node_id IS NULL OR target_node_id = '$nid_esc')
          AND deliver_at <= $now
    ");

    $ready = [];
    $ids   = [];
    while ($frame = $result->fetchArray(SQLITE3_ASSOC)) {
        $ids[]   = (int)$frame['id'];
        $ready[] = [
            'nodeId'       => $frame['node_id'],
            'targetNodeId' => $frame['target_node_id'],
            'data'         => json_decode($frame['data'], true),
            'timestamp_ms' => (int)$frame['timestamp_ms'],
            'delay_ms'     => (int)$frame['delay_ms'],
        ];
    }

    if ($ids) {
        $db->exec('DELETE FROM relay_frames WHERE id IN (' . implode(',', $ids) . ')');
    }

    sendJSON(200, ['frames' => $ready]);
}

// ── Router ────────────────────────────────────────────────────────────────────

$method   = $_SERVER['REQUEST_METHOD'];
$pathInfo = $_SERVER['PATH_INFO'] ?? parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH);

// Strip script name from path if present
$script = $_SERVER['SCRIPT_NAME'] ?? '';
if ($script && strpos($pathInfo, $script) === 0) {
    $pathInfo = substr($pathInfo, strlen($script));
}
$pathInfo = '/' . ltrim($pathInfo ?? '', '/');

if ($method === 'GET'  && $pathInfo === '/relay/health')  handleHealth();
if ($method === 'POST' && $pathInfo === '/relay/session') handleRegisterSession();

if (preg_match('#^/relay/session/([^/]+)$#', $pathInfo, $m)) {
    if ($method === 'DELETE') handleDeleteSession($m[1]);
}

if (preg_match('#^/relay/([^/]+)/send$#', $pathInfo, $m)) {
    if ($method === 'POST') handleSend($m[1]);
}

if (preg_match('#^/relay/([^/]+)/receive$#', $pathInfo, $m)) {
    if ($method === 'GET') handleReceive($m[1]);
}

sendJSON(404, ['error' => 'Not found', 'path' => $pathInfo]);
