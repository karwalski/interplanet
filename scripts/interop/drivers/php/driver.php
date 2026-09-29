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
$plan->segments = [
    new LtxSegmentTemplate(type: 'PLAN_CONFIRM', q: 2),
    new LtxSegmentTemplate(type: 'TX', q: 3, speaker: 'N0', label: 'Ouverture: état de la mission'),
    new LtxSegmentTemplate(type: 'RX', q: 3),
    new LtxSegmentTemplate(type: 'TX', q: 2, speaker: 'N1', label: 'Réponse 🔴'),
    new LtxSegmentTemplate(type: 'BUFFER', q: 1),
];
echo "NOTE no typed v3 upgrade\n";

$token = substr(L::encodeHash($plan), 3);
file_put_contents("$outDir/wire-v2.json", base64_decode(strtr($token, '-_', '+/')));
echo 'ID_V2 ' . L::makePlanId($plan) . "\n";

foreach (['2', '3', 'P'] as $v) {
    $parsed = json_decode(file_get_contents("$inDir/js-v$v.json"));
    echo "JS_V$v " . L::makePlanId($parsed) . "\n";
}
