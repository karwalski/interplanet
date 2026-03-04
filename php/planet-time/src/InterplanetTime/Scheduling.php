<?php
declare(strict_types=1);

namespace InterplanetTime;

/**
 * Meeting window finder — ported from planet-time.js findMeetingWindows().
 */
final class Scheduling
{
    private function __construct() {}

    /**
     * Find overlapping work windows for two planets over a range of Earth days.
     *
     * @param string $planetA  Planet key (e.g. 'earth', 'mars')
     * @param string $planetB  Planet key
     * @param int    $fromMs   Start UTC ms
     * @param int    $earthDays Number of Earth days to scan (default 7)
     * @return MeetingWindow[]
     */
    public static function findMeetingWindows(
        string $planetA,
        string $planetB,
        int    $fromMs,
        int    $earthDays = 7,
    ): array {
        $STEP_MS = 15 * 60 * 1000; // 15-minute step
        $endMs   = $fromMs + $earthDays * Constants::EARTH_DAY_MS;

        $windows     = [];
        $inWindow    = false;
        $windowStart = 0;

        for ($t = $fromMs; $t < $endMs; $t += $STEP_MS) {
            $ta = Time::getPlanetTime($planetA, $t);
            $tb = Time::getPlanetTime($planetB, $t);
            $overlap = $ta->isWorkHour && $tb->isWorkHour;

            if ($overlap && !$inWindow) {
                $inWindow    = true;
                $windowStart = $t;
            } elseif (!$overlap && $inWindow) {
                $inWindow = false;
                $dur      = (int)(($t - $windowStart) / 60000);
                $windows[] = new MeetingWindow($windowStart, $t, $dur);
            }
        }

        if ($inWindow) {
            $dur       = (int)(($endMs - $windowStart) / 60000);
            $windows[] = new MeetingWindow($windowStart, $endMs, $dur);
        }

        return $windows;
    }
}
