// InterplanetLTXTests — standalone test runner (no XCTest needed)
// Run with: swift run InterplanetLTXTests
import Foundation
import InterplanetLTX

var passed = 0
var failed = 0

func check(_ name: String, _ cond: Bool) {
    if cond {
        passed += 1
    } else {
        failed += 1
        print("FAIL: \(name)")
    }
}

// ── Constants (9) ──────────────────────────────────────────────────────────

check("version is 1.1.0", InterplanetLTX.version == "1.1.0")
check("defaultQuantum is 5", InterplanetLTX.defaultQuantum == 5)
check("defaultAPIBase correct", InterplanetLTX.defaultAPIBase == "https://interplanet.live/api/ltx.php")
check("defaultSegments count is 7", InterplanetLTX.defaultSegments.count == 7)
check("defaultSegments[0] type PLAN_CONFIRM", InterplanetLTX.defaultSegments[0].type == "PLAN_CONFIRM")
check("defaultSegments[0] q==2", InterplanetLTX.defaultSegments[0].q == 2)
check("defaultSegments[3] type CAUCUS", InterplanetLTX.defaultSegments[3].type == "CAUCUS")
check("defaultSegments[6] type BUFFER", InterplanetLTX.defaultSegments[6].type == "BUFFER")
check("defaultSegments[6] q==1", InterplanetLTX.defaultSegments[6].q == 1)

// ── createPlan (16) ────────────────────────────────────────────────────────

let plan = InterplanetLTX.createPlan(start: "2026-03-15T14:00:00Z")
check("createPlan v==2", plan.v == 2)
check("createPlan title default", plan.title == "LTX Session")
check("createPlan start preserved", plan.start == "2026-03-15T14:00:00Z")
check("createPlan quantum==5", plan.quantum == 5)
check("createPlan mode==LTX", plan.mode == "LTX")
check("createPlan nodes count==2", plan.nodes.count == 2)
check("createPlan nodes[0].id==N0", plan.nodes[0].id == "N0")
check("createPlan nodes[0].role==HOST", plan.nodes[0].role == "HOST")
check("createPlan nodes[0].location==earth", plan.nodes[0].location == "earth")
check("createPlan nodes[0].delay==0", plan.nodes[0].delay == 0)
check("createPlan nodes[1].id==N1", plan.nodes[1].id == "N1")
check("createPlan nodes[1].role==PARTICIPANT", plan.nodes[1].role == "PARTICIPANT")
check("createPlan nodes[1].location==mars", plan.nodes[1].location == "mars")
check("createPlan segments count==7", plan.segments.count == 7)
let planCustom = InterplanetLTX.createPlan(title: "My Session", start: "2026-04-01T10:00:00Z", delayS: 860)
check("createPlan custom title", planCustom.title == "My Session")
check("createPlan custom delayS", planCustom.nodes[1].delay == 860)

// ── upgradeConfig (7) ──────────────────────────────────────────────────────

let cfg1: [String: Any] = [
    "title": "Config Test",
    "start": "2026-05-01T09:00:00Z",
    "quantum": 5,
    "mode": "LTX",
    "nodes": [
        ["id": "N0", "name": "Base Alpha", "role": "HOST",        "delay": 0,    "location": "earth"] as [String: Any],
        ["id": "N1", "name": "Rover Beta",  "role": "PARTICIPANT","delay": 1200, "location": "mars"]  as [String: Any],
    ] as [[String: Any]],
    "segments": [
        ["type": "TX", "q": 3] as [String: Any],
        ["type": "RX", "q": 3] as [String: Any],
    ] as [[String: Any]],
]
let upgraded = InterplanetLTX.upgradeConfig(cfg1)
check("upgradeConfig title", upgraded.title == "Config Test")
check("upgradeConfig start", upgraded.start == "2026-05-01T09:00:00Z")
check("upgradeConfig quantum", upgraded.quantum == 5)
check("upgradeConfig nodes count", upgraded.nodes.count == 2)
check("upgradeConfig nodes[0].name", upgraded.nodes[0].name == "Base Alpha")
check("upgradeConfig nodes[1].delay", upgraded.nodes[1].delay == 1200)
check("upgradeConfig segments count", upgraded.segments.count == 2)

// ── computeSegments (11) ───────────────────────────────────────────────────

let segs = (try? InterplanetLTX.computeSegments(plan)) ?? []
check("computeSegments count==7", segs.count == 7)
check("computeSegments[0] type", segs[0].type == "PLAN_CONFIRM")
check("computeSegments[0] q==2", segs[0].q == 2)
check("computeSegments[0] durMin==10", segs[0].durMin == 10)
check("computeSegments[0] startMs>0", segs[0].startMs > 0)
let startMs0 = segs[0].startMs
let expectedEnd0 = startMs0 + 2 * 5 * 60 * 1000
check("computeSegments[0] endMs correct", segs[0].endMs == expectedEnd0)
check("computeSegments[1] startMs==segs[0].endMs", segs[1].startMs == segs[0].endMs)
check("computeSegments[6] type BUFFER", segs[6].type == "BUFFER")
check("computeSegments[6] q==1", segs[6].q == 1)
check("computeSegments[6] durMin==5", segs[6].durMin == 5)
check("computeSegments sequential", segs[2].startMs == segs[1].endMs)
// quantum guard
var badPlan = InterplanetLTX.createPlan(start: "2026-03-15T14:00:00Z")
badPlan.quantum = 0
let badResult = try? InterplanetLTX.computeSegments(badPlan)
check("computeSegments quantum=0 throws", badResult == nil)
var badPlan2 = InterplanetLTX.createPlan(start: "2026-03-15T14:00:00Z")
badPlan2.quantum = -1
let badResult2 = try? InterplanetLTX.computeSegments(badPlan2)
check("computeSegments quantum=-1 throws", badResult2 == nil)

