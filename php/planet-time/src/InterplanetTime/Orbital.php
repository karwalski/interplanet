<?php
declare(strict_types=1);

namespace InterplanetTime;

/**
 * Orbital mechanics — ported from planet-time.js.
 *
 * All timestamps are UTC milliseconds since Unix epoch.
 * Distances in AU, angles in radians unless noted.
 */
final class Orbital
{
    private function __construct() {}

    // ── Leap seconds / TT ────────────────────────────────────────────────────

    public static function taiMinusUtc(int $utcMs): int
    {
        $ls = Constants::LEAP_SECONDS;
        $tai = 10;
        foreach ($ls as [$ts, $delta]) {
            if ($utcMs >= $ts) $tai = $delta;
            else break;
        }
        return $tai;
    }

    /** Julian Ephemeris Day (TT) from UTC milliseconds. */
    public static function jde(int $utcMs): float
    {
        $ttMs = $utcMs + self::taiMinusUtc($utcMs) * 1000 + 32184; // TT = TAI + 32.184s
        return 2440587.5 + $ttMs / 86400000.0;
    }

    /** Julian centuries from J2000.0 (TT). */
    public static function jc(int $utcMs): float
    {
        return (self::jde($utcMs) - Constants::J2000_JD) / 36525.0;
    }

    // ── Kepler solver ────────────────────────────────────────────────────────

    /** Solve Kepler's equation M = E - e*sin(E) via Newton-Raphson. */
    private static function keplerE(float $M, float $e): float
    {
        $E = $M;
        for ($i = 0; $i < 50; $i++) {
            $dE = ($M - $E + $e * sin($E)) / (1.0 - $e * cos($E));
            $E += $dE;
            if (abs($dE) < 1e-12) break;
        }
        return $E;
    }

    // ── Heliocentric position ─────────────────────────────────────────────────

    public static function helioPos(string $planet, int $utcMs): HelioPosResult
    {
        $elems = Constants::ORBITAL_ELEMENTS[$planet]
            ?? Constants::ORBITAL_ELEMENTS['earth'];

        $T  = self::jc($utcMs);
        $L  = fmod($elems['L0'] + $elems['dL'] * $T, 360.0);
        $om = $elems['om0'];
        $e  = $elems['e0'];
        $a  = $elems['a'];

        // Mean anomaly (deg → rad)
        $M = deg2rad(fmod($L - $om + 360.0, 360.0));
        $E = self::keplerE($M, $e);

        // True anomaly
        $nu = 2.0 * atan2(
            sqrt(1.0 + $e) * sin($E / 2.0),
            sqrt(1.0 - $e) * cos($E / 2.0)
        );

        // Heliocentric distance
        $r = $a * (1.0 - $e * cos($E));

        // Ecliptic longitude (radians)
        $lon = fmod(deg2rad($om) + $nu + 2.0 * M_PI, 2.0 * M_PI);

        return new HelioPosResult(
            x: $r * cos($lon),
            y: $r * sin($lon),
            r: $r,
            lon: $lon,
        );
    }

    // ── Distance & light travel ────────────────────────────────────────────────

    public static function bodyDistanceAu(string $a, string $b, int $utcMs): float
    {
        $pa = self::helioPos($a, $utcMs);
        $pb = self::helioPos($b, $utcMs);
        $dx = $pa->x - $pb->x;
        $dy = $pa->y - $pb->y;
        return sqrt($dx * $dx + $dy * $dy);
    }

    public static function lightTravelSeconds(string $a, string $b, int $utcMs): float
    {
        return self::bodyDistanceAu($a, $b, $utcMs) * Constants::AU_SECONDS;
    }

    // ── Line of sight ─────────────────────────────────────────────────────────

    public static function checkLineOfSight(string $a, string $b, int $utcMs): LineOfSightResult
    {
        $pa = self::helioPos($a, $utcMs);
        $pb = self::helioPos($b, $utcMs);

        // Vector from A to B
        $abx = $pb->x - $pa->x;
        $aby = $pb->y - $pa->y;
        $d2  = $abx * $abx + $aby * $aby;

        if ($d2 < 1e-20) {
            // Same body (Moon/Earth edge case)
            return new LineOfSightResult(
                clear: true, blocked: false, degraded: false,
                closestSunAu: null, elongDeg: 0.0,
            );
        }

        // Closest approach of Sun to line AB (t in [0,1])
        $t = max(0.0, min(1.0, -($pa->x * $abx + $pa->y * $aby) / $d2));
        $cx = $pa->x + $t * $abx;
        $cy = $pa->y + $t * $aby;
        $closestSunAu = sqrt($cx * $cx + $cy * $cy);

        // Solar elongation angle at observer A (degrees)
        $dotAB  = $abx * $pa->x + $aby * $pa->y;
        $abMag  = sqrt($d2);
        $aMag   = sqrt($pa->x ** 2 + $pa->y ** 2);
        $cos_el = ($aMag > 1e-10 && $abMag > 1e-10)
            ? -$dotAB / ($abMag * $aMag) : 0.0;
        $elongDeg = rad2deg(acos(max(-1.0, min(1.0, $cos_el))));

        $blocked  = $closestSunAu < 0.1;
        $degraded = !$blocked && ($closestSunAu < 0.25 || $elongDeg < 5.0);

        return new LineOfSightResult(
            clear: !$blocked && !$degraded,
            blocked: $blocked,
            degraded: $degraded,
            closestSunAu: $closestSunAu,
            elongDeg: $elongDeg,
        );
    }

    // ── Lower-quartile light time ──────────────────────────────────────────────

    /**
     * Sample one Earth year (360 samples) and return the lower-quartile
     * one-way light time in seconds (p25).
     */
    public static function lowerQuartileLightTime(string $a, string $b, int $refMs): float
    {
        $YEAR_MS = 365 * Constants::EARTH_DAY_MS;
        $STEP    = (int)($YEAR_MS / 360);
        $samples = [];
        for ($i = 0; $i < 360; $i++) {
            $samples[] = self::lightTravelSeconds($a, $b, $refMs + $i * $STEP);
        }
        sort($samples);
        return $samples[(int)(count($samples) * 0.25)];
    }
}
