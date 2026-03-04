<?php
declare(strict_types=1);

namespace InterplanetTime;

/** Heliocentric position (ecliptic J2000). */
final class HelioPosResult
{
    public function __construct(
        public readonly float $x,    // AU
        public readonly float $y,    // AU
        public readonly float $r,    // AU (distance from Sun)
        public readonly float $lon,  // radians (ecliptic longitude)
    ) {}
}
