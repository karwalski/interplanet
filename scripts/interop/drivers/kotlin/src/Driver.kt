// Interop driver for kotlin/ltx (see scripts/interop/run.js).
// Usage: driver <main|v11> <inDir> <outDir>
//   main  InterplanetLTX.createPlan / encodeHash / makePlanId (LtxPlan)
//   v11   LtxV11 model: PlanV11 / toJsonV2 / makePlanId, plus v3
import com.interplanet.ltx.*
import java.io.File
import java.util.Base64

const val TITLE = "Réunion Mars 🚀"
const val START = "2026-03-15T14:00:00.000Z"

@Suppress("UNCHECKED_CAST")
fun main(args: Array<String>) {
    val (mode, inDir, outDir) = args
    if (mode == "main") {
        val plan = InterplanetLTX.createPlan(
            title = TITLE, start = START, quantum = 3, mode = "LTX-ASYNC",
            nodes = listOf(
                LtxNode("N0", "Earth HQ", "HOST", 0, "earth"),
                LtxNode("N1", "Mars Hab-01", "PARTICIPANT", 840, "mars"),
                LtxNode("N2", "L-1 Gateway", "PARTICIPANT", 2, "moon")),
            // LtxSegmentTemplate is (type, q) only: no speaker/label.
            segments = listOf(
                LtxSegmentTemplate("PLAN_CONFIRM", 2), LtxSegmentTemplate("TX", 3),
                LtxSegmentTemplate("RX", 3), LtxSegmentTemplate("TX", 2), LtxSegmentTemplate("BUFFER", 1)))
        println("NOTE LtxPlan: no speaker/label, no v3")
        val token = InterplanetLTX.encodeHash(plan).removePrefix("#l=")
        File(outDir, "wire-v2.json").writeBytes(Base64.getUrlDecoder().decode(token))
        println("ID_V2 " + InterplanetLTX.makePlanId(plan))
    } else {
        val plan = PlanV11(
            v = 2, title = TITLE, start = START, quantum = 3, mode = "LTX-ASYNC",
            nodes = listOf(
                NodeV11("N0", "Earth HQ", "HOST", 0, "earth"),
                NodeV11("N1", "Mars Hab-01", "PARTICIPANT", 840, "mars"),
                NodeV11("N2", "L-1 Gateway", "PARTICIPANT", 2, "moon")),
            segments = listOf(
                SegmentTemplateV11("PLAN_CONFIRM", 2),
                SegmentTemplateV11("TX", 3, "N0", "Ouverture: état de la mission"),
                SegmentTemplateV11("RX", 3),
                SegmentTemplateV11("TX", 2, "N1", "Réponse 🔴"),
                SegmentTemplateV11("BUFFER", 1)))
        File(outDir, "wire-v2.json").writeText(LtxV11.toJsonV2(plan), Charsets.UTF_8)
        println("ID_V2 " + LtxV11.makePlanId(plan))
        // No upgrade function: build the v3 plan with copy().
        val v3 = plan.copy(v = 3, planVersion = 1, delays = mapOf("N1|N2" to 842L))
        File(outDir, "wire-v3.json").writeText(LtxJson.stringify(v3.toMap()), Charsets.UTF_8)
        println("ID_V3 " + LtxV11.makePlanId(v3))
        println("NOTE PlanV11: v2 wire via toJsonV2, v3 wire via LtxJson.stringify(toMap()); v3 via copy()")
    }
    for (v in listOf("2", "3")) {
        val parsed = LtxJson.parse(File(inDir, "js-v$v.json").readText(Charsets.UTF_8)) as Map<String, Any?>
        println("JS_V$v " + LtxPlans.makePlanId(parsed))
    }
}
