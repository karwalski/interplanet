<?php
/**
 * autoload.php — PSR-4 autoloader for InterplanetLTX namespace
 * Story 33.4 — PHP LTX library
 *
 * Usage:
 *   require_once __DIR__ . '/autoload.php';
 *   use InterplanetLTX\InterplanetLTX;
 */

spl_autoload_register(function (string $class): void {
    $prefix = 'InterplanetLTX\\';
    if (!str_starts_with($class, $prefix)) {
        return;
    }
    $relative = str_replace('\\', DIRECTORY_SEPARATOR, substr($class, strlen($prefix)));
    $file = __DIR__ . DIRECTORY_SEPARATOR . 'InterplanetLTX' . DIRECTORY_SEPARATOR . $relative . '.php';
    if (file_exists($file)) {
        require_once $file;
    }
});
