<?php
declare(strict_types=1);

namespace InterplanetTime;

/**
 * Immutable result object returned by Time::getPlanetTime().
 */
final class PlanetTimeResult
{
    public function __construct(
        public readonly int    $hour,
        public readonly int    $minute,
        public readonly int    $second,
        public readonly float  $localHour,
        public readonly float  $dayFraction,
        public readonly int    $dayNumber,
        public readonly int    $dayInYear,
        public readonly int    $yearNumber,
        public readonly int    $periodInWeek,
        public readonly bool   $isWorkPeriod,
        public readonly bool   $isWorkHour,
        public readonly string $timeStr,       // "HH:MM"
        public readonly string $timeStrFull,   // "HH:MM:SS"
        public readonly ?int    $solInYear,     // Mars only
        public readonly ?int    $solsPerYear,  // Mars only
        public readonly ?string $zoneId,       // null for Earth; e.g. "AMT+4" for others
    ) {}
}
