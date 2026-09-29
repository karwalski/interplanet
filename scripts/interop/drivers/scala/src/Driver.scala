// Interop driver for scala/ltx (see scripts/interop/run.js).
// Usage: Driver <main|v11> <inDir> <outDir>
//   main  InterplanetLtx.createPlan / encodeHash / makePlanId (LtxPlan)
//   v11   V11 model: PlanV11 / toJsonV2 / makePlanId, plus v3
import java.nio.charset.StandardCharsets.UTF_8
import java.nio.file.{Files, Paths}
import java.util.Base64

object Driver:
  val Title = "Réunion Mars 🚀"
  val Start = "2026-03-15T14:00:00.000Z"

  /**
   * Issue #36 extra case (not a run.js column): control characters, a lone
   * surrogate and JS \s whitespace (tab, NBSP, U+3000, U+2028, BOM, LF) in the
   * title and node names, plus a speaker-only and a label-only segment. The
   * typed wire JSON must be exactly what JSON.stringify writes for it, and the
   * typed planId must equal the JSON-based planId of that wire and the JS
   * reference id (ltx-sdk.js makePlanId on the same plan object).
   */
  def ctlCase(write: (String, Array[Byte]) => Unit): Unit =
    val ctl = LtxPlan(2,
      "Ctl\u0001\b\f\n\r\t\"\\\u001f\u007f\ud800 \ud83d\ude80",
      Start, 3, "LTX-ASYNC",
      List(
        LtxNode("N0", "Earth\tHQ", "HOST", 0, "earth"),
        LtxNode("N1", "Ma\u00a0r\u3000s\u2009Hab-01", "PARTICIPANT", 840, "mars"),
        LtxNode("N2", "L-1\u2028Gate\ufeffway\n", "PARTICIPANT", 2, "moon")),
      List(
        LtxSegmentTemplate("PLAN_CONFIRM", 2),
        LtxSegmentTemplate("TX", 3, Some("N0"), Some("Opening\tremarks")),
        LtxSegmentTemplate("RX", 3),
        LtxSegmentTemplate("TX", 2, speaker = Some("N1")),
        LtxSegmentTemplate("TX", 1, label = Some("Q&A \ud83d\udd34")),
        LtxSegmentTemplate("BUFFER", 1)))
    val ref = "LTX-20260315-EARTHHQ-MARS-L-1G-v2-39d48c2a"
    val wire = Base64.getUrlDecoder.decode(InterplanetLtx.encodeHash(ctl).stripPrefix("#l="))
    write("wire-ctl.json", wire)
    val json = new String(wire, UTF_8)
    val parsed = LtxJson.parse(json).asInstanceOf[Map[String, Any]]
    val id = InterplanetLtx.makePlanId(ctl)
    val jsonId = LtxPlans.makePlanId(parsed)
    val ok = LtxJson.stringify(parsed) == json && id == jsonId && id == ref
    println(s"NOTE ctl/whitespace case: typed $id, JSON $jsonId, JS $ref" + (if ok then " (ok)" else " (MISMATCH)"))
    if !ok then System.exit(1)

  def main(args: Array[String]): Unit =
    val Array(mode, inDir, outDir) = args
    def write(name: String, bytes: Array[Byte]): Unit = Files.write(Paths.get(outDir, name), bytes)
    if mode == "main" then
      val base = InterplanetLtx.createPlan(Map("title" -> Title, "start" -> Start, "quantum" -> 3, "mode" -> "LTX-ASYNC"))
      val plan = base.copy(
        nodes = List(
          LtxNode("N0", "Earth HQ", "HOST", 0, "earth"),
          LtxNode("N1", "Mars Hab-01", "PARTICIPANT", 840, "mars"),
          LtxNode("N2", "L-1 Gateway", "PARTICIPANT", 2, "moon")),
        segments = List(
          LtxSegmentTemplate("PLAN_CONFIRM", 2),
          LtxSegmentTemplate("TX", 3, Some("N0"), Some("Ouverture: état de la mission")),
          LtxSegmentTemplate("RX", 3),
          LtxSegmentTemplate("TX", 2, Some("N1"), Some("Réponse 🔴")),
          LtxSegmentTemplate("BUFFER", 1)))
      println("NOTE LtxPlan: no v3")
      write("wire-v2.json", Base64.getUrlDecoder.decode(InterplanetLtx.encodeHash(plan).stripPrefix("#l=")))
      println("ID_V2 " + InterplanetLtx.makePlanId(plan))
      ctlCase(write)
    else
      import V11.*
      val plan = PlanV11(
        v = 2, title = Title, start = Start, quantum = 3, mode = "LTX-ASYNC",
        nodes = List(
          NodeV11("N0", "Earth HQ", "HOST", 0, "earth"),
          NodeV11("N1", "Mars Hab-01", "PARTICIPANT", 840, "mars"),
          NodeV11("N2", "L-1 Gateway", "PARTICIPANT", 2, "moon")),
        segments = List(
          SegV11("PLAN_CONFIRM", 2),
          SegV11("TX", 3, Some("N0"), Some("Ouverture: état de la mission")),
          SegV11("RX", 3),
          SegV11("TX", 2, Some("N1"), Some("Réponse 🔴")),
          SegV11("BUFFER", 1)))
      write("wire-v2.json", V11.toJsonV2(plan).getBytes(UTF_8))
      println("ID_V2 " + V11.makePlanId(plan))
      // No upgrade function: build the v3 plan with copy().
      val v3 = plan.copy(v = 3, planVersion = Some(1), delays = Some(Map("N1|N2" -> 842L)))
      write("wire-v3.json", LtxJson.stringify(v3.toMap).getBytes(UTF_8))
      println("ID_V3 " + V11.makePlanId(v3))
      println("NOTE PlanV11: v2 wire via toJsonV2, v3 wire via LtxJson.stringify(toMap); v3 via copy()")
    for v <- Seq("2", "3") do
      val json = new String(Files.readAllBytes(Paths.get(inDir, s"js-v$v.json")), UTF_8)
      println(s"JS_V$v " + LtxPlans.makePlanId(LtxJson.parse(json).asInstanceOf[Map[String, Any]]))
