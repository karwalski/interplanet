<?php
/**
 * test_planid.php: the web API computes spec planIds
 * (docs/LTX-SPECIFICATION.md sections 4.3 and 4.5).
 *
 * Feeds every golden vector in spec/golden/plan-ids.json to
 *   1. ltx_make_plan_id() in api/ltx-planid.php, and
 *   2. POST api/ltx.php?action=session (and demo/relay-server.php
 *      POST /relay/session), each run under PHP's built-in web server,
 * and asserts the planId. CLI only.
 *
 * Run: php api/tests/test_planid.php
 */

declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

require_once __DIR__ . '/../ltx-planid.php';

$repo   = dirname(__DIR__, 2);
$golden = ltx_plan_decode((string)file_get_contents($repo . '/spec/golden/plan-ids.json'));

$passed = 0;
$failed = 0;
function check(string $name, bool $ok, string $detail = ''): void {
    global $passed, $failed;
    if ($ok) { $passed++; echo "PASS $name\n"; }
    else     { $failed++; echo "FAIL $name" . ($detail !== '' ? ": $detail" : '') . "\n"; }
}
function same(string $name, mixed $expected, mixed $got): void {
    check($name, $expected === $got, 'expected ' . var_export($expected, true) . ' got ' . var_export($got, true));
}

// ── 1. Library: golden vectors ──────────────────────────────────────────────

foreach ($golden->vectors as $v) {
    // Round-trip through JSON text so each plan is decoded the way the API decodes it.
    $plan = ltx_plan_decode(ltx_js_stringify($v->plan));
    same("ltx_make_plan_id {$v->name}", $v->planId, ltx_make_plan_id($plan));
    check("ltx_is_plan_id {$v->name}", ltx_is_plan_id($v->planId));
}

// ── 2. Library: JavaScript compatibility beyond the vectors ─────────────────
//
// Expected values produced by javascript/ltx/ltx-sdk.js:
//   makePlanId(JSON.parse(text)) and JSON.stringify(JSON.parse(text)).

$extraText = '{"v":2,"title":"Ünïcödé 🚀  /","start":"2026-05-01T23:30:00-02:00","quantum":3.0,'
    . '"mode":"LTX-ASYNC","nodes":[{"id":"N0","name":"Base Étoile","role":"HOST","delay":0,"location":"earth"},'
    . '{"id":"N1","name":"Ceres 🚀 Outpost","role":"PARTICIPANT","delay":1234.50,"location":"ceres"}],'
    . '"segments":[{"type":"TX","q":1.0},{"type":"RX","q":1}],'
    . '"meta":{"b":1,"10":2,"2":3,"x":1e21,"y":0.000001,"z":1.5e-7,"big":12345678901234567890,"e":{},"a":[]}}';
$extraJs = '{"v":2,"title":"Ünïcödé 🚀 ' . "\u{2028}" . '/","start":"2026-05-01T23:30:00-02:00","quantum":3,'
    . '"mode":"LTX-ASYNC","nodes":[{"id":"N0","name":"Base Étoile","role":"HOST","delay":0,"location":"earth"},'
    . '{"id":"N1","name":"Ceres 🚀 Outpost","role":"PARTICIPANT","delay":1234.5,"location":"ceres"}],'
    . '"segments":[{"type":"TX","q":1},{"type":"RX","q":1}],'
    . '"meta":{"2":3,"10":2,"b":1,"x":1e+21,"y":0.000001,"z":1.5e-7,"big":12345678901234567000,"e":{},"a":[]}}';
same('ltx_js_stringify matches JSON.stringify (numbers, U+2028, index keys, {} vs [])',
    $extraJs, ltx_js_stringify(ltx_plan_decode($extraText)));
same('ltx_make_plan_id non-ASCII names, UTF-16 slicing, offset start date',
    'LTX-20260502-BASEÉTOI-CERE-v2-69555394', ltx_make_plan_id(ltx_plan_decode($extraText)));

$v1Text = '{"title":"Legacy","start":"2026-01-02T03:04:05Z","quantum":5,"mode":"LTX",'
    . '"txName":"Earth HQ","rxName":"Moon Base","delay":2,"segments":[{"type":"TX","q":1}]}';
same('ltx_make_plan_id v1 plan (upgradeConfig)',
    'LTX-20260102-EARTHHQ-MOON-v2-bd952c22', ltx_make_plan_id(ltx_plan_decode($v1Text)));

