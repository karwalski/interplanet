<?php
/**
 * LtxSegmentTemplate.php — Segment type + quantum entry
 * Story 33.4 — PHP LTX library
 */

namespace InterplanetLTX;

/** A segment type and quantum count template entry. */
readonly class LtxSegmentTemplate
{
    public function __construct(
        public string $type,
        public int    $q,
    ) {}
}
