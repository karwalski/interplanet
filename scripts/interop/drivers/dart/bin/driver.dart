// Interop driver for dart/ltx (see scripts/interop/run.js).
import 'dart:convert';
import 'dart:io';

import 'package:interplanet_ltx/interplanet_ltx.dart';

void main(List<String> args) {
  final inDir = args[0], outDir = args[1];

  final plan = createPlan(
    title: 'Réunion Mars 🚀',
    start: '2026-03-15T14:00:00.000Z',
    quantum: 3,
    mode: 'LTX-ASYNC',
    nodes: const [
      LtxNode(id: 'N0', name: 'Earth HQ', role: 'HOST', delay: 0, location: 'earth'),
      LtxNode(id: 'N1', name: 'Mars Hab-01', role: 'PARTICIPANT', delay: 840, location: 'mars'),
      LtxNode(id: 'N2', name: 'L-1 Gateway', role: 'PARTICIPANT', delay: 2, location: 'moon'),
    ],
    segments: const [
      LtxSegmentTemplate(type: 'PLAN_CONFIRM', q: 2),
      LtxSegmentTemplate(type: 'TX', q: 3, speaker: 'N0', label: 'Ouverture: état de la mission'),
      LtxSegmentTemplate(type: 'RX', q: 3),
      LtxSegmentTemplate(type: 'TX', q: 2, speaker: 'N1', label: 'Réponse 🔴'),
      LtxSegmentTemplate(type: 'BUFFER', q: 1),
    ],
  );

  String unhash(String h) => utf8.decode(base64Url.decode(base64Url.normalize(h.substring(3))));

  File('$outDir/wire-v2.json').writeAsStringSync(unhash(encodeHash(plan)));
  print('ID_V2 ${makePlanId(plan)}');

  // No upgrade function: construct the v3 LtxPlan with its v3 fields.
  final v3 = LtxPlan(
    v: 3, title: plan.title, start: plan.start, quantum: plan.quantum, mode: plan.mode,
    nodes: plan.nodes, segments: plan.segments, delays: {'N1|N2': 842}, planVersion: 1);
  File('$outDir/wire-v3.json').writeAsStringSync(unhash(encodeHash(v3)));
  print('ID_V3 ${makePlanId(v3)}');
  print('NOTE v3 built as LtxPlan(v: 3, delays, planVersion) (no upgrade function)');

  for (final v in ['2', '3']) {
    final parsed = jsonDecode(File('$inDir/js-v$v.json').readAsStringSync()) as Map<String, dynamic>;
    print('JS_V$v ${makePlanIdFromMap(parsed)}');
  }
}
