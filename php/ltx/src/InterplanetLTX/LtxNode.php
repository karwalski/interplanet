<?php
/**
 * LtxNode.php — Participant node in an LTX session plan
 * Story 33.4 — PHP LTX library
 */

namespace InterplanetLTX;

/** A participant node in an LTX session. */
readonly class LtxNode
{
    public function __construct(
        public string $id,
        public string $name,
        public string $role,
        public int    $delay,
        public string $location,
    ) {}
}
