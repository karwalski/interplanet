<?php
/**
 * Test-only db-config.php: getDB() on a throwaway SQLite file, so api/ltx.php
 * session, ics and feedback actions run end to end without MySQL.
 * The schema mirrors api/schema.sql. "INSERT IGNORE" (MySQL) is rewritten to
 * SQLite's "INSERT OR IGNORE"; nothing else in api/ltx.php is MySQL-specific.
 */
declare(strict_types=1);

class SweepPDO extends PDO {
    public function prepare(string $query, array $options = []): PDOStatement|false {
        return parent::prepare(str_replace('INSERT IGNORE', 'INSERT OR IGNORE', $query), $options);
    }
}

function getDB(): PDO {
    static $db = null;
    if ($db) return $db;
    $path = getenv('SWEEP_SQLITE') ?: (__DIR__ . '/sweep.sqlite');
    $db = new SweepPDO('sqlite:' . $path, null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $db->exec('CREATE TABLE IF NOT EXISTS ltx_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT, plan_id TEXT NOT NULL UNIQUE,
        plan_json TEXT NOT NULL, total_min INTEGER NOT NULL DEFAULT 0,
        views INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)');
    $db->exec("CREATE TABLE IF NOT EXISTS ltx_feedback (
        id INTEGER PRIMARY KEY AUTOINCREMENT, plan_id TEXT, session_title TEXT,
        mode TEXT, actual_start TEXT, actual_end TEXT, nodes_json TEXT,
        segments_json TEXT, outcome TEXT NOT NULL DEFAULT 'unknown',
        satisfaction INTEGER, relay_used INTEGER NOT NULL DEFAULT 0,
        signal_issues INTEGER NOT NULL DEFAULT 0, notes TEXT, raw_json TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)");
    $db->exec('CREATE TABLE IF NOT EXISTS sky_configs (
        id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT NOT NULL UNIQUE,
        config TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        expires_at TEXT NOT NULL, views INTEGER NOT NULL DEFAULT 0)');
    return $db;
}
