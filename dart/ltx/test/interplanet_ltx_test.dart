// test/interplanet_ltx_test.dart — LTX SDK unit tests (≥80 check() assertions)

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:interplanet_ltx/interplanet_ltx.dart';

int passed = 0;
int failed = 0;

void check(bool condition, String label) {
  if (condition) {
    passed++;
    print('PASS: $label');
  } else {
    failed++;
    print('FAIL: $label');
  }
}

void main() async {
  // ── Constants ──────────────────────────────────────────────────────────────

  check(kVersion == '1.1.0', 'VERSION is 1.1.0');
  check(kDefaultQuantum == 5, 'DEFAULT_QUANTUM is 5');
  check(kDefaultApiBase == 'https://interplanet.live/api/ltx.php', 'DEFAULT_API_BASE correct');
  check(kDefaultSegments.length == 7, 'DEFAULT_SEGMENTS has 7 entries');
  check(kDefaultSegments[0]['type'] == 'PLAN_CONFIRM', 'DEFAULT_SEGMENTS[0] is PLAN_CONFIRM');
  check(kDefaultSegments[1]['type'] == 'TX', 'DEFAULT_SEGMENTS[1] is TX');
  check(kDefaultSegments[2]['type'] == 'RX', 'DEFAULT_SEGMENTS[2] is RX');
  check(kDefaultSegments[3]['type'] == 'CAUCUS', 'DEFAULT_SEGMENTS[3] is CAUCUS');
  check(kDefaultSegments[4]['type'] == 'TX', 'DEFAULT_SEGMENTS[4] is TX');
  check(kDefaultSegments[5]['type'] == 'RX', 'DEFAULT_SEGMENTS[5] is RX');
  check(kDefaultSegments[6]['type'] == 'BUFFER', 'DEFAULT_SEGMENTS[6] is BUFFER');
  check(kDefaultSegments[6]['q'] == 1, 'DEFAULT_SEGMENTS[6] q=1');
  check(kSegTypes.contains('PLAN_CONFIRM'), 'SEG_TYPES contains PLAN_CONFIRM');
  check(kSegTypes.contains('TX'), 'SEG_TYPES contains TX');
  check(kSegTypes.contains('RX'), 'SEG_TYPES contains RX');
  check(kSegTypes.contains('CAUCUS'), 'SEG_TYPES contains CAUCUS');
  check(kSegTypes.contains('BUFFER'), 'SEG_TYPES contains BUFFER');
  check(kSegTypes.contains('MERGE'), 'SEG_TYPES contains MERGE');

  // ── createPlan ────────────────────────────────────────────────────────────

  final plan = createPlan(title: 'LTX Session', start: '2024-01-15T14:00:00Z');
  check(plan.v == 2, 'createPlan v=2');
  check(plan.title == 'LTX Session', 'createPlan title correct');
  check(plan.start == '2024-01-15T14:00:00Z', 'createPlan start correct');
  check(plan.quantum == 5, 'createPlan quantum=5');
  check(plan.mode == 'LTX', 'createPlan mode=LTX');
  check(plan.nodes.length == 2, 'createPlan 2 nodes');
  check(plan.nodes[0].id == 'N0', 'first node id=N0');
  check(plan.nodes[0].name == 'Earth HQ', 'first node name=Earth HQ');
  check(plan.nodes[0].role == 'HOST', 'first node is HOST');
  check(plan.nodes[0].delay == 0.0, 'first node delay=0');
  check(plan.nodes[0].location == 'earth', 'first node location=earth');
  check(plan.nodes[1].id == 'N1', 'second node id=N1');
  check(plan.nodes[1].name == 'Mars Hab-01', 'second node name=Mars Hab-01');
  check(plan.nodes[1].role == 'PARTICIPANT', 'second node is PARTICIPANT');
  check(plan.nodes[1].location == 'mars', 'second node location=mars');
  check(plan.segments.length == 7, 'createPlan 7 segments');

  // createPlan with custom options
  final plan2 = createPlan(
    title: 'Custom Session',
    start: '2025-06-01T10:00:00Z',
    quantum: 5,
    mode: 'RELAY',
    hostName: 'Moon Base',
    remoteName: 'Mars Outpost',
    delay: 120.0,
  );
  check(plan2.v == 2, 'custom createPlan v=2');
  check(plan2.title == 'Custom Session', 'custom createPlan title');
  check(plan2.quantum == 5, 'custom createPlan quantum=5');
  check(plan2.mode == 'RELAY', 'custom createPlan mode=RELAY');
  check(plan2.nodes[0].name == 'Moon Base', 'custom createPlan hostName');
  check(plan2.nodes[1].name == 'Mars Outpost', 'custom createPlan remoteName');
  check(plan2.nodes[1].delay == 120.0, 'custom createPlan delay=120');

  // createPlan with no start (uses now + 5min)
  final plan3 = createPlan();
  check(plan3.v == 2, 'default createPlan v=2');
  check(plan3.title == 'LTX Session', 'default createPlan title');
  check(plan3.start.contains('T'), 'default createPlan start has T');

  // ── computeSegments ───────────────────────────────────────────────────────

  final segs = computeSegments(plan);
  check(segs.length == 7, 'computeSegments 7 segments');
  check(segs[0].type == 'PLAN_CONFIRM', 'first segment PLAN_CONFIRM');
  check(segs[0].q == 2, 'first segment q=2');
  check(segs[0].durMin == 10, 'first segment 10 min (q=2, quantum=5)');
  check(segs[1].type == 'TX', 'second segment TX');
  check(segs[2].type == 'RX', 'third segment RX');
  check(segs[3].type == 'CAUCUS', 'fourth segment CAUCUS');
  check(segs[4].type == 'TX', 'fifth segment TX');
  check(segs[5].type == 'RX', 'sixth segment RX');
  check(segs[6].type == 'BUFFER', 'seventh segment BUFFER');
  check(segs[6].q == 1, 'BUFFER q=1');
  check(segs[6].durMin == 5, 'BUFFER 5 min (q=1, quantum=5)');

  // Timing checks
  final t0 = DateTime.parse(segs[0].start).millisecondsSinceEpoch;
  final t1 = DateTime.parse(segs[1].start).millisecondsSinceEpoch;
  check(t1 - t0 == 10 * 60 * 1000, 'segment 1 starts 10 min after segment 0');
  check(segs[0].startMs == DateTime.parse('2024-01-15T14:00:00Z').millisecondsSinceEpoch,
      'first segment startMs correct');
  check(segs[0].endMs == segs[1].startMs, 'segment end = next segment start');

  // ── totalMin ──────────────────────────────────────────────────────────────

  check(totalMin(plan) == 65, 'totalMin 65');
  // 2+2+2+2+2+2+1 = 13 quanta × 5 min = 65 min
  check(totalMin(plan2) == 65, 'totalMin custom plan (13 quanta × 5 min = 65)');

  // ── makePlanId ────────────────────────────────────────────────────────────

  final id = makePlanId(plan);
  check(id.startsWith('LTX-'), 'planId starts with LTX-');
  check(id.contains('-v2-'), 'planId contains -v2-');
  check(id.contains('20240115'), 'planId contains date 20240115');
  check(id.contains('EARTHHQ'), 'planId contains EARTHHQ');
  check(id.contains('MARS'), 'planId contains MARS');
  check(id.length > 20, 'planId is reasonably long');

  // Deterministic: same plan → same id
  final id2 = makePlanId(plan);
  check(id == id2, 'makePlanId is deterministic');

  // Different plan → different id
  final idCustom = makePlanId(plan2);
  check(idCustom != id, 'different plan produces different planId');
  check(idCustom.startsWith('LTX-'), 'custom planId starts with LTX-');
  check(idCustom.contains('-v2-'), 'custom planId contains -v2-');

  // ── encodeHash / decodeHash ───────────────────────────────────────────────

  final hash = encodeHash(plan);
  check(hash.startsWith('#l='), 'encodeHash starts with #l=');
  check(hash.length > 10, 'encodeHash produces non-trivial hash');

  final decoded = decodeHash(hash);
  check(decoded != null, 'decodeHash not null');
  check(decoded!.title == plan.title, 'decodeHash title matches');
  check(decoded.v == plan.v, 'decodeHash v matches');
  check(decoded.start == plan.start, 'decodeHash start matches');
  check(decoded.quantum == plan.quantum, 'decodeHash quantum matches');
  check(decoded.mode == plan.mode, 'decodeHash mode matches');
  check(decoded.nodes.length == 2, 'decodeHash nodes.length == 2');
  check(decoded.nodes[0].name == 'Earth HQ', 'decodeHash node[0] name');
  check(decoded.nodes[1].name == 'Mars Hab-01', 'decodeHash node[1] name');
  check(decoded.segments.length == 7, 'decodeHash segments.length == 7');

  // decodeHash with l= prefix (no #)
  final hashNoHash = hash.substring(1); // remove leading #
  final decoded2 = decodeHash(hashNoHash);
  check(decoded2 != null, 'decodeHash without # works');
  check(decoded2!.title == plan.title, 'decodeHash without # title matches');

  // decodeHash with invalid input
  final decodedInvalid = decodeHash('invalid!!!');
  check(decodedInvalid == null, 'decodeHash invalid returns null');

  // ── LtxPlan.toJson / fromJson ─────────────────────────────────────────────

  final json = plan.toJson();
  check(json.contains('"v":2'), 'toJson contains "v":2');
  check(json.contains('"title":"LTX Session"'), 'toJson contains title');
  check(json.contains('"start":"2024-01-15T14:00:00Z"'), 'toJson contains start');
  check(json.contains('"quantum":5'), 'toJson contains quantum');
  check(json.contains('"mode":"LTX"'), 'toJson contains mode');
  check(json.contains('"nodes"'), 'toJson contains nodes');
  check(json.contains('"segments"'), 'toJson contains segments');
  check(json.contains('PLAN_CONFIRM'), 'toJson contains PLAN_CONFIRM');
  check(json.contains('Earth HQ'), 'toJson contains Earth HQ');

  final fromParsed = LtxPlan.fromJson(json);
  check(fromParsed != null, 'fromJson succeeds');
  check(fromParsed!.title == plan.title, 'fromJson title matches');
  check(fromParsed.start == plan.start, 'fromJson start matches');
  check(fromParsed.nodes.length == 2, 'fromJson nodes.length == 2');
  check(fromParsed.segments.length == 7, 'fromJson segments.length == 7');

  // fromJson with invalid JSON returns null
  final fromInvalid = LtxPlan.fromJson('not-json');
  check(fromInvalid == null, 'fromJson invalid returns null');

  // ── buildNodeUrls ─────────────────────────────────────────────────────────

  final urls = buildNodeUrls(plan, baseUrl: 'https://interplanet.live/ltx.html');
  check(urls.length == 2, 'buildNodeUrls 2 URLs');
  check(urls[0].nodeId == 'N0', 'buildNodeUrls[0] nodeId=N0');
  check(urls[0].role == 'HOST', 'buildNodeUrls[0] role=HOST');
  check(urls[0].url.contains('node=N0'), 'buildNodeUrls[0] url has node=N0');
  check(urls[0].url.contains('#l='), 'buildNodeUrls[0] url has hash');
  check(urls[0].url.startsWith('https://interplanet.live/ltx.html'), 'buildNodeUrls[0] base correct');
  check(urls[1].nodeId == 'N1', 'buildNodeUrls[1] nodeId=N1');
  check(urls[1].role == 'PARTICIPANT', 'buildNodeUrls[1] role=PARTICIPANT');
  check(urls[1].url.contains('node=N1'), 'buildNodeUrls[1] url has node=N1');

  // ── generateIcs ───────────────────────────────────────────────────────────

  final ics = generateIcs(plan);
  check(ics.contains('BEGIN:VCALENDAR'), 'ICS has BEGIN:VCALENDAR');
  check(ics.contains('END:VCALENDAR'), 'ICS has END:VCALENDAR');
  check(ics.contains('BEGIN:VEVENT'), 'ICS has BEGIN:VEVENT');
  check(ics.contains('END:VEVENT'), 'ICS has END:VEVENT');
  check(ics.contains('LTX-PLANID:'), 'ICS has LTX-PLANID');
  check(ics.contains('LTX-QUANTUM:'), 'ICS has LTX-QUANTUM');
  check(ics.contains('LTX-QUANTUM:PT5M'), 'ICS LTX-QUANTUM correct');
  check(ics.contains('LTX-MODE:LTX'), 'ICS has LTX-MODE');
  check(ics.contains('LTX-SEGMENT-TEMPLATE:'), 'ICS has LTX-SEGMENT-TEMPLATE');
  check(ics.contains('LTX-NODE:'), 'ICS has LTX-NODE');
  check(ics.contains('LTX-DELAY;'), 'ICS has LTX-DELAY');
  check(ics.contains('LTX-READINESS:'), 'ICS has LTX-READINESS');
  check(ics.contains('VERSION:2.0'), 'ICS has VERSION:2.0');
  check(ics.contains('PRODID:-//InterPlanet//LTX v1.1//EN'), 'ICS has PRODID');
  check(ics.contains('CALSCALE:GREGORIAN'), 'ICS has CALSCALE');
  check(ics.contains('METHOD:PUBLISH'), 'ICS has METHOD');
  check(ics.contains('SUMMARY:LTX Session'), 'ICS has SUMMARY');
  check(ics.contains('\r\n'), 'ICS uses CRLF');
  check(!ics.contains('\r\n\n'), 'ICS has no double newlines');
  check(ics.contains('@interplanet.live'), 'ICS UID has domain');

  // ── formatHms ─────────────────────────────────────────────────────────────

  check(formatHms(0) == '00:00', 'formatHms 0s = 00:00');
  check(formatHms(60) == '01:00', 'formatHms 60s = 01:00');
  check(formatHms(65) == '01:05', 'formatHms 65s = 01:05');
  check(formatHms(3600) == '01:00:00', 'formatHms 3600s = 01:00:00');
  check(formatHms(3661) == '01:01:01', 'formatHms 3661s = 01:01:01');
  check(formatHms(59) == '00:59', 'formatHms 59s = 00:59');
  check(formatHms(-5) == '00:00', 'formatHms negative = 00:00');
  check(formatHms(7200) == '02:00:00', 'formatHms 7200s = 02:00:00');

  // ── formatUtc ─────────────────────────────────────────────────────────────

  final testDt = DateTime.utc(2024, 1, 15, 14, 30, 45);
  check(formatUtc(testDt) == '14:30:45 UTC', 'formatUtc correct');
  final midnight = DateTime.utc(2024, 6, 1, 0, 0, 0);
  check(formatUtc(midnight) == '00:00:00 UTC', 'formatUtc midnight');

  // ── upgradeConfig ─────────────────────────────────────────────────────────

  final upgraded = upgradeConfig(plan);
  check(upgraded.v == 2, 'upgradeConfig returns v2');
  check(upgraded.nodes.length == 2, 'upgradeConfig nodes preserved');

  // ── LtxNode / LtxSegmentTemplate / LtxSegment / LtxNodeUrl models ─────────

  const node = LtxNode(id: 'N0', name: 'Earth', role: 'HOST', delay: 0, location: 'earth');
  check(node.id == 'N0', 'LtxNode id');
  check(node.name == 'Earth', 'LtxNode name');
  check(node.role == 'HOST', 'LtxNode role');
  check(node.delay == 0, 'LtxNode delay');
  check(node.location == 'earth', 'LtxNode location');

  const tpl = LtxSegmentTemplate(type: 'TX', q: 3);
  check(tpl.type == 'TX', 'LtxSegmentTemplate type');
  check(tpl.q == 3, 'LtxSegmentTemplate q');

  const nodeUrl = LtxNodeUrl(nodeId: 'N0', name: 'Earth', role: 'HOST', url: 'https://example.com');
  check(nodeUrl.nodeId == 'N0', 'LtxNodeUrl nodeId');
  check(nodeUrl.url == 'https://example.com', 'LtxNodeUrl url');

  // ── Round-trip hash integrity ──────────────────────────────────────────────

  final hash2 = encodeHash(plan2);
  final decoded3 = decodeHash(hash2);
  check(decoded3 != null, 'round-trip decodeHash not null');
  check(decoded3!.title == 'Custom Session', 'round-trip title');
  check(decoded3.quantum == 5, 'round-trip quantum');
  check(decoded3.nodes[0].name == 'Moon Base', 'round-trip node[0] name');
  check(decoded3.nodes[1].delay == 120.0, 'round-trip delay');

  // ── escapeIcsText (Story 26.3) ────────────────────────────────────────────

  check(escapeIcsText('') == '', 'escapeIcsText empty');
  check(escapeIcsText('hello') == 'hello', 'escapeIcsText no specials');
  check(escapeIcsText('a;b') == r'a\;b', 'escapeIcsText semicolon');
  check(escapeIcsText('a,b') == r'a\,b', 'escapeIcsText comma');
  check(escapeIcsText('a\\b') == r'a\\b', 'escapeIcsText backslash');
  check(escapeIcsText('a\nb') == r'a\nb', 'escapeIcsText newline');

  // ICS SUMMARY should contain escaped title
  final escapedIcs = generateIcs(
    createPlan(title: 'Hello, World; Test', start: '2026-03-15T14:00:00Z'),
  );
  check(escapedIcs.contains(r'SUMMARY:Hello\, World\; Test'),
      'generateIcs SUMMARY escaped');

  // ── SessionState constants (Story 26.4) ───────────────────────────────────

  check(kSessionStates.length == 5, 'kSessionStates has 5 entries');
  check(kSessionStates.contains('DEGRADED'), 'kSessionStates contains DEGRADED');
  check(kSessionStates[0] == 'INIT', 'kSessionStates[0] is INIT');
  check(kSessionStates[3] == 'DEGRADED', 'kSessionStates[3] is DEGRADED');
  check(kSessionStates[4] == 'COMPLETE', 'kSessionStates[4] is COMPLETE');

  // ── planLockTimeoutMs (Story 26.4) ────────────────────────────────────────

  check(kDefaultPlanLockTimeoutFactor == 2, 'kDefaultPlanLockTimeoutFactor is 2');
  check(planLockTimeoutMs(100) == 200000, 'planLockTimeoutMs(100) == 200000');
  check(planLockTimeoutMs(0) == 0, 'planLockTimeoutMs(0) == 0');
  check(planLockTimeoutMs(60) == 120000, 'planLockTimeoutMs(60) == 120000');

  // ── checkDelayViolation (Story 26.4) ──────────────────────────────────────

  check(kDelayViolationWarnS == 120, 'kDelayViolationWarnS is 120');
  check(kDelayViolationDegradedS == 300, 'kDelayViolationDegradedS is 300');
  check(
      checkDelayViolation(declaredDelayS: 100, measuredDelayS: 100) == 'ok',
      'checkDelayViolation ok (same)');
  check(
      checkDelayViolation(declaredDelayS: 100, measuredDelayS: 210) == 'ok',
      'checkDelayViolation ok within 120');
  check(
      checkDelayViolation(declaredDelayS: 100, measuredDelayS: 221) == 'violation',
      'checkDelayViolation violation');
  check(
      checkDelayViolation(declaredDelayS: 100, measuredDelayS: 401) == 'degraded',
      'checkDelayViolation degraded');
  check(
      checkDelayViolation(declaredDelayS: 0, measuredDelayS: 120) == 'ok',
      'checkDelayViolation boundary 120 ok');
  check(
      checkDelayViolation(declaredDelayS: 0, measuredDelayS: 301) == 'degraded',
      'checkDelayViolation boundary 301 degraded');

  // ── computeSegments quantum guard (Story 26.4) ────────────────────────────

  LtxPlan? badPlan = createPlan(start: '2026-03-15T14:00:00Z');
  badPlan = LtxPlan(
    v: badPlan.v,
    title: badPlan.title,
    start: badPlan.start,
    quantum: 0,
    mode: badPlan.mode,
    nodes: badPlan.nodes,
    segments: badPlan.segments,
  );
  bool badQuantumThrew = false;
  try {
    computeSegments(badPlan);
  } on ArgumentError {
    badQuantumThrew = true;
  }
  check(badQuantumThrew, 'computeSegments quantum=0 throws');

  LtxPlan badPlan2 = LtxPlan(
    v: 2,
    title: 'Test',
    start: '2026-03-15T14:00:00Z',
    quantum: -1,
    mode: 'LTX',
    nodes: const [],
    segments: const [],
  );
  bool badQuantumThrew2 = false;
  try {
    computeSegments(badPlan2);
  } on ArgumentError {
    badQuantumThrew2 = true;
  }
  check(badQuantumThrew2, 'computeSegments quantum=-1 throws');


  // ---- SecurityTests (Epic 29.1, 29.4, 29.5) ----

  // canonicalJSON_key_order
  final dA = <String, dynamic>{'z': 'last', 'a': 'first', 'm': 'mid'};
  final dB = <String, dynamic>{'m': 'mid', 'z': 'last', 'a': 'first'};
  final cA = canonicalJsonMap(dA);
  final cB = canonicalJsonMap(dB);
  check(cA == cB, 'canonicalJSON: key order normalised');
  check(cA == '{"a":"first","m":"mid","z":"last"}', 'canonicalJSON: exact output');

  // generateNIK_fields
  final nikR = await generateNik();
  final nik = nikR.nik;
  check(nik.nodeId.length == 16, 'generateNIK: nodeId is 16 hex chars');
  check(nik.nodeId == nik.nodeId.toLowerCase(), 'generateNIK: nodeId is lowercase hex');
  check(nik.publicKeyB64.isNotEmpty, 'generateNIK: publicKeyB64 set');
  check(nikR.privateKeyB64.isNotEmpty, 'generateNIK: privateKeyB64 set');
  check(nik.keyType == 'ltx-nik-v1', 'generateNIK: keyType=ltx-nik-v1');
  check(nik.validFrom.endsWith('Z'), 'generateNIK: validFrom UTC ISO');
  check(nik.validUntil.endsWith('Z'), 'generateNIK: validUntil UTC ISO');
  check(!isNikExpired(nik), 'generateNIK: fresh NIK not expired');
  final nik30R = await generateNik(validDays: 30, nodeLabel: 'test');
  check(nik30R.nik.nodeLabel == 'test', 'generateNIK: nodeLabel set');

  // isNIKExpired
  final expiredNik = nik.copyWith(validUntil: '2020-01-01T00:00:00Z');
  check(isNikExpired(expiredNik), 'isNIKExpired: past date true');
  final futureNik = nik.copyWith(validUntil: '2099-01-01T00:00:00Z');
  check(!isNikExpired(futureNik), 'isNIKExpired: future date false');

  // signVerifyPlan_valid
  final planData = <String, dynamic>{
    'title': 'Test Session',
    'start': '2024-01-15T14:00:00Z',
    'quantum': 3,
  };
  final signed = await signPlan(planData, nikR.privateKeyB64);
  check(signed.payloadB64.isNotEmpty, 'signPlan: payloadB64 set');
  check(signed.sig.isNotEmpty, 'signPlan: sig set');
  check(signed.signerNodeId.length == 16, 'signPlan: signerNodeId 16 hex');
  check(signed.signerNodeId == nikR.nik.nodeId, 'signPlan: signerNodeId matches NIK');
  final keyCache = <String, Nik>{nikR.nik.nodeId: nikR.nik};
  final vOk = await verifyPlan(signed, keyCache);
  check(vOk.valid, 'verifyPlan: valid returns true');
  check(vOk.reason == null, 'verifyPlan: reason null on success');

  // signVerifyPlan_tampered
  final tamperedPlan = <String, dynamic>{
    'title': 'TAMPERED',
    'start': '2024-01-15T14:00:00Z',
    'quantum': 3,
  };
  final tSigned = SignedPlan(
    plan: tamperedPlan,
    payloadB64: signed.payloadB64,
    sig: signed.sig,
    signerNodeId: signed.signerNodeId,
  );
  final vTampered = await verifyPlan(tSigned, keyCache);
  check(!vTampered.valid, 'verifyPlan tampered: false');
  check(vTampered.reason == 'payload_mismatch', 'verifyPlan tampered: payload_mismatch');

  // signVerifyPlan_wrong_key
  final emptyCache = <String, Nik>{};
  final vNoKey = await verifyPlan(signed, emptyCache);
  check(!vNoKey.valid, 'verifyPlan wrong key: false');
  check(vNoKey.reason == 'key_not_in_cache', 'verifyPlan wrong key: key_not_in_cache');

  // sequenceTracker_replay
  final tracker = SequenceTracker();
  const nid = 'node-alpha';
  final b1 = tracker.addSeq({'data': 'first'}, nid);
  check(b1['seq'] == 1, 'addSeq: first seq=1');
  final b2 = tracker.addSeq({'data': 'x'}, nid);
  check(b2['seq'] == 2, 'addSeq: second seq=2');
  final r1 = tracker.checkSeq(b1, nid);
  check(r1.accepted, 'checkSeq: seq=1 accepted');
  check(!r1.gap, 'checkSeq: seq=1 no gap');
  final r1r = tracker.checkSeq(b1, nid);
  check(!r1r.accepted, 'checkSeq replay: not accepted');
  check(r1r.reason == 'replay', 'checkSeq replay: reason=replay');

  // sequenceTracker_gap
  final tracker2 = SequenceTracker();
  const nid2 = 'node-beta';
  final bs = List.generate(5, (i) => tracker2.addSeq({'i': i}, nid2));
  final gr1 = tracker2.checkSeq(bs[0], nid2);
  check(gr1.accepted && !gr1.gap, 'checkSeq: seq=1 ok no gap');
  final gr2 = tracker2.checkSeq(bs[1], nid2);
  check(gr2.accepted && !gr2.gap, 'checkSeq: seq=2 ok no gap');
  final gr5 = tracker2.checkSeq(bs[4], nid2);
  check(gr5.accepted, 'checkSeq gap: seq=5 accepted');
  check(gr5.gap, 'checkSeq gap: Gap=true');
  check(gr5.gapSize == 2, 'checkSeq gap: GapSize=2');

  // ══════════════════════════════════════════════════════════════════════════
  // LTX v1.1 core subset — golden conformance vectors (Epic 72.4)
  // ══════════════════════════════════════════════════════════════════════════

  // test/v11.json is a copy of the .v11 section of conformance/vectors.json
  // (identical to go/ltx/testdata/v11.json); paths are relative to dart/ltx.
  final vectorsFile = File('test/v11.json');
  check(vectorsFile.existsSync(), 'v11: test/v11.json found');
  final v11Root =
      jsonDecode(vectorsFile.readAsStringSync()) as Map<String, dynamic>;
  final v11 = (v11Root['v11'] as Map<String, dynamic>?) ?? v11Root;

  final keyVec = v11['key'] as Map<String, dynamic>;
  final nikVec = keyVec['nik'] as Map<String, dynamic>;
  final seedB64 = keyVec['privateSeedB64'] as String;
  final vecNik = Nik(
    nodeId: nikVec['nodeId'] as String,
    publicKeyB64: nikVec['publicKey'] as String,
    validFrom: nikVec['validFrom'] as String,
    validUntil: nikVec['validUntil'] as String,
  );

  // Fixed seed reproduces the vector public key.
  final derivedPub = b64UrlEncode(await publicKeyFromSeed(seedB64));
  check(derivedPub == vecNik.publicKeyB64, 'v11: seed derives vector pubkey');

  // ── 1. v3 planId + v2 regression ─────────────────────────────────────────

  final planV3Map = (v11['planIdV3'] as Map)['plan'] as Map<String, dynamic>;
  check(canonicalJson(planV3Map) == (v11['planIdV3'] as Map)['canonicalJson'],
      'v11: v3 plan canonical JSON matches vector');
  check(
      sha256HexOfString(canonicalJson(planV3Map)) ==
          (v11['planIdV3'] as Map)['sha256'],
      'v11: v3 plan canonical sha256 matches vector');
  final planV3 = LtxPlan.fromJson(jsonEncode(planV3Map))!;
  check(makePlanId(planV3) == (v11['planIdV3'] as Map)['expectedPlanId'],
      'v11: makePlanId v3 == ${(v11['planIdV3'] as Map)['expectedPlanId']}');

  final planV2Map =
      (v11['planIdV2Regression'] as Map)['plan'] as Map<String, dynamic>;
  final planV2 = LtxPlan.fromJson(jsonEncode(planV2Map))!;
  check(
      makePlanId(planV2) ==
          (v11['planIdV2Regression'] as Map)['expectedPlanId'],
      'v11: FROZEN v2 planId regression (${makePlanId(planV2)})');

  // ── 2. pairDelay + computeSegmentsFor ────────────────────────────────────

  final pdVec = v11['pairDelay'] as Map<String, dynamic>;
  final pdPlan = LtxPlan.fromJson(jsonEncode(pdVec['plan']))!;
  for (final c in (pdVec['cases'] as List)) {
    final cm = c as Map<String, dynamic>;
    check(pairDelay(pdPlan, cm['a'] as String, cm['b'] as String) == cm['expected'],
        'v11: pairDelay(${cm['a']},${cm['b']}) == ${cm['expected']}');
  }
  final fbVec = pdVec['fallbackCase'] as Map<String, dynamic>;
  final fbPlan = LtxPlan.fromJson(jsonEncode(fbVec['plan']))!;
  check(
      pairDelay(fbPlan, fbVec['a'] as String, fbVec['b'] as String) ==
          fbVec['expected'],
      'v11: pairDelay fallback == ${fbVec['expected']}');

  // Viewer-perspective segments over the v3 pair-delay plan.
  final segN2 = computeSegmentsFor(pdPlan, 'N2');
  check(segN2.length == 4, 'v11: computeSegmentsFor 4 segments');
  check(segN2[0].perspective == 'neutral' && segN2[0].arrivalOffsetS == 0,
      'v11: PLAN_CONFIRM neutral for N2');
  check(segN2[1].perspective == 'receive' && segN2[1].arrivalOffsetS == 2,
      'v11: N0 TX received by N2 with +2s (HOST row)');
  check(segN2[2].perspective == 'receive' && segN2[2].arrivalOffsetS == 500,
      'v11: N1 TX received by N2 with +500s (pair matrix)');
  final baseSegs = computeSegments(pdPlan);
  check(segN2[2].startMs == baseSegs[2].startMs + 500 * 1000,
      'v11: receive segment start shifted by pairDelay');
  check(segN2[2].speaker == 'N1' && segN2[2].label == 'Mars Report',
      'v11: viewer segment keeps speaker/label');
  final segN1 = computeSegmentsFor(pdPlan, 'N1');
  check(segN1[2].perspective == 'transmit' && segN1[2].arrivalOffsetS == 0,
      'v11: own TX is transmit with no shift');
  check(segN1[2].startMs == baseSegs[2].startMs,
      'v11: transmit segment unshifted');
  bool unknownViewerThrew = false;
  try {
    computeSegmentsFor(pdPlan, 'N9');
  } on ArgumentError {
    unknownViewerThrew = true;
  }
  check(unknownViewerThrew, 'v11: computeSegmentsFor unknown viewer throws');

  // ── 3. Amendment-chain verify ────────────────────────────────────────────

  final chainVec = (v11['amendmentChain'] as Map<String, dynamic>);
  final chain = (chainVec['chain'] as List)
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();
  final v11KeyCache = <String, Nik>{vecNik.nodeId: vecNik};
  final rootPlan = (chain[0]['plan'] as Map).cast<String, dynamic>();
  check(planHash(rootPlan) == chainVec['rootPlanHash'],
      'v11: planHash(root) matches vector rootPlanHash');
  final chainOk = await verifyAmendmentChain(chain, v11KeyCache);
  check(chainOk.valid, 'v11: amendment chain verifies (${chainOk.reason})');

  // Tamper the amended link's title → chain must fail.
  final tamperedChain = (jsonDecode(jsonEncode(chain)) as List)
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();
  (tamperedChain[1]['plan'] as Map)['title'] = 'Tampered Summit';
  final chainBad = await verifyAmendmentChain(tamperedChain, v11KeyCache);
  check(!chainBad.valid, 'v11: tampered amendment chain rejected');

  // createAmendment roundtrip with the fixed seed.
  final signedRoot = await signPlanEnvelope(rootPlan, seedB64);
  final rootVerify = await verifyPlanEnvelope(signedRoot, v11KeyCache);
  check(rootVerify.valid, 'v11: signPlanEnvelope roundtrip verifies');
  final amended = await createAmendment(
      signedRoot, {'title': 'Vector Summit (amended)'}, seedB64);
  check((amended['plan'] as Map)['planVersion'] == 2 &&
          (amended['plan'] as Map)['prevPlanHash'] == planHash(rootPlan),
      'v11: createAmendment sets planVersion+1 and prevPlanHash');
  final rtChain = await verifyAmendmentChain([signedRoot, amended], v11KeyCache);
  check(rtChain.valid, 'v11: createAmendment chain verifies (${rtChain.reason})');

  // ── 4. Register entries + reducers + entriesRoot ─────────────────────────

  final regVec = v11['registerEntries'] as Map<String, dynamic>;
  final regEntries = (regVec['entries'] as List)
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();
  final regKeyCache = <String, Nik>{'N0': vecNik, 'N1': vecNik};
  for (final e in regEntries) {
    final vr = await verifyRegisterEntry(e, regKeyCache);
    check(vr.valid, 'v11: register entry ${e['entryId']} verifies (${vr.reason})');
  }
  final tamperedEntry =
      (jsonDecode(jsonEncode(regEntries[0])) as Map).cast<String, dynamic>();
  (tamperedEntry['content'] as Map)['text'] = 'Tampered?';
  final tv = await verifyRegisterEntry(tamperedEntry, regKeyCache);
  check(!tv.valid && tv.reason == 'signature_invalid',
      'v11: tampered register entry rejected');

  final reduced = reduceQuestions(regEntries);
  final expState = (regVec['expectedQuestionState'] as Map)
      .cast<String, dynamic>();
  check(reduced.byId.length == expState.length,
      'v11: reduceQuestions question count');
  var qMatches = true;
  expState.forEach((qid, expected) {
    final got = reduced.byId[qid];
    if (got == null) {
      qMatches = false;
      return;
    }
    (expected as Map).forEach((k, v) {
      if (got[k] != v) qMatches = false;
    });
  });
  check(qMatches, 'v11: reduceQuestions state matches vector');
  check(reduced.superseded.isEmpty, 'v11: no superseded entries in vector');
  // Order-insensitivity: reversed input produces identical state.
  final reducedRev = reduceQuestions(regEntries.reversed.toList());
  check(canonicalJson(reducedRev.byId) == canonicalJson(reduced.byId),
      'v11: reduceQuestions is input-order independent');

  check(entriesRoot(regEntries) == regVec['entriesRoot'],
      'v11: entriesRoot matches vector');
  check(entriesRoot(regEntries.reversed.toList()) == regVec['entriesRoot'],
      'v11: entriesRoot input-order independent');

  // createRegisterEntry roundtrip.
  final newEntry = await createRegisterEntry(
    'action',
    {'description': 'Test action'},
    sessionId: 'VEC-SESSION',
    nodeId: 'N1',
    seq: 2,
    timestamp: '2040-02-01T11:10:00.000Z',
    privateKeyB64: seedB64,
  );
  check(newEntry['entryId'] == 'ACT-N1-2', 'v11: createRegisterEntry id');
  final newOk = await verifyRegisterEntry(newEntry, regKeyCache);
  check(newOk.valid, 'v11: created register entry verifies');
  final actions = reduceActions([newEntry]);
  check(actions.byId['ACT-N1-2']?['status'] == 'PROPOSED',
      'v11: reduceActions PROPOSED');

  // ── 5. CBOR decode + COSE_Sign1 verify ───────────────────────────────────

  final coseVec = v11['coseSign1'] as Map<String, dynamic>;
  final coseEnvelope = <String, dynamic>{
    'plan': coseVec['plan'],
    'coseSign1CborB64': coseVec['coseSign1CborB64'],
  };
  final coseKeyCache = <String, Nik>{vecNik.nodeId: vecNik};
  final coseOk = await verifyPlanCose(coseEnvelope, coseKeyCache);
  check(coseOk.valid == coseVec['expectedValid'],
      'v11: COSE_Sign1 vector verifies (${coseOk.reason})');

  // b64 and hex encodings agree.
  final cborBytes =
      Uint8List.fromList(b64UrlDecode(coseVec['coseSign1CborB64'] as String));
  final hexStr = cborBytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  check(hexStr == coseVec['coseSign1CborHex'], 'v11: CBOR b64 == hex vector');

  // Tampered plan → payload mismatch.
  final coseTampered = <String, dynamic>{
    'plan': {...(coseVec['plan'] as Map).cast<String, dynamic>(), 'title': 'X'},
    'coseSign1CborB64': coseVec['coseSign1CborB64'],
  };
  final coseBad = await verifyPlanCose(coseTampered, coseKeyCache);
  check(!coseBad.valid && coseBad.reason == 'payload_mismatch',
      'v11: COSE tampered plan rejected');
  final coseNoKey = await verifyPlanCose(coseEnvelope, <String, Nik>{});
  check(!coseNoKey.valid && coseNoKey.reason == 'key_not_in_cache',
      'v11: COSE unknown key rejected');

  // CBOR codec unit checks.
  final decodedCose = decodeCbor(cborBytes);
  check(decodedCose is CborTag && decodedCose.tag == 18,
      'v11: CBOR decodes to tag 18');
  final roundtrip = encodeCbor(decodedCose);
  check(b64UrlEncode(roundtrip) == coseVec['coseSign1CborB64'],
      'v11: CBOR deterministic re-encode roundtrip');
  check(b64UrlEncode(encodeCbor({1: -19})) == b64UrlEncode(
          Uint8List.fromList([0xa1, 0x01, 0x32])),
      'v11: CBOR {1:-19} == a10132');
  bool trailingThrew = false;
  try {
    decodeCbor(Uint8List.fromList([0x01, 0x02]));
  } on FormatException {
    trailingThrew = true;
  }
  check(trailingThrew, 'v11: CBOR trailing bytes rejected');
  bool floatThrew = false;
  try {
    decodeCbor(Uint8List.fromList([0xf9, 0x3c, 0x00]));
  } on FormatException {
    floatThrew = true;
  }
  check(floatThrew, 'v11: CBOR floats rejected');
  bool indefThrew = false;
  try {
    decodeCbor(Uint8List.fromList([0x9f, 0x01, 0xff]));
  } on FormatException {
    indefThrew = true;
  }
  check(indefThrew, 'v11: CBOR indefinite length rejected');

  // signPlanCose roundtrip with the fixed seed.
  final coseSigned = await signPlanCose(
      (coseVec['plan'] as Map).cast<String, dynamic>(), seedB64);
  check(coseSigned['coseSign1CborB64'] == coseVec['coseSign1CborB64'],
      'v11: signPlanCose reproduces vector bytes');
  final coseSignedOk = await verifyPlanCose(coseSigned, coseKeyCache);
  check(coseSignedOk.valid, 'v11: signPlanCose roundtrip verifies');

  // ── 6. transition() state machine (golden table) ─────────────────────────

  final smVec = v11['stateMachine'] as Map<String, dynamic>;
  final smPlan = LtxPlan.fromJson(jsonEncode(smVec['plan']))!;
  check(makePlanId(smPlan) == smVec['planId'],
      'v11: state machine planId matches vector');
  var smCtx = createSession(smPlan, smVec['planId'] as String,
      quorum: smVec['quorum']);
  check(smCtx.state == 'DRAFT' && smCtx.lock == null,
      'v11: createSession starts DRAFT');
  check(smCtx.lockTimeoutMs == 1800000, 'v11: lock timeout 2×maxDelay');
  var smStepsOk = true;
  var smStepIdx = 0;
  for (final rawStep in (smVec['steps'] as List)) {
    final step = (rawStep as Map).cast<String, dynamic>();
    final result =
        transition(smCtx, (step['event'] as Map).cast<String, dynamic>());
    smCtx = result.ctx;
    final expectState = step['expectState'];
    final expectLock = step['expectLock'];
    if (smCtx.state != expectState || smCtx.lock != expectLock) {
      smStepsOk = false;
      print('  v11 state machine step $smStepIdx: '
          'got (${smCtx.state}, ${smCtx.lock}) '
          'expected ($expectState, $expectLock)');
    }
    smStepIdx += 1;
  }
  check(smStepsOk, 'v11: golden transition table replay (${smStepIdx} steps)');
  check(smCtx.subset == null,
      'v11: subset cleared after late full-lock recovery');
  check(smCtx.degradedReasons.first.contains('[N0,N2]'),
      'v11: quorum subset [N0,N2] recorded at degrade time');
  check(smCtx.degradedReasons.length == 2, 'v11: two degraded reasons logged');

  // Invalid event in terminal state is a no-op with INVALID_EVENT notify.
  final afterEnd = transition(smCtx, {'type': 'SESSION_START', 'nowMs': 6000000});
  check(afterEnd.ctx.state == 'COMPLETE' &&
          afterEnd.effects.any((e) => e['code'] == 'INVALID_EVENT'),
      'v11: invalid event ignored in COMPLETE');

  // EOK override + resume path (not covered by the golden table).
  var eokCtx = createSession(smPlan, smVec['planId'] as String, quorum: 'all');
  eokCtx = transition(eokCtx, {'type': 'START_LOCK', 'nowMs': 0}).ctx;
  for (final nid in ['N1', 'N2']) {
    eokCtx = transition(eokCtx, {
      'type': 'PLAN_CONFIRM',
      'nowMs': 1,
      'nodeId': nid,
      'planId': smVec['planId'],
    }).ctx;
  }
  check(eokCtx.state == 'LOCKED' && eokCtx.lock == 'FULL',
      'v11: full lock with quorum=all');
  eokCtx = transition(eokCtx, {'type': 'SESSION_START', 'nowMs': 2}).ctx;
  eokCtx = transition(eokCtx,
      {'type': 'EOK_OVERRIDE', 'nowMs': 3, 'verified': true}).ctx;
  check(eokCtx.state == 'EMERGENCY_HOLD', 'v11: verified EOK holds session');
  eokCtx = transition(eokCtx,
      {'type': 'HOST_DECISION', 'nowMs': 4, 'decision': 'resume'}).ctx;
  check(eokCtx.state == 'ACTIVE', 'v11: HOST resume returns to prior state');
  final rejected = transition(eokCtx,
      {'type': 'EOK_OVERRIDE', 'nowMs': 5, 'verified': false});
  check(rejected.ctx.state == 'ACTIVE' &&
          rejected.effects.any((e) => e['code'] == 'OVERRIDE_REJECTED'),
      'v11: unverified EOK rejected');
  eokCtx = transition(eokCtx, {
    'type': 'AMENDMENT_PROPOSED',
    'nowMs': 6,
    'planId': 'PLAN-2',
    'planVersion': 2,
    'affectedNodeIds': ['N1'],
  }).ctx;
  eokCtx = transition(eokCtx, {
    'type': 'AMENDMENT_CONFIRMED',
    'nowMs': 7,
    'nodeId': 'N1',
    'planId': 'PLAN-2',
  }).ctx;
  check(eokCtx.planId == 'PLAN-2' && eokCtx.planVersion == 2,
      'v11: amendment applied after all confirms');
  eokCtx = transition(eokCtx,
      {'type': 'HOST_DECISION', 'nowMs': 8, 'decision': 'abort'}).ctx;
  check(eokCtx.state == 'ABORTED', 'v11: HOST abort');

  // ══════════════════════════════════════════════════════════════════════════
  // Conformance: golden planId vectors (spec/golden/plan-ids.json)
  // ══════════════════════════════════════════════════════════════════════════

  final goldenFile = File('../../spec/golden/plan-ids.json');
  check(goldenFile.existsSync(), 'golden: spec/golden/plan-ids.json found');
  final golden =
      jsonDecode(goldenFile.readAsStringSync()) as Map<String, dynamic>;
  final gVectors = (golden['vectors'] as List)
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();
  check(gVectors.length >= 9, 'golden: vectors present');
  final gvByName = {for (final gv in gVectors) gv['name'] as String: gv};
  var typedCovered = 0;
  for (final gv in gVectors) {
    final raw = (gv['plan'] as Map).cast<String, dynamic>();
    check(makePlanIdFromMap(raw) == gv['planId'], 'golden planId ${gv['name']}');
    if (gv['planHash'] != null) {
      check(planHash(raw) == gv['planHash'], 'golden planHash ${gv['name']}');
    }
    // The typed LtxPlan serialises v2 plans in the fixed order v, title,
    // start, quantum, mode, nodes, segments and drops unmodelled fields, so
    // its planId is only comparable when that projection is lossless.
    final typed = LtxPlan.fromJson(jsonEncode(raw));
    final lossless = typed != null &&
        ((raw['v'] as int) >= 3
            ? canonicalJson(typed.toMap()) == canonicalJson(raw)
            : typed.toJson() == jsonEncode(raw));
    if (lossless) {
      typedCovered++;
      check(makePlanId(typed) == gv['planId'],
          'golden typed planId ${gv['name']}');
    }
  }
  check(typedCovered >= 3,
      'golden: typed makePlanId covers $typedCovered vectors');
  check(
      gvByName['v2-freeze-check']!['planId'] ==
          'LTX-20260801-EARTHHQ-MARS-v2-d132e85d',
      'golden v2 freeze anchor');
  check(
      gvByName['v2-unicode-title']!['planId'] ==
          'LTX-20261231-EARTHHQ-MARS-v2-7bc93af8',
      'golden v2 unicode anchor');
  check(
      gvByName['v2-createPlan-default']!['planId'] !=
          gvByName['v2-key-order-sensitive']!['planId'],
      'golden v2 order-sensitive');
  check(
      gvByName['v3-upgrade-delays']!['planId'] ==
          gvByName['v3-key-order-insensitive']!['planId'],
      'golden v3 order-insensitive');
  check(
      (gvByName['v3-amendment']!['plan'] as Map)['prevPlanHash'] ==
          gvByName['v3-upgrade-delays']!['planHash'],
      'golden v3 amendment chain hash');
  check(createPlan().quantum == 5 && kDefaultQuantum == 5,
      'createPlan default quantum is 5');

  // ── Plan validation: reserved streams / branching (§3.5, §7) ────────────

  for (final gv in gVectors) {
    check(validatePlan(gv['plan']).valid,
        'validatePlan accepts golden ${gv['name']}');
  }
  Map<String, dynamic> withF(
          Map<String, dynamic> base, Map<String, dynamic> extra) =>
      {...base, ...extra};
  final vpBase =
      (gvByName['v3-upgrade-delays']!['plan'] as Map).cast<String, dynamic>();
  final vpV2 =
      (gvByName['v2-freeze-check']!['plan'] as Map).cast<String, dynamic>();
  check(validatePlan(withF(vpBase, {'streams': []})).valid,
      'validatePlan v3 empty streams ok');
  final vpStreams = validatePlan(withF(vpBase, {
    'streams': [
      {'id': 'S1'}
    ]
  }));
  check(!vpStreams.valid && vpStreams.codes.contains('reserved_streams'),
      'validatePlan non-empty streams');
  check(
      vpStreams.errors.firstWhere((e) => e.code == 'reserved_streams').path ==
          'streams',
      'validatePlan streams error path');
  check(
      validatePlan(withF(vpBase, {'streams': 'S1'}))
          .codes
          .contains('reserved_streams'),
      'validatePlan streams non-array');
  check(
      validatePlan(withF(vpBase, {
        'segments': [
          {'type': 'TX', 'q': 1, 'stream': 'S1'}
        ]
      })).codes.contains('reserved_streams'),
      'validatePlan segment stream');
  check(
      validatePlan(withF(vpBase, {'branches': []}))
          .codes
          .contains('reserved_branching'),
      'validatePlan branches');
  check(
      validatePlan(withF(vpBase, {
        'branching': {'mode': 'local'}
      })).codes.contains('reserved_branching'),
      'validatePlan branching');
  final vpSegBranch = validatePlan(withF(vpBase, {
    'segments': [
      {'type': 'CAUCUS', 'q': 1, 'branch': 'B1'}
    ]
  }));
  check(
      vpSegBranch.codes.contains('reserved_branching') &&
          vpSegBranch.errors[0].path == 'segments[0].branch',
      'validatePlan segment branch');
  check(
      validatePlan(withF(vpV2, {'streams': []}))
          .codes
          .contains('v3_field_in_v2'),
      'validatePlan v2 streams is v3 field');
  check(
      validatePlan(withF(vpV2, {'branching': true}))
          .codes
          .contains('reserved_branching'),
      'validatePlan v2 branching');
  check(validatePlan(null).codes.contains('not_an_object'),
      'validatePlan non-object');
  check(validatePlan(withF(vpV2, {'v': 7})).codes.contains('invalid_version'),
      'validatePlan bad version');
  check(
      validatePlan(withF(
              vpV2, {'nodes': (vpV2['nodes'] as List).reversed.toList()}))
          .codes
          .contains('invalid_host'),
      'validatePlan host not first');
  check(
      validatePlan(withF(vpBase, {
        'delays': {'N1|N0': 860}
      })).codes.contains('invalid_delays'),
      'validatePlan unsorted delays key');
  check(
      validatePlan(withF(vpV2, {
        'segments': [
          {'type': 'TX', 'q': 1, 'speaker': 'N9'}
        ]
      })).codes.contains('unknown_speaker'),
      'validatePlan unknown speaker');
  check(
      validatePlan(withF(vpV2, {'quantum': 0}))
          .codes
          .contains('invalid_quantum'),
      'validatePlan quantum out of range');
  Future<String?> throwsCode(Future<Object?> Function() fn) async {
    try {
      await fn();
      return null;
    } on ReservedFieldException catch (e) {
      return e.code;
    }
  }

  final vpSigned = await signPlanEnvelope(vpBase, seedB64);
  check(
      await throwsCode(() =>
              createAmendment(vpSigned, {'branching': {}}, seedB64)) ==
          'reserved_branching',
      'createAmendment rejects branching');
  check(
      await throwsCode(() => createAmendment(vpSigned, {
                'streams': [1]
              }, seedB64)) ==
          'reserved_streams',
      'createAmendment rejects streams');
  check(
      await throwsCode(
              () => createAmendment(vpSigned, {'title': 'x'}, seedB64)) ==
          null,
      'createAmendment ok without');
  check(await throwsCode(() async => createSession(smPlan, 'id')) == null,
      'createSession accepts typed plan');
  var assertThrew = false;
  try {
    assertNoReservedFields(withF(vpBase, {
      'streams': [1]
    }), 'createSession');
  } on ReservedFieldException catch (e) {
    assertThrew = e.code == 'reserved_streams' &&
        e.message.startsWith('createSession:') &&
        e.errors.length == 1;
  }
  check(assertThrew, 'assertNoReservedFields throws with code and errors');

  // ── Registers: reduceDecisions (§10.3) + merge snapshot ─────────────────

  final decHost = await generateNik(nodeLabel: 'HOST');
  final decMars = await generateNik(nodeLabel: 'MARS');
  final decCache = <String, Nik>{'N0': decHost.nik, 'N1': decMars.nik};
  Future<Map<String, dynamic>> mkDec(String type, Map<String, dynamic> content,
          String nodeId, int seq, String ts, String priv,
          {String? entryId}) =>
      createRegisterEntry(type, content,
          sessionId: 'LTX-DEC-TEST',
          nodeId: nodeId,
          seq: seq,
          timestamp: ts,
          privateKeyB64: priv,
          entryId: entryId);
  final dec1 = await mkDec(
      'decision',
      {
        'text': 'Proceed with EVA-3',
        'rationale': 'Weather window',
        'originWindow': 'W2'
      },
      'N0',
      1,
      '2026-08-01T12:00:00.000Z',
      decHost.privateKeyB64);
  check(dec1['entryId'] == 'DEC-N0-1', 'decision id prefix DEC');
  check((await verifyRegisterEntry(dec1, decCache)).valid,
      'decision entry verifies');
  final decReg1 = reduceDecisions([dec1]);
  check(
      decReg1.byId['DEC-N0-1']!['status'] == 'RECORDED' &&
          decReg1.byId['DEC-N0-1']!['version'] == 1,
      'decision RECORDED');
  check(
      decReg1.byId['DEC-N0-1']!['text'] == 'Proceed with EVA-3' &&
          decReg1.byId['DEC-N0-1']!['recordedBy'] == 'N0' &&
          decReg1.byId['DEC-N0-1']!['rationale'] == 'Weather window',
      'decision fields');
  final decRev = await mkDec(
      'decision_update',
      {'did': 'DEC-N0-1', 'text': 'Proceed with EVA-3 at 14:00', 'version': 2},
      'N1',
      1,
      '2026-08-01T12:10:00.000Z',
      decMars.privateKeyB64);
  check(decRev['entryId'] == 'DEC-N1-1', 'decision_update id prefix DEC');
  final decRes = await mkDec(
      'decision_update',
      {'did': 'DEC-N0-1', 'status': 'RESCINDED', 'version': 3},
      'N0',
      2,
      '2026-08-01T12:20:00.000Z',
      decHost.privateKeyB64);
  final decReg2 = reduceDecisions([decRes, dec1, decRev]);
  check(decReg2.byId['DEC-N0-1']!['text'] == 'Proceed with EVA-3 at 14:00',
      'decision update applied');
  check(
      decReg2.byId['DEC-N0-1']!['status'] == 'RESCINDED' &&
          decReg2.byId['DEC-N0-1']!['version'] == 3,
      'decision RESCINDED v3');
  check(decReg2.byId['DEC-N0-1']!['editor'] == 'N0',
      'decision editor recorded');
  check(decReg2.superseded.contains(decRev['entryId']),
      'decision older update superseded');
  final decA = await mkDec(
      'decision_update',
      {'did': 'DEC-N0-1', 'text': 'From N0', 'version': 5},
      'N0',
      7,
      '2026-08-01T13:00:00.000Z',
      decHost.privateKeyB64);
  final decB = await mkDec(
      'decision_update',
      {'did': 'DEC-N0-1', 'text': 'From N1', 'version': 5},
      'N1',
      7,
      '2026-08-01T13:00:00.000Z',
      decMars.privateKeyB64);
  final decConf1 = reduceDecisions([dec1, decB, decA]);
  final decConf2 = reduceDecisions([decA, dec1, decB]);
  check(decConf1.byId['DEC-N0-1']!['text'] == 'From N0',
      'decision tie lowest nodeId wins');
  check(
      decConf1.superseded.contains(decB['entryId']) &&
          !decConf1.superseded.contains(decA['entryId']),
      'decision tie loser superseded');
  check(
      jsonEncode(decConf1.byId) == jsonEncode(decConf2.byId) &&
          jsonEncode(decConf1.superseded) == jsonEncode(decConf2.superseded),
      'decision reduce order-independent');
  final decHi = await mkDec(
      'decision_update',
      {'did': 'DEC-N0-1', 'text': 'N1 v6', 'version': 6},
      'N1',
      8,
      '2026-08-01T12:30:00.000Z',
      decMars.privateKeyB64);
  check(
      reduceDecisions([dec1, decA, decHi]).byId['DEC-N0-1']!['text'] ==
          'N1 v6',
      'decision higher version wins');
  final decOrphan = await mkDec(
      'decision_update',
      {'did': 'DEC-NOPE-1', 'version': 2},
      'N1',
      9,
      '2026-08-01T12:40:00.000Z',
      decMars.privateKeyB64);
  final decDup = await mkDec('decision', {'text': 'dup'}, 'N1', 10,
      '2026-08-01T12:50:00.000Z', decMars.privateKeyB64,
      entryId: 'DEC-N0-1');
  final decReg3 = reduceDecisions([dec1, decOrphan, decDup]);
  check(decReg3.superseded.contains('DEC-N1-9'),
      'decision orphan update superseded');
  check(
      decReg3.byId['DEC-N0-1']!['text'] == 'Proceed with EVA-3' &&
          decReg3.byId['DEC-N0-1']!['recordedBy'] == 'N0',
      'decision duplicate create ignored');
  check(
      reduceDecisions([dec1, decRev]).byId.length == 1 &&
          reduceActions([dec1]).byId.isEmpty,
      'decision reducer ignores others');
  final decSnap = await runMergeSegment([dec1], [decRev], decCache,
      sessionId: 'LTX-DEC-TEST',
      nodeId: 'N0',
      seq: 99,
      timestamp: '2026-08-01T15:00:00.000Z',
      privateKeyB64: decHost.privateKeyB64);
  final snapContent = decSnap.snapshot['content'] as Map;
  check((snapContent['decisionRegister'] as Map)['DEC-N0-1']['version'] == 2,
      'snapshot decisionRegister');
  check(
      decSnap.snapshot['entryId'] == 'MRG-N0-99' &&
          snapContent['entryCount'] == 2 &&
          snapContent['rejectedCount'] == 0,
      'snapshot entry id and counts');
  check((await verifyRegisterEntry(decSnap.snapshot, decCache)).valid,
      'snapshot signature verifies');
  final decMergeRej =
      await mergeLogs([dec1], [decRev], <String, Nik>{'N0': decHost.nik});
  check(
      decMergeRej.entries.length == 1 &&
          decMergeRej.rejected.single['reason'] == 'key_not_in_cache',
      'mergeLogs rejects unverifiable entries');

  // ── Summary ───────────────────────────────────────────────────────────────

  print('\n$passed passed  $failed failed');
  if (failed > 0) throw Exception('Tests failed');
}
