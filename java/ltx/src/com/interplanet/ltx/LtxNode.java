package com.interplanet.ltx;

/**
 * LtxNode — a participant node in an LTX session plan.
 * Story 33.2 — Java LTX library
 */
public record LtxNode(
    /** Node identifier, e.g. "N0", "N1". */
    String id,
    /** Human-readable name, e.g. "Earth HQ". */
    String name,
    /** Role: "HOST" or "PARTICIPANT". */
    String role,
    /** One-way signal delay in seconds (0 for host). */
    int delay,
    /** Location key: "earth", "mars", "moon". */
    String location
) {}
