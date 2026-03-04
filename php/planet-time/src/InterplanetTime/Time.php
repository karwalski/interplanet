<?php
declare(strict_types=1);

namespace InterplanetTime;

/**
 * Planet time calculations — ported from planet-time.js.
 */
final class Time
{
    private function __construct() {}

    // ── Work-hour constants (same as JS) ─────────────────────────────────────
    // Work period: period 2 of a 3-period day (each period = 8 hours)
    // Work hours:  09:00–17:00 in local time

    private const WORK_START = 9;
    private const WORK_END   = 17;
    private const PERIOD_LEN = 8; // hours per period (3 periods per day)

    // ── Mars calendar ────────────────────────────────────────────────────────

    private const MARS_SOLS_PER_YEAR = 669;

    // ── Main planet-time function ─────────────────────────────────────────────

    /**
     * Compute local time for any planet at a given UTC instant.
     *
     * @param string $planet  One of: mercury, venus, earth, mars, jupiter,
     *                        saturn, uranus, neptune, moon
     * @param int    $utcMs   UTC milliseconds since Unix epoch
     * @param float  $tzOffset Planet timezone offset in planet-local hours
     */
    public static function getPlanetTime(
        string $planet,
        int    $utcMs,
        float  $tzOffset = 0.0,
    ): PlanetTimeResult {
        // Moon uses Earth's sidereal day for display purposes
        $effectivePlanet = ($planet === 'moon') ? 'earth' : $planet;

        // Epoch reference = J2000_MS for all planets except Mars
        $epochMs = ($effectivePlanet === 'mars')
            ? Constants::MARS_EPOCH_MS
            : Constants::J2000_MS;

        // Day length in milliseconds
        $dayMs = self::dayLengthMs($effectivePlanet);

        $elapsedMs  = $utcMs - $epochMs;
        $dayFrac    = fmod($elapsedMs / $dayMs, 1.0);
        if ($dayFrac < 0.0) $dayFrac += 1.0;

        $localHour  = ($dayFrac * 24.0 + $tzOffset + 24.0);
        $localHour  = fmod($localHour, 24.0);

        $hour   = (int)$localHour;
        $minF   = ($localHour - $hour) * 60.0;
        $minute = (int)$minF;
        $second = (int)(($minF - $minute) * 60.0);

        // Day number (0-indexed from epoch)
        $dayNumber = (int)floor($elapsedMs / $dayMs);

        // Work period (0=sleep, 1=morning, 2=work, 3=evening — split into 3 even periods)
        $periodInWeek = (int)floor($localHour / self::PERIOD_LEN);
        $isWorkPeriod = ($periodInWeek === 1); // period 1 = 08:00-16:00 (loose)
        $isWorkHour   = ($localHour >= self::WORK_START && $localHour < self::WORK_END);

        // Day in year / year number
        $totalDays  = (int)floor(abs($elapsedMs) / $dayMs) * ($elapsedMs < 0 ? -1 : 1);
        $daysPerYear = self::daysPerYear($effectivePlanet);
        $yearNumber  = (int)floor($dayNumber / $daysPerYear);
        $dayInYear   = (($dayNumber % $daysPerYear) + $daysPerYear) % $daysPerYear;

        // Mars sol-in-year
        $solInYear   = ($effectivePlanet === 'mars') ? $dayInYear % self::MARS_SOLS_PER_YEAR : null;
        $solsPerYear = ($effectivePlanet === 'mars') ? self::MARS_SOLS_PER_YEAR : null;

        $h2 = str_pad((string)$hour,   2, '0', STR_PAD_LEFT);
        $m2 = str_pad((string)$minute, 2, '0', STR_PAD_LEFT);
        $s2 = str_pad((string)$second, 2, '0', STR_PAD_LEFT);

        return new PlanetTimeResult(
            hour:         $hour,
            minute:       $minute,
            second:       $second,
            localHour:    $localHour,
            dayFraction:  $dayFrac,
            dayNumber:    $dayNumber,
            dayInYear:    $dayInYear,
            yearNumber:   $yearNumber,
            periodInWeek: $periodInWeek,
            isWorkPeriod: $isWorkPeriod,
            isWorkHour:   $isWorkHour,
            timeStr:      "$h2:$m2",
            timeStrFull:  "$h2:$m2:$s2",
            solInYear:    $solInYear,
            solsPerYear:  $solsPerYear,
        );
    }

    // ── Mars Time Convention ──────────────────────────────────────────────────

    public static function getMTC(int $utcMs): MTCResult
    {
        $ms  = $utcMs - Constants::MARS_EPOCH_MS;
        $sol = (int)floor($ms / Constants::MARS_SOL_MS);

        $fracMs = fmod((float)$ms, (float)Constants::MARS_SOL_MS);
        if ($fracMs < 0.0) $fracMs += Constants::MARS_SOL_MS;

        $totalSec = $fracMs / 1000.0;
        $hour     = (int)floor($totalSec / 3600.0);
        $minute   = (int)floor(fmod($totalSec, 3600.0) / 60.0);
        $second   = (int)fmod($totalSec, 60.0);

        $h2 = str_pad((string)$hour,   2, '0', STR_PAD_LEFT);
        $m2 = str_pad((string)$minute, 2, '0', STR_PAD_LEFT);

        return new MTCResult(
            sol:    $sol,
            hour:   $hour,
            minute: $minute,
            second: $second,
            mtcStr: "$h2:$m2",
        );
    }

    public static function getMarsTimeAtOffset(int $utcMs, float $offsetHours): PlanetTimeResult
    {
        return self::getPlanetTime('mars', $utcMs, $offsetHours);
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    /**
     * Sidereal day length in milliseconds for each planet.
     * Values from JS planet-time.js PLANETS table.
     */
    private static function dayLengthMs(string $planet): int
    {
        return match ($planet) {
            'mercury' => 5067840000,
            'venus'   => 20996640000,
            'earth'   => 86400000,
            'mars'    => 88775244,
            'jupiter' => 35730000,
            'saturn'  => 38361600000,
            'uranus'  => 62054400000,
            'neptune' => 57996000000,
            default   => 86400000,  // moon → earth
        };
    }

    private static function daysPerYear(string $planet): int
    {
        return match ($planet) {
            'mercury' => 2,
            'venus'   => 1,
            'earth'   => 365,
            'mars'    => 669,
            'jupiter' => 10476,
            'saturn'  => 24491,
            'uranus'  => 42718,
            'neptune' => 89666,
            default   => 365,
        };
    }
}