// ── totalMin (2) ───────────────────────────────────────────────────────────

let total = InterplanetLTX.totalMin(plan)
check("totalMin default plan==65", total == 65)
let plan2 = LtxPlan(segments: [LtxSegmentTemplate(type: "TX", q: 4)])
check("totalMin single segment", InterplanetLTX.totalMin(plan2) == 20) // 4*5

// ── makePlanID (6) ─────────────────────────────────────────────────────────

let pid = InterplanetLTX.makePlanID(plan)
check("makePlanID starts LTX-", pid.hasPrefix("LTX-"))
check("makePlanID has date 20260315", pid.contains("20260315"))
check("makePlanID has EARTHHQ", pid.contains("EARTHHQ"))
check("makePlanID has MARS", pid.contains("MARS"))
check("makePlanID has -v2-", pid.contains("-v2-"))
let pidParts = pid.components(separatedBy: "-")
let hashPart = pidParts.last ?? ""
check("makePlanID hash 8 hex chars", hashPart.count == 8 && hashPart.allSatisfy { $0.isHexDigit })

// ── encodeHash / decodeHash (12) ───────────────────────────────────────────

let hash = InterplanetLTX.encodeHash(plan)
check("encodeHash starts #l=", hash.hasPrefix("#l="))
// The "#l=" prefix contains "=" but the base64url payload must not have padding "="
let hashPayload = hash.hasPrefix("#l=") ? String(hash.dropFirst(3)) : hash
check("encodeHash no padding =", !hashPayload.contains("="))
check("encodeHash no + chars", !hash.contains("+"))
check("encodeHash no / chars", !hash.contains("/"))

let decoded = InterplanetLTX.decodeHash(hash)
check("decodeHash not nil", decoded != nil)
check("decodeHash v==2", decoded?.v == 2)
check("decodeHash title", decoded?.title == plan.title)
check("decodeHash start", decoded?.start == plan.start)
check("decodeHash quantum", decoded?.quantum == plan.quantum)
check("decodeHash nodes count", decoded?.nodes.count == plan.nodes.count)
check("decodeHash segments count", decoded?.segments.count == plan.segments.count)

// decode with "l=" prefix (drop the leading "#")
let tokenOnly = String(hash.dropFirst())
let decoded2 = InterplanetLTX.decodeHash(tokenOnly)
check("decodeHash l= prefix works", decoded2?.title == plan.title)

// ── buildNodeURLs (8) ──────────────────────────────────────────────────────

let urls = InterplanetLTX.buildNodeURLs(plan, baseURL: "https://interplanet.live/ltx.html")
check("buildNodeURLs count==2", urls.count == 2)
check("buildNodeURLs[0].nodeId==N0", urls[0].nodeId == "N0")
check("buildNodeURLs[0].role==HOST", urls[0].role == "HOST")
check("buildNodeURLs[0].url contains ?node=N0", urls[0].url.contains("?node=N0"))
check("buildNodeURLs[0].url contains #l=", urls[0].url.contains("#l="))
check("buildNodeURLs[1].nodeId==N1", urls[1].nodeId == "N1")
check("buildNodeURLs[1].url contains ?node=N1", urls[1].url.contains("?node=N1"))
check("buildNodeURLs base no stray fragment", urls[0].url.contains("ltx.html?node=N0"))

// ── generateICS (13) ───────────────────────────────────────────────────────

let ics = InterplanetLTX.generateICS(plan)
check("generateICS starts BEGIN:VCALENDAR", ics.hasPrefix("BEGIN:VCALENDAR"))
check("generateICS ends with CRLF", ics.hasSuffix("\r\n"))
check("generateICS contains END:VCALENDAR", ics.contains("END:VCALENDAR"))
check("generateICS contains BEGIN:VEVENT", ics.contains("BEGIN:VEVENT"))
check("generateICS contains END:VEVENT", ics.contains("END:VEVENT"))
check("generateICS contains LTX:1", ics.contains("LTX:1"))
check("generateICS contains LTX-PLANID", ics.contains("LTX-PLANID:"))
check("generateICS contains LTX-QUANTUM", ics.contains("LTX-QUANTUM:PT5M"))
check("generateICS contains LTX-SEGMENT-TEMPLATE", ics.contains("LTX-SEGMENT-TEMPLATE:"))
check("generateICS contains LTX-NODE", ics.contains("LTX-NODE:"))
check("generateICS contains LTX-DELAY", ics.contains("LTX-DELAY;"))
check("generateICS uses CRLF line endings", ics.contains("\r\n"))
check("generateICS contains plan title in SUMMARY", ics.contains("SUMMARY:LTX Session"))