$v3Text = '{"v":3,"title":"x","start":"2026-02-03T00:00:00Z","quantum":5,"mode":"LTX",'
    . '"nodes":[{"id":"N0","name":"Ärth","role":"HOST","delay":0}],"segments":[{"type":"TX","q":1}],'
    . '"delays":{},"planVersion":1}';
same('ltx_make_plan_id v3 single node, empty delays object',
    'LTX-20260203-ÄRTH-RX-v3-4e9a2240', ltx_make_plan_id(ltx_plan_decode($v3Text)));

check('ltx_is_plan_id rejects junk', !ltx_is_plan_id("LTX-1' OR 1=1") && !ltx_is_plan_id('LTX-20260315-A-B-v2-XYZ'));

// ── 3. HTTP: api/ltx.php and demo/relay-server.php under php -S ─────────────

function startServer(string $docroot, int $port) {
    $cmd = [PHP_BINARY, '-S', "127.0.0.1:$port", '-t', $docroot];
    $proc = proc_open($cmd, [1 => ['file', '/dev/null', 'w'], 2 => ['file', '/dev/null', 'w']], $pipes);
    for ($i = 0; $i < 50; $i++) {
        $fp = @fsockopen('127.0.0.1', $port);
        if ($fp) { fclose($fp); return $proc; }
        usleep(100000);
    }
    throw new RuntimeException("server on port $port did not start");
}

function postJson(string $url, string $body): array {
    $ctx = stream_context_create(['http' => [
        'method' => 'POST', 'header' => "Content-Type: application/json\r\n",
        'content' => $body, 'ignore_errors' => true,
    ]]);
    $resp = (string)file_get_contents($url, false, $ctx);
    return (array)json_decode($resp, true);
}

// api/ltx.php requires ../db-config.php (not in the repo): run a copy of it
// from a temp docroot with a stub whose getDB() fails, which the API treats
// as non-fatal. (A symlink would not do: __DIR__ resolves symlinks.)
$site = sys_get_temp_dir() . '/ltx-planid-test-' . getmypid();
@mkdir($site . '/api', 0777, true);
foreach (['ltx.php', 'ltx-planid.php'] as $f) copy($repo . "/api/$f", "$site/api/$f");
file_put_contents($site . '/db-config.php',
    "<?php function getDB(): PDO { throw new RuntimeException('no database in tests'); }\n");

$apiPort   = 18000 + getmypid() % 1000;
$relayPort = $apiPort + 1000;
$servers   = [startServer($site, $apiPort), startServer($repo . '/demo', $relayPort)];

try {
    foreach ($golden->vectors as $v) {
        $body = ltx_js_stringify($v->plan);   // JSON.stringify(plan), key order kept
        $r = postJson("http://127.0.0.1:$apiPort/api/ltx.php?action=session", $body);
        same("POST api/ltx.php?action=session {$v->name}", $v->planId, $r['plan_id'] ?? null);
        $r = postJson("http://127.0.0.1:$relayPort/relay-server.php/relay/session", $body);
        same("POST relay-server.php/relay/session {$v->name}", $v->planId, $r['sessionId'] ?? null);
    }
    $r = postJson("http://127.0.0.1:$apiPort/api/ltx.php?action=session", $extraText);
    same('POST api/ltx.php?action=session non-ASCII plan', 'LTX-20260502-BASEÉTOI-CERE-v2-69555394', $r['plan_id'] ?? null);
    same('POST api/ltx.php?action=session mode response unchanged (LTX-ASYNC)', 'LTX-ASYNC', $r['mode'] ?? null);
    $r = postJson("http://127.0.0.1:$apiPort/api/ltx.php?action=session", $v1Text);
    same('POST api/ltx.php?action=session mode "LTX" still reported as LTX-LIVE', 'LTX-LIVE', $r['mode'] ?? null);
} finally {
    foreach ($servers as $p) { proc_terminate($p); proc_close($p); }
    foreach (['ltx.php', 'ltx-planid.php'] as $f) @unlink("$site/api/$f");
    @rmdir($site . '/api');
    @unlink($site . '/db-config.php');
    @rmdir($site);
}

echo "\n$passed passed, $failed failed\n";
exit($failed ? 1 : 0);
