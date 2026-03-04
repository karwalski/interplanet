<?php
/**
 * LtxSegment.php — Computed, timed segment with UTC epoch milliseconds
 * Story 33.4 — PHP LTX library
 */

namespace InterplanetLTX;

/** A computed, timed LTX segment. */
readonly class LtxSegment
{
    public function __construct(
        public string $type,
        public int    $q,
        public int    $startMs,
        public int    $endMs,
        public int    $durMin,
    ) {}
}
