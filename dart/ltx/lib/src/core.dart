// core.dart — LTX core algorithms
// Dart port of ltx-sdk.js (Story 33.11)

import 'dart:convert';
import 'models.dart';
import 'constants.dart';

// ── Internal utilities ─────────────────────────────────────────────────────

String _pad(int n) => n.toString().padLeft(2, '0');

/// Base64url encode a UTF-8 string (no padding).
String _b64enc(String s) {
  return base64Url.encode(utf8.encode(s)).replaceAll('=', '');
}

/// Base64url decode to a UTF-8 string. Returns null on failure.
String? _b64dec(String s) {
  final padded = s + '=' * ((4 - s.length % 4) % 4);
  try {
    return utf8.decode(base64Url.decode(padded));
  } catch (_) {
    return null;
  }
}

/// Polynomial hash matching JS Math.imul(31, h) pattern (32-bit unsigned).
int _djbHash(String s) {
  int h = 0;
  for (final c in s.codeUnits) {
    h = ((h * 31) + c) & 0xFFFFFFFF;
  }
  return h;
}

// ── Config management ──────────────────────────────────────────────────────

/// Upgrade a v1 config (txName/rxName/delay) to v2 schema (nodes[]).
/// v2 configs (with nodes) are returned unchanged.
LtxPlan upgradeConfig(LtxPlan cfg) {
  if (cfg.v >= 2 && cfg.nodes.isNotEmpty) return cfg;
  // If we reach here, treat as v1 and produce default nodes
  return LtxPlan(
    v: 2,
    title: cfg.title,
    start: cfg.start,
    quantum: cfg.quantum,
    mode: cfg.mode,
    nodes: [
      LtxNode(id: 'N0', name: 'Earth HQ', role: 'HOST', delay: 0, location: 'earth'),
      LtxNode(id: 'N1', name: 'Mars Hab-01', role: 'PARTICIPANT', delay: 0, location: 'mars'),
    ],
    segments: cfg.segments,
  );
}

/// Create a new LTX session plan.
LtxPlan createPlan({
  String title = 'LTX Session',
  String? start,
  int quantum = kDefaultQuantum,
  String mode = 'LTX',
  List<LtxNode>? nodes,
  String hostName = 'Earth HQ',
  String hostLocation = 'earth',
  String remoteName = 'Mars Hab-01',
  String remoteLocation = 'mars',
  double delay = 0.0,
  List<LtxSegmentTemplate>? segments,
}) {
  String startStr;
  if (start != null) {
    startStr = start;
  } else {
    final now = DateTime.now().toUtc();
    final rounded = DateTime.utc(
        now.year, now.month, now.day, now.hour, now.minute);
    final plus5 = rounded.add(const Duration(minutes: 5));
    startStr = plus5.toIso8601String().replaceAll('.000000Z', 'Z').replaceAll('.000Z', 'Z');
    // Ensure format is YYYY-MM-DDTHH:MM:SS.000Z or similar
    if (!startStr.endsWith('Z')) startStr = '${startStr}Z';
  }

  final effectiveNodes = nodes ??
      [
        LtxNode(id: 'N0', name: hostName, role: 'HOST', delay: 0, location: hostLocation),
        LtxNode(id: 'N1', name: remoteName, role: 'PARTICIPANT', delay: delay, location: remoteLocation),
      ];

  final effectiveSegments = segments ??
      kDefaultSegments
          .map((s) => LtxSegmentTemplate(type: s['type'] as String, q: s['q'] as int))
          .toList();

  return LtxPlan(
    v: 2,
    title: title,
    start: startStr,
    quantum: quantum,
    mode: mode,
    nodes: effectiveNodes,
    segments: effectiveSegments,
  );
}

// ── Segment computation ────────────────────────────────────────────────────

// ── Story 26.3: ICS text escaping ──────────────────────────────────────────

/// Escape a string for RFC 5545 TEXT property values.
/// Escapes backslash, semicolon, comma, and newline.
String escapeIcsText(String s) {
  return s
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\n', r'\n');
}

// ── Story 26.4: Protocol hardening ─────────────────────────────────────────

/// Compute plan-lock timeout in milliseconds.
/// timeout = delaySeconds * DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * 1000
int planLockTimeoutMs(num delaySeconds) {
  return (delaySeconds * kDefaultPlanLockTimeoutFactor * 1000).round();
}

