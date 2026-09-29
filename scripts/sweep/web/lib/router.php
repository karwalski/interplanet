<?php
// php -S router for the sweep site: serve demo/ as-is (including /api/*.php and
// relay-server.php/relay/...), but never the test-only DB stub or its data.
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?: '/';
if ($path === '/db-config.php' || str_ends_with($path, '.sqlite')) {
    http_response_code(404);
    echo 'not found';
    return true;
}
return false;
