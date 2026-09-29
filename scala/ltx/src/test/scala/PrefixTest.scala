/**
 * PrefixTest.scala -- spec/golden/plan-id-prefixes.json (issue #37, spec §4.3).
 * HOSTSTR / NODESTR use JS whitespace, JS toUpperCase (full Unicode mapping
 * with special casing) and UTF-16 slicing. A Scala String is UTF-16, so the
 * exact JS id (planId, lone surrogates included) is expected on every path:
 * LtxPlans.makePlanId (JSON map), V11.makePlanId (typed PlanV11) and
 * InterplanetLtx.makePlanId (typed LtxPlan, v2 only).
 */

import V11.*

object PrefixTest:
  var passed = 0
  var failed = 0

  def checkId(label: String, got: String, want: String): Unit =
    if got == want then passed += 1
    else
      failed += 1
      println(s"FAIL: $label\n  got  ${LtxJson.stringify(got)}\n  want ${LtxJson.stringify(want)}")

  private def goldenPath: java.io.File =
    var dir = new java.io.File("").getAbsoluteFile
    var found: Option[java.io.File] = None
    while dir != null && found.isEmpty do
      val f = new java.io.File(dir, "spec/golden/plan-id-prefixes.json")
      if f.exists then found = Some(f)
      dir = dir.getParentFile
    found.getOrElse(new java.io.File("../../spec/golden/plan-id-prefixes.json"))

  private def m(v: Any): Map[String, Any] = v.asInstanceOf[Map[String, Any]]
  private def num(v: Any): Int = v.asInstanceOf[Number].intValue
  private def prefix(id: String): String = id.dropRight(12)

  def main(args: Array[String]): Unit =
    println("-- Conformance: planId prefix vectors --")
    val src = scala.io.Source.fromFile(goldenPath, "UTF-8")
    val golden = try m(LtxJson.parse(src.mkString)) finally src.close()
    val vectors = golden("vectors").asInstanceOf[Seq[Any]].map(m).toList
    if vectors.length >= 18 then passed += 1 else { failed += 1; println("FAIL: prefix vectors present") }
    for gv <- vectors do
      val name = gv("name").asInstanceOf[String]
      val want = gv("planId").asInstanceOf[String]
      val plan = m(gv("plan"))
      checkId(s"json $name", LtxPlans.makePlanId(plan), want)
      checkId(s"json text $name", LtxPlans.makePlanId(m(LtxJson.parse(LtxJson.stringify(plan)))), want)
      // Typed models write nodes before segments: the v2 hash matches only
      // for nodes-first vectors; v3 (canonical JSON) always.
      val keys = plan.keys.toList
      val nodesFirst = keys.indexOf("nodes") < keys.indexOf("segments")
      val v11 = V11.makePlanId(PlanV11.fromMap(plan))
      checkId(s"typed v11 prefix $name", prefix(v11), prefix(want))
      if nodesFirst || num(plan("v")) >= 3 then checkId(s"typed v11 $name", v11, want)
      if num(plan("v")) == 2 then
        val typed = LtxPlan(
          v = 2, title = plan("title").asInstanceOf[String], start = plan("start").asInstanceOf[String],
          quantum = num(plan("quantum")), mode = plan("mode").asInstanceOf[String],
          nodes = plan("nodes").asInstanceOf[Seq[Any]].map(m).map(n => LtxNode(
            n("id").asInstanceOf[String], n("name").asInstanceOf[String], n("role").asInstanceOf[String],
            num(n("delay")), n("location").asInstanceOf[String])).toList,
          segments = plan("segments").asInstanceOf[Seq[Any]].map(m).map(s => LtxSegmentTemplate(
            s("type").asInstanceOf[String], num(s("q")),
            s.get("speaker").map(_.asInstanceOf[String]), s.get("label").map(_.asInstanceOf[String]))).toList)
        val tid = InterplanetLtx.makePlanId(typed)
        checkId(s"typed prefix $name", prefix(tid), prefix(want))
        if nodesFirst then checkId(s"typed $name", tid, want)
    println(s"\n$passed passed  $failed failed")
    if failed > 0 then sys.exit(1)