/// Check if the measured delay violates the declared delay threshold.
/// Returns "ok", "violation", or "degraded".
String checkDelayViolation({
  required num declaredDelayS,
  required num measuredDelayS,
}) {
  final diff = (measuredDelayS - declaredDelayS).abs();
  if (diff > kDelayViolationDegradedS) return 'degraded';
  if (diff > kDelayViolationWarnS) return 'violation';
  return 'ok';
}

/// Compute the timed segment array for a plan.
/// Throws [ArgumentError] if plan.quantum < 1.
List<LtxSegment> computeSegments(LtxPlan cfg) {
  final c = upgradeConfig(cfg);
  if (c.quantum < 1) {
    throw ArgumentError('quantum must be >= 1, got ${c.quantum}');
  }
  final qMs = c.quantum * 60 * 1000;
  int t = DateTime.parse(c.start).millisecondsSinceEpoch;

  return c.segments.map((s) {
    final durMs = s.q * qMs;
    final startMs = t;
    final endMs = t + durMs;
    final startDt = DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true);
    final endDt = DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true);
    t += durMs;
    return LtxSegment(
      type: s.type,
      q: s.q,
      start: startDt.toIso8601String(),
      end: endDt.toIso8601String(),
      durMin: s.q * c.quantum,
      startMs: startMs,
      endMs: endMs,
    );
  }).toList();
}

/// Total session duration in minutes.
int totalMin(LtxPlan cfg) {
  return cfg.segments.fold(0, (acc, s) => acc + s.q * cfg.quantum);
}

// ── Plan ID ────────────────────────────────────────────────────────────────

/// Compute the deterministic plan ID string for a config.
/// Matches the ID generated by ltx.html and api/ltx.php.
/// e.g. "LTX-20240115-EARTHHQ-MARS-v2-d3317d5e"
String makePlanId(LtxPlan cfg) {
  final c = upgradeConfig(cfg);

  // Extract date portion
  final date = c.start.substring(0, 10).replaceAll('-', '');

  // Host string: first node name, no spaces, uppercase, max 8 chars
  final hostStr = c.nodes.isNotEmpty
      ? c.nodes[0].name.replaceAll(RegExp(r'\s+'), '').toUpperCase().substring(
            0,
            c.nodes[0].name.replaceAll(RegExp(r'\s+'), '').length > 8
                ? 8
                : c.nodes[0].name.replaceAll(RegExp(r'\s+'), '').length,
          )
      : 'HOST';

  // Node string: remaining nodes, first 4 chars each, joined by -, max 16 chars
  String nodeStr;
  if (c.nodes.length > 1) {
    final parts = c.nodes.skip(1).map((n) {
      final cleaned = n.name.replaceAll(RegExp(r'\s+'), '').toUpperCase();
      return cleaned.length > 4 ? cleaned.substring(0, 4) : cleaned;
    }).join('-');
    nodeStr = parts.length > 16 ? parts.substring(0, 16) : parts;
  } else {
    nodeStr = 'RX';
  }

  // Hash: use toJson() which produces the exact key order needed
  final raw = c.toJson();
  final h = _djbHash(raw);
  final hexHash = h.toRadixString(16).padLeft(8, '0');

  return 'LTX-$date-$hostStr-$nodeStr-v2-$hexHash';
}

// ── URL hash encoding ──────────────────────────────────────────────────────

/// Encode a plan config to a URL hash fragment (#l=...).
String encodeHash(LtxPlan cfg) {
  return '#l=' + _b64enc(cfg.toJson());
}

/// Decode a plan config from a URL hash fragment.
/// Accepts "#l=..." or just "l=..." or the raw base64 token.
/// Returns null if the hash is invalid.
LtxPlan? decodeHash(String hash) {
  final str = hash.replaceFirst(RegExp(r'^#?l='), '');
  final jsonStr = _b64dec(str);
  if (jsonStr == null) return null;
  return LtxPlan.fromJson(jsonStr);
}

