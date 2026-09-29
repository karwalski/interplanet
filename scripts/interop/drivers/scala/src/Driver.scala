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
        // LtxSegmentTemplate is (segType, q) only: no speaker/label.
        segments = List(
          LtxSegmentTemplate("PLAN_CONFIRM", 2), LtxSegmentTemplate("TX", 3), LtxSegmentTemplate("RX", 3),
          LtxSegmentTemplate("TX", 2), LtxSegmentTemplate("BUFFER", 1)))
      println("NOTE LtxPlan: no speaker/label, no v3")
      write("wire-v2.json", Base64.getUrlDecoder.decode(InterplanetLtx.encodeHash(plan).stripPrefix("#l=")))
      println("ID_V2 " + InterplanetLtx.makePlanId(plan))
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