// ── formatHMS (8) ──────────────────────────────────────────────────────────

check("formatHMS(0)=='00:00'",         InterplanetLTX.formatHMS(0)    == "00:00")
check("formatHMS(59)=='00:59'",        InterplanetLTX.formatHMS(59)   == "00:59")
check("formatHMS(60)=='01:00'",        InterplanetLTX.formatHMS(60)   == "01:00")
check("formatHMS(3599)=='59:59'",      InterplanetLTX.formatHMS(3599) == "59:59")
check("formatHMS(3600)=='01:00:00'",   InterplanetLTX.formatHMS(3600) == "01:00:00")
check("formatHMS(3661)=='01:01:01'",   InterplanetLTX.formatHMS(3661) == "01:01:01")
check("formatHMS(-1)=='00:00' clamp",  InterplanetLTX.formatHMS(-1)   == "00:00")
check("formatHMS(7322)=='02:02:02'",   InterplanetLTX.formatHMS(7322) == "02:02:02")

// ── formatUTC (3) ──────────────────────────────────────────────────────────

check("formatUTC(0)=='00:00:00 UTC'",        InterplanetLTX.formatUTC(0)        == "00:00:00 UTC")
check("formatUTC(3661000)=='01:01:01 UTC'",  InterplanetLTX.formatUTC(3661000)  == "01:01:01 UTC")
check("formatUTC(86399000)=='23:59:59 UTC'", InterplanetLTX.formatUTC(86399000) == "23:59:59 UTC")

// ── escapeIcsText (7) ──────────────────────────────────────────────────────

check("escapeIcsText empty", InterplanetLTX.escapeIcsText("") == "")
check("escapeIcsText no special", InterplanetLTX.escapeIcsText("hello") == "hello")
check("escapeIcsText semicolon", InterplanetLTX.escapeIcsText("a;b") == "a\\;b")
check("escapeIcsText comma", InterplanetLTX.escapeIcsText("a,b") == "a\\,b")
check("escapeIcsText backslash", InterplanetLTX.escapeIcsText("a\\b") == "a\\\\b")
check("escapeIcsText newline", InterplanetLTX.escapeIcsText("a\nb") == "a\\nb")
let escapedIcs = InterplanetLTX.generateICS(InterplanetLTX.createPlan(title: "Hello, World; Test", start: "2026-03-15T14:00:00Z"))
check("generateICS SUMMARY escaped", escapedIcs.contains("SUMMARY:Hello\\, World\\; Test"))

// ── DEGRADED state (6) ─────────────────────────────────────────────────────

check("SessionState DEGRADED raw", InterplanetLTX.SessionState.degraded.rawValue == "DEGRADED")
check("SessionState INIT raw", InterplanetLTX.SessionState.initState.rawValue == "INIT")
check("SessionState COMPLETE raw", InterplanetLTX.SessionState.complete.rawValue == "COMPLETE")
check("SessionState all cases count", InterplanetLTX.SessionState.allCases.count == 5)

// ── planLockTimeoutMs (3) ──────────────────────────────────────────────────

check("defaultPlanLockTimeoutFactor==2", InterplanetLTX.defaultPlanLockTimeoutFactor == 2)
check("planLockTimeoutMs(100)==200000", InterplanetLTX.planLockTimeoutMs(100) == 200000)
check("planLockTimeoutMs(0)==0", InterplanetLTX.planLockTimeoutMs(0) == 0)

// ── checkDelayViolation (8) ────────────────────────────────────────────────

check("delayViolationWarnS==120", InterplanetLTX.delayViolationWarnS == 120)
check("delayViolationDegradedS==300", InterplanetLTX.delayViolationDegradedS == 300)
check("violation ok", InterplanetLTX.checkDelayViolation(declaredDelayS: 100, measuredDelayS: 100) == "ok")
check("violation ok within", InterplanetLTX.checkDelayViolation(declaredDelayS: 100, measuredDelayS: 210) == "ok")
check("violation warn", InterplanetLTX.checkDelayViolation(declaredDelayS: 100, measuredDelayS: 221) == "violation")
check("violation degraded", InterplanetLTX.checkDelayViolation(declaredDelayS: 100, measuredDelayS: 401) == "degraded")
check("violation boundary 120 ok", InterplanetLTX.checkDelayViolation(declaredDelayS: 0, measuredDelayS: 120) == "ok")
check("violation boundary 301 degraded", InterplanetLTX.checkDelayViolation(declaredDelayS: 0, measuredDelayS: 301) == "degraded")


// ── canonicalJSON (5) ─────────────────────────────────────────────────────

let cj1 = InterplanetLTX.canonicalJSON(["b": 2, "a": 1] as [String: Any])
let cj2 = InterplanetLTX.canonicalJSON(["a": 1, "b": 2] as [String: Any])
check("canonicalJSON sorted keys", cj1 == cj2)
check("canonicalJSON sorted output", cj1 == "{\"a\":1,\"b\":2}")
check("canonicalJSON nested", InterplanetLTX.canonicalJSON(["z": ["b": 2, "a": 1] as [String: Any]] as [String: Any]) == "{\"z\":{\"a\":1,\"b\":2}}")
check("canonicalJSON array", InterplanetLTX.canonicalJSON([1, 2, 3] as [Any]) == "[1,2,3]")
check("canonicalJSON null", InterplanetLTX.canonicalJSON(nil) == "null")

