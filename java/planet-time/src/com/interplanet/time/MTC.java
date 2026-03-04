package com.interplanet.time;

/**
 * Mars Coordinated Time (MTC) — the Martian equivalent of UTC.
 * Mirrors the MTC object returned by planet-time.js getMTC().
 */
public record MTC(
    long sol,
    int  hour,
    int  minute,
    int  second,
    String mtcStr    // "HH:MM"
) {}
