// validate.dart — Plan validation and raw-plan planId (LTX-SPECIFICATION.md
// §3.5, §4, §7). Dart port of validatePlan / _reservedFieldErrors /
// _assertNoReservedFields and makePlanId(JSON.parse(...)) in ltx-sdk.js.
//
// validatePlan works on the wire form (a Map from jsonDecode) because the
// typed LtxPlan model has no slot for the reserved fields it has to detect.

import 'dart:convert';

import 'security.dart';

/// One validation failure: a stable [code], the JSON [path] and a message.
class PlanValidationError {
  final String code;
  final String path;
  final String message;
  const PlanValidationError(this.code, this.path, this.message);

  Map<String, String> toMap() => {'code': code, 'path': path, 'message': message};

  @override
  String toString() => '$code at $path: $message';
}

/// Result of [validatePlan].
class PlanValidation {
  final bool valid;
  final List<PlanValidationError> errors;
  const PlanValidation(this.valid, this.errors);

  List<String> get codes => errors.map((e) => e.code).toList();
}

/// Thrown by upgrade, amendment and session creation when a plan uses the
/// reserved streams (§3.5) or branching (§7) fields. [code] is the code of the
/// first violation ('reserved_streams' or 'reserved_branching'); [errors]
/// lists all of them.
class ReservedFieldException implements Exception {
  final String code;
  final String message;
  final List<PlanValidationError> errors;
  const ReservedFieldException(this.code, this.message, this.errors);

  @override
  String toString() => 'ReservedFieldException($code): $message';
}

/// Core segment types (§3.4) plus the auxiliary types the SDKs handle.
const List<String> kPlanSegmentTypes = [
  'PLAN_CONFIRM', 'TX', 'RX', 'CAUCUS', 'BUFFER', 'MERGE',
  'SPEAK', 'REST', 'PAD', 'OPEN', 'RELAY',
];
const List<String> kPlanModes = ['LTX', 'LTX-LIVE', 'LTX-RELAY', 'LTX-ASYNC'];

/// Fields that exist only in v3 plans (§4.4); MUST NOT appear in v2 (§4.3).
const List<String> kV3OnlyFields = [
  'delays', 'planVersion', 'prevPlanHash', 'questions', 'actions', 'streams',
];
const List<String> _reservedBranchPlanFields = ['branches', 'branching'];
const List<String> _reservedBranchSegmentFields = ['branch'];
const List<String> _reservedStreamSegmentFields = ['stream'];

bool _isInteger(dynamic v) =>
    v is int || (v is double && v.isFinite && v == v.truncateToDouble());

/// Reserved-field violations only (§3.5 streams, §7 branching).
List<PlanValidationError> reservedFieldErrors(dynamic plan) {
  final errors = <PlanValidationError>[];
  if (plan is! Map) return errors;
  if (plan.containsKey('streams') &&
      !(plan['streams'] is List && (plan['streams'] as List).isEmpty)) {
    errors.add(const PlanValidationError('reserved_streams', 'streams',
        'streams[] is reserved (§3.5) and MUST be absent or empty'));
  }
  for (final f in _reservedBranchPlanFields) {
    if (plan.containsKey(f)) {
      errors.add(PlanValidationError('reserved_branching', f,
          '$f is reserved for branching (§7, not yet implemented) and MUST be absent'));
    }
  }
  final segs = plan['segments'];
  if (segs is List) {
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      if (s is! Map) continue;
      for (final f in _reservedStreamSegmentFields) {
        if (s.containsKey(f)) {
          errors.add(PlanValidationError('reserved_streams', 'segments[$i].$f',
              'segment $f is reserved (§3.5) and MUST be absent'));
        }
      }
      for (final f in _reservedBranchSegmentFields) {
        if (s.containsKey(f)) {
          errors.add(PlanValidationError('reserved_branching', 'segments[$i].$f',
              'segment $f is reserved for branching (§7) and MUST be absent'));
        }
      }
    }
  }
  return errors;
}

