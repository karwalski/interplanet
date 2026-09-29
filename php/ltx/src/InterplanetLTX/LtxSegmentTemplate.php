<?php
/**
 * LtxSegmentTemplate.php — Segment type + quantum entry
 * Story 33.4 — PHP LTX library
 */

namespace InterplanetLTX;

/**
 * A segment type and quantum count template entry. speaker (a node id) and
 * label (an agenda title) are optional attribution (LTX-SPECIFICATION.md
 * §3.4.1); null means absent, and absent fields are not serialised.
 */
readonly class LtxSegmentTemplate
{
    public function __construct(
        public string  $type,
        public int     $q,
        public ?string $speaker = null,
        public ?string $label   = null,
    ) {}

    /** The segment as serialised: {type, q, speaker?, label?} (ltx-sdk.js order). */
    public function toArray(): array
    {
        $a = ['type' => $this->type, 'q' => $this->q];
        if ($this->speaker !== null) $a['speaker'] = $this->speaker;
        if ($this->label !== null)   $a['label']   = $this->label;
        return $a;
    }

    /** A segment template from a decoded JSON segment, keeping speaker/label. */
    public static function fromArray(array $s): self
    {
        return new self(
            type:    (string)($s['type'] ?? 'TX'),
            q:       (int)($s['q'] ?? 2),
            speaker: isset($s['speaker']) ? (string)$s['speaker'] : null,
            label:   isset($s['label']) ? (string)$s['label'] : null,
        );
    }
}
