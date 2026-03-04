<?php
/**
 * LtxPlan.php — LTX session plan configuration (v2 schema)
 * Story 33.4 — PHP LTX library
 */

namespace InterplanetLTX;

/** An LTX session plan configuration (v2 schema). */
class LtxPlan
{
    public int    $v       = 2;
    public string $title   = 'LTX Session';
    public string $start   = '';
    public int    $quantum = 3;
    public string $mode    = 'LTX';

    /** @var LtxNode[] */
    public array $nodes = [];

    /** @var LtxSegmentTemplate[] */
    public array $segments = [];

    /**
     * Serialise the plan to compact JSON (matches JS JSON.stringify key order).
     * The output is used for encodeHash and makePlanId — must be deterministic.
     */
    public function toJson(): string
    {
        $data = [
            'v'        => $this->v,
            'title'    => $this->title,
            'start'    => $this->start,
            'quantum'  => $this->quantum,
            'mode'     => $this->mode,
            'nodes'    => array_map(fn(LtxNode $n) => [
                'id'       => $n->id,
                'name'     => $n->name,
                'role'     => $n->role,
                'delay'    => $n->delay,
                'location' => $n->location,
            ], $this->nodes),
            'segments' => array_map(fn(LtxSegmentTemplate $s) => [
                'type' => $s->type,
                'q'    => $s->q,
            ], $this->segments),
        ];

        /* JSON_UNESCAPED_SLASHES matches JS JSON.stringify (no \/ escaping).
           JSON_UNESCAPED_UNICODE matches JS behaviour for non-ASCII chars.  */
        return json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    }

    /**
     * Deserialise a plan from compact JSON.
     * @return static|null  null on parse failure
     */
    public static function fromJson(string $json): ?static
    {
        $data = json_decode($json, true);
        if (!is_array($data)) {
            return null;
        }

        $plan           = new static();
        $plan->v        = (int)($data['v']       ?? 2);
        $plan->title    = (string)($data['title']   ?? 'LTX Session');
        $plan->start    = (string)($data['start']   ?? '');
        $plan->quantum  = (int)($data['quantum'] ?? 3);
        $plan->mode     = (string)($data['mode']    ?? 'LTX');

        if (isset($data['nodes']) && is_array($data['nodes'])) {
            $plan->nodes = array_map(fn(array $n) => new LtxNode(
                id:       (string)($n['id']       ?? ''),
                name:     (string)($n['name']     ?? ''),
                role:     (string)($n['role']     ?? 'HOST'),
                delay:    (int)($n['delay']    ?? 0),
                location: (string)($n['location'] ?? 'earth'),
            ), $data['nodes']);
        }

        if (isset($data['segments']) && is_array($data['segments'])) {
            $plan->segments = array_map(fn(array $s) => new LtxSegmentTemplate(
                type: (string)($s['type'] ?? 'TX'),
                q:    (int)($s['q']    ?? 2),
            ), $data['segments']);
        }

        return $plan;
    }
}
