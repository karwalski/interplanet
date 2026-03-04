package com.interplanet.ltx;

/**
 * LtxSegmentTemplate — a segment in a plan's segment list.
 * Has a type and a number of quanta.
 * Story 33.2 — Java LTX library
 */
public record LtxSegmentTemplate(
    /** Segment type, e.g. "TX", "RX", "PLAN_CONFIRM". */
    String type,
    /** Duration in quanta (minutes = q * quantum). */
    int q
) {}
