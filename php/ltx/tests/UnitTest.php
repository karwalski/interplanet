<?php
/**
 * UnitTest.php — Unit tests for PHP LTX library
 * Story 33.4 · PHP 8.1+ · No external dependencies
 * Run with: php tests/UnitTest.php  (or: make test)
 */

require_once __DIR__ . '/../src/autoload.php';

use InterplanetLTX\InterplanetLTX as LTX;
use InterplanetLTX\LtxPlan;

$passed = 0;
$failed = 0;

function check(string $name, bool $cond): void {
    global $passed, $failed;
    if ($cond) { $passed++; }
    else { $failed++; echo "FAIL: $name\n"; }
}

function section(string $name): void {
    echo "\n-- $name --\n";
}

/* ── Constants ─────────────────────────────────────────────────────── */
section('Constants');
check('VERSION not empty',              strlen(LTX::VERSION) > 0);
check('VERSION is 1.0.0',              LTX::VERSION === '1.0.0');
check('DEFAULT_QUANTUM == 5',          LTX::DEFAULT_QUANTUM === 5);
check('DEFAULT_SEG_COUNT == 7',        LTX::DEFAULT_SEG_COUNT === 7);
check('DEFAULT_API_BASE has https',    str_starts_with(LTX::DEFAULT_API_BASE, 'https://'));
check('DEFAULT_SEGMENTS[0] PLAN_CONFIRM', LTX::DEFAULT_SEGMENTS[0]['type'] === 'PLAN_CONFIRM');
check('DEFAULT_SEGMENTS[1] TX',        LTX::DEFAULT_SEGMENTS[1]['type'] === 'TX');
check('DEFAULT_SEGMENTS[2] RX',        LTX::DEFAULT_SEGMENTS[2]['type'] === 'RX');
check('DEFAULT_SEGMENTS[6] BUFFER',    LTX::DEFAULT_SEGMENTS[6]['type'] === 'BUFFER');
check('DEFAULT_SEGMENTS[0] q == 2',    LTX::DEFAULT_SEGMENTS[0]['q'] === 2);
check('DEFAULT_SEGMENTS[6] q == 1',    LTX::DEFAULT_SEGMENTS[6]['q'] === 1);

/* ── createPlan ────────────────────────────────────────────────────── */
section('createPlan');
$plan = LTX::createPlan(null, '2026-03-15T14:00:00Z', 0);
check('v == 2',                        $plan->v === 2);
check('title == LTX Session',          $plan->title === 'LTX Session');
check('start preserved',               $plan->start === '2026-03-15T14:00:00Z');
check('quantum == 5',                  $plan->quantum === 5);
check('mode == LTX',                   $plan->mode === 'LTX');
check('node_count == 2',              count($plan->nodes) === 2);
check('nodes[0].id == N0',             $plan->nodes[0]->id === 'N0');
check('nodes[0].role == HOST',         $plan->nodes[0]->role === 'HOST');
check('nodes[0].location == earth',    $plan->nodes[0]->location === 'earth');
check('nodes[0].delay == 0',           $plan->nodes[0]->delay === 0);
check('nodes[1].id == N1',             $plan->nodes[1]->id === 'N1');
check('nodes[1].role == PARTICIPANT',  $plan->nodes[1]->role === 'PARTICIPANT');
check('nodes[1].location == mars',     $plan->nodes[1]->location === 'mars');
check('seg_count == 7',               count($plan->segments) === 7);

$plan2 = LTX::createPlan('Q3 Review', '2026-06-01T10:00:00Z', 860);
check('custom title',                  $plan2->title === 'Q3 Review');
check('custom delay',                  $plan2->nodes[1]->delay === 860);

/* ── upgradeConfig ─────────────────────────────────────────────────── */
section('upgradeConfig');
$cfg = ['title' => 'Upgraded', 'start' => '2026-04-01T09:00:00Z', 'quantum' => 5];
$up  = LTX::upgradeConfig($cfg);
check('upgraded title',                $up->title === 'Upgraded');
check('upgraded start',                $up->start === '2026-04-01T09:00:00Z');
check('upgraded quantum',              $up->quantum === 5);
check('upgraded has default nodes',    count($up->nodes) === 2);
check('upgraded has default segments', count($up->segments) === 7);

$cfgNodes = [
    'nodes' => [
        ['id' => 'X0', 'name' => 'Base Alpha', 'role' => 'HOST',        'delay' => 0,   'location' => 'earth'],
        ['id' => 'X1', 'name' => 'Base Beta',  'role' => 'PARTICIPANT', 'delay' => 1200, 'location' => 'mars'],
    ],
];
$up2 = LTX::upgradeConfig($cfgNodes);
check('custom nodes[0] id',            $up2->nodes[0]->id === 'X0');
check('custom nodes[1] delay',         $up2->nodes[1]->delay === 1200);

