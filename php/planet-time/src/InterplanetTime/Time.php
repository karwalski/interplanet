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
        // Mirrors getPlanetTime() in planet-time.js.
        // Moon uses Earth's solar day (tidally locked; work schedules run on Earth time)
        $key = ($planet === 'moon') ? 'earth' : $planet;
        $p   = Constants::PLANET_DATA[$key] ?? null;
        if ($p === null) {
            throw new \InvalidArgumentException("Unknown planet: $planet");
        }
        $solarDayMs = (float)$p['solarDayMs'];

        $elapsedMs   = $utcMs - $p['epochMs'] + $tzOffset / 24.0 * $solarDayMs;
        $totalDays   = $elapsedMs / $solarDayMs;
        $dayNumber   = (int)floor($totalDays);
        $dayFrac     = $totalDays - $dayNumber;

        $localHour = $dayFrac * 24.0;
        $hour      = (int)floor($localHour);
        $minute    = (int)floor(($localHour - $hour) * 60.0);
        $second    = (int)floor((($localHour - $hour) * 60.0 - $minute) * 60.0);

        if ($p['earthClockSchedule']) {
            // Mercury/Venus: Earth-standard work week (0=Mon..6=Sun), UTC work hours.
            $msOfDay      = self::floorMod($utcMs, Constants::EARTH_DAY_MS);
            $secOfDay     = intdiv($msOfDay, 1000);
            $daysSince    = intdiv($utcMs - $msOfDay, Constants::EARTH_DAY_MS);
            $utcDay       = self::floorMod($daysSince + 4, 7);   // 1970-01-01 was a Thursday (0=Sun)
            $periodInWeek = ($utcDay + 6) % 7;
            $isWorkPeriod = $periodInWeek < $p['workPeriodsPerWeek'];
            $utcHour      = intdiv($secOfDay, 3600) + intdiv($secOfDay % 3600, 60) / 60.0 + ($secOfDay % 60) / 3600.0;
            $isWorkHour   = $isWorkPeriod && $utcHour >= $p['workHoursStart'] && $utcHour < $p['workHoursEnd'];
        } else {
            $totalPeriods = $totalDays / $p['daysPerPeriod'];
            $periodInWeek = self::floorMod((int)floor($totalPeriods), $p['periodsPerWeek']);
            $isWorkPeriod = $periodInWeek < $p['workPeriodsPerWeek'];
            $isWorkHour   = $isWorkPeriod && $localHour >= $p['workHoursStart'] && $localHour < $p['workHoursEnd'];
        }

        $yearLenDays = $p['siderealYrMs'] / $solarDayMs;
        $yearNumber  = (int)floor($totalDays / $yearLenDays);
        $dayInYear   = $totalDays - $yearNumber * $yearLenDays;

        $solInYear   = ($key === 'mars') ? (int)floor($dayInYear) : null;
        $solsPerYear = ($key === 'mars') ? (int)round($yearLenDays) : null;

        // Zone ID: null for Earth, otherwise PREFIX + sign + trunc(offset), as in JS
        $zonePrefixes = [
            'mercury' => 'MMT', 'venus'   => 'VMT', 'mars'    => 'AMT',
            'jupiter' => 'JMT', 'saturn'  => 'SMT', 'uranus'  => 'UMT',
            'neptune' => 'NMT', 'moon'    => 'LMT',
        ];
        $prefix = $zonePrefixes[$planet] ?? null;
        $zoneId = ($prefix === null)
            ? null
            : $prefix . ($tzOffset >= 0.0 ? '+' : '') . (string)(int)$tzOffset;

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
            dayInYear:    (int)floor($dayInYear),
            yearNumber:   $yearNumber,
            periodInWeek: $periodInWeek,
            isWorkPeriod: $isWorkPeriod,
            isWorkHour:   $isWorkHour,
            timeStr:      "$h2:$m2",
            timeStrFull:  "$h2:$m2:$s2",
            solInYear:    $solInYear,
            solsPerYear:  $solsPerYear,
            zoneId:       $zoneId,
        );
    }

    private static function floorMod(int $a, int $b): int
    {
        return (($a % $b) + $b) % $b;
    }

    // ── Mars Time Convention ──────────────────────────────────────────────────

    /**
     * Mars Coordinated Time: the Mars clock at the prime meridian (AMT+0), in
     * Mars hours (1/24 sol), matching getMTC in planet-time.js.
     */
    public static function getMTC(int $utcMs): MTCResult
    {
        $totalSols = ($utcMs - Constants::MARS_EPOCH_MS) / Constants::MARS_SOL_MS;
        $sol       = (int)floor($totalSols);
        $frac      = $totalSols - $sol;
        $hour      = (int)floor($frac * 24);
        $minute    = (int)floor(($frac * 24 - $hour) * 60);
        $second    = (int)floor((($frac * 24 - $hour) * 60 - $minute) * 60);

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
}
