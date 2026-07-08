// registers.dart — Question and Action registers (LTX v1.1, Epic 72 cascade)
// LTX-SPECIFICATION.md §9/§10, LTX-SECURITY.md §9.5/§9.6
//
// Registers are not mutable state: they are deterministic reductions over the
// signed, append-only audit log. Every entry is individually signed by its
// originating node; entries are ordered by (timestamp, nodeId, seq) — a total
// order since (nodeId, seq) is unique — and object-level conflicts resolve by
// highest object version, then lexicographically lowest editor nodeId (§8.2).
//
// Entry envelope (LTX-SECURITY.md §9.5):
//   { entryId, sessionId, nodeId, seq, type, content, timestamp, sig }
// sig = Ed25519 over the canonical JSON of the entry without 'sig'.

import 'dart:convert';

import 'security.dart';

const Map<String, String> _entryPrefix = {
  'question': 'QST',
  'question_response': 'QST',
  'action': 'ACT',
  'action_update': 'ACT',
  'amendment': 'AMD',
  'state_transition': 'STA',
  'merge_snapshot': 'MRG',
  'decision': 'DEC',
};

/// Create a signed register entry (LTX-SECURITY.md §9.5).
Future<Map<String, dynamic>> createRegisterEntry(
  String type,
  Map<String, dynamic> content, {
  required String sessionId,
  required String nodeId,
  required int seq,
  required String timestamp,
  required String privateKeyB64,
  String? entryId,
}) async {
  final id = entryId ?? '${_entryPrefix[type] ?? 'ENT'}-$nodeId-$seq';
  final unsigned = <String, dynamic>{
    'entryId': id,
    'sessionId': sessionId,
    'nodeId': nodeId,
    'seq': seq,
    'type': type,
    'content': content,
    'timestamp': timestamp,
  };
  final sig = await signBytesEd25519(
      utf8.encode(canonicalJson(unsigned)), privateKeyB64);
  return {...unsigned, 'sig': sig};
}

/// Verify a register entry signature against a keyCache mapping the entry's
/// nodeId to its NIK.
Future<VerifyResult> verifyRegisterEntry(
    Map<String, dynamic> entry, Map<String, Nik> keyCache) async {
  final sig = entry['sig'];
  if (sig is! String || sig.isEmpty) {
    return const VerifyResult(valid: false, reason: 'missing_sig');
  }
  final nik = keyCache[entry['nodeId']];
  if (nik == null) {
    return const VerifyResult(valid: false, reason: 'key_not_in_cache');
  }
  final unsigned = Map<String, dynamic>.of(entry)..remove('sig');
  final ok = await verifyBytesEd25519(
      utf8.encode(canonicalJson(unsigned)), sig, nik);
  return ok
      ? const VerifyResult(valid: true)
      : const VerifyResult(valid: false, reason: 'signature_invalid');
}

// ── Deterministic ordering (LTX-SPECIFICATION.md §8.2) ─────────────────────

/// Total order: (timestamp, nodeId, seq).
int compareEntries(Map<String, dynamic> a, Map<String, dynamic> b) {
  final ta = a['timestamp'] as String, tb = b['timestamp'] as String;
  if (ta != tb) return ta.compareTo(tb);
  final na = a['nodeId'] as String, nb = b['nodeId'] as String;
  if (na != nb) return na.compareTo(nb);
  return (a['seq'] as int) - (b['seq'] as int);
}

/// De-duplicate by (nodeId, seq) and sort into the §8.2 total order.
List<Map<String, dynamic>> orderEntries(List<Map<String, dynamic>> entries) {
  final seen = <String, Map<String, dynamic>>{};
  for (final e in entries) {
    final key = '${e['nodeId']} ${e['seq']}';
    seen.putIfAbsent(key, () => e);
  }
  return seen.values.toList()..sort(compareEntries);
}

// ── Reducers ────────────────────────────────────────────────────────────────

/// Reduction result: byId (object state maps) and superseded entryIds
/// (entries that lost a §8.2 conflict — flagged, never dropped).
class RegisterReduction {
  final Map<String, Map<String, dynamic>> byId;
  final List<String> superseded;
  const RegisterReduction({required this.byId, required this.superseded});
}

/// §8.2 conflict rule: higher version wins; tie → lowest editor nodeId.
bool _wins(int inVersion, String inEditor, int curVersion, String curEditor) {
  if (inVersion != curVersion) return inVersion > curVersion;
  return inEditor.compareTo(curEditor) < 0;
}

