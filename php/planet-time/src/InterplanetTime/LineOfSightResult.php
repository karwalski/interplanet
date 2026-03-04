<?php
declare(strict_types=1);

namespace InterplanetTime;

/** Line-of-sight check result from Orbital::checkLineOfSight(). */
final class LineOfSightResult
{
    public function __construct(
        public readonly bool   $clear,
        public readonly bool   $blocked,
        public readonly bool   $degraded,
        public readonly ?float $closestSunAu,
        public readonly float  $elongDeg,
    ) {}
}
