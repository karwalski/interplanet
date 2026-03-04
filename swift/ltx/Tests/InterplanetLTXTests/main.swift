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

check("version is 1.0.0", InterplanetLTX.version == "1.0.0")
check("defaultQuantum is 3", InterplanetLTX.defaultQuantum == 3)
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
check("createPlan quantum==3", plan.quantum == 3)
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
check("computeSegments[0] durMin==6", segs[0].durMin == 6)
check("computeSegments[0] startMs>0", segs[0].startMs > 0)
let startMs0 = segs[0].startMs
let expectedEnd0 = startMs0 + 2 * 3 * 60 * 1000
check("computeSegments[0] endMs correct", segs[0].endMs == expectedEnd0)
check("computeSegments[1] startMs==segs[0].endMs", segs[1].startMs == segs[0].endMs)
check("computeSegments[6] type BUFFER", segs[6].type == "BUFFER")
check("computeSegments[6] q==1", segs[6].q == 1)
check("computeSegments[6] durMin==3", segs[6].durMin == 3)
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
check("totalMin default plan==39", total == 39)
let plan2 = LtxPlan(segments: [LtxSegmentTemplate(type: "TX", q: 4)])
check("totalMin single segment", InterplanetLTX.totalMin(plan2) == 12) // 4*3

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
check("generateICS contains LTX-QUANTUM", ics.contains("LTX-QUANTUM:PT3M"))
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

// ── Summary ────────────────────────────────────────────────────────────────

print("\n\(passed) passed  \(failed) failed")
if failed > 0 { exit(1) }
