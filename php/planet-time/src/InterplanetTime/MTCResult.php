<?php
declare(strict_types=1);

namespace InterplanetTime;

/** Mars Time Convention result from Time::getMTC(). */
final class MTCResult
{
    public function __construct(
        public readonly int    $sol,
        public readonly int    $hour,
        public readonly int    $minute,
        public readonly int    $second,
        public readonly string $mtcStr,   // "HH:MM"
    ) {}
}
