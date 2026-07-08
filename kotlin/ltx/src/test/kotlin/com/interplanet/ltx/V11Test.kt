package com.interplanet.ltx

// V11Test.kt -- Epic 72 (Story 72.3): LTX v1.1 core subset conformance tests.
// Golden constants embedded from conformance/vectors.json (.v11 section).
// Invoked from InterplanetLTXTest.kt main().

private const val NODE_ID = "Vkdap1RjR0wChd9dvyvKtw"
private const val PUBLIC_KEY = "A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg"
private const val VALID_UNTIL = "2046-01-01T00:00:00.000Z"

private const val EXPECTED_PLAN_ID_V3 = "LTX-20400201-EARTHHQ-MARS-LUNA-v3-a6120a8d"
private const val EXPECTED_PLAN_ID_V2 = "LTX-20400201-EARTHHQ-MARS-LUNA-v2-3471002b"
private const val EXPECTED_SHA256 = "a6120a8db075fb40de472c30c8afcce6c8635f829621723e6855769641b1b028"
private const val ROOT_PLAN_HASH = "58710a510afe517cbd2ed014a3fc5c33d48b9ba26cc59d7ab75613528fa9411f"
private const val EXPECTED_ENTRIES_ROOT = "1ab1318b96825b442e6d2a43bebc11a909bc8bcf775055542a54c2faa1b96f3d"

private const val PROTECTED = "eyJhbGciOi0xOX0"
private const val ROOT_PAYLOAD = "eyJtb2RlIjoiTFRYLUFTWU5DIiwibm9kZXMiOlt7ImRlbGF5IjowLCJpZCI6Ik4wIiwibG9jYXRpb24iOiJlYXJ0aCIsIm5hbWUiOiJFYXJ0aCBIUSIsInJvbGUiOiJIT1NUIn0seyJkZWxheSI6OTAwLCJpZCI6Ik4xIiwibG9jYXRpb24iOiJtYXJzIiwibmFtZSI6Ik1hcnMgSGFiIiwicm9sZSI6IlBBUlRJQ0lQQU5UIn0seyJkZWxheSI6MiwiaWQiOiJOMiIsImxvY2F0aW9uIjoibW9vbiIsIm5hbWUiOiJMdW5hIEJhc2UiLCJyb2xlIjoiUEFSVElDSVBBTlQifV0sInF1YW50dW0iOjUsInNlZ21lbnRzIjpbeyJxIjoyLCJ0eXBlIjoiUExBTl9DT05GSVJNIn0seyJsYWJlbCI6Ik9wZW5pbmciLCJxIjozLCJzcGVha2VyIjoiTjAiLCJ0eXBlIjoiVFgifSx7ImxhYmVsIjoiTWFycyBSZXBvcnQiLCJxIjozLCJzcGVha2VyIjoiTjEiLCJ0eXBlIjoiVFgifSx7InEiOjIsInR5cGUiOiJNRVJHRSJ9XSwic3RhcnQiOiIyMDQwLTAyLTAxVDEyOjAwOjAwLjAwMFoiLCJ0aXRsZSI6IlZlY3RvciBTdW1taXQiLCJ2IjoyfQ"
private const val ROOT_SIG = "2zHRgtxRFQvcNfj-XPFtqB0qg-Ipbx0CsmxgKK9zWCguMfvVADHdEYQtE1ko5z2fZnxd2MPVrx6FrFsww5hgAw"
private const val AMD_PAYLOAD = "eyJtb2RlIjoiTFRYLUFTWU5DIiwibm9kZXMiOlt7ImRlbGF5IjowLCJpZCI6Ik4wIiwibG9jYXRpb24iOiJlYXJ0aCIsIm5hbWUiOiJFYXJ0aCBIUSIsInJvbGUiOiJIT1NUIn0seyJkZWxheSI6OTAwLCJpZCI6Ik4xIiwibG9jYXRpb24iOiJtYXJzIiwibmFtZSI6Ik1hcnMgSGFiIiwicm9sZSI6IlBBUlRJQ0lQQU5UIn0seyJkZWxheSI6MiwiaWQiOiJOMiIsImxvY2F0aW9uIjoibW9vbiIsIm5hbWUiOiJMdW5hIEJhc2UiLCJyb2xlIjoiUEFSVElDSVBBTlQifV0sInBsYW5WZXJzaW9uIjoyLCJwcmV2UGxhbkhhc2giOiI1ODcxMGE1MTBhZmU1MTdjYmQyZWQwMTRhM2ZjNWMzM2Q0OGI5YmEyNmNjNTlkN2FiNzU2MTM1MjhmYTk0MTFmIiwicXVhbnR1bSI6NSwic2VnbWVudHMiOlt7InEiOjIsInR5cGUiOiJQTEFOX0NPTkZJUk0ifSx7ImxhYmVsIjoiT3BlbmluZyIsInEiOjMsInNwZWFrZXIiOiJOMCIsInR5cGUiOiJUWCJ9LHsibGFiZWwiOiJNYXJzIFJlcG9ydCIsInEiOjMsInNwZWFrZXIiOiJOMSIsInR5cGUiOiJUWCJ9LHsicSI6MiwidHlwZSI6Ik1FUkdFIn1dLCJzdGFydCI6IjIwNDAtMDItMDFUMTI6MDA6MDAuMDAwWiIsInRpdGxlIjoiVmVjdG9yIFN1bW1pdCAoYW1lbmRlZCkiLCJ2IjozfQ"
private const val AMD_SIG = "_LfyAbDXQf-0ayJeC8-Tif9PNGMxiTHoCCYOz9C9Oa5Hg0I5GHZSa6c-HiYdOnFBkBgCr4TrrUGoJ_bKUrc7AA"