/// Throw [ReservedFieldException] if [plan] uses reserved stream/branch fields.
void assertNoReservedFields(dynamic plan, String fnName) {
  final errors = reservedFieldErrors(plan);
  if (errors.isEmpty) return;
  throw ReservedFieldException(
      errors[0].code, '$fnName: ${errors[0].message}', errors);
}

/// Validate a v2 or v3 plan (wire form) against spec/ltx-schema.json and the
/// reserved-field rules (§3.5 streams, §7 branching). v1 configs must be
/// upgraded first. Pure; never throws.
///
/// Error codes: not_an_object, invalid_version, missing_field, invalid_field,
/// invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
/// duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
/// invalid_delays, reserved_streams, reserved_branching.
PlanValidation validatePlan(dynamic plan) {
  final errors = <PlanValidationError>[];
  void err(String code, String path, String message) =>
      errors.add(PlanValidationError(code, path, message));
  if (plan is! Map) {
    err('not_an_object', '', 'plan must be an object');
    return PlanValidation(false, errors);
  }
  final v = plan['v'];
  final isV2 = v is num && v == 2;
  final isV3 = v is num && v == 3;
  if (!isV2 && !isV3) err('invalid_version', 'v', 'v must be 2 or 3');
  for (final f in ['title', 'start', 'quantum', 'mode', 'nodes', 'segments']) {
    if (!plan.containsKey(f)) err('missing_field', f, '$f is required');
  }
  if (plan.containsKey('title') && plan['title'] is! String) {
    err('invalid_field', 'title', 'title must be a string');
  }
  if (plan.containsKey('start') &&
      (plan['start'] is! String ||
          DateTime.tryParse(plan['start'] as String) == null)) {
    err('invalid_field', 'start', 'start must be an ISO 8601 UTC timestamp');
  }
  if (plan.containsKey('quantum')) {
    final q = plan['quantum'];
    if (!(_isInteger(q) && q >= 1 && q <= 60)) {
      err('invalid_quantum', 'quantum', 'quantum must be an integer 1..60 minutes (§3.2)');
    }
  }
  if (plan.containsKey('mode') && !kPlanModes.contains(plan['mode'])) {
    err('invalid_mode', 'mode', 'mode must be one of ${kPlanModes.join(', ')}');
  }

  final ids = <String>{};
  if (plan.containsKey('nodes')) {
    final nodes = plan['nodes'];
    if (nodes is! List || nodes.isEmpty) {
      err('invalid_nodes', 'nodes', 'nodes must be a non-empty array');
    } else {
      var hosts = 0;
      for (var i = 0; i < nodes.length; i++) {
        final n = nodes[i];
        if (n is! Map ||
            n['id'] is! String ||
            (n['id'] as String).isEmpty ||
            (n['id'] as String).contains('|') ||
            n['name'] is! String ||
            !['HOST', 'PARTICIPANT', 'OBSERVER'].contains(n['role']) ||
            n['delay'] is! num ||
            !((n['delay'] as num) >= 0)) {
          err('invalid_nodes', 'nodes[$i]',
              'node needs id (no "|"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0');
          continue;
        }
        final id = n['id'] as String;
        if (ids.contains(id)) {
          err('duplicate_node_id', 'nodes[$i].id', 'duplicate node id $id');
        }
        ids.add(id);
        if (n['role'] == 'HOST') hosts++;
      }
      final h = nodes[0];
      if (hosts != 1 || h is! Map || h['role'] != 'HOST' || h['delay'] != 0) {
        err('invalid_host', 'nodes[0]',
            'exactly one HOST, first in nodes[], with delay 0 (§3.1)');
      }
    }
  }

  if (plan.containsKey('segments')) {
    final segs = plan['segments'];
    if (segs is! List) {
      err('invalid_segment', 'segments', 'segments must be an array');
    } else {
      for (var i = 0; i < segs.length; i++) {
        final s = segs[i];
        if (s is! Map ||
            !kPlanSegmentTypes.contains(s['type']) ||
            !(_isInteger(s['q']) && (s['q'] as num) >= 1)) {
          err('invalid_segment', 'segments[$i]',
              'segment needs a known type and integer q >= 1');
          continue;
        }
        if (s.containsKey('speaker') && !ids.contains(s['speaker'])) {
          err('unknown_speaker', 'segments[$i].speaker',
              'speaker ${s['speaker']} is not a node id');
        }
      }
    }
  }

  if (isV2) {
    for (final f in kV3OnlyFields) {
      if (plan.containsKey(f)) {
        err('v3_field_in_v2', f,
            '$f is a v3 field and MUST NOT appear in a v2 plan (§4.3)');
      }
    }
  } else if (isV3) {
    if (plan.containsKey('delays')) {
      final d = plan['delays'];
      if (d is! Map) {
        err('invalid_delays', 'delays', 'delays must be an object');
      } else {
        for (final k in d.keys) {
          final parts = '$k'.split('|');
          final val = d[k];
          if (parts.length != 2 ||
              !(parts[0].compareTo(parts[1]) < 0) ||
              (ids.isNotEmpty &&
                  (!ids.contains(parts[0]) || !ids.contains(parts[1]))) ||
              val is! num ||
              !(val >= 0)) {
            err('invalid_delays', 'delays.$k',
                'key must be two known node ids joined by "|" in sorted order; value >= 0 (§3.7.2)');
          }
        }
      }
    }
    if (plan.containsKey('planVersion') &&
        !(_isInteger(plan['planVersion']) && (plan['planVersion'] as num) >= 1)) {
      err('invalid_field', 'planVersion', 'planVersion must be an integer >= 1');
    }
    if (plan.containsKey('prevPlanHash') &&
        !(plan['prevPlanHash'] is String &&
            RegExp(r'^[0-9a-f]{64}$').hasMatch(plan['prevPlanHash'] as String))) {
      err('invalid_field', 'prevPlanHash',
          'prevPlanHash must be 64 lowercase hex characters');
    }
    for (final f in ['questions', 'actions']) {
      if (plan.containsKey(f) && plan[f] is! List) {
        err('invalid_field', f, '$f must be an array');
      }
    }
  }

  errors.addAll(reservedFieldErrors(plan));
  return PlanValidation(errors.isEmpty, errors);
}