// ── generateNIK (5) ────────────────────────────────────────────────────────

let nikResult = InterplanetLTX.generateNIK(validDays: 365, nodeLabel: "TestNode")
let nik = nikResult.nik
check("generateNIK nodeId non-empty", !nik.nodeId.isEmpty)
check("generateNIK publicKey non-empty", !nik.publicKey.isEmpty)
check("generateNIK algorithm Ed25519", nik.algorithm == "Ed25519")
check("generateNIK not expired", !InterplanetLTX.isNIKExpired(nik))
let nik2 = InterplanetLTX.generateNIK().nik
check("generateNIK unique nodeIds", nik.nodeId != nik2.nodeId)

// ── isNIKExpired (2) ───────────────────────────────────────────────────────

let expiredNIK = InterplanetLTX.LtxNIK(nodeId: "abc", publicKey: "pub", algorithm: "Ed25519",
    validFrom: "2020-01-01T00:00:00Z", validUntil: "2020-12-31T23:59:59Z", keyVersion: 1, label: "")
check("isNIKExpired past", InterplanetLTX.isNIKExpired(expiredNIK))
check("isNIKExpired future", !InterplanetLTX.isNIKExpired(nik))

// ── signPlan / verifyPlan (5) ──────────────────────────────────────────────

let testPlan: [String: Any] = ["planId": "P1", "title": "Test", "v": 2]
let signedPlan = InterplanetLTX.signPlan(testPlan, privateKeyB64: nikResult.privateKeyB64)
check("signPlan returns non-nil", signedPlan != nil)

var keyCache: [String: InterplanetLTX.LtxNIK] = [:]
keyCache[nik.nodeId] = nik
let vr = InterplanetLTX.verifyPlan(signedPlan!, keyCache: keyCache)
check("verifyPlan valid roundtrip", vr.valid)

let emptyCache: [String: InterplanetLTX.LtxNIK] = [:]
let vrMiss = InterplanetLTX.verifyPlan(signedPlan!, keyCache: emptyCache)
check("verifyPlan wrong cache", !vrMiss.valid && vrMiss.reason == "key_not_in_cache")

var tamperedPlan = signedPlan!
// Tamper with the plan payload
let coseOrig = tamperedPlan.coseSign1
let tamperedCose = InterplanetLTX.LtxCoseSign1(protected: coseOrig.protected, unprotected: coseOrig.unprotected,
    payload: coseOrig.payload, signature: coseOrig.signature)
let tamperedSP = InterplanetLTX.LtxSignedPlan(plan: ["planId": "P1", "title": "TAMPERED", "v": 2], coseSign1: tamperedCose)
let vrTamper = InterplanetLTX.verifyPlan(tamperedSP, keyCache: keyCache)
check("verifyPlan tampered payload fails", !vrTamper.valid)

let expiredKeyNIK = InterplanetLTX.LtxNIK(nodeId: nik.nodeId, publicKey: nik.publicKey, algorithm: "Ed25519",
    validFrom: "2020-01-01T00:00:00Z", validUntil: "2020-12-31T23:59:59Z", keyVersion: 1, label: "")
var expiredKeyCache: [String: InterplanetLTX.LtxNIK] = [:]
expiredKeyCache[nik.nodeId] = expiredKeyNIK
let vrExpired = InterplanetLTX.verifyPlan(signedPlan!, keyCache: expiredKeyCache)
check("verifyPlan expired key fails", !vrExpired.valid && vrExpired.reason == "key_expired")

// ── createSequenceTracker / addSeq / checkSeq (8) ─────────────────────────

let tracker = InterplanetLTX.createSequenceTracker(planId: "PLAN-1")

var bundle1: [String: Any] = ["type": "MSG"]
bundle1 = InterplanetLTX.addSeq(bundle1, tracker: tracker, nodeId: "N0")
check("addSeq first seq is 1", (bundle1["seq"] as? Int) == 1)

var bundle2: [String: Any] = ["type": "MSG"]
bundle2 = InterplanetLTX.addSeq(bundle2, tracker: tracker, nodeId: "N0")
check("addSeq second seq is 2", (bundle2["seq"] as? Int) == 2)

var bundle3: [String: Any] = ["type": "MSG"]
bundle3 = InterplanetLTX.addSeq(bundle3, tracker: tracker, nodeId: "N1")
check("addSeq N1 first seq is 1", (bundle3["seq"] as? Int) == 1)

let cr1 = InterplanetLTX.checkSeq(bundle1, tracker: tracker, senderNodeId: "N0")
check("checkSeq accepts first message", cr1.accepted)

let cr2 = InterplanetLTX.checkSeq(bundle2, tracker: tracker, senderNodeId: "N0")
check("checkSeq accepts second message", cr2.accepted)

