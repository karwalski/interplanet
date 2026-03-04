package interplanet.time

/**
 * Scheduling.kt — findMeetingWindows
 * Ported from planet-time.js v1.1.0
 */

/**
 * Find overlapping work windows between two planets over N Earth days.
 * Step size: 15 minutes.
 */
fun findMeetingWindows(
    planetA: Planet,
    planetB: Planet,
    earthDays: Int = 7,
    startMs: Long = System.currentTimeMillis()
): List<MeetingWindow> {
    val stepMs = 15 * 60000L
    val endMs = startMs + earthDays * EARTH_DAY_MS
    val windows = mutableListOf<MeetingWindow>()
    var inWindow = false
    var windowStart = 0L

    var t = startMs
    while (t < endMs) {
        val ta = getPlanetTime(planetA, t)
        val tb = getPlanetTime(planetB, t)
        val overlap = ta.isWorkHour && tb.isWorkHour
        if (overlap && !inWindow) {
            inWindow = true
            windowStart = t
        }
        if (!overlap && inWindow) {
            inWindow = false
            windows.add(MeetingWindow(
                startMs = windowStart,
                endMs = t,
                durationMin = ((t - windowStart) / 60000L).toInt()
            ))
        }
        t += stepMs
    }
    if (inWindow) {
        windows.add(MeetingWindow(
            startMs = windowStart,
            endMs = endMs,
            durationMin = ((endMs - windowStart) / 60000L).toInt()
        ))
    }
    return windows
}
