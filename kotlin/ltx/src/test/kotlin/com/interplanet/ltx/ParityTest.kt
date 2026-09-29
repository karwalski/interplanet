package com.interplanet.ltx

// ParityTest.kt -- LTX parity with javascript/ltx/tests/run.js (issue #27):
// golden planId vectors (spec/golden/plan-ids.json), validatePlan reserved
// streams/branching, createSession enforcement, reduceDecisions and the
// merge_snapshot decisionRegister. Invoked from InterplanetLTXTest.kt main().

import java.io.File

private fun goldenFile(): File {
    val env = System.getenv("LTX_GOLDEN")
    if (env != null) return File(env)
    var dir: File? = File("").absoluteFile
    while (dir != null) {
        val f = File(dir, "spec/golden/plan-ids.json")
        if (f.exists()) return f
        dir = dir.parentFile
    }
    return File("../../spec/golden/plan-ids.json")
}

@Suppress("UNCHECKED_CAST")
private fun asMap(v: Any?) = v as Map<String, Any?>

private fun codesOf(r: PlanValidation) = r.errors.map { it.code }

private fun throwsCode(fn: () -> Unit): String? = try {
    fn(); null
} catch (e: LtxPlanException) { e.code }

private fun with(base: Map<String, Any?>, vararg kv: Pair<String, Any?>): Map<String, Any?> =
    LinkedHashMap(base).apply { kv.forEach { (k, v) -> put(k, v) } }

