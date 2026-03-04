package com.interplanet.ltx;

/**
 * LtxSegment — a computed timed segment with absolute start/end times.
 * Story 33.2 — Java LTX library
 */
public record LtxSegment(
    /** Segment type, e.g. "TX", "RX". */
    String type,
    /** Duration in quanta. */
    int q,
    /** Absolute start time (UTC milliseconds since Unix epoch). */
    long startMs,
    /** Absolute end time (UTC milliseconds since Unix epoch). */
    long endMs,
    /** Duration in minutes (q * quantum). */
    int durMin
) {}