/* ── computeSegments ───────────────────────────────────────────────── */
section('computeSegments');
$segs = LTX::computeSegments($plan);
check('seg_count == 7',               count($segs) === 7);
check('segs[0].type PLAN_CONFIRM',     $segs[0]->type === 'PLAN_CONFIRM');
check('segs[6].type BUFFER',           $segs[6]->type === 'BUFFER');
check('segs[0].q == 2',               $segs[0]->q === 2);
check('segs[0].startMs > 0',          $segs[0]->startMs > 0);
check('segs[0].endMs > startMs',       $segs[0]->endMs > $segs[0]->startMs);
check('segs[0].durMin == 10',          $segs[0]->durMin === 10);
check('segs[6].durMin == 5',           $segs[6]->durMin === 5);
/* Contiguous segments */
for ($i = 0; $i < count($segs) - 1; $i++) {
    check("segs[$i] contiguous",       $segs[$i]->endMs === $segs[$i + 1]->startMs);
}

/* ── totalMin ──────────────────────────────────────────────────────── */
section('totalMin');
$total = LTX::totalMin($plan);
check('totalMin == 65',               $total === 65);
$segSum = array_sum(array_map(fn($s) => $s->durMin, $segs));
check('totalMin matches seg sum',      $segSum === $total);

/* ── makePlanId ────────────────────────────────────────────────────── */
section('makePlanId');
$pid = LTX::makePlanId($plan);
check('planId not empty',             strlen($pid) > 0);
check('planId starts LTX-',           str_starts_with($pid, 'LTX-'));
check('planId has date 20260315',      str_contains($pid, '20260315'));
check('planId has -v2-',              str_contains($pid, '-v2-'));
/* Deterministic */
check('planId deterministic',          LTX::makePlanId($plan) === $pid);
check('planId length > 20',           strlen($pid) > 20);

/* ── encodeHash / decodeHash ───────────────────────────────────────── */
section('encodeHash / decodeHash');
$hash = LTX::encodeHash($plan);
check('hash starts #l=',              str_starts_with($hash, '#l='));
check('hash non-empty payload',       strlen($hash) > 10);
check('hash url-safe (no +)',         !str_contains($hash, '+'));
check('hash url-safe (no /)',         !str_contains($hash, '/'));
check('hash no = padding',            !str_contains(substr($hash, 3), '='));

$decoded = LTX::decodeHash($hash);
check('decodeHash returns plan',       $decoded !== null);
check('decoded v == 2',               $decoded?->v === 2);
check('decoded title matches',        $decoded?->title === $plan->title);
check('decoded quantum matches',      $decoded?->quantum === $plan->quantum);
check('decoded node_count == 2',      count($decoded?->nodes ?? []) === 2);
check('decoded seg_count == 7',       count($decoded?->segments ?? []) === 7);

/* Strip # prefix */
$decoded2 = LTX::decodeHash(substr($hash, 1));  /* "l=eyJ..." */
check('decode without # works',       $decoded2 !== null);

/* Invalid */
$bad = LTX::decodeHash('!@#$%');
check('invalid hash returns null',     $bad === null);

/* ── buildNodeUrls ─────────────────────────────────────────────────── */
section('buildNodeUrls');
$urls = LTX::buildNodeUrls($plan, 'https://interplanet.live/ltx.html');
check('url_count == 2',              count($urls) === 2);
check('urls[0].nodeId == N0',        $urls[0]->nodeId === 'N0');
check('urls[0].role == HOST',        $urls[0]->role === 'HOST');
check('urls[0].url has ?node=N0',    str_contains($urls[0]->url, '?node=N0'));
check('urls[0].url has #l=',         str_contains($urls[0]->url, '#l='));
check('urls[0].url has base',        str_starts_with($urls[0]->url, 'https://interplanet.live'));
check('urls[1].nodeId == N1',        $urls[1]->nodeId === 'N1');
check('urls[1].role == PARTICIPANT', $urls[1]->role === 'PARTICIPANT');