private const val ENTRY1_SIG = "-_CozI8Uz_sCodjoOab097slBkYttOnE-3jY8-MXbBPYk_B5CUP-Xem4Xz1BSokXVzoQAUP15_CWMi8oHACvDw"
private const val ENTRY2_SIG = "uvMUnPlkMCKqjpU4MPuBBQXq1O7oEKs4tUaDQHTu50G8CX4NjyeJ8cX65Ot23rVer3Ea1VrIFrEq7lKWCNz8DA"

private const val COSE_SIGN1_CBOR_B64 =
    "0oRDoQEyoQRQVkdap1RjR0wChd9dvyvKt1kCBXsibW9kZSI6IkxUWC1BU1lOQyIsIm5vZGVzIjpbeyJkZWxheSI6MCwiaWQiOiJO" +
    "MCIsImxvY2F0aW9uIjoiZWFydGgiLCJuYW1lIjoiRWFydGggSFEiLCJyb2xlIjoiSE9TVCJ9LHsiZGVsYXkiOjkwMCwiaWQiOiJO" +
    "MSIsImxvY2F0aW9uIjoibWFycyIsIm5hbWUiOiJNYXJzIEhhYiIsInJvbGUiOiJQQVJUSUNJUEFOVCJ9LHsiZGVsYXkiOjIsImlk" +
    "IjoiTjIiLCJsb2NhdGlvbiI6Im1vb24iLCJuYW1lIjoiTHVuYSBCYXNlIiwicm9sZSI6IlBBUlRJQ0lQQU5UIn1dLCJxdWFudHVt" +
    "Ijo1LCJzZWdtZW50cyI6W3sicSI6MiwidHlwZSI6IlBMQU5fQ09ORklSTSJ9LHsibGFiZWwiOiJPcGVuaW5nIiwicSI6Mywic3Bl" +
    "YWtlciI6Ik4wIiwidHlwZSI6IlRYIn0seyJsYWJlbCI6Ik1hcnMgUmVwb3J0IiwicSI6Mywic3BlYWtlciI6Ik4xIiwidHlwZSI6" +
    "IlRYIn0seyJxIjoyLCJ0eXBlIjoiTUVSR0UifV0sInN0YXJ0IjoiMjA0MC0wMi0wMVQxMjowMDowMC4wMDBaIiwidGl0bGUiOiJW" +
    "ZWN0b3IgU3VtbWl0IiwidiI6Mn1YQNDg5fHexnBLnLbQ5eCoVQfGOlbfhyXYx0xD4Q42Kh8T-FgyPhB_2-QrwEuvYgmZHnDGwfzj" +
    "oxnAI_NVLJE2XQI"

