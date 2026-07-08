// amend.dart — Plan amendment chains (LTX v1.1, Epic 72 cascade)
// LTX-SPECIFICATION.md §6.4, LTX-SECURITY.md §7.6
//
// An amendment replaces a locked plan with a re-signed successor:
// planVersion + 1 and prevPlanHash = SHA-256(canonicalJSON(predecessor)).
// The canonical-JSON hash is order-insensitive and collision-resistant —
// never the legacy v2 polynomial planId hash.
//
// Chain links carry the TRANSITIONAL JSON COSE_Sign1 envelope
// { plan, coseSign1: { protected, unprotected: { kid }, payload, signature } }
// with Sig_structure = canonicalJSON(["Signature1", protected, "", payload]).

import 'dart:convert';

import 'security.dart';

/// SHA-256 hex of the RFC 8785 canonical JSON of a plan.
String planHash(Map<String, dynamic> plan) =>
    sha256HexOfString(canonicalJson(plan));

/// Sign a plan into the TRANSITIONAL JSON COSE_Sign1 envelope (the format
/// used by amendment chains). kid = base64url of the first 16 bytes of
/// SHA-256(raw public key) — the cross-port COSE key id.
Future<Map<String, dynamic>> signPlanEnvelope(
    Map<String, dynamic> plan, String privKeyB64) async {
  final protectedB64 = b64UrlEncode(utf8.encode(canonicalJson({'alg': -19})));
  final payloadB64 = b64UrlEncode(utf8.encode(canonicalJson(plan)));
  final sigStructure =
      canonicalJson(['Signature1', protectedB64, '', payloadB64]);
  final sig = await signBytesEd25519(utf8.encode(sigStructure), privKeyB64);
  return _envelope(
      plan, protectedB64, payloadB64, sig, await _kidFromSeed(privKeyB64));
}

Map<String, dynamic> _envelope(Map<String, dynamic> plan, String protectedB64,
        String payloadB64, String sig, String kid) =>
    {
      'plan': plan,
      'coseSign1': {
        'protected': protectedB64,
        'unprotected': {'kid': kid},
        'payload': payloadB64,
        'signature': sig,
      },
    };

Future<String> _kidFromSeed(String privKeyB64) async {
  final pub = await publicKeyFromSeed(privKeyB64);
  return b64UrlEncode(sha256Bytes(pub).sublist(0, 16));
}

/// Verify a TRANSITIONAL JSON COSE_Sign1 plan envelope (the amendment-chain
/// link format) against a keyCache of kid → NIK.
Future<VerifyResult> verifyPlanEnvelope(
    Map<String, dynamic> envelope, Map<String, Nik> keyCache) async {
  final cose = envelope['coseSign1'];
  if (cose is! Map) {
    return const VerifyResult(valid: false, reason: 'missing_cose_sign1');
  }
  final kid = (cose['unprotected'] is Map)
      ? (cose['unprotected'] as Map)['kid'] as String?
      : null;
  if (kid == null || kid.isEmpty) {
    return const VerifyResult(valid: false, reason: 'missing_kid');
  }
  final signerNik = lookupNik(kid, keyCache);
  if (signerNik == null) {
    return const VerifyResult(valid: false, reason: 'key_not_in_cache');
  }
  if (isNikExpired(signerNik)) {
    return const VerifyResult(valid: false, reason: 'key_expired');
  }
  final sigStructure = canonicalJson(
      ['Signature1', cose['protected'], '', cose['payload']]);
  final ok = await verifyBytesEd25519(
      utf8.encode(sigStructure), cose['signature'] as String, signerNik);
  if (!ok) {
    return const VerifyResult(valid: false, reason: 'signature_invalid');
  }
  final payloadStr = utf8.decode(b64UrlDecode(cose['payload'] as String));
  if (payloadStr != canonicalJson(envelope['plan'])) {
    return const VerifyResult(valid: false, reason: 'payload_mismatch');
  }
  return const VerifyResult(valid: true);
}

/// Create a signed amendment of [signedPlan] (a JSON-envelope signed plan)
/// with [changes] applied. The successor is always a v3 plan; fields managed
/// here ('v', 'planVersion', 'prevPlanHash') cannot be overridden.
Future<Map<String, dynamic>> createAmendment(Map<String, dynamic> signedPlan,
    Map<String, dynamic> changes, String privKeyB64) async {
  final prev = (signedPlan['plan'] as Map).cast<String, dynamic>();
  final prevVersion = (prev['planVersion'] as int?) ?? 1;
  final successor = <String, dynamic>{
    ...prev,
    ...changes,
    'v': 3,
    'planVersion': prevVersion + 1,
    'prevPlanHash': planHash(prev),
  };
  final protectedB64 = b64UrlEncode(utf8.encode(canonicalJson({'alg': -19})));
  final payloadB64 = b64UrlEncode(utf8.encode(canonicalJson(successor)));
  final sigStructure =
      canonicalJson(['Signature1', protectedB64, '', payloadB64]);
  final sig = await signBytesEd25519(utf8.encode(sigStructure), privKeyB64);
  return _envelope(
      successor, protectedB64, payloadB64, sig, await _kidFromSeed(privKeyB64));
}

/// Verify an amendment chain: chain[0] is the root plan, each later element
/// a successive amendment. Checks, per link: HOST signature against
/// [keyCache], planVersion increment of exactly 1, and prevPlanHash equality
/// with the recomputed predecessor hash (LTX-SECURITY.md §7.6).
Future<VerifyResult> verifyAmendmentChain(
    List<Map<String, dynamic>> chain, Map<String, Nik> keyCache) async {
  if (chain.isEmpty) {
    return const VerifyResult(valid: false, reason: 'empty_chain');
  }
  for (int i = 0; i < chain.length; i++) {
    final sig = await verifyPlanEnvelope(chain[i], keyCache);
    if (!sig.valid) {
      return VerifyResult(valid: false, reason: 'link_${i}_${sig.reason}');
    }
  }
  final root = (chain[0]['plan'] as Map).cast<String, dynamic>();
  if (root.containsKey('prevPlanHash')) {
    return const VerifyResult(valid: false, reason: 'root_has_prev_hash');
  }
  var prevPlan = root;
  var prevVersion = (root['planVersion'] as int?) ?? 1;
  for (int i = 1; i < chain.length; i++) {
    final p = (chain[i]['plan'] as Map).cast<String, dynamic>();
    if (p['v'] != 3) {
      return VerifyResult(valid: false, reason: 'link_${i}_not_v3');
    }
    if (((p['planVersion'] as int?) ?? 0) != prevVersion + 1) {
      return VerifyResult(valid: false, reason: 'link_${i}_version_gap');
    }
    if (p['prevPlanHash'] != planHash(prevPlan)) {
      return VerifyResult(valid: false, reason: 'link_${i}_prev_hash_mismatch');
    }
    prevPlan = p;
    prevVersion = p['planVersion'] as int;
  }
  return const VerifyResult(valid: true);
}
