// cose.dart — COSE_Sign1 (RFC 9052) plan signing/verification
// LTX v1.1 (Epic 72 cascade) — real CBOR COSE_Sign1 alongside the
// TRANSITIONAL JSON envelope (LTX-SECURITY.md §7.2/§7.5).
//
// Algorithm: Ed25519, COSE algorithm ID -19 (RFC 9864; the polymorphic EdDSA
// id -8 is deprecated and rejected). Payload: RFC 8785 canonical JSON bytes
// of the plan. Structure: COSE_Sign1 = tag 18 of
//   [ protected: bstr .cbor { 1: -19 },
//     unprotected: { 4: kid-bytes },
//     payload: bstr,
//     signature: bstr ]
// Sig_structure = ["Signature1", protected, external_aad = h'', payload].

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'cbor.dart';
import 'security.dart';

const int kCoseSign1Tag = 18;
const int kCoseAlgEd25519 = -19;

/// Sign a plan as a real CBOR COSE_Sign1 (tag 18). The kid (header label 4)
/// is the raw 16-byte NIK nodeId — first 16 bytes of SHA-256(raw public key).
/// Returns {'plan': plan, 'coseSign1CborB64': <base64url>}.
Future<Map<String, dynamic>> signPlanCose(
    Map<String, dynamic> plan, String privKeyB64) async {
  final algo = Ed25519();
  final keyPair = await algo.newKeyPairFromSeed(b64UrlDecode(privKeyB64));
  final pub = await keyPair.extractPublicKey();

  final protectedBytes = encodeCbor({1: kCoseAlgEd25519});
  final payload = Uint8List.fromList(utf8.encode(canonicalJson(plan)));
  final sigStructure = encodeCbor(
      ['Signature1', protectedBytes, Uint8List(0), payload]);
  final sig = await algo.sign(sigStructure, keyPair: keyPair);

  final kid = Uint8List.fromList(sha256Bytes(pub.bytes).sublist(0, 16));
  final coseSign1 = CborTag(kCoseSign1Tag, [
    protectedBytes,
    {4: kid},
    payload,
    Uint8List.fromList(sig.bytes),
  ]);
  return {
    'plan': plan,
    'coseSign1CborB64': b64UrlEncode(encodeCbor(coseSign1)),
  };
}

/// Verify a CBOR COSE_Sign1 plan envelope against the key cache.
/// Rejects non-Ed25519 algorithms (including the deprecated -8) and payloads
/// that do not match the accompanying plan object.
Future<VerifyResult> verifyPlanCose(
    Map<String, dynamic> envelope, Map<String, Nik> keyCache) async {
  final b64 = envelope['coseSign1CborB64'];
  if (b64 is! String) {
    return const VerifyResult(valid: false, reason: 'missing_cose_sign1');
  }

  dynamic decoded;
  try {
    decoded = decodeCbor(Uint8List.fromList(b64UrlDecode(b64)));
  } catch (_) {
    return const VerifyResult(valid: false, reason: 'cbor_decode_failed');
  }
  if (decoded is! CborTag || decoded.tag != kCoseSign1Tag) {
    return const VerifyResult(valid: false, reason: 'not_cose_sign1');
  }
  final arr = decoded.value;
  if (arr is! List || arr.length != 4) {
    return const VerifyResult(valid: false, reason: 'malformed_cose_sign1');
  }
  final protectedBytes = arr[0];
  final unprotected = arr[1];
  final payload = arr[2];
  final signature = arr[3];
  if (protectedBytes is! Uint8List ||
      payload is! Uint8List ||
      signature is! Uint8List) {
    return const VerifyResult(valid: false, reason: 'malformed_cose_sign1');
  }

  dynamic protectedMap;
  try {
    protectedMap = decodeCbor(protectedBytes);
  } catch (_) {
    return const VerifyResult(valid: false, reason: 'protected_decode_failed');
  }
  if (protectedMap is! Map || protectedMap[1] != kCoseAlgEd25519) {
    return const VerifyResult(valid: false, reason: 'unsupported_alg');
  }

  // The decoder converts bstr map keys/values: kid arrives as Uint8List.
  dynamic kidRaw = unprotected is Map ? unprotected[4] : null;
  final kid = kidRaw is Uint8List
      ? b64UrlEncode(kidRaw)
      : kidRaw is String
          ? kidRaw
          : '';
  if (kid.isEmpty) {
    return const VerifyResult(valid: false, reason: 'missing_kid');
  }

  final signerNik = lookupNik(kid, keyCache);
  if (signerNik == null) {
    return const VerifyResult(valid: false, reason: 'key_not_in_cache');
  }
  if (isNikExpired(signerNik)) {
    return const VerifyResult(valid: false, reason: 'key_expired');
  }

  final sigStructure =
      encodeCbor(['Signature1', protectedBytes, Uint8List(0), payload]);
  final ok = await verifyBytesEd25519(
      sigStructure, b64UrlEncode(signature), signerNik);
  if (!ok) {
    return const VerifyResult(valid: false, reason: 'signature_invalid');
  }

  if (envelope['plan'] != null &&
      utf8.decode(payload) != canonicalJson(envelope['plan'])) {
    return const VerifyResult(valid: false, reason: 'payload_mismatch');
  }
  return const VerifyResult(valid: true);
}