let cr_replay = InterplanetLTX.checkSeq(bundle1, tracker: tracker, senderNodeId: "N0")
check("checkSeq rejects replay", !cr_replay.accepted && cr_replay.reason == "replay")

var bundle5: [String: Any] = ["type": "MSG", "seq": 5]
let cr_gap = InterplanetLTX.checkSeq(bundle5, tracker: tracker, senderNodeId: "N0")
check("checkSeq detects gap", cr_gap.accepted && cr_gap.gap && cr_gap.gapSize == 2)

var bundleNoSeq: [String: Any] = ["type": "MSG"]
let cr_missing = InterplanetLTX.checkSeq(bundleNoSeq, tracker: tracker, senderNodeId: "N0")
check("checkSeq missing_seq", !cr_missing.accepted && cr_missing.reason == "missing_seq")

// ═══════════════════════════════════════════════════════════════════════════
// LTX v1.1 core subset — golden conformance vectors (Epic 72.4)
// ═══════════════════════════════════════════════════════════════════════════

let vectorsPath = "../../../conformance/vectors.json"
let vectorsData = FileManager.default.contents(atPath: vectorsPath)
check("v11: conformance/vectors.json found", vectorsData != nil)
let vectorsRoot = (try? JSONSerialization.jsonObject(with: vectorsData ?? Data())) as? [String: Any]
let v11 = vectorsRoot?["v11"] as? [String: Any] ?? [:]
check("v11: v11 section parsed", !v11.isEmpty)

let keyVec = v11["key"] as? [String: Any] ?? [:]
let nikVec = keyVec["nik"] as? [String: Any] ?? [:]
let seedB64 = keyVec["privateSeedB64"] as? String ?? ""
let vecNIK = InterplanetLTX.LtxNIK(
    nodeId:     nikVec["nodeId"] as? String ?? "",
    publicKey:  nikVec["publicKey"] as? String ?? "",
    algorithm:  nikVec["algorithm"] as? String ?? "Ed25519",
    validFrom:  nikVec["validFrom"] as? String ?? "",
    validUntil: nikVec["validUntil"] as? String ?? "",
    keyVersion: nikVec["keyVersion"] as? Int ?? 1,
    label: ""
)
check("v11: vector NIK not expired", !InterplanetLTX.isNIKExpired(vecNIK))

// ── 1. v3 planId + v2 regression ───────────────────────────────────────────

let planV3Vec = v11["planIdV3"] as? [String: Any] ?? [:]
let planV3Map = planV3Vec["plan"] as? [String: Any] ?? [:]
check("v11: v3 plan canonical JSON matches vector",
      InterplanetLTX.canonicalJSON(planV3Map) == (planV3Vec["canonicalJson"] as? String))
let planV3 = InterplanetLTX.upgradeConfig(planV3Map)
check("v11: v3 plan dict canonicalises identically",
      InterplanetLTX.canonicalJSON(InterplanetLTX.planToDict(planV3)) == (planV3Vec["canonicalJson"] as? String))
check("v11: makePlanID v3 == expected",
      InterplanetLTX.makePlanID(planV3) == (planV3Vec["expectedPlanId"] as? String))

let planV2Vec = v11["planIdV2Regression"] as? [String: Any] ?? [:]
let planV2 = InterplanetLTX.upgradeConfig(planV2Vec["plan"] as? [String: Any] ?? [:])
check("v11: FROZEN v2 planId regression",
      InterplanetLTX.makePlanID(planV2) == (planV2Vec["expectedPlanId"] as? String))

// ── 2. pairDelay + computeSegmentsFor ──────────────────────────────────────

let pdVec = v11["pairDelay"] as? [String: Any] ?? [:]
let pdPlan = InterplanetLTX.upgradeConfig(pdVec["plan"] as? [String: Any] ?? [:])
for c in (pdVec["cases"] as? [[String: Any]] ?? []) {
    let a = c["a"] as? String ?? "", b = c["b"] as? String ?? ""
    let expected = c["expected"] as? Int ?? -1
    check("v11: pairDelay(\(a),\(b)) == \(expected)",
          InterplanetLTX.pairDelay(pdPlan, a, b) == expected)
}
let fbVec = pdVec["fallbackCase"] as? [String: Any] ?? [:]
let fbPlan = InterplanetLTX.upgradeConfig(fbVec["plan"] as? [String: Any] ?? [:])
check("v11: pairDelay fallback == \(fbVec["expected"] as? Int ?? -1)",
      InterplanetLTX.pairDelay(fbPlan, fbVec["a"] as? String ?? "", fbVec["b"] as? String ?? "")
          == (fbVec["expected"] as? Int))
check("v11: pairDelay unknown node is nil",
      InterplanetLTX.pairDelay(fbPlan, "N1", "N9") == nil)

let baseSegs = (try? InterplanetLTX.computeSegments(pdPlan)) ?? []
let segN2 = (try? InterplanetLTX.computeSegmentsFor(pdPlan, viewerNodeId: "N2")) ?? []
check("v11: computeSegmentsFor 4 segments", segN2.count == 4)
check("v11: PLAN_CONFIRM neutral for N2",
      segN2[0].perspective == "neutral" && segN2[0].arrivalOffsetS == 0)