/* ── generateICS ───────────────────────────────────────────────────── */
section('generateICS');
$ics = LTX::generateICS($plan);
check('ICS starts VCALENDAR',        str_starts_with($ics, 'BEGIN:VCALENDAR'));
check('ICS has END:VCALENDAR',       str_contains($ics, 'END:VCALENDAR'));
check('ICS has BEGIN:VEVENT',        str_contains($ics, 'BEGIN:VEVENT'));
check('ICS has END:VEVENT',          str_contains($ics, 'END:VEVENT'));
check('ICS has VERSION:2.0',         str_contains($ics, 'VERSION:2.0'));
check('ICS has DTSTART',             str_contains($ics, 'DTSTART:'));
check('ICS has DTEND',               str_contains($ics, 'DTEND:'));
check('ICS has SUMMARY',             str_contains($ics, 'SUMMARY:'));
check('ICS has LTX:1',              str_contains($ics, 'LTX:1'));
check('ICS has LTX-PLANID',         str_contains($ics, 'LTX-PLANID:'));
check('ICS has LTX-QUANTUM:PT5M',   str_contains($ics, 'LTX-QUANTUM:PT5M'));
check('ICS has LTX-NODE',           str_contains($ics, 'LTX-NODE:'));
check('ICS has CRLF',               str_contains($ics, "\r\n"));

/* ── formatHMS / formatUTC ─────────────────────────────────────────── */
section('formatHMS / formatUTC');
check('formatHMS(0) == 00:00',        LTX::formatHMS(0)    === '00:00');
check('formatHMS(30) == 00:30',       LTX::formatHMS(30)   === '00:30');
check('formatHMS(59) == 00:59',       LTX::formatHMS(59)   === '00:59');
check('formatHMS(60) == 01:00',       LTX::formatHMS(60)   === '01:00');
check('formatHMS(3600) == 01:00:00',  LTX::formatHMS(3600) === '01:00:00');
check('formatHMS(3661) == 01:01:01',  LTX::formatHMS(3661) === '01:01:01');
check('formatHMS(7322) == 02:02:02',  LTX::formatHMS(7322) === '02:02:02');
check('formatHMS(-1) == 00:00',       LTX::formatHMS(-1)   === '00:00');

/* 2026-03-01T14:30:45Z = epoch 1772375445000 */
$utc = LTX::formatUTC(1772375445000);
check('formatUTC has time part',      str_starts_with($utc, '14:30:45'));
check('formatUTC ends UTC',           str_ends_with($utc, 'UTC'));
check('formatUTC(0) == 00:00:00 UTC', LTX::formatUTC(0) === '00:00:00 UTC');

/* ── LtxPlan JSON round-trip ───────────────────────────────────────── */
section('LtxPlan JSON round-trip');
$json = $plan->toJson();
check('toJson not empty',             strlen($json) > 0);
check('toJson starts with {',         str_starts_with($json, '{'));
check('toJson has v key',             str_contains($json, '"v":'));
check('toJson has title key',         str_contains($json, '"title":'));
check('toJson has nodes key',         str_contains($json, '"nodes":'));
check('toJson has segments key',      str_contains($json, '"segments":'));

$rt = LtxPlan::fromJson($json);
check('fromJson returns plan',        $rt !== null);
check('fromJson v preserved',         $rt?->v === $plan->v);
check('fromJson title preserved',     $rt?->title === $plan->title);
check('fromJson quantum preserved',   $rt?->quantum === $plan->quantum);
check('fromJson node_count preserved', count($rt?->nodes ?? []) === count($plan->nodes));
check('fromJson seg_count preserved', count($rt?->segments ?? []) === count($plan->segments));

check('fromJson invalid returns null', LtxPlan::fromJson('not json') === null);

/* ── Conformance: golden planId vectors (spec/golden/plan-ids.json) ── */
section('Conformance: golden planId vectors');
$golden = json_decode(file_get_contents(__DIR__ . '/../../../spec/golden/plan-ids.json'));
$gv = [];
foreach ($golden->vectors as $vec) $gv[$vec->name] = $vec;
check('golden vectors present (>= 9)',   count($golden->vectors) >= 9);
foreach ($golden->vectors as $vec) {
    $got = LTX::makePlanId($vec->plan);
    check("golden {$vec->name} planId (got $got)", $got === $vec->planId);
    if (isset($vec->planHash)) check("golden {$vec->name} planHash", LTX::planHash($vec->plan) === $vec->planHash);
}
check('golden anchor v2 default',        $gv['v2-createPlan-default']->planId === 'LTX-20260315-EARTHHQ-MARS-v2-2596ffe8');
check('golden v2 key-order sensitive',   $gv['v2-createPlan-default']->planId !== $gv['v2-key-order-sensitive']->planId);
check('golden v3 order-insensitive',     $gv['v3-upgrade-delays']->planId === $gv['v3-key-order-insensitive']->planId);
check('golden v3 amendment chain hash',  $gv['v3-amendment']->plan->prevPlanHash === $gv['v3-upgrade-delays']->planHash);
$fcAssoc = json_decode(json_encode($gv['v2-freeze-check']->plan), true);
check('golden v2 from assoc array',      LTX::makePlanId($fcAssoc) === $gv['v2-freeze-check']->planId);
$fcAssoc['nodes'][1]['delay'] = (float)$fcAssoc['nodes'][1]['delay'];
check('v2 hash formats 840.0 as 840',    LTX::makePlanId($fcAssoc) === $gv['v2-freeze-check']->planId);
check('JsJson::number matches JS',       array_map([\InterplanetLTX\JsJson::class, 'number'],
                                             [840.0, 0.1, 1e21, 1e-7, 1.5e-7, 1e16, -2.5, 0.000001]) ===
                                         ['840', '0.1', '1e+21', '1e-7', '1.5e-7', '10000000000000000', '-2.5', '0.000001']);

