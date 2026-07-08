/**
 * V11Test.scala -- Epic 72 (Story 72.3): LTX v1.1 core subset conformance tests.
 * Golden constants embedded from conformance/vectors.json (.v11 section).
 */

import V11.*

object V11Test:
  var passed = 0
  var failed = 0

  def check(label: String, cond: Boolean): Unit =
    if cond then passed += 1
    else { failed += 1; println(s"FAIL: $label") }

  // ---- golden vector constants (conformance/vectors.json .v11) ----

  val NODE_ID = "Vkdap1RjR0wChd9dvyvKtw"
  val PUBLIC_KEY = "A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg"
  val VALID_UNTIL = "2046-01-01T00:00:00.000Z"

  val EXPECTED_PLAN_ID_V3 = "LTX-20400201-EARTHHQ-MARS-LUNA-v3-a6120a8d"
  val EXPECTED_PLAN_ID_V2 = "LTX-20400201-EARTHHQ-MARS-LUNA-v2-3471002b"
  val EXPECTED_SHA256 = "a6120a8db075fb40de472c30c8afcce6c8635f829621723e6855769641b1b028"
  val ROOT_PLAN_HASH = "58710a510afe517cbd2ed014a3fc5c33d48b9ba26cc59d7ab75613528fa9411f"
  val EXPECTED_ENTRIES_ROOT = "1ab1318b96825b442e6d2a43bebc11a909bc8bcf775055542a54c2faa1b96f3d"

  val PROTECTED = "eyJhbGciOi0xOX0"
  val ROOT_PAYLOAD = "eyJtb2RlIjoiTFRYLUFTWU5DIiwibm9kZXMiOlt7ImRlbGF5IjowLCJpZCI6Ik4wIiwibG9jYXRpb24iOiJlYXJ0aCIsIm5hbWUiOiJFYXJ0aCBIUSIsInJvbGUiOiJIT1NUIn0seyJkZWxheSI6OTAwLCJpZCI6Ik4xIiwibG9jYXRpb24iOiJtYXJzIiwibmFtZSI6Ik1hcnMgSGFiIiwicm9sZSI6IlBBUlRJQ0lQQU5UIn0seyJkZWxheSI6MiwiaWQiOiJOMiIsImxvY2F0aW9uIjoibW9vbiIsIm5hbWUiOiJMdW5hIEJhc2UiLCJyb2xlIjoiUEFSVElDSVBBTlQifV0sInF1YW50dW0iOjUsInNlZ21lbnRzIjpbeyJxIjoyLCJ0eXBlIjoiUExBTl9DT05GSVJNIn0seyJsYWJlbCI6Ik9wZW5pbmciLCJxIjozLCJzcGVha2VyIjoiTjAiLCJ0eXBlIjoiVFgifSx7ImxhYmVsIjoiTWFycyBSZXBvcnQiLCJxIjozLCJzcGVha2VyIjoiTjEiLCJ0eXBlIjoiVFgifSx7InEiOjIsInR5cGUiOiJNRVJHRSJ9XSwic3RhcnQiOiIyMDQwLTAyLTAxVDEyOjAwOjAwLjAwMFoiLCJ0aXRsZSI6IlZlY3RvciBTdW1taXQiLCJ2IjoyfQ"
  val ROOT_SIG = "2zHRgtxRFQvcNfj-XPFtqB0qg-Ipbx0CsmxgKK9zWCguMfvVADHdEYQtE1ko5z2fZnxd2MPVrx6FrFsww5hgAw"
  val AMD_PAYLOAD = "eyJtb2RlIjoiTFRYLUFTWU5DIiwibm9kZXMiOlt7ImRlbGF5IjowLCJpZCI6Ik4wIiwibG9jYXRpb24iOiJlYXJ0aCIsIm5hbWUiOiJFYXJ0aCBIUSIsInJvbGUiOiJIT1NUIn0seyJkZWxheSI6OTAwLCJpZCI6Ik4xIiwibG9jYXRpb24iOiJtYXJzIiwibmFtZSI6Ik1hcnMgSGFiIiwicm9sZSI6IlBBUlRJQ0lQQU5UIn0seyJkZWxheSI6MiwiaWQiOiJOMiIsImxvY2F0aW9uIjoibW9vbiIsIm5hbWUiOiJMdW5hIEJhc2UiLCJyb2xlIjoiUEFSVElDSVBBTlQifV0sInBsYW5WZXJzaW9uIjoyLCJwcmV2UGxhbkhhc2giOiI1ODcxMGE1MTBhZmU1MTdjYmQyZWQwMTRhM2ZjNWMzM2Q0OGI5YmEyNmNjNTlkN2FiNzU2MTM1MjhmYTk0MTFmIiwicXVhbnR1bSI6NSwic2VnbWVudHMiOlt7InEiOjIsInR5cGUiOiJQTEFOX0NPTkZJUk0ifSx7ImxhYmVsIjoiT3BlbmluZyIsInEiOjMsInNwZWFrZXIiOiJOMCIsInR5cGUiOiJUWCJ9LHsibGFiZWwiOiJNYXJzIFJlcG9ydCIsInEiOjMsInNwZWFrZXIiOiJOMSIsInR5cGUiOiJUWCJ9LHsicSI6MiwidHlwZSI6Ik1FUkdFIn1dLCJzdGFydCI6IjIwNDAtMDItMDFUMTI6MDA6MDAuMDAwWiIsInRpdGxlIjoiVmVjdG9yIFN1bW1pdCAoYW1lbmRlZCkiLCJ2IjozfQ"
  val AMD_SIG = "_LfyAbDXQf-0ayJeC8-Tif9PNGMxiTHoCCYOz9C9Oa5Hg0I5GHZSa6c-HiYdOnFBkBgCr4TrrUGoJ_bKUrc7AA"

  val ENTRY1_SIG = "-_CozI8Uz_sCodjoOab097slBkYttOnE-3jY8-MXbBPYk_B5CUP-Xem4Xz1BSokXVzoQAUP15_CWMi8oHACvDw"
  val ENTRY2_SIG = "uvMUnPlkMCKqjpU4MPuBBQXq1O7oEKs4tUaDQHTu50G8CX4NjyeJ8cX65Ot23rVer3Ea1VrIFrEq7lKWCNz8DA"

  val COSE_SIGN1_CBOR_B64 =
    "0oRDoQEyoQRQVkdap1RjR0wChd9dvyvKt1kCBXsibW9kZSI6IkxUWC1BU1lOQyIsIm5vZGVzIjpbeyJkZWxheSI6MCwiaWQiOiJO" +
    "MCIsImxvY2F0aW9uIjoiZWFydGgiLCJuYW1lIjoiRWFydGggSFEiLCJyb2xlIjoiSE9TVCJ9LHsiZGVsYXkiOjkwMCwiaWQiOiJO" +
    "MSIsImxvY2F0aW9uIjoibWFycyIsIm5hbWUiOiJNYXJzIEhhYiIsInJvbGUiOiJQQVJUSUNJUEFOVCJ9LHsiZGVsYXkiOjIsImlk" +
    "IjoiTjIiLCJsb2NhdGlvbiI6Im1vb24iLCJuYW1lIjoiTHVuYSBCYXNlIiwicm9sZSI6IlBBUlRJQ0lQQU5UIn1dLCJxdWFudHVt" +
    "Ijo1LCJzZWdtZW50cyI6W3sicSI6MiwidHlwZSI6IlBMQU5fQ09ORklSTSJ9LHsibGFiZWwiOiJPcGVuaW5nIiwicSI6Mywic3Bl" +
    "YWtlciI6Ik4wIiwidHlwZSI6IlRYIn0seyJsYWJlbCI6Ik1hcnMgUmVwb3J0IiwicSI6Mywic3BlYWtlciI6Ik4xIiwidHlwZSI6" +
    "IlRYIn0seyJxIjoyLCJ0eXBlIjoiTUVSR0UifV0sInN0YXJ0IjoiMjA0MC0wMi0wMVQxMjowMDowMC4wMDBaIiwidGl0bGUiOiJW" +
    "ZWN0b3IgU3VtbWl0IiwidiI6Mn1YQNDg5fHexnBLnLbQ5eCoVQfGOlbfhyXYx0xD4Q42Kh8T-FgyPhB_2-QrwEuvYgmZHnDGwfzj" +
    "oxnAI_NVLJE2XQI"

  // ---- plan builders ----

  def vectorPlanV2: PlanV11 = PlanV11(
    v = 2, title = "Vector Summit", start = "2040-02-01T12:00:00.000Z",
    quantum = 5, mode = "LTX-ASYNC",
    nodes = List(
      NodeV11("N0", "Earth HQ", "HOST", 0, "earth"),
      NodeV11("N1", "Mars Hab", "PARTICIPANT", 900, "mars"),
      NodeV11("N2", "Luna Base", "PARTICIPANT", 2, "moon")),
    segments = List(
      SegV11("PLAN_CONFIRM", 2),
      SegV11("TX", 3, speaker = Some("N0"), label = Some("Opening")),
      SegV11("TX", 3, speaker = Some("N1"), label = Some("Mars Report")),
      SegV11("MERGE", 2)))

  def vectorPlanV3: PlanV11 =
    vectorPlanV2.copy(v = 3, delays = Some(Map("N1|N2" -> 500L)), planVersion = Some(1))

  def amendedPlan: PlanV11 = vectorPlanV2.copy(
    v = 3, title = "Vector Summit (amended)",
    planVersion = Some(2), prevPlanHash = Some(ROOT_PLAN_HASH))

  def vectorNik: Security.Nik =
    val pubRaw = Security.b64uDecode(PUBLIC_KEY)
    Security.Nik(
      keyType = "ltx-nik-v1", nodeId = NODE_ID, kid = NODE_ID,
      issuedAt = "2026-01-01T00:00:00.000Z", expiresAt = VALID_UNTIL,
      nodeLabel = "", publicKeyB64 = Security.b64uEncode(pubRaw),
      privateKeyB64 = "", pubRaw = pubRaw, privRaw = Array.empty[Byte])

  def main(args: Array[String]): Unit =
    val nik = vectorNik
    val kidCache = Map(NODE_ID -> nik)
    val emptyCache = Map.empty[String, Security.Nik]
    val planV2 = vectorPlanV2
    val planV3 = vectorPlanV3

    // ---- 1a/1b. plan ids ----
    check("v11 planIdV3: canonical SHA-256 matches", planHash(planV3) == EXPECTED_SHA256)
    check("v11 planIdV3: expected plan id", makePlanId(planV3) == EXPECTED_PLAN_ID_V3)
    check("v11 planIdV2: FROZEN v2 hash unchanged", makePlanId(planV2) == EXPECTED_PLAN_ID_V2)

    // ---- 1c. pairDelay ----
    check("v11 pairDelay: N0|N1 = 900", pairDelay(planV3, "N0", "N1") == 900L)
    check("v11 pairDelay: N1|N0 symmetric", pairDelay(planV3, "N1", "N0") == 900L)
    check("v11 pairDelay: v3 matrix N1|N2 = 500", pairDelay(planV3, "N1", "N2") == 500L)
    check("v11 pairDelay: matrix symmetric", pairDelay(planV3, "N2", "N1") == 500L)
    check("v11 pairDelay: same node = 0", pairDelay(planV3, "N1", "N1") == 0L)
    check("v11 pairDelay: conservative fallback 902", pairDelay(planV2, "N1", "N2") == 902L)

    // ---- 1d. computeSegmentsFor ----
    val baseSegs = computeSegmentsV11(planV3)
    val forN0 = computeSegmentsFor(planV3, "N0")
    val forN1 = computeSegmentsFor(planV3, "N1")
    val forN2 = computeSegmentsFor(planV3, "N2")
    check("v11 segmentsFor: 4 segments", forN2.length == 4)
    check("v11 segmentsFor: PLAN_CONFIRM neutral",
      forN2(0).perspective == "neutral" && forN2(0).arrivalOffsetS == 0L)
    check("v11 segmentsFor: own TX is transmit",
      forN0(1).perspective == "transmit" && forN0(1).arrivalOffsetS == 0L)
    check("v11 segmentsFor: N0 TX arrives at N2 +2s",
      forN2(1).perspective == "receive" && forN2(1).arrivalOffsetS == 2L)
    check("v11 segmentsFor: start shifted by pair delay",
      forN2(1).startMs == baseSegs(1).startMs + 2000L)
    check("v11 segmentsFor: N1 TX arrives at N2 +500s (v3 matrix)",
      forN2(2).perspective == "receive" && forN2(2).arrivalOffsetS == 500L)
    check("v11 segmentsFor: N0 TX arrives at N1 +900s",
      forN1(1).arrivalOffsetS == 900L && forN1(1).endMs == baseSegs(1).endMs + 900000L)
    check("v11 segmentsFor: MERGE neutral", forN0(3).perspective == "neutral")
    val unknownViewerThrew =
      try { computeSegmentsFor(planV3, "NX"); false }
      catch { case _: IllegalArgumentException => true }
    check("v11 segmentsFor: unknown viewer throws", unknownViewerThrew)

    // ---- 3. amendment chain ----
    val chain = List(
      SignedPlanV11(planV2, Security.CoseSign1(PROTECTED, NODE_ID, ROOT_PAYLOAD, ROOT_SIG)),
      SignedPlanV11(amendedPlan, Security.CoseSign1(PROTECTED, NODE_ID, AMD_PAYLOAD, AMD_SIG)))
    check("v11 amend: root plan hash matches", planHash(planV2) == ROOT_PLAN_HASH)
    check("v11 amend: root signature valid", verifyPlanEnvelope(chain(0), kidCache)._1)
    check("v11 amend: amendment signature valid", verifyPlanEnvelope(chain(1), kidCache)._1)
    check("v11 amend: chain verifies", verifyAmendmentChain(chain, kidCache)._1)
    val tampered = List(chain(0),
      chain(1).copy(plan = chain(1).plan.copy(title = "EVIL")))
    val (tOk, tReason) = verifyAmendmentChain(tampered, kidCache)
    check("v11 amend: tampered title rejected", !tOk)
    check("v11 amend: tamper reason payload_mismatch", tReason == "link_1_payload_mismatch")
    check("v11 amend: empty chain invalid", !verifyAmendmentChain(Nil, kidCache)._1)
    check("v11 amend: unknown key rejected", !verifyAmendmentChain(chain, emptyCache)._1)

    // ---- 4. register entries + reducers ----
    val entry1 = RegisterEntryV11(
      "QST-N1-1", "VEC-SESSION", "N1", 1, "question",
      Map("text" -> "Status?", "urgency" -> "high"),
      "2040-02-01T11:00:00.000Z", ENTRY1_SIG)
    val entry2 = RegisterEntryV11(
      "QST-N0-1", "VEC-SESSION", "N0", 1, "question_response",
      Map("qid" -> "QST-N1-1", "response" -> "Nominal", "version" -> 2),
      "2040-02-01T11:05:00.000Z", ENTRY2_SIG)
    val nodeCache = Map("N0" -> nik, "N1" -> nik)

    check("v11 registers: entry 1 signature valid", verifyRegisterEntry(entry1, nodeCache)._1)
    check("v11 registers: entry 2 signature valid", verifyRegisterEntry(entry2, nodeCache)._1)
    check("v11 registers: tampered entry rejected",
      !verifyRegisterEntry(entry1.copy(seq = 9), nodeCache)._1)
    check("v11 registers: unknown node key rejected",
      !verifyRegisterEntry(entry1, emptyCache)._1)

    val ordered = orderEntries(List(entry2, entry1, entry1))
    check("v11 registers: dedup + (timestamp,nodeId,seq) order",
      ordered.length == 2 && ordered(0).entryId == "QST-N1-1")

    val (questions, superseded) = reduceQuestions(List(entry2, entry1))
    check("v11 registers: reduceQuestions single question", questions.size == 1)
    questions.get("QST-N1-1") match
      case Some(q) =>
        check("v11 registers: question state matches expectedQuestionState",
          q.qid == "QST-N1-1" && q.text == "Status?" && q.submitter == "N1" &&
          q.urgency.contains("high") && q.status == "ANSWERED" && q.version == 2 &&
          q.response.contains("Nominal") && q.responder.contains("N0"))
      case None => check("v11 registers: question state matches expectedQuestionState", false)
    check("v11 registers: nothing superseded", superseded.isEmpty)

    check("v11 registers: entriesRoot Merkle root matches",
      entriesRoot(ordered) == EXPECTED_ENTRIES_ROOT)

    // action reducer sanity (no golden vector -- semantics per §10.2)
    val act1 = RegisterEntryV11("ACT-N1-2", "VEC-SESSION", "N1", 2, "action",
      Map("description" -> "Fix antenna"), "2040-02-01T11:10:00.000Z", "x")
    val act2 = RegisterEntryV11("ACT-N0-2", "VEC-SESSION", "N0", 2, "action_update",
      Map("aid" -> "ACT-N1-2", "status" -> "ACCEPTED", "version" -> 2),
      "2040-02-01T11:11:00.000Z", "x")
    val (actions, _) = reduceActions(List(act2, act1))
    check("v11 registers: reduceActions applies update",
      actions.get("ACT-N1-2").exists(a => a.status == "ACCEPTED" && a.version == 2))

    // ---- 5. CBOR + COSE_Sign1 ----
    val coseBytes = Security.b64uDecode(COSE_SIGN1_CBOR_B64)
    decodeCbor(coseBytes) match
      case CborValue.CTag(18L, CborValue.CArray(arr)) =>
        check("v11 cose: decodes to tag 18 array of 4", arr.length == 4)
      case _ => check("v11 cose: decodes to tag 18 array of 4", false)

    check("v11 cose: COSE_Sign1 verifies against plan + key",
      verifyPlanCose(Some(planV2), COSE_SIGN1_CBOR_B64, kidCache)._1)
    check("v11 cose: mismatched plan rejected",
      !verifyPlanCose(Some(planV2.copy(title = "EVIL")), COSE_SIGN1_CBOR_B64, kidCache)._1)
    check("v11 cose: unknown kid rejected",
      !verifyPlanCose(Some(planV2), COSE_SIGN1_CBOR_B64, emptyCache)._1)
    val truncatedB64 = Security.b64uEncode(coseBytes.dropRight(1))
    check("v11 cose: truncated CBOR rejected",
      !verifyPlanCose(Some(planV2), truncatedB64, kidCache)._1)
    val floatRejected =
      try { decodeCbor(Array[Byte](0xf9.toByte, 0x3c, 0x00)); false }
      catch { case _: CborException => true }
    check("v11 cbor: floats rejected", floatRejected)
    val trailingRejected =
      try { decodeCbor(Array[Byte](0x01, 0x02)); false }
      catch { case _: CborException => true }
    check("v11 cbor: trailing bytes rejected", trailingRejected)
    check("v11 cbor: uint decode", decodeCbor(Array[Byte](0x18, 0x2a)) == CborValue.CInt(42L))
    check("v11 cbor: negative int decode", decodeCbor(Array[Byte](0x20)) == CborValue.CInt(-1L))

    // ---- 2. session state machine (golden transition table) ----
    var ctx = createSession(planV2, EXPECTED_PLAN_ID_V2, 1)
    check("v11 session: starts DRAFT", ctx.state == "DRAFT" && ctx.lock.isEmpty)
    check("v11 session: lock timeout 2x900s", ctx.lockTimeoutMs == 1800000L)
    check("v11 session: quorum threshold 1", ctx.quorumThreshold == 1)

    val steps: List[(SessionEventV11, String, Option[String])] = List(
      (SessionEventV11("START_LOCK", 1000L), "LOCKING", None),
      (SessionEventV11("PLAN_CONFIRM", 2000L, nodeId = Some("N2"), planId = Some(EXPECTED_PLAN_ID_V2)), "LOCKING", None),
      (SessionEventV11("TICK", 1800999L), "LOCKING", None),
      (SessionEventV11("TICK", 1801000L), "DEGRADED", Some("QUORUM")),
      (SessionEventV11("PLAN_CONFIRM", 4000000L, nodeId = Some("N1"), planId = Some(EXPECTED_PLAN_ID_V2)), "LOCKED", Some("FULL")),
      (SessionEventV11("SESSION_START", 4100000L), "ACTIVE", Some("FULL")),
      (SessionEventV11("DELAY_MEASURED", 4200000L, nodeId = Some("N1"), measuredDelayS = Some(1201L)), "DEGRADED", Some("FULL")),
      (SessionEventV11("HOST_DECISION", 4300000L, decision = Some("continue")), "ACTIVE", Some("FULL")),
      (SessionEventV11("SESSION_END", 5000000L), "COMPLETE", Some("FULL")))

    var quorumSubset: Option[List[String]] = None
    steps.zipWithIndex.foreach { case ((ev, expState, expLock), i) =>
      ctx = transition(ctx, ev)
      if ctx.lock.contains("QUORUM") && quorumSubset.isEmpty then quorumSubset = ctx.subset
      check(s"v11 session step $i: ${ev.eventType} -> state $expState", ctx.state == expState)
      check(s"v11 session step $i: ${ev.eventType} -> lock $expLock", ctx.lock == expLock)
    }
    check("v11 session: quorum subset [N0,N2] (ascending delay)",
      quorumSubset.contains(List("N0", "N2")))
    check("v11 session: subset cleared on full-lock recovery", ctx.subset.isEmpty)

    // extra machine coverage: abort / emergency hold / amendments
    var ctx2 = createSession(planV2, EXPECTED_PLAN_ID_V2, "all")
    check("v11 session: quorum 'all' = 2 participants", ctx2.quorumThreshold == 2)
    ctx2 = transition(ctx2, SessionEventV11("START_LOCK", 0L))
    ctx2 = transition(ctx2, SessionEventV11("HOST_DECISION", 1L, decision = Some("abort")))
    check("v11 session: host abort", ctx2.state == "ABORTED")

    var ctx3 = createSession(planV2, EXPECTED_PLAN_ID_V2, "majority")
    check("v11 session: majority of 2 = 2", ctx3.quorumThreshold == 2)
    ctx3 = transition(ctx3, SessionEventV11("START_LOCK", 0L))
    ctx3 = transition(ctx3, SessionEventV11("PLAN_CONFIRM", 1L, nodeId = Some("N1"), planId = Some(EXPECTED_PLAN_ID_V2)))
    ctx3 = transition(ctx3, SessionEventV11("PLAN_CONFIRM", 2L, nodeId = Some("N2"), planId = Some(EXPECTED_PLAN_ID_V2)))
    check("v11 session: full lock on all confirms", ctx3.state == "LOCKED" && ctx3.lock.contains("FULL"))
    ctx3 = transition(ctx3, SessionEventV11("SESSION_START", 3L))
    ctx3 = transition(ctx3, SessionEventV11("EOK_OVERRIDE", 4L, verified = Some(true)))
    check("v11 session: verified EOK override holds", ctx3.state == "EMERGENCY_HOLD")
    ctx3 = transition(ctx3, SessionEventV11("HOST_DECISION", 5L, decision = Some("resume")))
    check("v11 session: resume returns to prior state", ctx3.state == "ACTIVE")
    ctx3 = transition(ctx3, SessionEventV11("AMENDMENT_PROPOSED", 6L,
      planId = Some("LTX-AMENDED"), planVersion = Some(2), affectedNodeIds = Some(List("N1"))))
    check("v11 session: amendment pending", ctx3.pendingAmendment.isDefined)
    ctx3 = transition(ctx3, SessionEventV11("AMENDMENT_CONFIRMED", 7L,
      nodeId = Some("N1"), planId = Some("LTX-AMENDED")))
    check("v11 session: amendment applied after all confirms",
      ctx3.planId == "LTX-AMENDED" && ctx3.planVersion == 2 && ctx3.pendingAmendment.isEmpty)

    var ctx4 = createSession(planV2, EXPECTED_PLAN_ID_V2, "all")
    ctx4 = transition(ctx4, SessionEventV11("START_LOCK", 0L))
    ctx4 = transition(ctx4, SessionEventV11("PLAN_CONFIRM", 1L, nodeId = Some("N1"), planId = Some("LTX-WRONG")))
    check("v11 session: planId mismatch flagged (§5.5)",
      ctx4.state == "LOCKING" && ctx4.mismatched.contains("N1"))

    // ---- version ----
    check("v11 VERSION is 1.1.0", V11.VERSION == "1.1.0")

    println(s"\n$passed passed  $failed failed")
    if failed > 0 then System.exit(1)
