// models.dart — LTX data model classes

import 'dart:convert';

/// A participant node in an LTX session.
class LtxNode {
  final String id;
  final String name;
  final String role;
  final double delay;
  final String location;

  const LtxNode({
    required this.id,
    required this.name,
    required this.role,
    required this.delay,
    required this.location,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'role': role,
        'delay': delay,
        'location': location,
      };

  static LtxNode fromMap(Map<String, dynamic> m) => LtxNode(
        id: m['id'] as String,
        name: m['name'] as String,
        role: m['role'] as String,
        delay: (m['delay'] as num).toDouble(),
        location: m['location'] as String,
      );
}

/// A segment template (type + quantum count, optional v3 speaker/label).
class LtxSegmentTemplate {
  final String type;
  final int q;
  final String? speaker;
  final String? label;

  const LtxSegmentTemplate({
    required this.type,
    required this.q,
    this.speaker,
    this.label,
  });

  Map<String, dynamic> toMap() => {
        'type': type,
        'q': q,
        if (speaker != null) 'speaker': speaker,
        if (label != null) 'label': label,
      };

  static LtxSegmentTemplate fromMap(Map<String, dynamic> m) =>
      LtxSegmentTemplate(
        type: m['type'] as String,
        q: m['q'] as int,
        speaker: m['speaker'] as String?,
        label: m['label'] as String?,
      );
}

/// A computed timed segment.
class LtxSegment {
  final String type;
  final int q;
  final String start;
  final String end;
  final int durMin;
  final int startMs;
  final int endMs;

  const LtxSegment({
    required this.type,
    required this.q,
    required this.start,
    required this.end,
    required this.durMin,
    required this.startMs,
    required this.endMs,
  });
}

/// A computed segment from a specific viewer's perspective (§14.3).
class LtxViewerSegment {
  final String type;
  final int q;
  final String start;
  final String end;
  final int durMin;
  final int startMs;
  final int endMs;

  /// Presenting node id, when the segment is attributed.
  final String? speaker;

  /// Agenda label, when present.
  final String? label;

  /// 'transmit' (viewer presents), 'receive' (after light-time), 'neutral'.
  final String perspective;

  /// Light-time shift applied to start/end, in seconds (0 unless receiving).
  final num arrivalOffsetS;

  const LtxViewerSegment({
    required this.type,
    required this.q,
    required this.start,
    required this.end,
    required this.durMin,
    required this.startMs,
    required this.endMs,
    this.speaker,
    this.label,
    required this.perspective,
    required this.arrivalOffsetS,
  });
}

/// A node URL entry.
class LtxNodeUrl {
  final String nodeId;
  final String name;
  final String role;
  final String url;

  const LtxNodeUrl({
    required this.nodeId,
    required this.name,
    required this.role,
    required this.url,
  });
}

/// An LTX session plan.
class LtxPlan {
  final int v;
  final String title;
  final String start;
  final int quantum;
  final String mode;
  final List<LtxNode> nodes;
  final List<LtxSegmentTemplate> segments;

  /// v3 pair-delay matrix: key "A|B" (node ids sorted) → one-way delay (s).
  final Map<String, num>? delays;

  /// v3 amendment-chain version (LTX-SPECIFICATION.md §4.4).
  final int? planVersion;

  /// SHA-256 hex of the canonical JSON of the predecessor plan (§6.4).
  final String? prevPlanHash;

  LtxPlan({
    required this.v,
    required this.title,
    required this.start,
    required this.quantum,
    required this.mode,
    required this.nodes,
    required this.segments,
    this.delays,
    this.planVersion,
    this.prevPlanHash,
  });

  /// Plain-map representation (canonical field set; integral delays as int).
  /// Used by the v3 canonical-JSON plan hash and the security functions.
  Map<String, dynamic> toMap() => {
        'v': v,
        'title': title,
        'start': start,
        'quantum': quantum,
        'mode': mode,
        'nodes': nodes
            .map((n) => {
                  'id': n.id,
                  'name': n.name,
                  'role': n.role,
                  'delay': n.delay == n.delay.truncateToDouble()
                      ? n.delay.toInt()
                      : n.delay,
                  'location': n.location,
                })
            .toList(),
        'segments': segments.map((s) => s.toMap()).toList(),
        if (delays != null) 'delays': delays,
        if (planVersion != null) 'planVersion': planVersion,
        if (prevPlanHash != null) 'prevPlanHash': prevPlanHash,
      };

