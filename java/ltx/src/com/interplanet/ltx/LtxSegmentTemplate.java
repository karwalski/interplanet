package com.interplanet.ltx;

/**
 * LtxSegmentTemplate — a segment in a plan's segment list.
 * Has a type and a number of quanta, and optionally a speaker node id and an
 * agenda label (attributed segments, LTX-SPECIFICATION.md §3.4.1).
 * Story 33.2 — Java LTX library
 */
public record LtxSegmentTemplate(
    /** Segment type, e.g. "TX", "RX", "PLAN_CONFIRM". */
    String type,
    /** Duration in quanta (minutes = q * quantum). */
    int q,
    /** Presenting node id (e.g. "N1"), or null when the segment is unattributed. */
    String speaker,
    /** Short agenda title, or null when absent. */
    String label
) {
    /** An unattributed segment (no speaker, no label). */
    public LtxSegmentTemplate(String type, int q) {
        this(type, q, null, null);
    }
}
