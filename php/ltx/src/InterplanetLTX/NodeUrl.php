<?php
/**
 * NodeUrl.php — Per-node perspective URL
 * Story 33.4 — PHP LTX library
 */

namespace InterplanetLTX;

/** A per-node perspective URL for an LTX session. */
readonly class NodeUrl
{
    public function __construct(
        public string $nodeId,
        public string $name,
        public string $role,
        public string $url,
    ) {}
}