  /// Serialize to JSON string.
  /// EXACT key order: v, title, start, quantum, mode, nodes, segments
  String toJson() {
    final buf = StringBuffer();
    buf.write('{');
    buf.write('"v":$v,');
    buf.write('"title":${_jsonStr(title)},');
    buf.write('"start":${_jsonStr(start)},');
    buf.write('"quantum":$quantum,');
    buf.write('"mode":${_jsonStr(mode)},');

    // nodes array
    buf.write('"nodes":[');
    for (int i = 0; i < nodes.length; i++) {
      if (i > 0) buf.write(',');
      final n = nodes[i];
      final delayVal = n.delay == n.delay.truncateToDouble()
          ? n.delay.toInt().toString()
          : n.delay.toString();
      buf.write('{');
      buf.write('"id":${_jsonStr(n.id)},');
      buf.write('"name":${_jsonStr(n.name)},');
      buf.write('"role":${_jsonStr(n.role)},');
      buf.write('"delay":$delayVal,');
      buf.write('"location":${_jsonStr(n.location)}');
      buf.write('}');
    }
    buf.write('],');

    // segments array
    buf.write('"segments":[');
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) buf.write(',');
      final s = segments[i];
      buf.write('{"type":${_jsonStr(s.type)},"q":${s.q}');
      if (s.speaker != null) buf.write(',"speaker":${_jsonStr(s.speaker!)}');
      if (s.label != null) buf.write(',"label":${_jsonStr(s.label!)}');
      buf.write('}');
    }
    buf.write(']');

    // v3 optional fields (never present on v2 plans — the frozen v2 planId
    // hash covers exactly the original byte sequence above).
    if (delays != null) {
      buf.write(',"delays":{');
      var first = true;
      delays!.forEach((k, v) {
        if (!first) buf.write(',');
        first = false;
        final dv = (v is double && v == v.truncateToDouble())
            ? v.toInt().toString()
            : v.toString();
        buf.write('${_jsonStr(k)}:$dv');
      });
      buf.write('}');
    }
    if (planVersion != null) buf.write(',"planVersion":$planVersion');
    if (prevPlanHash != null) {
      buf.write(',"prevPlanHash":${_jsonStr(prevPlanHash!)}');
    }

    buf.write('}');
    return buf.toString();
  }

  /// Parse from JSON string.
  static LtxPlan? fromJson(String jsonStr) {
    try {
      final m = jsonDecode(jsonStr) as Map<String, dynamic>;
      final nodesList = (m['nodes'] as List).map((n) {
        final nm = n as Map<String, dynamic>;
        return LtxNode(
          id: nm['id'] as String,
          name: nm['name'] as String,
          role: nm['role'] as String,
          delay: (nm['delay'] as num).toDouble(),
          location: nm['location'] as String,
        );
      }).toList();

      final segList = (m['segments'] as List).map((s) {
        final sm = s as Map<String, dynamic>;
        return LtxSegmentTemplate(
          type: sm['type'] as String,
          q: sm['q'] as int,
          speaker: sm['speaker'] as String?,
          label: sm['label'] as String?,
        );
      }).toList();

      return LtxPlan(
        v: m['v'] as int,
        title: m['title'] as String,
        start: m['start'] as String,
        quantum: m['quantum'] as int,
        mode: m['mode'] as String,
        nodes: nodesList,
        segments: segList,
        delays: (m['delays'] as Map?)?.cast<String, num>(),
        planVersion: m['planVersion'] as int?,
        prevPlanHash: m['prevPlanHash'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

String _jsonStr(String s) {
  // Encode a string value for JSON (handle quotes, backslashes, control chars)
  final escaped = s
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');
  return '"$escaped"';
}