check("v11: N0 TX received by N2 with +2s (HOST row)",
      segN2[1].perspective == "receive" && segN2[1].arrivalOffsetS == 2)
check("v11: N1 TX received by N2 with +500s (pair matrix)",
      segN2[2].perspective == "receive" && segN2[2].arrivalOffsetS == 500)
check("v11: receive segment start shifted by pairDelay",
      segN2[2].startMs == baseSegs[2].startMs + 500_000)
check("v11: viewer segment keeps speaker/label",
      segN2[2].speaker == "N1" && segN2[2].label == "Mars Report")
let segN1 = (try? InterplanetLTX.computeSegmentsFor(pdPlan, viewerNodeId: "N1")) ?? []
check("v11: own TX is transmit with no shift",
      segN1[2].perspective == "transmit" && segN1[2].arrivalOffsetS == 0
          && segN1[2].startMs == baseSegs[2].startMs)
check("v11: computeSegmentsFor unknown viewer throws",
      (try? InterplanetLTX.computeSegmentsFor(pdPlan, viewerNodeId: "N9")) == nil)

// ── 3. Amendment-chain verify ──────────────────────────────────────────────

let chainVec = v11["amendmentChain"] as? [String: Any] ?? [:]
let chainDicts = chainVec["chain"] as? [[String: Any]] ?? []
let chain = chainDicts.compactMap { InterplanetLTX.signedPlanFromDict($0) }
check("v11: chain has 2 parsed links", chain.count == 2)
var v11KeyCache: [String: InterplanetLTX.LtxNIK] = [vecNIK.nodeId: vecNIK]
let rootPlan = chainDicts.first?["plan"] as? [String: Any] ?? [:]
check("v11: planHash(root) matches vector rootPlanHash",
      InterplanetLTX.planHash(rootPlan) == (chainVec["rootPlanHash"] as? String))
let chainResult = InterplanetLTX.verifyAmendmentChain(chain, keyCache: v11KeyCache)
check("v11: amendment chain verifies (\(chainResult.reason))", chainResult.valid)

// Tamper the amended link's title → chain must fail.
var tamperedDicts = chainDicts
var tamperedLink = tamperedDicts[1]
var tamperedPlanDict = tamperedLink["plan"] as? [String: Any] ?? [:]
tamperedPlanDict["title"] = "Tampered Summit"
tamperedLink["plan"] = tamperedPlanDict
tamperedDicts[1] = tamperedLink
let tamperedChain = tamperedDicts.compactMap { InterplanetLTX.signedPlanFromDict($0) }
check("v11: tampered amendment chain rejected",
      !InterplanetLTX.verifyAmendmentChain(tamperedChain, keyCache: v11KeyCache).valid)

// createAmendment roundtrip with the fixed seed.
let signedRoot = InterplanetLTX.signPlan(rootPlan, privateKeyB64: seedB64)
check("v11: signPlan(root) kid matches vector nodeId",
      signedRoot?.coseSign1.unprotected["kid"] == vecNIK.nodeId)
if let signedRoot = signedRoot,
   let amended = InterplanetLTX.createAmendment(signedRoot,
       changes: ["title": "Vector Summit (amended)"], privateKeyB64: seedB64) {
    check("v11: createAmendment sets planVersion+1 and prevPlanHash",
          amended.plan["planVersion"] as? Int == 2
              && amended.plan["prevPlanHash"] as? String == InterplanetLTX.planHash(rootPlan))
    let rtChain = InterplanetLTX.verifyAmendmentChain([signedRoot, amended], keyCache: v11KeyCache)
    check("v11: createAmendment chain verifies (\(rtChain.reason))", rtChain.valid)
} else {
    check("v11: createAmendment produced a chain", false)
}

// ── 4. Register entries + reducers + entriesRoot ───────────────────────────

let regVec = v11["registerEntries"] as? [String: Any] ?? [:]
let regEntries = regVec["entries"] as? [[String: Any]] ?? []
let regKeyCache: [String: InterplanetLTX.LtxNIK] = ["N0": vecNIK, "N1": vecNIK]
for e in regEntries {
    let vr = InterplanetLTX.verifyRegisterEntry(e, keyCache: regKeyCache)
    check("v11: register entry \(e["entryId"] as? String ?? "?") verifies (\(vr.reason))", vr.valid)
}
var tamperedEntry = regEntries[0]
var tamperedContent = tamperedEntry["content"] as? [String: Any] ?? [:]
tamperedContent["text"] = "Tampered?"
tamperedEntry["content"] = tamperedContent
let tamperedEntryResult = InterplanetLTX.verifyRegisterEntry(tamperedEntry, keyCache: regKeyCache)
check("v11: tampered register entry rejected",
      !tamperedEntryResult.valid && tamperedEntryResult.reason == "signature_invalid")

let reduced = InterplanetLTX.reduceQuestions(regEntries)
let expQuestionState = regVec["expectedQuestionState"] as? [String: Any] ?? [:]
check("v11: reduceQuestions state matches vector",
      InterplanetLTX.canonicalJSON(reduced.byId) == InterplanetLTX.canonicalJSON(expQuestionState))
