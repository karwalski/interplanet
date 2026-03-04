/**
 * SecurityTest.scala -- Epic 29, Stories 29.1 / 29.4 / 29.5
 */

object SecurityTest:
  var passed = 0
  var failed = 0

  def check(label: String, cond: Boolean): Unit =
    if cond then passed += 1
    else { failed += 1; println(s"FAIL: $label") }

  def checkEq(label: String, got: Any, exp: Any): Unit =
    if got == exp then passed += 1
    else { failed += 1; println(s"FAIL: $label  expected=$exp  got=$got") }

  def main(args: Array[String]): Unit =
    // ---- canonical_json ----
    checkEq("empty object", Security.canonicalJson(Map.empty[String,Any]), "{}")
    checkEq("sorted keys", Security.canonicalJson(Map("z" -> 1, "a" -> 2)), "{\"a\":2,\"z\":1}")
    checkEq("array", Security.canonicalJson(Seq(1, 2, 3)), "[1,2,3]")
    checkEq("number", Security.canonicalJson(42), "42")
    checkEq("bool", Security.canonicalJson(true), "true")
    checkEq("string", Security.canonicalJson("hi"), "\"hi\"")
    checkEq("null", Security.canonicalJson(null), "null")
    val nested = Security.canonicalJson(Map("b" -> Map("y" -> 9, "x" -> 1), "a" -> 3))
    checkEq("nested sorted", nested, "{\"a\":3,\"b\":{\"x\":1,\"y\":9}}")

    // ---- generate_nik ----
    val nik1 = Security.generateNik()
    val nik2 = Security.generateNik()
    checkEq("key_type", nik1.keyType, "ltx-nik-v1")
    check("node_id non-empty", nik1.nodeId.nonEmpty)
    check("kid non-empty", nik1.kid.nonEmpty)
    checkEq("node_id 22 chars", nik1.nodeId.length, 22)
    check("pub_key non-empty", nik1.publicKeyB64.nonEmpty)
    check("priv_key non-empty", nik1.privateKeyB64.nonEmpty)
    check("issued_at set", nik1.issuedAt.nonEmpty)
    check("expires_at set", nik1.expiresAt.nonEmpty)
    val nikLbl = Security.generateNik(validDays = 30, nodeLabel = "TestNode")
    checkEq("node_label", nikLbl.nodeLabel, "TestNode")
    check("expires after issued", nikLbl.expiresAt > nikLbl.issuedAt)
    check("unique node_ids", nik1.nodeId != nik2.nodeId)

    // ---- is_nik_expired ----
    check("fresh nik not expired", !Security.isNikExpired(nik1))
    val oldNik = nik1.copy(expiresAt = "2000-01-01T00:00:00Z")
    check("old nik expired", Security.isNikExpired(oldNik))

    // ---- sign_plan / verify_plan ----
    val plan = Map("planId" -> "p1", "startAt" -> "2026-05-01T00:00:00Z", "quantum" -> 60)
    val sp   = Security.signPlan(plan, nik1)
    check("coseSign1 protected", sp.coseSign1.protectedHdr.nonEmpty)
    check("coseSign1 signature", sp.coseSign1.signature.nonEmpty)
    checkEq("kid in unprotected", sp.coseSign1.kid, nik1.kid)

    val cache = Map(nik1.kid -> nik1)
    val (ok1, r1) = Security.verifyPlan(sp, cache)
    check("verify ok", ok1)
    checkEq("verify reason", r1, "ok")

    val (ok2, r2) = Security.verifyPlan(sp, Map.empty)
    check("verify fails empty cache", !ok2)
    checkEq("reason key_not_in_cache", r2, "key_not_in_cache")

    val expiredCache = Map(nik1.kid -> oldNik)
    val (ok3, r3) = Security.verifyPlan(sp, expiredCache)
    check("verify fails expired key", !ok3)
    checkEq("reason key_expired", r3, "key_expired")

    val tampered = sp.copy(plan = Map("planId" -> "TAMPERED"))
    val (ok4, r4) = Security.verifyPlan(tampered, cache)
    check("verify fails tampered", !ok4)
    checkEq("reason payload_mismatch", r4, "payload_mismatch")

    // ---- SequenceTracker ----
    val st = new Security.SequenceTracker("plan-x")
    checkEq("plan_id stored", st.planId, "plan-x")

    val (r1a, m1a) = st.addSeq("alice", 1)
    check("first seq accepted", r1a)
    checkEq("first seq msg", m1a, "ok")

    val (r2a, m2a) = st.addSeq("alice", 2)
    check("seq 2 accepted", r2a)
    checkEq("seq 2 msg", m2a, "ok")

    val (r3a, m3a) = st.addSeq("alice", 2)
    check("replay rejected", !r3a)
    checkEq("replay msg", m3a, "replay")

    val (r4a, m4a) = st.addSeq("alice", 10)
    check("gap accepted", r4a)
    checkEq("gap msg", m4a, "gap")

    val (c1, _) = st.checkSeq("alice", 10)
    check("check_seq replay", !c1)
    val (c2, _) = st.checkSeq("alice", 11)
    check("check_seq next", c2)
    val (c3, mc) = st.checkSeq("alice", 20)
    check("check_seq gap", c3)
    checkEq("check_seq gap msg", mc, "gap")

    val (rb, mb) = st.addSeq("bob", 5)
    check("bob first seq", rb)
    checkEq("bob first msg", mb, "ok")

    println(s"\n$passed passed  $failed failed")
    if failed > 0 then System.exit(1)
