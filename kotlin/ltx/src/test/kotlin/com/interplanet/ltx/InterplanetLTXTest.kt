package com.interplanet.ltx

var passed = 0
var failed = 0

fun check(name: String, result: Boolean) {
    if (result) { passed++; println("  PASS: $name") }
    else { failed++; println("  FAIL: $name") }
}

fun main() {
    val node1 = LtxNode("N0", "Earth HQ", "host", 0, "earth")
    val node2 = LtxNode("N1", "Mars Base", "participant", 1240, "mars")
    val plan = InterplanetLTX.createPlan("Test Meeting", listOf(node1, node2))

    println("── Constants ────────────────────────────────")
    check("VERSION is 1.0.0", InterplanetLTX.VERSION == "1.0.0")
    check("DEFAULT_QUANTUM is 5", InterplanetLTX.DEFAULT_QUANTUM == 5)
    check("DEFAULT_SEGMENTS not empty", InterplanetLTX.DEFAULT_SEGMENTS.isNotEmpty())
    check("DEFAULT_SEGMENTS has SPEAK", InterplanetLTX.DEFAULT_SEGMENTS.any { it.type == "SPEAK" })
    check("DEFAULT_SEGMENTS has RELAY", InterplanetLTX.DEFAULT_SEGMENTS.any { it.type == "RELAY" })
    check("DEFAULT_SEGMENTS has REST", InterplanetLTX.DEFAULT_SEGMENTS.any { it.type == "REST" })
    check("DEFAULT_API_BASE starts https", InterplanetLTX.DEFAULT_API_BASE.startsWith("https://"))
    check("DEFAULT_API_BASE contains interplanet", InterplanetLTX.DEFAULT_API_BASE.contains("interplanet"))

    println("── CreatePlan ───────────────────────────────")
    check("plan.v == 2", plan.v == 2)
    check("plan.title matches", plan.title == "Test Meeting")
    check("plan.nodes.size == 2", plan.nodes.size == 2)
    check("plan.nodes[0].name == Earth HQ", plan.nodes[0].name == "Earth HQ")
    check("plan.nodes[1].name == Mars Base", plan.nodes[1].name == "Mars Base")
    check("plan.nodes[0].role == host", plan.nodes[0].role == "host")
    check("plan.nodes[1].delay == 1240", plan.nodes[1].delay == 1240)
    check("plan.mode == async", plan.mode == "async")
    check("plan.quantum == 5", plan.quantum == 5)
    check("plan.start not empty", plan.start.isNotEmpty())
    check("plan.start contains T", plan.start.contains("T"))
    check("plan.segments not empty", plan.segments.isNotEmpty())
    check("plan.segments has SPEAK", plan.segments.any { it.type == "SPEAK" })

    println("── UpgradeConfig ────────────────────────────")
    val oldMap = mapOf("v" to 1, "title" to "Old Meeting", "start" to "2040-01-15T14:00:00Z",
        "quantum" to 5, "mode" to "async",
        "nodes" to listOf(mapOf("id" to "N0","name" to "Earth HQ","role" to "host","delay" to 0,"location" to "earth")),
        "segments" to listOf(mapOf("type" to "SPEAK","q" to 3)))
    val upgraded = InterplanetLTX.upgradeConfig(oldMap)
    check("upgrade v == 2", upgraded.v == 2)
    check("upgrade title preserved", upgraded.title == "Old Meeting")
    check("upgrade nodes preserved", upgraded.nodes.size == 1)
    check("upgrade segments preserved", upgraded.segments.size == 1)
    check("upgrade start preserved", upgraded.start == "2040-01-15T14:00:00Z")
    check("upgrade quantum == 5", upgraded.quantum == 5)
    check("upgrade mode == async", upgraded.mode == "async")
    check("upgrade node[0].name == Earth HQ", upgraded.nodes[0].name == "Earth HQ")

    println("── ComputeSegments ──────────────────────────")
    val segs = InterplanetLTX.computeSegments(plan)
    check("segments not empty", segs.isNotEmpty())
    check("first seg has startMs > 0", segs.first().startMs > 0)
    check("each seg has durationMs > 0", segs.all { it.durationMs > 0 })
    check("segments are contiguous", segs.zipWithNext().all { (a,b) -> a.endMs == b.startMs })
    check("seg types match template types", segs.map { it.segType } == plan.segments.map { it.type })
    check("seg durationMs = q * quantum * 60000", segs[0].durationMs == plan.segments[0].q.toLong() * plan.quantum * 60000L)
    check("seg endMs = startMs + durationMs", segs.all { it.endMs == it.startMs + it.durationMs })
    check("segments have nodeId", segs.all { it.nodeId.isNotEmpty() })
    check("segment count matches template count", segs.size == plan.segments.size)
    check("SPEAK seg has host nodeId", segs.first { it.segType == "SPEAK" }.nodeId.isNotEmpty())

    println("── TotalMin ─────────────────────────────────")
    val tm = InterplanetLTX.totalMin(plan)
    check("totalMin > 0", tm > 0)
    check("totalMin == sum of q*quantum", tm == plan.segments.sumOf { it.q } * plan.quantum)
    check("totalMin is Int", tm is Int)

    println("── MakePlanId ───────────────────────────────")
    val pid = InterplanetLTX.makePlanId(plan)
    check("planId not empty", pid.isNotEmpty())
    check("planId consistent", InterplanetLTX.makePlanId(plan) == pid)
    check("planId length > 0", pid.length > 0)
    check("planId no spaces", !pid.contains(" "))
    check("planId no padding =", !pid.contains("="))
    check("planId no + or /", !pid.contains("+") && !pid.contains("/"))

    println("── EncodeHash / DecodeHash ──────────────────")
    val hash = InterplanetLTX.encodeHash(plan)
    check("hash starts #l=", hash.startsWith("#l="))
    check("hash payload no =", !hash.removePrefix("#l=").contains("="))
    check("hash no +", !hash.contains("+"))
    check("hash no /", !hash.contains("/"))
    val decoded = InterplanetLTX.decodeHash(hash)
    check("decoded not null", decoded != null)
    check("decoded.v == 2", decoded?.v == 2)
    check("decoded.title matches", decoded?.title == plan.title)
    check("decoded.nodes.size matches", decoded?.nodes?.size == plan.nodes.size)
    check("decoded.quantum matches", decoded?.quantum == plan.quantum)
    check("decoded.mode matches", decoded?.mode == plan.mode)
    check("decodeHash null on invalid", InterplanetLTX.decodeHash("invalid") == null)
    check("decodeHash null on empty", InterplanetLTX.decodeHash("") == null)

    println("── BuildNodeUrls ────────────────────────────")
    val urls = InterplanetLTX.buildNodeUrls(plan, "https://interplanet.live/ltx.html")
    check("urls not empty", urls.isNotEmpty())
    check("urls.size == nodes.size", urls.size == plan.nodes.size)
    check("first url contains ?node=", urls.first().url.contains("?node="))
    check("first url contains #", urls.first().url.contains("#"))
    check("first url nodeId matches", urls.first().nodeId == plan.nodes.first().id)
    check("first url name matches", urls.first().name == plan.nodes.first().name)
    check("second url nodeId == N1", urls[1].nodeId == "N1")
    check("all urls start with base", urls.all { it.url.startsWith("https://interplanet.live") })

    println("── GenerateICS ──────────────────────────────")
    val ics = InterplanetLTX.generateICS(plan)
    check("ics contains BEGIN:VCALENDAR", ics.contains("BEGIN:VCALENDAR"))
    check("ics contains END:VCALENDAR", ics.contains("END:VCALENDAR"))
    check("ics contains BEGIN:VEVENT", ics.contains("BEGIN:VEVENT"))
    check("ics contains END:VEVENT", ics.contains("END:VEVENT"))
    check("ics contains LTX-PLANID", ics.contains("LTX-PLANID"))
    check("ics contains LTX-QUANTUM", ics.contains("LTX-QUANTUM"))
    check("ics contains DTSTART", ics.contains("DTSTART"))
    check("ics contains SUMMARY", ics.contains("SUMMARY"))
    check("ics uses CRLF", ics.contains("\r\n"))
    check("ics contains PRODID", ics.contains("PRODID"))
    check("ics contains LTX-NODE", ics.contains("LTX-NODE"))
    check("ics contains plan title", ics.contains(plan.title))
    check("ics ends with CRLF", ics.endsWith("\r\n"))

    println("── FormatHMS ────────────────────────────────")
    check("formatHMS(0) == 00:00", InterplanetLTX.formatHMS(0) == "00:00")
    check("formatHMS(59) == 00:59", InterplanetLTX.formatHMS(59) == "00:59")
    check("formatHMS(60) == 01:00", InterplanetLTX.formatHMS(60) == "01:00")
    check("formatHMS(3599) == 59:59", InterplanetLTX.formatHMS(3599) == "59:59")
    check("formatHMS(3600) == 01:00:00", InterplanetLTX.formatHMS(3600) == "01:00:00")
    check("formatHMS(3661) == 01:01:01", InterplanetLTX.formatHMS(3661) == "01:01:01")
    check("formatHMS(7320) == 02:02:00", InterplanetLTX.formatHMS(7320) == "02:02:00")
    check("formatHMS(-1) == 00:00", InterplanetLTX.formatHMS(-1) == "00:00")

    println("── FormatUTC ────────────────────────────────")
    check("formatUTC(0) == 00:00:00 UTC", InterplanetLTX.formatUTC(0L) == "00:00:00 UTC")
    check("formatUTC(3661000) == 01:01:01 UTC", InterplanetLTX.formatUTC(3661000L) == "01:01:01 UTC")
    check("formatUTC contains UTC", InterplanetLTX.formatUTC(12345678L).contains("UTC"))

    println("── EscapeIcsText (Story 26.3) ───────────────")
    check("escapeIcsText empty", InterplanetLTX.escapeIcsText("") == "")
    check("escapeIcsText no specials", InterplanetLTX.escapeIcsText("hello") == "hello")
    check("escapeIcsText comma", InterplanetLTX.escapeIcsText("a,b") == "a\\,b")
    check("escapeIcsText semicolon", InterplanetLTX.escapeIcsText("a;b") == "a\\;b")
    check("escapeIcsText backslash", InterplanetLTX.escapeIcsText("a\\b") == "a\\\\b")
    check("escapeIcsText newline", InterplanetLTX.escapeIcsText("a\nb") == "a\\nb")
    check("escapeIcsText all specials", InterplanetLTX.escapeIcsText("a,b;c\\d\ne") == "a\\,b\\;c\\\\d\\ne")

    // SUMMARY in ICS uses escapeIcsText
    val titleWithSpecials = "Mars,Earth;Session"
    val planSpecial = InterplanetLTX.createPlan(titleWithSpecials, listOf(node1, node2),
        start = "2024-01-15T14:00:00Z")
    val icsSpecial = InterplanetLTX.generateICS(planSpecial)
    check("ICS SUMMARY escapes title specials",
        icsSpecial.contains("SUMMARY:Mars\\,Earth\\;Session"))

    println("── Story 26.4 — Protocol hardening ─────────")
    check("DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR is 2", InterplanetLTX.DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR == 2)
    check("DELAY_VIOLATION_WARN_S is 120", InterplanetLTX.DELAY_VIOLATION_WARN_S == 120)
    check("DELAY_VIOLATION_DEGRADED_S is 300", InterplanetLTX.DELAY_VIOLATION_DEGRADED_S == 300)
    check("SESSION_STATES size is 5", InterplanetLTX.SESSION_STATES.size == 5)
    check("SESSION_STATES[0] is INIT", InterplanetLTX.SESSION_STATES[0] == "INIT")
    check("SESSION_STATES[1] is LOCKED", InterplanetLTX.SESSION_STATES[1] == "LOCKED")
    check("SESSION_STATES[2] is RUNNING", InterplanetLTX.SESSION_STATES[2] == "RUNNING")
    check("SESSION_STATES[3] is DEGRADED", InterplanetLTX.SESSION_STATES[3] == "DEGRADED")
    check("SESSION_STATES[4] is COMPLETE", InterplanetLTX.SESSION_STATES[4] == "COMPLETE")
    check("SESSION_STATES contains DEGRADED", InterplanetLTX.SESSION_STATES.contains("DEGRADED"))

    println("── PlanLockTimeoutMs ────────────────────────")
    check("planLockTimeoutMs(0) == 0", InterplanetLTX.planLockTimeoutMs(0L) == 0L)
    check("planLockTimeoutMs(100) == 200000", InterplanetLTX.planLockTimeoutMs(100L) == 200_000L)
    check("planLockTimeoutMs(60) == 120000", InterplanetLTX.planLockTimeoutMs(60L) == 120_000L)
    check("planLockTimeoutMs(1000) == 2000000", InterplanetLTX.planLockTimeoutMs(1000L) == 2_000_000L)

    println("── CheckDelayViolation ──────────────────────")
    check("checkDelayViolation same delay is ok",
        InterplanetLTX.checkDelayViolation(100L, 100L) == "ok")
    check("checkDelayViolation diff=100 is ok",
        InterplanetLTX.checkDelayViolation(100L, 200L) == "ok")
    check("checkDelayViolation diff=120 is ok (boundary)",
        InterplanetLTX.checkDelayViolation(100L, 220L) == "ok")
    check("checkDelayViolation diff=121 is violation",
        InterplanetLTX.checkDelayViolation(100L, 221L) == "violation")
    check("checkDelayViolation diff=300 is violation (boundary)",
        InterplanetLTX.checkDelayViolation(100L, 400L) == "violation")
    check("checkDelayViolation diff=301 is degraded",
        InterplanetLTX.checkDelayViolation(100L, 401L) == "degraded")
    check("checkDelayViolation large negative diff is degraded",
        InterplanetLTX.checkDelayViolation(500L, 100L) == "degraded")
    check("checkDelayViolation both zero is ok",
        InterplanetLTX.checkDelayViolation(0L, 0L) == "ok")

    println("── ComputeSegments quantum guard ───────────")
    val planBadQuantum0 = InterplanetLTX.createPlan("Bad Plan", listOf(node1),
        quantum = 0, start = "2024-01-15T14:00:00Z")
    var threw0 = false
    try { InterplanetLTX.computeSegments(planBadQuantum0) } catch (e: IllegalArgumentException) { threw0 = true }
    check("computeSegments quantum=0 throws IllegalArgumentException", threw0)

    val planBadQuantumNeg = InterplanetLTX.createPlan("Bad Plan", listOf(node1),
        quantum = -1, start = "2024-01-15T14:00:00Z")
    var threwNeg = false
    try { InterplanetLTX.computeSegments(planBadQuantumNeg) } catch (e: IllegalArgumentException) { threwNeg = true }
    check("computeSegments quantum=-1 throws IllegalArgumentException", threwNeg)


    println("\n-- Security (Epic 29.1, 29.4, 29.5) --")

    // canonicalJSON
    val dA = mapOf("z" to "last", "a" to "first", "m" to "mid")
    val dB = mapOf("m" to "mid", "z" to "last", "a" to "first")
    val cA = LtxSecurity.canonicalJson(dA)
    val cB = LtxSecurity.canonicalJson(dB)
    check("canonicalJSON: key order normalised", cA == cB)
    check("canonicalJSON: exact output", cA == "{\"a\":\"first\",\"m\":\"mid\",\"z\":\"last\"}")

    // generateNIK
    val nikR = LtxSecurity.generateNik()
    val nik = nikR.nik
    check("generateNIK: nodeId is 16 hex chars", nik.nodeId.length == 16)
    check("generateNIK: nodeId is lowercase hex", nik.nodeId == nik.nodeId.lowercase())
    check("generateNIK: publicKeyB64 set", nik.publicKeyB64.isNotEmpty())
    check("generateNIK: privateKeyB64 set", nikR.privateKeyB64.isNotEmpty())
    check("generateNIK: KeyType=ltx-nik-v1", nik.keyType == "ltx-nik-v1")
    check("generateNIK: validFrom UTC ISO", nik.validFrom.endsWith("Z"))
    check("generateNIK: validUntil UTC ISO", nik.validUntil.endsWith("Z"))
    check("generateNIK: fresh NIK not expired", !LtxSecurity.isNikExpired(nik))
    val nik30 = LtxSecurity.generateNik(validDays = 30, nodeLabel = "test")
    check("generateNIK: nodeLabel set", nik30.nik.nodeLabel == "test")

    // isNIKExpired
    val expiredNik = nik.copy(validUntil = "2020-01-01T00:00:00Z")
    check("isNIKExpired: past date true", LtxSecurity.isNikExpired(expiredNik))
    val futureNik = nik.copy(validUntil = "2099-01-01T00:00:00Z")
    check("isNIKExpired: future date false", !LtxSecurity.isNikExpired(futureNik))

    // signVerifyPlan_valid
    val planData = mapOf("title" to "Test Session", "start" to "2024-01-15T14:00:00Z", "quantum" to 3)
    val signed = LtxSecurity.signPlan(planData, nikR.privateKeyB64)
    check("signPlan: payloadB64 set", signed.payloadB64.isNotEmpty())
    check("signPlan: sig set", signed.sig.isNotEmpty())
    check("signPlan: signerNodeId 16 hex", signed.signerNodeId.length == 16)
    check("signPlan: signerNodeId matches NIK", signed.signerNodeId == nik.nodeId)
    val keyCache = mapOf(nik.nodeId to nik)
    val vOk = LtxSecurity.verifyPlan(signed, keyCache)
    check("verifyPlan: valid returns true", vOk.valid)
    check("verifyPlan: reason null on success", vOk.reason == null)

    // signVerifyPlan_tampered
    val tamperedPlanData = mapOf("title" to "TAMPERED", "start" to "2024-01-15T14:00:00Z", "quantum" to 3)
    val tSigned = SignedPlan(tamperedPlanData, signed.payloadB64, signed.sig, signed.signerNodeId)
    val vTampered = LtxSecurity.verifyPlan(tSigned, keyCache)
    check("verifyPlan tampered: false", !vTampered.valid)
    check("verifyPlan tampered: payload_mismatch", vTampered.reason == "payload_mismatch")

    // signVerifyPlan_wrong_key
    val emptyCache = emptyMap<String, Nik>()
    val vNoKey = LtxSecurity.verifyPlan(signed, emptyCache)
    check("verifyPlan wrong key: false", !vNoKey.valid)
    check("verifyPlan wrong key: key_not_in_cache", vNoKey.reason == "key_not_in_cache")

    // sequenceTracker_replay
    val tracker = LtxSecurity.SequenceTracker()
    val nid = "node-alpha"
    val b1 = tracker.addSeq(mapOf("data" to "first"), nid)
    check("addSeq: first seq=1", b1["seq"] == 1)
    val b2 = tracker.addSeq(mapOf("data" to "x"), nid)
    check("addSeq: second seq=2", b2["seq"] == 2)
    val r1 = tracker.checkSeq(b1, nid)
    check("checkSeq: seq=1 accepted", r1.accepted)
    check("checkSeq: seq=1 no gap", !r1.gap)
    val r1r = tracker.checkSeq(b1, nid)
    check("checkSeq replay: not accepted", !r1r.accepted)
    check("checkSeq replay: reason=replay", r1r.reason == "replay")

    // sequenceTracker_gap
    val tracker2 = LtxSecurity.SequenceTracker()
    val nid2 = "node-beta"
    val bs = (0 until 5).map { i -> tracker2.addSeq(mapOf("i" to i), nid2) }
    val gr1 = tracker2.checkSeq(bs[0], nid2)
    check("checkSeq: seq=1 ok no gap", gr1.accepted && !gr1.gap)
    val gr2 = tracker2.checkSeq(bs[1], nid2)
    check("checkSeq: seq=2 ok no gap", gr2.accepted && !gr2.gap)
    val gr5 = tracker2.checkSeq(bs[4], nid2)
    check("checkSeq gap: seq=5 accepted", gr5.accepted)
    check("checkSeq gap: Gap=true", gr5.gap)
    check("checkSeq gap: GapSize=2", gr5.gapSize == 2)

        println("\n$passed passed  $failed failed")
}