/* ── Plan validation: reserved streams / branching (§3.5, §7) ─────── */
section('Plan validation: reserved fields');
$codesOf = fn(array $r) => array_column($r['errors'], 'code');
$with = function (\stdClass $p, array $changes): \stdClass {
    $c = clone $p;
    foreach ($changes as $k => $v) $c->$k = $v;
    return $c;
};
foreach ($golden->vectors as $vec) {
    check("validatePlan accepts golden {$vec->name}", LTX::validatePlan($vec->plan)['valid'] === true);
}
$vpBase = $gv['v3-upgrade-delays']->plan;
$vpV2   = $gv['v2-freeze-check']->plan;
check('validatePlan v3 empty streams ok', LTX::validatePlan($with($vpBase, ['streams' => []]))['valid'] === true);
$vpStreams = LTX::validatePlan($with($vpBase, ['streams' => [(object)['id' => 'S1']]]));
check('validatePlan non-empty streams',   $vpStreams['valid'] === false && in_array('reserved_streams', $codesOf($vpStreams), true));
$se = array_values(array_filter($vpStreams['errors'], fn($e) => $e['code'] === 'reserved_streams'));
check('validatePlan streams error path',  $se[0]['path'] === 'streams');
check('validatePlan streams non-array',   in_array('reserved_streams', $codesOf(LTX::validatePlan($with($vpBase, ['streams' => 'S1']))), true));
check('validatePlan segment stream',      in_array('reserved_streams', $codesOf(LTX::validatePlan($with($vpBase,
                                              ['segments' => [(object)['type' => 'TX', 'q' => 1, 'stream' => 'S1']]]))), true));
check('validatePlan branches',            in_array('reserved_branching', $codesOf(LTX::validatePlan($with($vpBase, ['branches' => []]))), true));
check('validatePlan branching',           in_array('reserved_branching', $codesOf(LTX::validatePlan($with($vpBase,
                                              ['branching' => (object)['mode' => 'local']]))), true));
$vpSegBranch = LTX::validatePlan($with($vpBase, ['segments' => [(object)['type' => 'CAUCUS', 'q' => 1, 'branch' => 'B1']]]));
check('validatePlan segment branch',      in_array('reserved_branching', $codesOf($vpSegBranch), true) &&
                                          $vpSegBranch['errors'][0]['path'] === 'segments[0].branch');
check('validatePlan v2 streams is v3 field', in_array('v3_field_in_v2', $codesOf(LTX::validatePlan($with($vpV2, ['streams' => []]))), true));
check('validatePlan v2 branching',        in_array('reserved_branching', $codesOf(LTX::validatePlan($with($vpV2, ['branching' => true]))), true));
check('validatePlan assoc array input',   in_array('reserved_branching', $codesOf(LTX::validatePlan(
                                              json_decode(json_encode($with($vpV2, ['branches' => [1]])), true))), true));
check('validatePlan non-object',          in_array('not_an_object', $codesOf(LTX::validatePlan(null)), true));
check('validatePlan bad version',         in_array('invalid_version', $codesOf(LTX::validatePlan($with($vpV2, ['v' => 7]))), true));
check('validatePlan host not first',      in_array('invalid_host', $codesOf(LTX::validatePlan($with($vpV2, ['nodes' => array_reverse($vpV2->nodes)]))), true));
check('validatePlan unsorted delays key', in_array('invalid_delays', $codesOf(LTX::validatePlan($with($vpBase,
                                              ['delays' => (object)['N1|N0' => 860]]))), true));
check('validatePlan unknown speaker',     in_array('unknown_speaker', $codesOf(LTX::validatePlan($with($vpV2,
                                              ['segments' => [(object)['type' => 'TX', 'q' => 1, 'speaker' => 'N9']]]))), true));
check('validatePlan quantum out of range', in_array('invalid_quantum', $codesOf(LTX::validatePlan($with($vpV2, ['quantum' => 0]))), true));

/* ── Summary ─────────────────────────────────────────────────────── */
echo "\n==========================================\n";
echo "$passed passed  $failed failed\n";
exit($failed > 0 ? 1 : 0);
