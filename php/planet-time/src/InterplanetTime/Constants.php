<?php
declare(strict_types=1);

namespace InterplanetTime;

/**
 * Constants — numerical constants ported from planet-time.js.
 * All times in UTC milliseconds since Unix epoch (same convention as JS).
 */
final class Constants
{
    // Version
    public const VERSION = '0.1.0';

    // Epoch reference
    public const J2000_MS  = 946728000000;   // Date.UTC(2000,0,1,12,0,0)
    public const J2000_JD  = 2451545.0;

    // Time units
    public const EARTH_DAY_MS  = 86400000;
    public const MARS_EPOCH_MS = -524069761536; // MY 0 sol 0 — 1953-05-24T09:03:58.464Z
    public const MARS_SOL_MS   = 88775244;      // ms per Mars solar day

    // Distance / light travel
    public const AU_KM     = 149597870.7;
    public const C_KMS     = 299792.458;
    public const AU_SECONDS = self::AU_KM / self::C_KMS;  // ~499.0 s

    // Planet keys (strings matching JS)
    public const PLANETS = [
        'mercury', 'venus', 'earth', 'mars',
        'jupiter', 'saturn', 'uranus', 'neptune', 'moon',
    ];

    /**
     * Keplerian orbital elements at J2000.0 (ecliptic J2000).
     * Keys: L0 (mean longitude deg), dL (deg/century), om0 (longitude of perihelion deg),
     *       e0 (eccentricity), a (semi-major axis AU).
     * Moon uses Earth values.
     */
    public const ORBITAL_ELEMENTS = [
        'mercury' => ['L0' => 252.2509, 'dL' =>  149474.0722, 'om0' =>  77.4561, 'e0' => 0.20563, 'a' => 0.38710],
        'venus'   => ['L0' => 181.9798, 'dL' =>   58519.2130, 'om0' => 131.5637, 'e0' => 0.00677, 'a' => 0.72333],
        'earth'   => ['L0' => 100.4664, 'dL' =>   36000.7698, 'om0' => 102.9373, 'e0' => 0.01671, 'a' => 1.00000],
        'mars'    => ['L0' => 355.4330, 'dL' =>   19141.6964, 'om0' => 336.0602, 'e0' => 0.09341, 'a' => 1.52366],
        'jupiter' => ['L0' =>  34.3515, 'dL' =>    3036.3027, 'om0' =>  14.3320, 'e0' => 0.04854, 'a' => 5.20260],
        'saturn'  => ['L0' =>  50.0774, 'dL' =>    1223.5110, 'om0' =>  93.0568, 'e0' => 0.05560, 'a' => 9.55491],
        'uranus'  => ['L0' => 314.0550, 'dL' =>     428.4748, 'om0' => 173.0052, 'e0' => 0.04638, 'a' => 19.2184],
        'neptune' => ['L0' => 304.3487, 'dL' =>     218.4862, 'om0' =>  48.1209, 'e0' => 0.00946, 'a' => 30.0700],
        'moon'    => ['L0' => 100.4664, 'dL' =>   36000.7698, 'om0' => 102.9373, 'e0' => 0.01671, 'a' => 1.00000],
    ];

    /**
     * Leap-second table: [UTC_ms, TAI-UTC] pairs, ascending order.
     * From IERS Bulletin C — last checked 2024-01.
     */
    public const LEAP_SECONDS = [
        [  63072000000,  10], [  78796800000,  11], [  94694400000,  12],
        [ 126230400000,  13], [ 157766400000,  14], [ 189302400000,  15],
        [ 220924800000,  16], [ 252460800000,  17], [ 283996800000,  18],
        [ 315532800000,  19], [ 362793600000,  20], [ 394329600000,  21],
        [ 425865600000,  22], [ 489024000000,  23], [ 567993600000,  24],
        [ 631152000000,  25], [ 662688000000,  26], [ 709948800000,  27],
        [ 741484800000,  28], [ 773020800000,  29], [ 820454400000,  30],
        [ 867715200000,  31], [ 915148800000,  32], [1136073600000,  33],
        [1230768000000,  34], [1341100800000,  35], [1435708800000,  36],
        [1483228800000,  37],
    ];
}
