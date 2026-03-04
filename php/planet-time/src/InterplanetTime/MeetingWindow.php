<?php
declare(strict_types=1);

namespace InterplanetTime;

/** A meeting window where all parties have overlapping work hours. */
final class MeetingWindow
{
    public function __construct(
        public readonly int $startMs,
        public readonly int $endMs,
        public readonly int $durationMinutes,
    ) {}
}