fun runParityTests() {
    println("── Conformance: golden planId vectors ───────")
    val golden = asMap(LtxJson.parse(goldenFile().readText(Charsets.UTF_8)))
    val vectors = (golden["vectors"] as List<*>).map { asMap(it) }
    check("golden vectors present", vectors.size >= 9)
    for (gv in vectors) {
        val plan = asMap(gv["plan"])
        check("golden planId ${gv["name"]}", LtxPlans.makePlanId(plan) == gv["planId"])
        if (gv.containsKey("planHash")) {
            check("golden planHash ${gv["name"]}", LtxPlans.planHash(plan) == gv["planHash"])
        }
    }
    val byName = vectors.associateBy { it["name"] as String }
    check("golden v2 freeze anchor", byName["v2-freeze-check"]!!["planId"] == "LTX-20260801-EARTHHQ-MARS-v2-d132e85d")
    check("golden v2 unicode anchor", byName["v2-unicode-title"]!!["planId"] == "LTX-20261231-EARTHHQ-MARS-v2-7bc93af8")
    check("golden v2 order-sensitive", byName["v2-createPlan-default"]!!["planId"] != byName["v2-key-order-sensitive"]!!["planId"])
    check("golden v3 order-insensitive", byName["v3-upgrade-delays"]!!["planId"] == byName["v3-key-order-insensitive"]!!["planId"])
    check("golden v3 amendment chain hash",
        asMap(byName["v3-amendment"]!!["plan"])["prevPlanHash"] == byName["v3-upgrade-delays"]!!["planHash"])
    check("default quantum is 5", InterplanetLTX.DEFAULT_QUANTUM == 5 && PlanV11().quantum == 5)
    // Typed v3 plan agrees with the generic path.
    val v3 = asMap(byName["v3-upgrade-delays"]!!["plan"])
    check("typed PlanV11 v3 planId matches golden", LtxV11.makePlanId(PlanV11.fromMap(v3)) == byName["v3-upgrade-delays"]!!["planId"])
    // Typed createPlan with DEFAULT_SEGMENTS: planToJson writes nodes before
    // segments, which is the v2-key-order-sensitive vector's key order.
    val typedDefault = InterplanetLTX.createPlan("Golden Default",
        listOf(LtxNode("N0", "Earth HQ", "HOST", 0, "earth"),
               LtxNode("N1", "Mars Hab-01", "PARTICIPANT", 840, "mars")),
        mode = "LTX", start = "2026-03-15T14:00:00.000Z")
    check("typed createPlan defaults match golden (nodes-first)",
        InterplanetLTX.makePlanId(typedDefault) == byName["v2-key-order-sensitive"]!!["planId"])
    // JSON.stringify escaping and number formatting
    check("stringify escapes control chars", LtxJson.stringify("a\u0001\n\"") == "\"a\\u0001\\n\\\"\"")
    check("stringify lone surrogate escaped", LtxJson.stringify("\ud83d") == "\"\\ud83d\"")
    check("jsNumber formats", LtxJson.jsNumber(1.5) == "1.5" && LtxJson.jsNumber(2.0) == "2" &&
        LtxJson.jsNumber(1e21) == "1e+21" && LtxJson.jsNumber(1e-7) == "1e-7" && LtxJson.jsNumber(0.000001) == "0.000001")

    println("── Plan validation: reserved fields ─────────")
    for (gv in vectors) {
        check("validatePlan accepts golden ${gv["name"]}", LtxPlans.validatePlan(gv["plan"]).valid)
    }
    val vpBase = v3
    check("validatePlan v3 empty streams ok", LtxPlans.validatePlan(with(vpBase, "streams" to emptyList<Any?>())).valid)
    val vpStreams = LtxPlans.validatePlan(with(vpBase, "streams" to listOf(mapOf("id" to "S1"))))
    check("validatePlan non-empty streams", !vpStreams.valid && "reserved_streams" in codesOf(vpStreams))
    check("validatePlan streams error path", vpStreams.errors.first { it.code == "reserved_streams" }.path == "streams")
    check("validatePlan streams non-array", "reserved_streams" in codesOf(LtxPlans.validatePlan(with(vpBase, "streams" to "S1"))))
    val vpSegStream = LtxPlans.validatePlan(with(vpBase, "segments" to listOf(mapOf("type" to "TX", "q" to 1, "stream" to "S1"))))
    check("validatePlan segment stream", "reserved_streams" in codesOf(vpSegStream))
    check("validatePlan branches", "reserved_branching" in codesOf(LtxPlans.validatePlan(with(vpBase, "branches" to emptyList<Any?>()))))
    check("validatePlan branching", "reserved_branching" in codesOf(LtxPlans.validatePlan(with(vpBase, "branching" to mapOf("mode" to "local")))))
    val vpSegBranch = LtxPlans.validatePlan(with(vpBase, "segments" to listOf(mapOf("type" to "CAUCUS", "q" to 1, "branch" to "B1"))))
    check("validatePlan segment branch", "reserved_branching" in codesOf(vpSegBranch) &&
        vpSegBranch.errors[0].path == "segments[0].branch")
    val vpV2 = asMap(byName["v2-freeze-check"]!!["plan"])
    check("validatePlan v2 streams is v3 field", "v3_field_in_v2" in codesOf(LtxPlans.validatePlan(with(vpV2, "streams" to emptyList<Any?>()))))
    check("validatePlan v2 branching", "reserved_branching" in codesOf(LtxPlans.validatePlan(with(vpV2, "branching" to true))))
    check("validatePlan non-object", "not_an_object" in codesOf(LtxPlans.validatePlan(null)))
    check("validatePlan bad version", "invalid_version" in codesOf(LtxPlans.validatePlan(with(vpV2, "v" to 7))))
    check("validatePlan host not first", "invalid_host" in codesOf(LtxPlans.validatePlan(
        with(vpV2, "nodes" to (vpV2["nodes"] as List<*>).reversed()))))
    check("validatePlan unsorted delays key", "invalid_delays" in codesOf(LtxPlans.validatePlan(
        with(vpBase, "delays" to mapOf("N1|N0" to 860)))))
    check("validatePlan unknown speaker", "unknown_speaker" in codesOf(LtxPlans.validatePlan(
        with(vpV2, "segments" to listOf(mapOf("type" to "TX", "q" to 1, "speaker" to "N9"))))))
    check("validatePlan quantum out of range", "invalid_quantum" in codesOf(LtxPlans.validatePlan(with(vpV2, "quantum" to 0))))
    // Enforcement: createSession throws with a code
    check("createSession rejects streams (map)", throwsCode {
        LtxV11.createSession(with(vpBase, "streams" to listOf(1)), "id") } == "reserved_streams")
    check("createSession rejects segment branch (map)", throwsCode {
        LtxV11.createSession(with(vpBase, "segments" to listOf(mapOf("type" to "TX", "q" to 1, "branch" to "B"))), "id") } == "reserved_branching")
    check("createSession rejects branching (map)", throwsCode {
        LtxV11.createSession(with(vpBase, "branching" to mapOf<String, Any?>()), "id") } == "reserved_branching")
    check("createSession accepts golden (map)", throwsCode { LtxV11.createSession(vpBase, "id") } == null)
    check("createSession rejects streams (typed)", throwsCode {
        LtxV11.createSession(PlanV11.fromMap(vpBase).copy(streams = listOf("S1")), "id") } == "reserved_streams")
    check("createSession typed empty streams ok", throwsCode {
        LtxV11.createSession(PlanV11.fromMap(vpBase).copy(streams = emptyList()), "id") } == null)

    println("── Registers: reduceDecisions ───────────────")
    val decHost = LtxSecurity.generateNik(nodeLabel = "HOST")
    val decMars = LtxSecurity.generateNik(nodeLabel = "MARS")
    val decCache = mapOf(
        "N0" to NikV11("N0", decHost.nik.publicKeyB64, decHost.nik.validUntil),
        "N1" to NikV11("N1", decMars.nik.publicKeyB64, decMars.nik.validUntil))
    fun mkDec(type: String, content: Map<String, Any?>, nodeId: String, seq: Int, ts: String, priv: String) =
        LtxV11.createRegisterEntry(type, content, "LTX-DEC-TEST", nodeId, seq, ts, priv)
    val dec1 = mkDec("decision", mapOf("text" to "Proceed with EVA-3", "rationale" to "Weather window", "originWindow" to "W2"),
        "N0", 1, "2026-08-01T12:00:00.000Z", decHost.privateKeyB64)
    check("decision id prefix DEC", dec1.entryId == "DEC-N0-1")
    check("decision entry verifies", LtxV11.verifyRegisterEntry(dec1, decCache).valid)
    val decReg1 = LtxV11.reduceDecisions(listOf(dec1))
    check("decision RECORDED", decReg1.byId["DEC-N0-1"]!!.status == "RECORDED" && decReg1.byId["DEC-N0-1"]!!.version == 1)
    check("decision fields", decReg1.byId["DEC-N0-1"]!!.text == "Proceed with EVA-3" &&
        decReg1.byId["DEC-N0-1"]!!.recordedBy == "N0" && decReg1.byId["DEC-N0-1"]!!.rationale == "Weather window")
    val decRev = mkDec("decision_update", mapOf("did" to "DEC-N0-1", "text" to "Proceed with EVA-3 at 14:00", "version" to 2),
        "N1", 1, "2026-08-01T12:10:00.000Z", decMars.privateKeyB64)
    val decRes = mkDec("decision_update", mapOf("did" to "DEC-N0-1", "status" to "RESCINDED", "version" to 3),
        "N0", 2, "2026-08-01T12:20:00.000Z", decHost.privateKeyB64)
    val decReg2 = LtxV11.reduceDecisions(listOf(decRes, dec1, decRev))
    check("decision update applied", decReg2.byId["DEC-N0-1"]!!.text == "Proceed with EVA-3 at 14:00")
    check("decision RESCINDED v3", decReg2.byId["DEC-N0-1"]!!.status == "RESCINDED" && decReg2.byId["DEC-N0-1"]!!.version == 3)
    check("decision editor recorded", decReg2.byId["DEC-N0-1"]!!.editor == "N0")
    check("decision older update superseded", decRev.entryId in decReg2.superseded)
    val decA = mkDec("decision_update", mapOf("did" to "DEC-N0-1", "text" to "From N0", "version" to 5), "N0", 7, "2026-08-01T13:00:00.000Z", decHost.privateKeyB64)
    val decB = mkDec("decision_update", mapOf("did" to "DEC-N0-1", "text" to "From N1", "version" to 5), "N1", 7, "2026-08-01T13:00:00.000Z", decMars.privateKeyB64)
    val decConf1 = LtxV11.reduceDecisions(listOf(dec1, decB, decA))
    val decConf2 = LtxV11.reduceDecisions(listOf(decA, dec1, decB))
    check("decision tie lowest nodeId wins", decConf1.byId["DEC-N0-1"]!!.text == "From N0")
    check("decision tie loser superseded", decB.entryId in decConf1.superseded && decA.entryId !in decConf1.superseded)
    check("decision reduce order-independent", decConf1 == decConf2)
    val decHi = mkDec("decision_update", mapOf("did" to "DEC-N0-1", "text" to "N1 v6", "version" to 6), "N1", 8, "2026-08-01T12:30:00.000Z", decMars.privateKeyB64)
    check("decision higher version wins", LtxV11.reduceDecisions(listOf(dec1, decA, decHi)).byId["DEC-N0-1"]!!.text == "N1 v6")
    val decOrphan = mkDec("decision_update", mapOf("did" to "DEC-NOPE-1", "version" to 2), "N1", 9, "2026-08-01T12:40:00.000Z", decMars.privateKeyB64)
    val decDup = LtxV11.createRegisterEntry("decision", mapOf("text" to "dup"), "LTX-DEC-TEST", "N1", 10,
        "2026-08-01T12:50:00.000Z", decMars.privateKeyB64, entryId = "DEC-N0-1")
    val decReg3 = LtxV11.reduceDecisions(listOf(dec1, decOrphan, decDup))
    check("decision orphan update superseded", "DEC-N1-9" in decReg3.superseded)
    check("decision duplicate create ignored", decReg3.byId["DEC-N0-1"]!!.text == "Proceed with EVA-3" && decReg3.byId["DEC-N0-1"]!!.recordedBy == "N0")
    check("decision reducer ignores others", LtxV11.reduceDecisions(listOf(dec1, decRev)).byId.size == 1 &&
        LtxV11.reduceActions(listOf(dec1)).byId.isEmpty())
    val decSnap = LtxV11.runMergeSegment(listOf(dec1), listOf(decRev), decCache,
        "LTX-DEC-TEST", "N0", 99, "2026-08-01T15:00:00.000Z", decHost.privateKeyB64)
    val decRegister = asMap(decSnap.snapshot.content["decisionRegister"])
    check("snapshot decisionRegister", asMap(decRegister["DEC-N0-1"])["version"] == 2)
    check("snapshot entry type and id", decSnap.snapshot.type == "merge_snapshot" && decSnap.snapshot.entryId == "MRG-N0-99")
    check("snapshot signature verifies", LtxV11.verifyRegisterEntry(decSnap.snapshot, decCache).valid)
    check("snapshot counts", decSnap.snapshot.content["entryCount"] == 2 && decSnap.snapshot.content["rejectedCount"] == 0)
}