check("v11: no superseded entries in vector", reduced.superseded.isEmpty)
let reducedRev = InterplanetLTX.reduceQuestions(regEntries.reversed())
check("v11: reduceQuestions is input-order independent",
      InterplanetLTX.canonicalJSON(reducedRev.byId) == InterplanetLTX.canonicalJSON(reduced.byId))

check("v11: entriesRoot matches vector",
      InterplanetLTX.entriesRoot(regEntries) == (regVec["entriesRoot"] as? String))
check("v11: entriesRoot input-order independent",
      InterplanetLTX.entriesRoot(regEntries.reversed()) == (regVec["entriesRoot"] as? String))

// createRegisterEntry roundtrip.
if let newEntry = InterplanetLTX.createRegisterEntry(
    type: "action", content: ["description": "Test action"],
    sessionId: "VEC-SESSION", nodeId: "N1", seq: 2,
    timestamp: "2040-02-01T11:10:00.000Z", privateKeyB64: seedB64) {
    check("v11: createRegisterEntry id", newEntry["entryId"] as? String == "ACT-N1-2")
    check("v11: created register entry verifies",
          InterplanetLTX.verifyRegisterEntry(newEntry, keyCache: regKeyCache).valid)
    let actions = InterplanetLTX.reduceActions([newEntry])
    check("v11: reduceActions PROPOSED",
          actions.byId["ACT-N1-2"]?["status"] as? String == "PROPOSED")
} else {
    check("v11: createRegisterEntry returned entry", false)
}

// ── 5. CBOR decode + COSE_Sign1 verify ─────────────────────────────────────

let coseVec = v11["coseSign1"] as? [String: Any] ?? [:]
let coseB64 = coseVec["coseSign1CborB64"] as? String ?? ""
let coseEnvelope: [String: Any] = [
    "plan": coseVec["plan"] as? [String: Any] ?? [:],
    "coseSign1CborB64": coseB64,
]
let coseKeyCache: [String: InterplanetLTX.LtxNIK] = [vecNIK.nodeId: vecNIK]
let coseResult = InterplanetLTX.verifyPlanCose(coseEnvelope, keyCache: coseKeyCache)
check("v11: COSE_Sign1 vector verifies (\(coseResult.reason))",
      coseResult.valid == (coseVec["expectedValid"] as? Bool ?? true))

let cborBytes = InterplanetLTX.nikB64urlDecode(coseB64) ?? Data()
check("v11: CBOR b64 == hex vector",
      cborBytes.map { String(format: "%02x", $0) }.joined() == (coseVec["coseSign1CborHex"] as? String))

var cosePlanTampered = coseVec["plan"] as? [String: Any] ?? [:]
cosePlanTampered["title"] = "X"
let coseTampered = InterplanetLTX.verifyPlanCose(
    ["plan": cosePlanTampered, "coseSign1CborB64": coseB64], keyCache: coseKeyCache)
check("v11: COSE tampered plan rejected",
      !coseTampered.valid && coseTampered.reason == "payload_mismatch")
let coseNoKey = InterplanetLTX.verifyPlanCose(coseEnvelope, keyCache: [:])
check("v11: COSE unknown key rejected",
      !coseNoKey.valid && coseNoKey.reason == "key_not_in_cache")

// CBOR codec unit checks.
if let decodedCose = try? InterplanetLTX.decodeCbor(cborBytes) {
    if case .tag(let t, _) = decodedCose {
        check("v11: CBOR decodes to tag 18", t == 18)
    } else {
        check("v11: CBOR decodes to tag 18", false)
    }
    check("v11: CBOR deterministic re-encode roundtrip",
          InterplanetLTX.nikB64url(InterplanetLTX.encodeCbor(decodedCose)) == coseB64)
} else {
    check("v11: CBOR vector decodes", false)
}
check("v11: CBOR {1:-19} == a10132",
      InterplanetLTX.encodeCbor(.map([(.int(1), .int(-19))])) == Data([0xa1, 0x01, 0x32]))
check("v11: CBOR trailing bytes rejected",
      (try? InterplanetLTX.decodeCbor(Data([0x01, 0x02]))) == nil)
check("v11: CBOR floats rejected",
      (try? InterplanetLTX.decodeCbor(Data([0xf9, 0x3c, 0x00]))) == nil)
check("v11: CBOR indefinite length rejected",
      (try? InterplanetLTX.decodeCbor(Data([0x9f, 0x01, 0xff]))) == nil)

// signPlanCose roundtrip with the fixed seed. CryptoKit Ed25519 signatures
// are randomized (RFC 8032 determinism is not guaranteed), so compare the
// protected/kid/payload prefix and verify rather than expecting exact bytes.
if let coseSigned = InterplanetLTX.signPlanCose(coseVec["plan"] as? [String: Any] ?? [:],
                                                privateKeyB64: seedB64),
   let signedB64 = coseSigned["coseSign1CborB64"] as? String,
   let signedBytes = InterplanetLTX.nikB64urlDecode(signedB64) {
    // Everything before the 64-byte signature bstr must match the vector.
    let prefixLen = cborBytes.count - 66 // 0x58 0x40 + 64 signature bytes
    check("v11: signPlanCose matches vector envelope (sans signature)",
          signedBytes.count == cborBytes.count
              && signedBytes.prefix(prefixLen) == cborBytes.prefix(prefixLen))
    check("v11: signPlanCose roundtrip verifies",
          InterplanetLTX.verifyPlanCose(coseSigned, keyCache: coseKeyCache).valid)
} else {
    check("v11: signPlanCose returned envelope", false)
}

