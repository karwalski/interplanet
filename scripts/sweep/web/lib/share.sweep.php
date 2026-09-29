<?php
/**
 * Sweep stand-in for share.php, which is server-side only (.gitignore) and
 * so absent from demo/. site.js copies this file into the test site as
 * share.php so the index share button and ?share= links run end to end.
 * It implements the contract sky.js uses:
 *
 * POST share.php            body: {"config":"<JSON string from getConfigJSON()>"}
 *   -> {"code":"Ab3dE9","url":"http://host/?share=Ab3dE9"}
 * GET  share.php?code=Ab3dE9
 *   -> {"config":"<JSON string>"}   (404 when unknown or expired)
 *
 * Stored in sky_configs (demo/db-schema.sql) via the SQLite getDB() stub.
 */
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function shareOut(int $status, array $body): never {
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

$cfgFile = __DIR__ . '/db-config.php';
if (!is_file($cfgFile)) shareOut(503, ['error' => 'Sharing is not configured on this server']);
require_once $cfgFile;

const SHARE_MAX_BYTES = 65536;
const SHARE_TTL_DAYS  = 30;

try {
    $db = getDB();
} catch (Throwable $e) {
    error_log('share.php db error: ' . $e->getMessage());
    shareOut(503, ['error' => 'Database unavailable']);
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
    $code = is_string($_GET['code'] ?? null) ? $_GET['code'] : '';
    if (!preg_match('/^[A-Za-z0-9]{6}$/', $code)) shareOut(400, ['error' => 'Invalid code']);
    $st = $db->prepare('SELECT config, expires_at FROM sky_configs WHERE code = ? LIMIT 1');
    $st->execute([$code]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row || strtotime($row['expires_at'] . ' UTC') < time()) shareOut(404, ['error' => 'Share link not found or expired']);
    try {
        $db->prepare('UPDATE sky_configs SET views = views + 1 WHERE code = ?')->execute([$code]);
    } catch (Throwable) {}
    shareOut(200, ['config' => $row['config']]);
}

if ($method !== 'POST') shareOut(405, ['error' => 'GET or POST required']);

$raw = (string)file_get_contents('php://input');
if (strlen($raw) > SHARE_MAX_BYTES) shareOut(413, ['error' => 'Config too large']);
$body = json_decode($raw, true);
$config = is_array($body) ? ($body['config'] ?? null) : null;
if (!is_string($config) || !is_array(json_decode($config, true))) {
    shareOut(400, ['error' => 'Body must be {"config": "<JSON object string>"}']);
}

$alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
$expires  = gmdate('Y-m-d H:i:s', time() + SHARE_TTL_DAYS * 86400);
$insert   = $db->prepare('INSERT INTO sky_configs (code, config, expires_at) VALUES (?, ?, ?)');
for ($attempt = 0; $attempt < 5; $attempt++) {
    $code = '';
    for ($i = 0; $i < 6; $i++) $code .= $alphabet[random_int(0, 61)];
    try {
        $insert->execute([$code, $config, $expires]);
    } catch (Throwable) {
        continue;   // code collision (unique key): try another
    }
    $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
          || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
    $host  = preg_replace('/[^A-Za-z0-9.:\-\[\]]/', '', (string)($_SERVER['HTTP_HOST'] ?? 'interplanet.live'));
    $dir   = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/share.php')), '/');
    shareOut(200, ['code' => $code, 'url' => ($https ? 'https' : 'http') . '://' . $host . $dir . '/?share=' . $code]);
}
shareOut(500, ['error' => 'Could not allocate a share code']);
