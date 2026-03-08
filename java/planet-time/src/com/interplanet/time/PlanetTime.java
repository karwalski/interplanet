package com.interplanet.time;

/**
 * Time reading on a solar-system body.
 * Mirrors the PlanetTime object returned by planet-time.js getPlanetTime().
 */
public record PlanetTime(
    int    hour,
    int    minute,
    int    second,
    double localHour,
    double dayFraction,
    long   dayNumber,
    int    dayInYear,
    long   yearNumber,
    int    periodInWeek,
    boolean isWorkPeriod,
    boolean isWorkHour,
    String  timeStr,        // "HH:MM"
    String  timeStrFull,    // "HH:MM:SS"
    Integer solInYear,      // Mars only (null for other planets)
    Integer solsPerYear,    // Mars only (null for other planets)
    String  zoneId          // e.g. "AMT+4", "LMT+0"; null for Earth
) {
    /** @return "HH:MM" formatted time string. */
    @Override
    public String toString() {
        return timeStr + (zoneId != null ? " (" + zoneId + ")" : "");
    }
}