/// Build perspective URLs for all nodes in a plan.
List<LtxNodeUrl> buildNodeUrls(LtxPlan cfg, {String baseUrl = ''}) {
  final c = upgradeConfig(cfg);
  final hash = '#l=' + _b64enc(c.toJson());
  final base = baseUrl.replaceAll(RegExp(r'[#?].*$'), '');
  return c.nodes.map((node) {
    final encodedId = Uri.encodeComponent(node.id);
    return LtxNodeUrl(
      nodeId: node.id,
      name: node.name,
      role: node.role,
      url: '$base?node=$encodedId$hash',
    );
  }).toList();
}

// ── ICS generation ─────────────────────────────────────────────────────────

/// Generate LTX-extended iCalendar (.ics) content for a plan.
/// Uses CRLF line endings as per RFC 5545.
String generateIcs(LtxPlan cfg) {
  final c = upgradeConfig(cfg);
  final segs = computeSegments(c);
  final start = DateTime.parse(c.start).toUtc();
  final end = DateTime.fromMillisecondsSinceEpoch(segs.last.endMs, isUtc: true);
  final planId = makePlanId(c);
  final nodes = c.nodes;
  final host = nodes.isNotEmpty
      ? nodes[0]
      : LtxNode(id: 'N0', name: 'Earth HQ', role: 'HOST', delay: 0, location: 'earth');
  final participants = nodes.length > 1 ? nodes.sublist(1) : <LtxNode>[];

  String fmtDT(DateTime dt) {
    final s = dt.toIso8601String().replaceAll(RegExp(r'[-:.]'), '');
    return '${s.substring(0, 15)}Z';
  }

  String toId(String name) => name.replaceAll(RegExp(r'\s+'), '-').toUpperCase();

  final segTpl = c.segments.map((s) => s.type).join(',');

  final nodeLines = nodes.map((n) => 'LTX-NODE:ID=${toId(n.name)};ROLE=${n.role}').toList();

  final delayLines = participants.map((n) {
    final d = n.delay.toInt();
    return 'LTX-DELAY;NODEID=${toId(n.name)}:ONEWAY-MIN=$d;ONEWAY-MAX=${d + 120};ONEWAY-ASSUMED=$d';
  }).toList();

  final localTimeLines = nodes
      .where((n) => n.location == 'mars')
      .map((n) => 'LTX-LOCALTIME:NODE=${toId(n.name)};SCHEME=LMST;PARAMS=LONGITUDE:0E')
      .toList();

  final hostName = host.name;
  final partNames = participants.isNotEmpty
      ? participants.map((p) => p.name).join(', ')
      : 'remote nodes';
  final delayDesc = participants.isNotEmpty
      ? participants.map((p) => '${p.name}: ${(p.delay / 60).round()} min one-way').join(' · ')
      : 'no participant delay configured';

  final now = DateTime.now().toUtc();

  final lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//InterPlanet//LTX v1.1//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:$planId@interplanet.live',
    'DTSTAMP:${fmtDT(now)}',
    'DTSTART:${fmtDT(start)}',
    'DTEND:${fmtDT(end)}',
    'SUMMARY:${escapeIcsText(c.title)}',
    'DESCRIPTION:LTX session — ${escapeIcsText(hostName)} with ${escapeIcsText(partNames)}\\n'
        'Signal delays: $delayDesc\\n'
        'Mode: ${c.mode} · Segment plan: $segTpl\\n'
        'Generated by InterPlanet (https://interplanet.live)',
    'LTX:1',
    'LTX-PLANID:$planId',
    'LTX-QUANTUM:PT${c.quantum}M',
    'LTX-SEGMENT-TEMPLATE:$segTpl',
    'LTX-MODE:${c.mode}',
    ...nodeLines,
    ...delayLines,
    'LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY',
    ...localTimeLines,
    'END:VEVENT',
    'END:VCALENDAR',
  ];

  return lines.join('\r\n');
}

// ── Formatting utilities ───────────────────────────────────────────────────

/// Format seconds as MM:SS or H:MM:SS.
String formatHms(int sec) {
  if (sec < 0) sec = 0;
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  if (h > 0) {
    return '${_pad(h)}:${_pad(m)}:${_pad(s)}';
  }
  return '${_pad(m)}:${_pad(s)}';
}

/// Format a UTC timestamp as "HH:MM:SS UTC".
String formatUtc(DateTime dt) {
  final utc = dt.toUtc();
  return '${_pad(utc.hour)}:${_pad(utc.minute)}:${_pad(utc.second)} UTC';
}
