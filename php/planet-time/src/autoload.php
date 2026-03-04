<?php
/**
 * Simple PSR-4-style autoloader for InterplanetTime namespace.
 * Use this when Composer is not available.
 */
spl_autoload_register(function (string $class): void {
    $prefix = 'InterplanetTime\\';
    $base   = __DIR__ . '/InterplanetTime/';

    if (!str_starts_with($class, $prefix)) return;

    $relative = substr($class, strlen($prefix));
    $file = $base . str_replace('\\', DIRECTORY_SEPARATOR, $relative) . '.php';
    if (file_exists($file)) require_once $file;
});