// ── 6. transition() state machine (golden table) ───────────────────────────

let smVec = v11["stateMachine"] as? [String: Any] ?? [:]
let smPlan = InterplanetLTX.upgradeConfig(smVec["plan"] as? [String: Any] ?? [:])
let smPlanId = smVec["planId"] as? String ?? ""
check("v11: state machine planId matches vector", InterplanetLTX.makePlanID(smPlan) == smPlanId)
var smCtx = InterplanetLTX.createSession(smPlan, planId: smPlanId,
                                         quorum: .count(smVec["quorum"] as? Int ?? 1))
check("v11: createSession starts DRAFT", smCtx.state == "DRAFT" && smCtx.lock == nil)
check("v11: lock timeout 2×maxDelay", smCtx.lockTimeoutMs == 1_800_000)
var smStepsOk = true
for (idx, rawStep) in (smVec["steps"] as? [[String: Any]] ?? []).enumerated() {
    let event = rawStep["event"] as? [String: Any] ?? [:]
    let result = InterplanetLTX.transition(smCtx, event)
    smCtx = result.ctx
    let expectState = rawStep["expectState"] as? String
    let expectLock = rawStep["expectLock"] as? String  // nil for JSON null
    if smCtx.state != expectState || smCtx.lock != expectLock {
        smStepsOk = false
        print("  v11 state machine step \(idx): got (\(smCtx.state), \(smCtx.lock ?? "nil")) expected (\(expectState ?? "?"), \(expectLock ?? "nil"))")
    }
}
check("v11: golden transition table replay", smStepsOk)
check("v11: subset cleared after late full-lock recovery", smCtx.subset == nil)
check("v11: quorum subset [N0,N2] recorded at degrade time",
      smCtx.degradedReasons.first?.contains("[N0,N2]") == true)
check("v11: two degraded reasons logged", smCtx.degradedReasons.count == 2)

let afterEnd = InterplanetLTX.transition(smCtx, ["type": "SESSION_START", "nowMs": 6_000_000])
check("v11: invalid event ignored in COMPLETE",
      afterEnd.ctx.state == "COMPLETE"
          && afterEnd.effects.contains { $0["code"] as? String == "INVALID_EVENT" })

// EOK override + resume + amendment path (not covered by the golden table).
var eokCtx = InterplanetLTX.createSession(smPlan, planId: smPlanId, quorum: .all)
eokCtx = InterplanetLTX.transition(eokCtx, ["type": "START_LOCK", "nowMs": 0]).ctx
for nid in ["N1", "N2"] {
    eokCtx = InterplanetLTX.transition(eokCtx,
        ["type": "PLAN_CONFIRM", "nowMs": 1, "nodeId": nid, "planId": smPlanId]).ctx
}
check("v11: full lock with quorum=all", eokCtx.state == "LOCKED" && eokCtx.lock == "FULL")
eokCtx = InterplanetLTX.transition(eokCtx, ["type": "SESSION_START", "nowMs": 2]).ctx
eokCtx = InterplanetLTX.transition(eokCtx,
    ["type": "EOK_OVERRIDE", "nowMs": 3, "verified": true]).ctx
check("v11: verified EOK holds session", eokCtx.state == "EMERGENCY_HOLD")
eokCtx = InterplanetLTX.transition(eokCtx,
    ["type": "HOST_DECISION", "nowMs": 4, "decision": "resume"]).ctx
check("v11: HOST resume returns to prior state", eokCtx.state == "ACTIVE")
let rejectedEok = InterplanetLTX.transition(eokCtx,
    ["type": "EOK_OVERRIDE", "nowMs": 5, "verified": false])
check("v11: unverified EOK rejected",
      rejectedEok.ctx.state == "ACTIVE"
          && rejectedEok.effects.contains { $0["code"] as? String == "OVERRIDE_REJECTED" })
eokCtx = InterplanetLTX.transition(eokCtx, [
    "type": "AMENDMENT_PROPOSED", "nowMs": 6, "planId": "PLAN-2",
    "planVersion": 2, "affectedNodeIds": ["N1"],
]).ctx
eokCtx = InterplanetLTX.transition(eokCtx, [
    "type": "AMENDMENT_CONFIRMED", "nowMs": 7, "nodeId": "N1", "planId": "PLAN-2",
]).ctx
check("v11: amendment applied after all confirms",
      eokCtx.planId == "PLAN-2" && eokCtx.planVersion == 2)
eokCtx = InterplanetLTX.transition(eokCtx,
    ["type": "HOST_DECISION", "nowMs": 8, "decision": "abort"]).ctx
check("v11: HOST abort", eokCtx.state == "ABORTED")

// ── Summary ────────────────────────────────────────────────────────────────

print("\n\(passed) passed  \(failed) failed")
if failed > 0 { exit(1) }