/// Reduce question register state from log entries (§9.4).
/// Pure: identical entry sets (in any input order) produce identical state.
RegisterReduction reduceQuestions(List<Map<String, dynamic>> entries) {
  final byId = <String, Map<String, dynamic>>{};
  final winners = <String, List<dynamic>>{}; // qid → [version, editor, entryId]
  final superseded = <String>[];

  for (final e in orderEntries(entries)) {
    final content = (e['content'] as Map).cast<String, dynamic>();
    if (e['type'] == 'question') {
      final qid = e['entryId'] as String;
      if (byId.containsKey(qid)) {
        superseded.add(qid);
        continue;
      }
      winners[qid] = [1, e['nodeId'], e['entryId']];
      byId[qid] = {
        'qid': qid,
        'text': '${content['text'] ?? ''}',
        'submitter': e['nodeId'],
        if (content['urgency'] != null) 'urgency': '${content['urgency']}',
        if (content['intendedWindow'] != null)
          'intendedWindow': '${content['intendedWindow']}',
        'status': 'OPEN',
        'version': 1,
      };
    } else if (e['type'] == 'question_response') {
      final qid = '${content['qid'] ?? ''}';
      final q = byId[qid];
      if (q == null) {
        superseded.add(e['entryId'] as String);
        continue;
      }
      final version =
          (content['version'] as int?) ?? (q['version'] as int) + 1;
      final current = winners[qid];
      if (current != null &&
          !_wins(version, e['nodeId'] as String, current[0] as int,
              current[1] as String)) {
        superseded.add(e['entryId'] as String);
        continue;
      }
      if (current != null && current[2] != q['qid']) {
        superseded.add(current[2] as String);
      }
      winners[qid] = [version, e['nodeId'], e['entryId']];
      final status =
          content['status'] == 'WITHDRAWN' ? 'WITHDRAWN' : 'ANSWERED';
      byId[qid] = {
        ...q,
        'status': status,
        if (content['response'] != null) 'response': '${content['response']}',
        'responder': e['nodeId'],
        'version': version,
      };
    }
  }
  return RegisterReduction(byId: byId, superseded: superseded);
}

const List<String> _actionStatuses = ['PROPOSED', 'ACCEPTED', 'REJECTED', 'DONE'];

/// Reduce action register state from log entries (§10.2).
RegisterReduction reduceActions(List<Map<String, dynamic>> entries) {
  final byId = <String, Map<String, dynamic>>{};
  final winners = <String, List<dynamic>>{};
  final superseded = <String>[];

  for (final e in orderEntries(entries)) {
    final content = (e['content'] as Map).cast<String, dynamic>();
    if (e['type'] == 'action') {
      final aid = e['entryId'] as String;
      if (byId.containsKey(aid)) {
        superseded.add(aid);
        continue;
      }
      winners[aid] = [1, e['nodeId'], e['entryId']];
      byId[aid] = {
        'aid': aid,
        'description': '${content['description'] ?? ''}',
        if (content['owner'] != null) 'owner': '${content['owner']}',
        if (content['dueTimeUTC'] != null)
          'dueTimeUTC': '${content['dueTimeUTC']}',
        if (content['originWindow'] != null)
          'originWindow': '${content['originWindow']}',
        'status': 'PROPOSED',
        'version': 1,
      };
    } else if (e['type'] == 'action_update') {
      final aid = '${content['aid'] ?? ''}';
      final a = byId[aid];
      if (a == null) {
        superseded.add(e['entryId'] as String);
        continue;
      }
      final version =
          (content['version'] as int?) ?? (a['version'] as int) + 1;
      final current = winners[aid];
      if (current != null &&
          !_wins(version, e['nodeId'] as String, current[0] as int,
              current[1] as String)) {
        superseded.add(e['entryId'] as String);
        continue;
      }
      if (current != null && current[2] != a['aid']) {
        superseded.add(current[2] as String);
      }
      winners[aid] = [version, e['nodeId'], e['entryId']];
      final status = _actionStatuses.contains(content['status'])
          ? content['status'] as String
          : a['status'] as String;
      byId[aid] = {
        ...a,
        'status': status,
        if (content['description'] != null)
          'description': '${content['description']}',
        if (content['owner'] != null) 'owner': '${content['owner']}',
        if (content['dueTimeUTC'] != null)
          'dueTimeUTC': '${content['dueTimeUTC']}',
        'version': version,
      };
    }
  }
  return RegisterReduction(byId: byId, superseded: superseded);
}

// ── Merkle audit-log root (RFC 9162 style) ─────────────────────────────────
// Leaf hash: SHA-256(0x00 || canonicalJSON(entry)); node hash:
// SHA-256(0x01 || left || right); empty root: 32 zero bytes.

List<int> _leafHash(Map<String, dynamic> entry) =>
    sha256Bytes([0x00, ...utf8.encode(canonicalJson(entry))]);

List<int> _nodeHash(List<int> left, List<int> right) =>
    sha256Bytes([0x01, ...left, ...right]);

List<int> _rootOf(List<List<int>> leaves) {
  if (leaves.isEmpty) return List.filled(32, 0);
  if (leaves.length == 1) return leaves[0];
  // Split at the largest power of two strictly less than the leaf count.
  int mid = 1;
  while (mid * 2 < leaves.length) {
    mid *= 2;
  }
  return _nodeHash(_rootOf(leaves.sublist(0, mid)), _rootOf(leaves.sublist(mid)));
}

/// Merkle log root (hex) over the §8.2-ordered entries.
String entriesRoot(List<Map<String, dynamic>> entries) {
  final leaves = orderEntries(entries).map(_leafHash).toList();
  return _rootOf(leaves)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Re-emit v3 plan question seeds (§9.2) as signed log entries at plan lock.
Future<List<Map<String, dynamic>>> emitQuestionSeeds(
  List<Map<String, dynamic>> seeds, {
  required String sessionId,
  required String nodeId,
  required String timestamp,
  required String privateKeyB64,
  int startSeq = 1,
}) async {
  final out = <Map<String, dynamic>>[];
  var seq = startSeq;
  for (final seed in seeds) {
    out.add(await createRegisterEntry('question', seed,
        sessionId: sessionId,
        nodeId: nodeId,
        seq: seq,
        timestamp: timestamp,
        privateKeyB64: privateKeyB64));
    seq += 1;
  }
  return out;
}