private fun vectorPlanV2() = PlanV11(
    v = 2, title = "Vector Summit", start = "2040-02-01T12:00:00.000Z",
    quantum = 5, mode = "LTX-ASYNC",
    nodes = listOf(
        NodeV11("N0", "Earth HQ", "HOST", 0, "earth"),
        NodeV11("N1", "Mars Hab", "PARTICIPANT", 900, "mars"),
        NodeV11("N2", "Luna Base", "PARTICIPANT", 2, "moon")),
    segments = listOf(
        SegmentTemplateV11("PLAN_CONFIRM", 2),
        SegmentTemplateV11("TX", 3, speaker = "N0", label = "Opening"),
        SegmentTemplateV11("TX", 3, speaker = "N1", label = "Mars Report"),
        SegmentTemplateV11("MERGE", 2)))

private fun vectorPlanV3() = vectorPlanV2().copy(
    v = 3, delays = mapOf("N1|N2" to 500L), planVersion = 1)

private fun amendedPlan() = vectorPlanV2().copy(
    v = 3, title = "Vector Summit (amended)",
    planVersion = 2, prevPlanHash = ROOT_PLAN_HASH)

fun runV11Tests() {
    println("── LTX v1.1 core subset (Epic 72) ───────────")
    val nik = NikV11(NODE_ID, PUBLIC_KEY, VALID_UNTIL)
    val kidCache = mapOf(NODE_ID to nik)
    val emptyCache = emptyMap<String, NikV11>()
    val planV2 = vectorPlanV2()
    val planV3 = vectorPlanV3()

    // ---- 1a/1b. plan ids ----
    check("v11 planIdV3: canonical SHA-256 matches", LtxV11.planHash(planV3) == EXPECTED_SHA256)
    check("v11 planIdV3: expected plan id", LtxV11.makePlanId(planV3) == EXPECTED_PLAN_ID_V3)
    check("v11 planIdV2: FROZEN v2 hash unchanged", LtxV11.makePlanId(planV2) == EXPECTED_PLAN_ID_V2)

    // ---- 1c. pairDelay ----
    check("v11 pairDelay: N0|N1 = 900", LtxV11.pairDelay(planV3, "N0", "N1") == 900L)
    check("v11 pairDelay: N1|N0 symmetric", LtxV11.pairDelay(planV3, "N1", "N0") == 900L)
    check("v11 pairDelay: v3 matrix N1|N2 = 500", LtxV11.pairDelay(planV3, "N1", "N2") == 500L)
    check("v11 pairDelay: matrix symmetric", LtxV11.pairDelay(planV3, "N2", "N1") == 500L)
    check("v11 pairDelay: same node = 0", LtxV11.pairDelay(planV3, "N1", "N1") == 0L)
    check("v11 pairDelay: conservative fallback 902", LtxV11.pairDelay(planV2, "N1", "N2") == 902L)

    // ---- 1d. computeSegmentsFor ----
    val baseSegs = LtxV11.computeSegmentsV11(planV3)
    val forN0 = LtxV11.computeSegmentsFor(planV3, "N0")
    val forN1 = LtxV11.computeSegmentsFor(planV3, "N1")
    val forN2 = LtxV11.computeSegmentsFor(planV3, "N2")
    check("v11 segmentsFor: 4 segments", forN2.size == 4)
    check("v11 segmentsFor: PLAN_CONFIRM neutral",
        forN2[0].perspective == "neutral" && forN2[0].arrivalOffsetS == 0L)
    check("v11 segmentsFor: own TX is transmit",
        forN0[1].perspective == "transmit" && forN0[1].arrivalOffsetS == 0L)
    check("v11 segmentsFor: N0 TX arrives at N2 +2s",
        forN2[1].perspective == "receive" && forN2[1].arrivalOffsetS == 2L)
    check("v11 segmentsFor: start shifted by pair delay",
        forN2[1].startMs == baseSegs[1].startMs + 2000L)
    check("v11 segmentsFor: N1 TX arrives at N2 +500s (v3 matrix)",
        forN2[2].perspective == "receive" && forN2[2].arrivalOffsetS == 500L)
    check("v11 segmentsFor: N0 TX arrives at N1 +900s",
        forN1[1].arrivalOffsetS == 900L && forN1[1].endMs == baseSegs[1].endMs + 900000L)
    check("v11 segmentsFor: MERGE neutral", forN0[3].perspective == "neutral")
    val unknownViewerThrew = try {
        LtxV11.computeSegmentsFor(planV3, "NX"); false
    } catch (_: IllegalArgumentException) { true }
    check("v11 segmentsFor: unknown viewer throws", unknownViewerThrew)

    // ---- 3. amendment chain ----
    val chain = listOf(
        SignedPlanV11(planV2, CoseSign1Json(PROTECTED, NODE_ID, ROOT_PAYLOAD, ROOT_SIG)),
        SignedPlanV11(amendedPlan(), CoseSign1Json(PROTECTED, NODE_ID, AMD_PAYLOAD, AMD_SIG)))
    check("v11 amend: root plan hash matches", LtxV11.planHash(planV2) == ROOT_PLAN_HASH)
    check("v11 amend: root signature valid", LtxV11.verifyPlanEnvelope(chain[0], kidCache).valid)
    check("v11 amend: amendment signature valid", LtxV11.verifyPlanEnvelope(chain[1], kidCache).valid)
    check("v11 amend: chain verifies", LtxV11.verifyAmendmentChain(chain, kidCache).valid)
    val tampered = listOf(chain[0], chain[1].copy(plan = chain[1].plan.copy(title = "EVIL")))
    val tv = LtxV11.verifyAmendmentChain(tampered, kidCache)
    check("v11 amend: tampered title rejected", !tv.valid)
    check("v11 amend: tamper reason payload_mismatch", tv.reason == "link_1_payload_mismatch")
    check("v11 amend: empty chain invalid", !LtxV11.verifyAmendmentChain(emptyList(), kidCache).valid)
    check("v11 amend: unknown key rejected", !LtxV11.verifyAmendmentChain(chain, emptyCache).valid)

    // ---- 4. register entries + reducers ----
    val entry1 = RegisterEntryV11(
        "QST-N1-1", "VEC-SESSION", "N1", 1, "question",
        mapOf("text" to "Status?", "urgency" to "high"),
        "2040-02-01T11:00:00.000Z", ENTRY1_SIG)
    val entry2 = RegisterEntryV11(
        "QST-N0-1", "VEC-SESSION", "N0", 1, "question_response",
        mapOf("qid" to "QST-N1-1", "response" to "Nominal", "version" to 2),
        "2040-02-01T11:05:00.000Z", ENTRY2_SIG)
    val nodeCache = mapOf("N0" to nik, "N1" to nik)

    check("v11 registers: entry 1 signature valid", LtxV11.verifyRegisterEntry(entry1, nodeCache).valid)
    check("v11 registers: entry 2 signature valid", LtxV11.verifyRegisterEntry(entry2, nodeCache).valid)
    check("v11 registers: tampered entry rejected",
        !LtxV11.verifyRegisterEntry(entry1.copy(seq = 9), nodeCache).valid)
    check("v11 registers: unknown node key rejected",
        !LtxV11.verifyRegisterEntry(entry1, emptyCache).valid)

    val ordered = LtxV11.orderEntries(listOf(entry2, entry1, entry1))
    check("v11 registers: dedup + (timestamp,nodeId,seq) order",
        ordered.size == 2 && ordered[0].entryId == "QST-N1-1")

    val red = LtxV11.reduceQuestions(listOf(entry2, entry1))
    check("v11 registers: reduceQuestions single question", red.byId.size == 1)
    val q = red.byId["QST-N1-1"]
    check("v11 registers: question state matches expectedQuestionState",
        q != null && q.qid == "QST-N1-1" && q.text == "Status?" && q.submitter == "N1" &&
        q.urgency == "high" && q.status == "ANSWERED" && q.version == 2 &&
        q.response == "Nominal" && q.responder == "N0")
    check("v11 registers: nothing superseded", red.superseded.isEmpty())

    check("v11 registers: entriesRoot Merkle root matches",
        LtxV11.entriesRoot(ordered) == EXPECTED_ENTRIES_ROOT)

    // action reducer sanity (no golden vector -- semantics per §10.2)
    val act1 = RegisterEntryV11("ACT-N1-2", "VEC-SESSION", "N1", 2, "action",
        mapOf("description" to "Fix antenna"), "2040-02-01T11:10:00.000Z", "x")
    val act2 = RegisterEntryV11("ACT-N0-2", "VEC-SESSION", "N0", 2, "action_update",
        mapOf("aid" to "ACT-N1-2", "status" to "ACCEPTED", "version" to 2),
        "2040-02-01T11:11:00.000Z", "x")
    val ar = LtxV11.reduceActions(listOf(act2, act1))
    val act = ar.byId["ACT-N1-2"]
    check("v11 registers: reduceActions applies update",
        act != null && act.status == "ACCEPTED" && act.version == 2)

    // ---- 5. CBOR + COSE_Sign1 ----
    val coseBytes = LtxSecurity.fromBase64Url(COSE_SIGN1_CBOR_B64)
    val decoded = LtxV11.decodeCbor(coseBytes)
    check("v11 cose: decodes to tag 18",
        decoded is CborTagV11 && decoded.tag == 18L && (decoded.value as? List<*>)?.size == 4)
    check("v11 cose: COSE_Sign1 verifies against plan + key",
        LtxV11.verifyPlanCose(planV2, COSE_SIGN1_CBOR_B64, kidCache).valid)
    check("v11 cose: mismatched plan rejected",
        !LtxV11.verifyPlanCose(planV2.copy(title = "EVIL"), COSE_SIGN1_CBOR_B64, kidCache).valid)
    check("v11 cose: unknown kid rejected",
        !LtxV11.verifyPlanCose(planV2, COSE_SIGN1_CBOR_B64, emptyCache).valid)
    val truncatedB64 = LtxSecurity.toBase64Url(coseBytes.copyOfRange(0, coseBytes.size - 1))
    check("v11 cose: truncated CBOR rejected",
        !LtxV11.verifyPlanCose(planV2, truncatedB64, kidCache).valid)
    val floatRejected = try {
        LtxV11.decodeCbor(byteArrayOf(0xf9.toByte(), 0x3c, 0x00)); false
    } catch (_: CborException) { true }
    check("v11 cbor: floats rejected", floatRejected)
    val trailingRejected = try {
        LtxV11.decodeCbor(byteArrayOf(0x01, 0x02)); false
    } catch (_: CborException) { true }
    check("v11 cbor: trailing bytes rejected", trailingRejected)
    check("v11 cbor: uint decode", LtxV11.decodeCbor(byteArrayOf(0x18, 0x2a)) == 42L)
    check("v11 cbor: negative int decode", LtxV11.decodeCbor(byteArrayOf(0x20)) == -1L)

    // ---- 2. session state machine (golden transition table) ----
    var ctx = LtxV11.createSession(planV2, EXPECTED_PLAN_ID_V2, 1)
    check("v11 session: starts DRAFT", ctx.state == "DRAFT" && ctx.lock == null)
    check("v11 session: lock timeout 2x900s", ctx.lockTimeoutMs == 1800000L)
    check("v11 session: quorum threshold 1", ctx.quorumThreshold == 1)

    data class Step(val ev: SessionEventV11, val state: String, val lock: String?)
    val steps = listOf(
        Step(SessionEventV11("START_LOCK", 1000), "LOCKING", null),
        Step(SessionEventV11("PLAN_CONFIRM", 2000, nodeId = "N2", planId = EXPECTED_PLAN_ID_V2), "LOCKING", null),
        Step(SessionEventV11("TICK", 1800999), "LOCKING", null),
        Step(SessionEventV11("TICK", 1801000), "DEGRADED", "QUORUM"),
        Step(SessionEventV11("PLAN_CONFIRM", 4000000, nodeId = "N1", planId = EXPECTED_PLAN_ID_V2), "LOCKED", "FULL"),
        Step(SessionEventV11("SESSION_START", 4100000), "ACTIVE", "FULL"),
        Step(SessionEventV11("DELAY_MEASURED", 4200000, nodeId = "N1", measuredDelayS = 1201), "DEGRADED", "FULL"),
        Step(SessionEventV11("HOST_DECISION", 4300000, decision = "continue"), "ACTIVE", "FULL"),
        Step(SessionEventV11("SESSION_END", 5000000), "COMPLETE", "FULL"))

    var quorumSubset: List<String>? = null
    steps.forEachIndexed { i, step ->
        ctx = LtxV11.transition(ctx, step.ev)
        if (ctx.lock == "QUORUM" && quorumSubset == null) quorumSubset = ctx.subset
        check("v11 session step $i: ${step.ev.type} -> state ${step.state}", ctx.state == step.state)
        check("v11 session step $i: ${step.ev.type} -> lock ${step.lock}", ctx.lock == step.lock)
    }
    check("v11 session: quorum subset [N0,N2] (ascending delay)",
        quorumSubset == listOf("N0", "N2"))
    check("v11 session: subset cleared on full-lock recovery", ctx.subset == null)

    // extra machine coverage: abort / emergency hold / amendments
    var ctx2 = LtxV11.createSession(planV2, EXPECTED_PLAN_ID_V2, "all")
    check("v11 session: quorum 'all' = 2 participants", ctx2.quorumThreshold == 2)
    ctx2 = LtxV11.transition(ctx2, SessionEventV11("START_LOCK", 0))
    ctx2 = LtxV11.transition(ctx2, SessionEventV11("HOST_DECISION", 1, decision = "abort"))
    check("v11 session: host abort", ctx2.state == "ABORTED")

    var ctx3 = LtxV11.createSession(planV2, EXPECTED_PLAN_ID_V2, "majority")
    check("v11 session: majority of 2 = 2", ctx3.quorumThreshold == 2)
    ctx3 = LtxV11.transition(ctx3, SessionEventV11("START_LOCK", 0))
    ctx3 = LtxV11.transition(ctx3, SessionEventV11("PLAN_CONFIRM", 1, nodeId = "N1", planId = EXPECTED_PLAN_ID_V2))
    ctx3 = LtxV11.transition(ctx3, SessionEventV11("PLAN_CONFIRM", 2, nodeId = "N2", planId = EXPECTED_PLAN_ID_V2))
    check("v11 session: full lock on all confirms", ctx3.state == "LOCKED" && ctx3.lock == "FULL")
    ctx3 = LtxV11.transition(ctx3, SessionEventV11("SESSION_START", 3))
    ctx3 = LtxV11.transition(ctx3, SessionEventV11("EOK_OVERRIDE", 4, verified = true))
    check("v11 session: verified EOK override holds", ctx3.state == "EMERGENCY_HOLD")
    ctx3 = LtxV11.transition(ctx3, SessionEventV11("HOST_DECISION", 5, decision = "resume"))
    check("v11 session: resume returns to prior state", ctx3.state == "ACTIVE")
    ctx3 = LtxV11.transition(ctx3, SessionEventV11("AMENDMENT_PROPOSED", 6,
        planId = "LTX-AMENDED", planVersion = 2, affectedNodeIds = listOf("N1")))
    check("v11 session: amendment pending", ctx3.pendingAmendment != null)
    ctx3 = LtxV11.transition(ctx3, SessionEventV11("AMENDMENT_CONFIRMED", 7,
        nodeId = "N1", planId = "LTX-AMENDED"))
    check("v11 session: amendment applied after all confirms",
        ctx3.planId == "LTX-AMENDED" && ctx3.planVersion == 2 && ctx3.pendingAmendment == null)

    var ctx4 = LtxV11.createSession(planV2, EXPECTED_PLAN_ID_V2, "all")
    ctx4 = LtxV11.transition(ctx4, SessionEventV11("START_LOCK", 0))
    ctx4 = LtxV11.transition(ctx4, SessionEventV11("PLAN_CONFIRM", 1, nodeId = "N1", planId = "LTX-WRONG"))
    check("v11 session: planId mismatch flagged (§5.5)",
        ctx4.state == "LOCKING" && "N1" in ctx4.mismatched)

    // ---- version ----
    check("v11 VERSION is 1.1.0", LtxV11.VERSION == "1.1.0")
}
