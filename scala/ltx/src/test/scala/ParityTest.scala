/**
 * ParityTest.scala -- LTX parity with javascript/ltx/tests/run.js (issue #27):
 * golden planId vectors (spec/golden/plan-ids.json), validatePlan reserved
 * streams/branching, createSession enforcement, reduceDecisions and the
 * merge_snapshot decisionRegister.
 */

import V11.*
import scala.collection.immutable.VectorMap

object ParityTest:
  var passed = 0
  var failed = 0

  def check(label: String, cond: Boolean): Unit =
    if cond then passed += 1
    else { failed += 1; println(s"FAIL: $label") }

  private def goldenPath: java.io.File =
    sys.env.get("LTX_GOLDEN").map(new java.io.File(_)).getOrElse {
      var dir = new java.io.File("").getAbsoluteFile
      var found: Option[java.io.File] = None
      while dir != null && found.isEmpty do
        val f = new java.io.File(dir, "spec/golden/plan-ids.json")
        if f.exists then found = Some(f)
        dir = dir.getParentFile
      found.getOrElse(new java.io.File("../../spec/golden/plan-ids.json"))
    }

  private def m(v: Any): Map[String, Any] = v.asInstanceOf[Map[String, Any]]
  private def codesOf(r: PlanValidation): List[String] = r.errors.map(_.code)
  private def throwsCode(fn: => Any): Option[String] =
    try { fn; None } catch { case e: LtxPlanException => Some(e.code) }
  private def w(base: Map[String, Any], kv: (String, Any)*): Map[String, Any] =
    kv.foldLeft(base)((acc, p) => LtxPlans.withKey(acc, p._1, p._2))

  def main(args: Array[String]): Unit =
    println("-- Conformance: golden planId vectors --")
    val src = scala.io.Source.fromFile(goldenPath, "UTF-8")
    val golden = try m(LtxJson.parse(src.mkString)) finally src.close()
    val vectors = golden("vectors").asInstanceOf[Seq[Any]].map(m).toList
    check("golden vectors present", vectors.length >= 9)
    for gv <- vectors do
      val plan = m(gv("plan"))
      check(s"golden planId ${gv("name")}", LtxPlans.makePlanId(plan) == gv("planId"))
      if gv.contains("planHash") then
        check(s"golden planHash ${gv("name")}", LtxPlans.planHash(plan) == gv("planHash"))
    val byName = vectors.map(gv => gv("name").asInstanceOf[String] -> gv).toMap
    check("golden v2 freeze anchor", byName("v2-freeze-check")("planId") == "LTX-20260801-EARTHHQ-MARS-v2-d132e85d")
    check("golden v2 unicode anchor", byName("v2-unicode-title")("planId") == "LTX-20261231-EARTHHQ-MARS-v2-7bc93af8")
    check("golden v2 order-sensitive", byName("v2-createPlan-default")("planId") != byName("v2-key-order-sensitive")("planId"))
    check("golden v3 order-insensitive", byName("v3-upgrade-delays")("planId") == byName("v3-key-order-insensitive")("planId"))
    check("golden v3 amendment chain hash",
      m(byName("v3-amendment")("plan"))("prevPlanHash") == byName("v3-upgrade-delays")("planHash"))
    check("default quantum is 5", DEFAULT_QUANTUM == 5 && PlanV11().quantum == 5)
    val v3 = m(byName("v3-upgrade-delays")("plan"))
    check("typed PlanV11 v3 planId matches golden", V11.makePlanId(PlanV11.fromMap(v3)) == byName("v3-upgrade-delays")("planId"))
    check("stringify escapes control chars", LtxJson.stringify("a\u0001\n\"") == "\"a\\u0001\\n\\\"\"")
    check("stringify lone surrogate escaped", LtxJson.stringify("\ud83d") == "\"\\ud83d\"")
    check("jsNumber formats", LtxJson.jsNumber(1.5) == "1.5" && LtxJson.jsNumber(2.0) == "2" &&
      LtxJson.jsNumber(1e21) == "1e+21" && LtxJson.jsNumber(1e-7) == "1e-7" && LtxJson.jsNumber(0.000001) == "0.000001")

    println("-- Plan validation: reserved fields --")
    for gv <- vectors do
      check(s"validatePlan accepts golden ${gv("name")}", LtxPlans.validatePlan(gv("plan")).valid)
    val vpBase = v3
    check("validatePlan v3 empty streams ok", LtxPlans.validatePlan(w(vpBase, "streams" -> Vector())).valid)
    val vpStreams = LtxPlans.validatePlan(w(vpBase, "streams" -> Vector(VectorMap("id" -> "S1"))))
    check("validatePlan non-empty streams", !vpStreams.valid && codesOf(vpStreams).contains("reserved_streams"))
    check("validatePlan streams error path", vpStreams.errors.find(_.code == "reserved_streams").map(_.path).contains("streams"))
    check("validatePlan streams non-array", codesOf(LtxPlans.validatePlan(w(vpBase, "streams" -> "S1"))).contains("reserved_streams"))
    val vpSegStream = LtxPlans.validatePlan(w(vpBase, "segments" -> Vector(VectorMap("type" -> "TX", "q" -> 1, "stream" -> "S1"))))
    check("validatePlan segment stream", codesOf(vpSegStream).contains("reserved_streams"))
    check("validatePlan branches", codesOf(LtxPlans.validatePlan(w(vpBase, "branches" -> Vector()))).contains("reserved_branching"))
    check("validatePlan branching", codesOf(LtxPlans.validatePlan(w(vpBase, "branching" -> VectorMap("mode" -> "local")))).contains("reserved_branching"))
    val vpSegBranch = LtxPlans.validatePlan(w(vpBase, "segments" -> Vector(VectorMap("type" -> "CAUCUS", "q" -> 1, "branch" -> "B1"))))
    check("validatePlan segment branch", codesOf(vpSegBranch).contains("reserved_branching") &&
      vpSegBranch.errors.head.path == "segments[0].branch")
    val vpV2 = m(byName("v2-freeze-check")("plan"))
    check("validatePlan v2 streams is v3 field", codesOf(LtxPlans.validatePlan(w(vpV2, "streams" -> Vector()))).contains("v3_field_in_v2"))
    check("validatePlan v2 branching", codesOf(LtxPlans.validatePlan(w(vpV2, "branching" -> true))).contains("reserved_branching"))
    check("validatePlan non-object", codesOf(LtxPlans.validatePlan(null)).contains("not_an_object"))
    check("validatePlan bad version", codesOf(LtxPlans.validatePlan(w(vpV2, "v" -> 7))).contains("invalid_version"))
    check("validatePlan host not first", codesOf(LtxPlans.validatePlan(
      w(vpV2, "nodes" -> vpV2("nodes").asInstanceOf[Seq[Any]].reverse))).contains("invalid_host"))
    check("validatePlan unsorted delays key", codesOf(LtxPlans.validatePlan(
      w(vpBase, "delays" -> VectorMap("N1|N0" -> 860)))).contains("invalid_delays"))
    check("validatePlan unknown speaker", codesOf(LtxPlans.validatePlan(
      w(vpV2, "segments" -> Vector(VectorMap("type" -> "TX", "q" -> 1, "speaker" -> "N9"))))).contains("unknown_speaker"))
    check("validatePlan quantum out of range", codesOf(LtxPlans.validatePlan(w(vpV2, "quantum" -> 0))).contains("invalid_quantum"))
    check("createSession rejects streams (map)",
      throwsCode(V11.createSessionFromMap(w(vpBase, "streams" -> Vector(1)), "id")).contains("reserved_streams"))
    check("createSession rejects segment branch (map)",
      throwsCode(V11.createSessionFromMap(w(vpBase, "segments" -> Vector(VectorMap("type" -> "TX", "q" -> 1, "branch" -> "B"))), "id"))
        .contains("reserved_branching"))
    check("createSession rejects branching (map)",
      throwsCode(V11.createSessionFromMap(w(vpBase, "branching" -> VectorMap()), "id")).contains("reserved_branching"))
    check("createSession accepts golden (map)", throwsCode(V11.createSessionFromMap(vpBase, "id")).isEmpty)
    check("createSession rejects streams (typed)",
      throwsCode(V11.createSession(PlanV11.fromMap(vpBase).copy(streams = Some(List("S1"))), "id")).contains("reserved_streams"))
    check("createSession typed empty streams ok",
      throwsCode(V11.createSession(PlanV11.fromMap(vpBase).copy(streams = Some(Nil)), "id")).isEmpty)

    println("-- Registers: reduceDecisions --")
    val decHost = Security.generateNik(nodeLabel = "HOST")
    val decMars = Security.generateNik(nodeLabel = "MARS")
    val decCache = Map("N0" -> decHost, "N1" -> decMars)
    def mkDec(t: String, content: Map[String, Any], nodeId: String, seq: Int, ts: String, nik: Security.Nik) =
      V11.createRegisterEntry(t, content, "LTX-DEC-TEST", nodeId, seq, ts, nik)
    val dec1 = mkDec("decision", Map("text" -> "Proceed with EVA-3", "rationale" -> "Weather window", "originWindow" -> "W2"),
      "N0", 1, "2026-08-01T12:00:00.000Z", decHost)
    check("decision id prefix DEC", dec1.entryId == "DEC-N0-1")
    check("decision entry verifies", V11.verifyRegisterEntry(dec1, decCache)._1)
    val (reg1, _) = V11.reduceDecisions(List(dec1))
    check("decision RECORDED", reg1("DEC-N0-1").status == "RECORDED" && reg1("DEC-N0-1").version == 1)
    check("decision fields", reg1("DEC-N0-1").text == "Proceed with EVA-3" &&
      reg1("DEC-N0-1").recordedBy == "N0" && reg1("DEC-N0-1").rationale.contains("Weather window"))
    val decRev = mkDec("decision_update", Map("did" -> "DEC-N0-1", "text" -> "Proceed with EVA-3 at 14:00", "version" -> 2),
      "N1", 1, "2026-08-01T12:10:00.000Z", decMars)
    val decRes = mkDec("decision_update", Map("did" -> "DEC-N0-1", "status" -> "RESCINDED", "version" -> 3),
      "N0", 2, "2026-08-01T12:20:00.000Z", decHost)
    val (reg2, sup2) = V11.reduceDecisions(List(decRes, dec1, decRev))
    check("decision update applied", reg2("DEC-N0-1").text == "Proceed with EVA-3 at 14:00")
    check("decision RESCINDED v3", reg2("DEC-N0-1").status == "RESCINDED" && reg2("DEC-N0-1").version == 3)
    check("decision editor recorded", reg2("DEC-N0-1").editor.contains("N0"))
    check("decision older update superseded", sup2.contains(decRev.entryId))
    val decA = mkDec("decision_update", Map("did" -> "DEC-N0-1", "text" -> "From N0", "version" -> 5), "N0", 7, "2026-08-01T13:00:00.000Z", decHost)
    val decB = mkDec("decision_update", Map("did" -> "DEC-N0-1", "text" -> "From N1", "version" -> 5), "N1", 7, "2026-08-01T13:00:00.000Z", decMars)
    val conf1 = V11.reduceDecisions(List(dec1, decB, decA))
    val conf2 = V11.reduceDecisions(List(decA, dec1, decB))
    check("decision tie lowest nodeId wins", conf1._1("DEC-N0-1").text == "From N0")
    check("decision tie loser superseded", conf1._2.contains(decB.entryId) && !conf1._2.contains(decA.entryId))
    check("decision reduce order-independent", conf1 == conf2)
    val decHi = mkDec("decision_update", Map("did" -> "DEC-N0-1", "text" -> "N1 v6", "version" -> 6), "N1", 8, "2026-08-01T12:30:00.000Z", decMars)
    check("decision higher version wins", V11.reduceDecisions(List(dec1, decA, decHi))._1("DEC-N0-1").text == "N1 v6")
    val decOrphan = mkDec("decision_update", Map("did" -> "DEC-NOPE-1", "version" -> 2), "N1", 9, "2026-08-01T12:40:00.000Z", decMars)
    val decDup = V11.createRegisterEntry("decision", Map("text" -> "dup"), "LTX-DEC-TEST", "N1", 10,
      "2026-08-01T12:50:00.000Z", decMars, entryId = Some("DEC-N0-1"))
    val (reg3, sup3) = V11.reduceDecisions(List(dec1, decOrphan, decDup))
    check("decision orphan update superseded", sup3.contains("DEC-N1-9"))
    check("decision duplicate create ignored", reg3("DEC-N0-1").text == "Proceed with EVA-3" && reg3("DEC-N0-1").recordedBy == "N0")
    check("decision reducer ignores others", V11.reduceDecisions(List(dec1, decRev))._1.size == 1 &&
      V11.reduceActions(List(dec1))._1.isEmpty)
    val snap = V11.runMergeSegment(List(dec1), List(decRev), decCache,
      "LTX-DEC-TEST", "N0", 99, "2026-08-01T15:00:00.000Z", decHost)
    val decRegister = m(snap.snapshot.content("decisionRegister"))
    check("snapshot decisionRegister", m(decRegister("DEC-N0-1"))("version") == 2)
    check("snapshot entry type and id", snap.snapshot.entryType == "merge_snapshot" && snap.snapshot.entryId == "MRG-N0-99")
    check("snapshot signature verifies", V11.verifyRegisterEntry(snap.snapshot, decCache)._1)
    check("snapshot counts", snap.snapshot.content("entryCount") == 2 && snap.snapshot.content("rejectedCount") == 0)

    println(s"$passed passed  $failed failed")
    if failed > 0 then System.exit(1)
