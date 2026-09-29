package com.interplanet.ltx

// PrefixTest.kt -- spec/golden/plan-id-prefixes.json (issue #37, spec §4.3).
// HOSTSTR / NODESTR use JS whitespace, JS toUpperCase (full Unicode mapping
// with special casing) and UTF-16 slicing. A Kotlin String is UTF-16, so the
// exact JS id (planId, lone surrogates included) is expected on every path:
// LtxPlans.makePlanId (JSON map), LtxV11.makePlanId (typed PlanV11) and
// InterplanetLTX.makePlanId (typed LtxPlan, v2 only). Invoked from
// InterplanetLTXTest.kt main().

import java.io.File

private fun prefixFile(): File {
    var dir: File? = File("").absoluteFile
    while (dir != null) {
        val f = File(dir, "spec/golden/plan-id-prefixes.json")
        if (f.exists()) return f
        dir = dir.parentFile
    }
    return File("../../spec/golden/plan-id-prefixes.json")
}

@Suppress("UNCHECKED_CAST")
private fun asMapP(v: Any?) = v as Map<String, Any?>

private fun checkId(name: String, got: String, want: String) {
    check(name, got == want)
    if (got != want) println("  got  ${LtxJson.stringify(got)}\n  want ${LtxJson.stringify(want)}")
}

fun runPrefixTests() {
    println("── Conformance: planId prefix vectors ───────")
    val golden = asMapP(LtxJson.parse(prefixFile().readText(Charsets.UTF_8)))
    val vectors = (golden["vectors"] as List<*>).map { asMapP(it) }
    check("prefix vectors present", vectors.size >= 18)
    for (gv in vectors) {
        val name = gv["name"] as String
        val want = gv["planId"] as String
        val plan = asMapP(gv["plan"])
        checkId("prefix json $name", LtxPlans.makePlanId(plan), want)
        checkId("prefix json text $name", LtxPlans.makePlanId(asMapP(LtxJson.parse(LtxJson.stringify(plan)))), want)
        // Typed PlanV11 writes nodes before segments: the v2 hash matches only
        // for nodes-first vectors; v3 (canonical JSON) always.
        val keys = plan.keys.toList()
        val nodesFirst = keys.indexOf("nodes") < keys.indexOf("segments")
        val v11 = LtxV11.makePlanId(PlanV11.fromMap(plan))
        checkId("prefix typed v11 prefix $name", v11.dropLast(12), want.dropLast(12))
        if (nodesFirst || (plan["v"] as Number).toInt() >= 3) checkId("prefix typed v11 $name", v11, want)
        if ((plan["v"] as Number).toInt() != 2) continue
        val typed = LtxPlan(
            v = 2, title = plan["title"] as String, start = plan["start"] as String,
            quantum = (plan["quantum"] as Number).toInt(), mode = plan["mode"] as String,
            nodes = (plan["nodes"] as List<*>).map { asMapP(it) }.map {
                LtxNode(it["id"] as String, it["name"] as String, it["role"] as String,
                    (it["delay"] as Number).toInt(), it["location"] as String)
            },
            segments = (plan["segments"] as List<*>).map { asMapP(it) }.map {
                LtxSegmentTemplate(it["type"] as String, (it["q"] as Number).toInt(),
                    it["speaker"] as String?, it["label"] as String?)
            })
        val tid = InterplanetLTX.makePlanId(typed)
        checkId("prefix typed prefix $name", tid.dropLast(12), want.dropLast(12))
        if (nodesFirst) checkId("prefix typed $name", tid, want)
    }
}
