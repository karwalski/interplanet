<?php
declare(strict_types=1);

namespace InterplanetTime;

/**
 * InterplanetTime — main facade.
 *
 * Provides a single-class static API mirroring the JavaScript planet-time.js
 * public surface, for use without Composer autoloading (single require_once).
 *
 * @example
 *   $pt = InterplanetTime::getPlanetTime('mars', 946728000000);
 *   echo $pt->timeStr;  // "HH:MM"
 *
 *   $lt = InterplanetTime::lightTravelSeconds('earth', 'mars', time() * 1000);
 *   echo InterplanetTime::formatLightTime($lt);  // e.g. "3 min 22 s"
 */
final class InterplanetTime
{
    public const VERSION = Constants::VERSION;

    private function __construct() {}

    // ── Planet time ──────────────────────────────────────────────────────────

    public static function getPlanetTime(
        string $planet,
        int    $utcMs,
        float  $tzOffset = 0.0,
    ): PlanetTimeResult {
        return Time::getPlanetTime($planet, $utcMs, $tzOffset);
    }

    public static function getMTC(int $utcMs): MTCResult
    {
        return Time::getMTC($utcMs);
    }

    public static function getMarsTimeAtOffset(int $utcMs, float $offsetHours): PlanetTimeResult
    {
        return Time::getMarsTimeAtOffset($utcMs, $offsetHours);
    }

    // ── Orbital mechanics ────────────────────────────────────────────────────

    public static function helioPos(string $planet, int $utcMs): HelioPosResult
    {
        return Orbital::helioPos($planet, $utcMs);
    }

    public static function bodyDistanceAu(string $a, string $b, int $utcMs): float
    {
        return Orbital::bodyDistanceAu($a, $b, $utcMs);
    }

    public static function lightTravelSeconds(string $a, string $b, int $utcMs): float
    {
        return Orbital::lightTravelSeconds($a, $b, $utcMs);
    }

    public static function checkLineOfSight(string $a, string $b, int $utcMs): LineOfSightResult
    {
        return Orbital::checkLineOfSight($a, $b, $utcMs);
    }

    public static function lowerQuartileLightTime(string $a, string $b, int $refMs): float
    {
        return Orbital::lowerQuartileLightTime($a, $b, $refMs);
    }

    // ── Scheduling ───────────────────────────────────────────────────────────

    /** @return MeetingWindow[] */
    public static function findMeetingWindows(
        string $planetA,
        string $planetB,
        int    $fromMs,
        int    $earthDays = 7,
    ): array {
        return Scheduling::findMeetingWindows($planetA, $planetB, $fromMs, $earthDays);
    }

    // ── Formatting ───────────────────────────────────────────────────────────

    public static function formatLightTime(float $seconds): string
    {
        return Formatting::formatLightTime($seconds);
    }

    public static function formatPlanetTimeIso(string $planet, int $h, int $m, int $s): string
    {
        return Formatting::formatPlanetTimeIso($planet, $h, $m, $s);
    }

    // ── Constants ────────────────────────────────────────────────────────────

    public static function taiMinusUtc(int $utcMs): int
    {
        return Orbital::taiMinusUtc($utcMs);
    }

    public static function jde(int $utcMs): float
    {
        return Orbital::jde($utcMs);
    }

    public static function jc(int $utcMs): float
    {
        return Orbital::jc($utcMs);
    }
}
