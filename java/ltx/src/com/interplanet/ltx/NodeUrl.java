package com.interplanet.ltx;

/**
 * NodeUrl — a perspective URL for a specific node in an LTX session.
 * Story 33.2 — Java LTX library
 */
public record NodeUrl(
    /** Node identifier, e.g. "N0". */
    String nodeId,
    /** Node display name. */
    String name,
    /** Node role: "HOST" or "PARTICIPANT". */
    String role,
    /** Full URL including ?node= and #l= parameters. */
    String url
) {}
