<?php
declare(strict_types=1);

namespace InterplanetTime;

/** Formatting utilities — ported from planet-time.js. */
final class Formatting
{
    private function __construct() {}

    /**
     * Format a light-travel duration in seconds to a human-readable string.
     * Examples: 45 → "45 s", 186 → "3 min 6 s", 3700 → "1 h 1 min 40 s"
     */
    public static function formatLightTime(float $seconds): string
    {
        $s   = (int)round($seconds);
        $h   = intdiv($s, 3600);
        $m   = intdiv($s % 3600, 60);
        $sec = $s % 60;

        if ($h > 0) {
            $parts = ["{$h} h"];
            if ($m > 0)   $parts[] = "{$m} min";
            if ($sec > 0) $parts[] = "{$sec} s";
            return implode(' ', $parts);
        }
        if ($m > 0) {
            $parts = ["{$m} min"];
            if ($sec > 0) $parts[] = "{$sec} s";
            return implode(' ', $parts);
        }
        return "{$sec} s";
    }

    /**
     * Format a planet local time as an ISO-8601-like string.
     * Example: "2026-056T14:30:00+Mars" (day-of-year format)
     */
    public static function formatPlanetTimeIso(string $planet, int $h, int $m, int $s): string
    {
        $H = str_pad((string)$h, 2, '0', STR_PAD_LEFT);
        $M = str_pad((string)$m, 2, '0', STR_PAD_LEFT);
        $S = str_pad((string)$s, 2, '0', STR_PAD_LEFT);
        return "{$H}:{$M}:{$S}+{$planet}";
    }
}
