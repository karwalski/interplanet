// test/interplanet_ltx_test.dart — LTX SDK unit tests (≥80 check() assertions)

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

  check(kVersion == '1.0.0', 'VERSION is 1.0.0');
  check(kDefaultQuantum == 3, 'DEFAULT_QUANTUM is 3');
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
  check(plan.quantum == 3, 'createPlan quantum=3');
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
  check(segs[0].durMin == 6, 'first segment 6 min (q=2, quantum=3)');
  check(segs[1].type == 'TX', 'second segment TX');
  check(segs[2].type == 'RX', 'third segment RX');
  check(segs[3].type == 'CAUCUS', 'fourth segment CAUCUS');
  check(segs[4].type == 'TX', 'fifth segment TX');
  check(segs[5].type == 'RX', 'sixth segment RX');
  check(segs[6].type == 'BUFFER', 'seventh segment BUFFER');
  check(segs[6].q == 1, 'BUFFER q=1');
  check(segs[6].durMin == 3, 'BUFFER 3 min (q=1, quantum=3)');

  // Timing checks
  final t0 = DateTime.parse(segs[0].start).millisecondsSinceEpoch;
  final t1 = DateTime.parse(segs[1].start).millisecondsSinceEpoch;
  check(t1 - t0 == 6 * 60 * 1000, 'segment 1 starts 6 min after segment 0');
  check(segs[0].startMs == DateTime.parse('2024-01-15T14:00:00Z').millisecondsSinceEpoch,
      'first segment startMs correct');
  check(segs[0].endMs == segs[1].startMs, 'segment end = next segment start');

  // ── totalMin ──────────────────────────────────────────────────────────────

  check(totalMin(plan) == 39, 'totalMin 39');
  // 2+2+2+2+2+2+1 = 13 quanta × 3 min = 39 min
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
  check(json.contains('"quantum":3'), 'toJson contains quantum');
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
  check(ics.contains('LTX-QUANTUM:PT3M'), 'ICS LTX-QUANTUM correct');
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

  // ── Summary ───────────────────────────────────────────────────────────────

  print('\n$passed passed  $failed failed');
  if (failed > 0) throw Exception('Tests failed');
}
