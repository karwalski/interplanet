// security.dart -- Epic 29 (Stories 29.1, 29.4, 29.5)
// Dart port of ltx-sdk.js security functions.

import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;

// ---- Models ----

class Nik {
  final String nodeId;
  final String publicKeyB64;
  final String validFrom;
  final String validUntil;
  final String keyType;
  final String nodeLabel;

  const Nik({
    required this.nodeId,
    required this.publicKeyB64,
    required this.validFrom,
    required this.validUntil,
    this.keyType = 'ltx-nik-v1',
    this.nodeLabel = '',
  });

  Nik copyWith({String? validUntil, String? validFrom}) => Nik(
    nodeId: nodeId,
    publicKeyB64: publicKeyB64,
    validFrom: validFrom ?? this.validFrom,
    validUntil: validUntil ?? this.validUntil,
    keyType: keyType,
    nodeLabel: nodeLabel,
  );
}

class NikResult {
  final Nik nik;
  final String privateKeyB64;
  const NikResult({required this.nik, required this.privateKeyB64});
}

class SignedPlan {
  final Map<String, dynamic> plan;
  final String payloadB64;
  final String sig;
  final String signerNodeId;
  const SignedPlan({
    required this.plan,
    required this.payloadB64,
    required this.sig,
    required this.signerNodeId,
  });
}

class VerifyResult {
  final bool valid;
  final String? reason;
  const VerifyResult({required this.valid, this.reason});
}

class CheckSeqResult {
  final bool accepted;
  final String? reason;
  final bool gap;
  final int gapSize;
  const CheckSeqResult({
    required this.accepted,
    this.reason,
    this.gap = false,
    this.gapSize = 0,
  });
}

// ---- Helpers ----

String _toBase64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

List<int> _fromBase64Url(String s) {
  String padded = s;
  final rem = s.length % 4;
  if (rem == 2) padded += '==';
  else if (rem == 3) padded += '=';
  return base64Url.decode(padded);
}

List<int> _sha256(List<int> data) => crypto.sha256.convert(data).bytes;

String _nodeIdFromPub(List<int> rawPub) {
  final hash = _sha256(rawPub);
  return hash
      .sublist(0, 8)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

// ---- CanonicalJSON ----

String canonicalJsonMap(Map<String, dynamic> obj) {
  final keys = obj.keys.toList()..sort();
  final parts = keys
      .map((k) => json.encode(k) + ':' + _serializeValue(obj[k]))
      .toList();
  return '{' + parts.join(',') + '}';
}

String _serializeValue(dynamic v) {
  if (v == null) return 'null';
  if (v is bool) return v ? 'true' : 'false';
  if (v is String) return json.encode(v);
  if (v is int) return v.toString();
  if (v is double) return v.toString();
  if (v is num) return v.toString();
  if (v is Map) return canonicalJsonMap(v.cast<String, dynamic>());
  if (v is List) {
    return '[' + v.map(_serializeValue).toList().join(',') + ']';
  }
  return json.encode(v.toString());
}

// ---- GenerateNIK ----

Future<NikResult> generateNik({int validDays = 365, String nodeLabel = ''}) async {
  final algo = Ed25519();
  final keyPair = await algo.newKeyPair();
  final pub = await keyPair.extractPublicKey();
  final rawPub = pub.bytes;
  final seed = await keyPair.extractPrivateKeyBytes();
  final nodeId = _nodeIdFromPub(rawPub);
  final now = DateTime.now().toUtc();
  final until = now.add(Duration(days: validDays));
  final nik = Nik(
    nodeId: nodeId,
    publicKeyB64: _toBase64Url(rawPub),
    validFrom: _isoZ(now),
    validUntil: _isoZ(until),
    keyType: 'ltx-nik-v1',
    nodeLabel: nodeLabel,
  );
  return NikResult(nik: nik, privateKeyB64: _toBase64Url(seed));
}

String _isoZ(DateTime dt) {
  final s = dt.toIso8601String();
  // Remove sub-second part: "2024-01-15T14:00:00.000000Z" -> "2024-01-15T14:00:00Z"
  final base = s.replaceFirst(RegExp(r'\.\d+'), '');
  if (base.endsWith('Z')) return base;
  return base + 'Z';
}

// ---- IsNIKExpired ----

bool isNikExpired(Nik nik) =>
    DateTime.now().toUtc().isAfter(DateTime.parse(nik.validUntil).toUtc());

// ---- SignPlan ----

Future<SignedPlan> signPlan(Map<String, dynamic> plan, String privKeyB64) async {
  final seed = _fromBase64Url(privKeyB64);
  final algo = Ed25519();
  final keyPair = await algo.newKeyPairFromSeed(seed);
  final pub = await keyPair.extractPublicKey();
  final rawPub = pub.bytes;
  final payStr = canonicalJsonMap(plan);
  final payBytes = utf8.encode(payStr);
  final sig = await algo.sign(payBytes, keyPair: keyPair);
  final nodeId = _nodeIdFromPub(rawPub);
  return SignedPlan(
    plan: plan,
    payloadB64: _toBase64Url(payBytes),
    sig: _toBase64Url(sig.bytes),
    signerNodeId: nodeId,
  );
}

// ---- VerifyPlan ----

Future<VerifyResult> verifyPlan(
    SignedPlan sp, Map<String, Nik> keyCache) async {
  final signer = keyCache[sp.signerNodeId];
  if (signer == null) {
    return const VerifyResult(valid: false, reason: 'key_not_in_cache');
  }
  if (isNikExpired(signer)) {
    return const VerifyResult(valid: false, reason: 'key_expired');
  }
  final expectedBytes = utf8.encode(canonicalJsonMap(sp.plan));
  final actualBytes = _fromBase64Url(sp.payloadB64);
  if (!_bytesEqual(expectedBytes, actualBytes)) {
    return const VerifyResult(valid: false, reason: 'payload_mismatch');
  }
  final rawPub = _fromBase64Url(signer.publicKeyB64);
  final algo = Ed25519();
  final pub = SimplePublicKey(rawPub, type: KeyPairType.ed25519);
  final sigBytes = _fromBase64Url(sp.sig);
  final sig = Signature(sigBytes, publicKey: pub);
  final ok = await algo.verify(actualBytes, signature: sig);
  return ok
      ? const VerifyResult(valid: true)
      : const VerifyResult(valid: false, reason: 'signature_invalid');
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---- SequenceTracker ----

class SequenceTracker {
  final Map<String, int> _rx = {};
  final Map<String, int> _tx = {};

  Map<String, dynamic> addSeq(Map<String, dynamic> bundle, String nodeId) {
    final cur = _tx[nodeId] ?? 0;
    final next = cur + 1;
    _tx[nodeId] = next;
    return {...bundle, 'seq': next};
  }

  CheckSeqResult checkSeq(Map<String, dynamic> bundle, String nodeId) {
    final seqVal = bundle['seq'];
    if (seqVal is! int) {
      return const CheckSeqResult(accepted: false, reason: 'missing_seq');
    }
    final seq = seqVal;
    final last = _rx[nodeId] ?? 0;
    if (seq <= last) {
      return const CheckSeqResult(accepted: false, reason: 'replay');
    }
    final gapBool = seq > last + 1;
    final gapSize = gapBool ? seq - last - 1 : 0;
    _rx[nodeId] = seq;
    return CheckSeqResult(accepted: true, gap: gapBool, gapSize: gapSize);
  }
}
