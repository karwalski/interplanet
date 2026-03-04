package com.interplanet.time;

/**
 * Result of a line-of-sight check between two solar system bodies.
 * Mirrors the LineOfSight object from planet-time.js checkLineOfSight().
 */
public record LineOfSight(
    boolean clear,
    boolean blocked,
    boolean degraded,
    Double  closestSunAu,   // null when bodies are co-located
    double  elongDeg
) {}