// ── planId over the wire form (golden vectors, spec/golden/plan-ids.json) ──

String _clip(String s, int n) => s.length > n ? s.substring(0, n) : s;

/// makePlanId over a raw plan map as produced by jsonDecode (which preserves
/// key insertion order). Mirrors ltx-sdk.js makePlanId(JSON.parse(json)) for
/// v2 and v3 plans with nodes: the FROZEN v2 hash is imul31 over the compact
/// JSON in insertion order, including any fields the typed LtxPlan model
/// does not carry (relay, key order); the v3 hash is SHA-256 over the
/// RFC 8785 canonical JSON.
String makePlanIdFromMap(Map<String, dynamic> plan) {
  final start = DateTime.parse(plan['start'] as String).toUtc();
  final date = '${start.year.toString().padLeft(4, '0')}'
      '${start.month.toString().padLeft(2, '0')}'
      '${start.day.toString().padLeft(2, '0')}';
  final nodes = (plan['nodes'] as List?) ?? const [];
  String clean(dynamic n) =>
      '${(n as Map)['name']}'.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  final hostStr = nodes.isNotEmpty ? _clip(clean(nodes[0]), 8) : 'HOST';
  final nodeStr = nodes.length > 1
      ? _clip(nodes.skip(1).map((n) => _clip(clean(n), 4)).join('-'), 16)
      : 'RX';
  final v = plan['v'];
  if (v is num && v >= 3) {
    final digest = sha256HexOfString(canonicalJson(plan));
    return 'LTX-$date-$hostStr-$nodeStr-v3-${digest.substring(0, 8)}';
  }
  // FROZEN v2 path (§4.3): imul31 over UTF-16 code units of JSON.stringify.
  var h = 0;
  for (final c in jsonEncode(plan).codeUnits) {
    h = ((h * 31) + c) & 0xFFFFFFFF;
  }
  return 'LTX-$date-$hostStr-$nodeStr-v2-${h.toRadixString(16).padLeft(8, '0')}';
}
