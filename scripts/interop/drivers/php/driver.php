<?php
// Interop driver for php/ltx (see scripts/interop/run.js).
require_once getenv('ROOT') . '/php/ltx/src/autoload.php';

use InterplanetLTX\InterplanetLTX as L;
use InterplanetLTX\LtxNode;
use InterplanetLTX\LtxSegmentTemplate;

[, $inDir, $outDir] = $argv;

$plan = L::createPlan('Réunion Mars 🚀', '2026-03-15T14:00:00.000Z', 840);
$plan->quantum = 3;
$plan->mode = 'LTX-ASYNC';
$plan->nodes = [
    new LtxNode(id: 'N0', name: 'Earth HQ', role: 'HOST', delay: 0, location: 'earth'),
    new LtxNode(id: 'N1', name: 'Mars Hab-01', role: 'PARTICIPANT', delay: 840, location: 'mars'),
    new LtxNode(id: 'N2', name: 'L-1 Gateway', role: 'PARTICIPANT', delay: 2, location: 'moon'),
];
// LtxSegmentTemplate has no speaker/label, so attributed segments cannot be built.
$plan->segments = array_map(
    fn($s) => new LtxSegmentTemplate(type: $s[0], q: $s[1]),
    [['PLAN_CONFIRM', 2], ['TX', 3], ['RX', 3], ['TX', 2], ['BUFFER', 1]]
);
echo "NOTE typed LtxSegmentTemplate has no speaker/label; no typed v3 upgrade\n";

$token = substr(L::encodeHash($plan), 3);
file_put_contents("$outDir/wire-v2.json", base64_decode(strtr($token, '-_', '+/')));
echo 'ID_V2 ' . L::makePlanId($plan) . "\n";

foreach (['2', '3'] as $v) {
    $parsed = json_decode(file_get_contents("$inDir/js-v$v.json"));
    echo "JS_V$v " . L::makePlanId($parsed) . "\n";
}
