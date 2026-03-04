/**
 * InterplanetLtxTest.scala - Unit tests for the Scala LTX library
 * Story 33.13 - Scala LTX library
 *
 * All tests are pure in-memory (no I/O).
 * Run with: make test
 */

object InterplanetLtxTest:
  var passed = 0
  var failed = 0

  def check(cond: Boolean, msg: String = ""): Unit =
    if cond then passed += 1
    else
      failed += 1
      println(s"FAIL: $msg")

  def main(args: Array[String]): Unit =

    // ── Constants ────────────────────────────────────────────────────────────

    check(VERSION == "1.0.0",              "VERSION should be 1.0.0")
    check(DEFAULT_QUANTUM == 3,            "DEFAULT_QUANTUM should be 3")
    check(DEFAULT_API_BASE.contains("interplanet.app"), "DEFAULT_API_BASE should contain interplanet.app")
    check(SEG_TYPES.contains("TX"),        "SEG_TYPES should contain TX")
    check(SEG_TYPES.contains("RX"),        "SEG_TYPES should contain RX")
    check(SEG_TYPES.contains("BUFFER"),    "SEG_TYPES should contain BUFFER")
    check(SEG_TYPES.contains("CAUCUS"),    "SEG_TYPES should contain CAUCUS")
    check(SEG_TYPES.contains("PLAN_CONFIRM"), "SEG_TYPES should contain PLAN_CONFIRM")
    check(SEG_TYPES.size == 6,             "SEG_TYPES should have 6 entries")
    check(DEFAULT_SEGMENTS.size == 7,      "DEFAULT_SEGMENTS should have 7 entries")
    check(DEFAULT_SEGMENTS.head.segType == "PLAN_CONFIRM", "First segment should be PLAN_CONFIRM")
    check(DEFAULT_SEGMENTS.last.segType == "BUFFER",       "Last segment should be BUFFER")
    check(DEFAULT_SEGMENTS.map(_.q).sum == 13,             "Total quanta should be 13")

    // ── createPlan ───────────────────────────────────────────────────────────

    val plan = InterplanetLtx.createPlan(Map(
      "title" -> "LTX Session",
      "start" -> "2024-01-15T14:00:00Z",
      "nodes" -> List(
        Map("id" -> "N0", "name" -> "Earth HQ",    "role" -> "HOST",        "delay" -> 0, "location" -> "earth"),
        Map("id" -> "N1", "name" -> "Mars Hab-01", "role" -> "PARTICIPANT", "delay" -> 0, "location" -> "mars")
      )
    ))

    check(plan.v == 2,                         "plan.v should be 2")
    check(plan.title == "LTX Session",         "plan.title should match")
    check(plan.start == "2024-01-15T14:00:00Z","plan.start should match")
    check(plan.quantum == DEFAULT_QUANTUM,      "plan.quantum should be DEFAULT_QUANTUM")
    check(plan.mode == "LTX",                  "plan.mode should be LTX")
    check(plan.nodes.size == 2,                "plan should have 2 nodes")
    check(plan.nodes.head.id == "N0",          "first node id should be N0")
    check(plan.nodes.head.name == "Earth HQ",  "first node name should be Earth HQ")
    check(plan.nodes.head.role == "HOST",      "first node role should be HOST")
    check(plan.nodes(1).id == "N1",            "second node id should be N1")
    check(plan.nodes(1).name == "Mars Hab-01", "second node name should be Mars Hab-01")
    check(plan.nodes(1).role == "PARTICIPANT", "second node role should be PARTICIPANT")
    check(plan.segments.size == 7,             "plan should have 7 segments")

    // createPlan with defaults
    val planDefault = InterplanetLtx.createPlan(Map.empty)
    check(planDefault.title == "LTX Session",  "default title should be LTX Session")
    check(planDefault.nodes.size == 2,         "default plan should have 2 nodes")
    check(planDefault.nodes.head.name == "Earth HQ",    "default host name")
    check(planDefault.nodes(1).name == "Mars Hab-01",   "default remote name")
    check(planDefault.quantum == DEFAULT_QUANTUM,       "default quantum")

    // createPlan with custom hostName
    val planCustom = InterplanetLtx.createPlan(Map(
      "hostName"   -> "Alpha Station",
      "remoteName" -> "Beta Outpost",
      "delay"      -> 240
    ))
    check(planCustom.nodes.head.name == "Alpha Station",  "custom host name")
    check(planCustom.nodes(1).name == "Beta Outpost",     "custom remote name")
    check(planCustom.nodes(1).delay == 240,               "custom delay")

    // ── upgradeConfig ────────────────────────────────────────────────────────

    val planV1 = LtxPlan(1, "Old Plan", "2024-01-01T00:00:00Z", 3, "LTX", Nil, DEFAULT_SEGMENTS)
    val upgraded = InterplanetLtx.upgradeConfig(planV1)
    check(upgraded.v == 2,                   "upgraded plan should be v2")
    check(upgraded.nodes.size == 2,          "upgraded plan should have 2 nodes")
    check(upgraded.nodes.head.name == "Earth HQ",    "upgraded host should be Earth HQ")

    val planV2 = InterplanetLtx.upgradeConfig(plan)
    check(planV2.v == 2,                     "v2 plan should pass through unchanged")
    check(planV2.nodes.size == 2,            "v2 plan nodes should be unchanged")

    // ── computeSegments ──────────────────────────────────────────────────────

    val segs = InterplanetLtx.computeSegments(plan)
    check(segs.size == 7,                    "should have 7 segments")
    check(segs.head.segType == "PLAN_CONFIRM","first segment type should be PLAN_CONFIRM")
    check(segs.last.segType == "BUFFER",     "last segment type should be BUFFER")

    val startMs = 1705327200000L  // 2024-01-15T14:00:00Z
    check(segs.head.startMs == startMs,      "first segment startMs should match")
    val q3ms = 3L * 60L * 1000L             // 3 minutes in ms
    check(segs.head.endMs == startMs + 2L * q3ms, "first segment endMs should match (q=2)")
    check(segs.head.durMin == 6,             "PLAN_CONFIRM durMin should be 6 min (q=2, quantum=3)")

    // Segments are contiguous
    check(segs(1).startMs == segs.head.endMs, "segments should be contiguous")
    check(segs(2).startMs == segs(1).endMs,   "segments should be contiguous (2)")

    // Total duration
    val totalDurMs = segs.last.endMs - segs.head.startMs
    val expectedDurMs = 13L * q3ms  // 13 quanta * 3 min
    check(totalDurMs == expectedDurMs,       "total duration should be 13 quanta * 3 min")

    // ── totalMin ─────────────────────────────────────────────────────────────

    check(InterplanetLtx.totalMin(plan) == 39, "totalMin should be 39 (13 quanta * 3 min)")

    val planQ5 = plan.copy(quantum = 5)
    check(InterplanetLtx.totalMin(planQ5) == 65, "totalMin with quantum=5 should be 65")

    // ── makePlanId ───────────────────────────────────────────────────────────

    val planId = InterplanetLtx.makePlanId(plan)
    check(planId.startsWith("LTX-"),           "planId should start with LTX-")
    check(planId.contains("20240115"),         "planId should contain date 20240115")
    check(planId.contains("EARTHHQ"),          "planId should contain EARTHHQ")
    check(planId.contains("MARS"),             "planId should contain MARS")
    check(planId.contains("-v2-"),             "planId should contain -v2-")
    check(planId == "LTX-20240115-EARTHHQ-MARS-v2-cc8a7fc0",
          s"planId golden value: expected LTX-20240115-EARTHHQ-MARS-v2-cc8a7fc0, got $planId")

    // planId hash part is 8 hex chars
    val hashPart = planId.split("-").last
    check(hashPart.length == 8,               "hash part should be 8 chars")
    check(hashPart.forall(c => "0123456789abcdef".contains(c)), "hash should be hex")

    // makePlanId with long names (truncation)
    val planLong = InterplanetLtx.createPlan(Map(
      "hostName"   -> "Very Long Station Name Here",
      "remoteName" -> "AnotherLongRemoteName",
      "start"      -> "2025-06-01T10:00:00Z"
    ))
    val longId = InterplanetLtx.makePlanId(planLong)
    val parts = longId.split("-")
    check(parts(2).length <= 8, "orig slug should be <= 8 chars")
    check(parts(3).length <= 4, "dest slug should be <= 4 chars")

    // ── djbHash ──────────────────────────────────────────────────────────────

    val h1 = InterplanetLtx.djbHash("")
    check(h1.length == 8,                    "djbHash of empty string should be 8 chars")
    check(h1 == "00000000",                  "djbHash of empty string should be 00000000")

    val h2 = InterplanetLtx.djbHash("hello")
    check(h2.length == 8,                    "djbHash of hello should be 8 chars")
    check(h2.forall(c => "0123456789abcdef".contains(c)), "djbHash should be lowercase hex")

    // djbHash is deterministic
    check(InterplanetLtx.djbHash("test") == InterplanetLtx.djbHash("test"),
          "djbHash should be deterministic")

    // ── toJson ───────────────────────────────────────────────────────────────

    val json = plan.toJson
    check(json.startsWith("{"),              "toJson should start with {")
    check(json.endsWith("}"),               "toJson should end with }")
    check(json.contains("\"v\":2"),          "toJson should contain v:2")
    check(json.contains("\"title\":\"LTX Session\""), "toJson should contain title")
    check(json.contains("\"nodes\":["),      "toJson should contain nodes array")
    check(json.contains("\"segments\":["),   "toJson should contain segments array")
    // nodes must come before segments
    check(json.indexOf("\"nodes\":[") < json.indexOf("\"segments\":["),
          "nodes should come before segments in JSON")
    check(json.contains("\"id\":\"N0\""),    "toJson should contain node N0")
    check(json.contains("\"type\":\"PLAN_CONFIRM\""), "toJson should contain PLAN_CONFIRM segment")

    // ── fromJson / decodeHash round-trip ──────────────────────────────────────

    val parsed = LtxPlan.fromJson(json)
    check(parsed.isDefined,                  "fromJson should return Some")
    val p = parsed.get
    check(p.v == 2,                          "parsed v should be 2")
    check(p.title == "LTX Session",          "parsed title should match")
    check(p.start == "2024-01-15T14:00:00Z", "parsed start should match")
    check(p.quantum == 3,                    "parsed quantum should match")
    check(p.mode == "LTX",                   "parsed mode should match")
    check(p.nodes.size == 2,                 "parsed nodes size should be 2")
    check(p.nodes.head.name == "Earth HQ",   "parsed first node name should match")
    check(p.segments.size == 7,              "parsed segments size should be 7")

    check(LtxPlan.fromJson("").isEmpty,      "fromJson of empty string should be None")
    check(LtxPlan.fromJson("{bad json}").isEmpty, "fromJson of bad json should be None")

    // ── encodeHash / decodeHash ───────────────────────────────────────────────

    val hash = InterplanetLtx.encodeHash(plan)
    check(hash.startsWith("#l="),            "encodeHash should start with #l=")
    check(!hash.contains("+"),               "encodeHash should not contain +")
    check(!hash.contains("/"),               "encodeHash should not contain /")
    check(!hash.stripPrefix("#l=").contains("="), "encodeHash base64 should not have padding =")

    val decoded = InterplanetLtx.decodeHash(hash)
    check(decoded.isDefined,                 "decodeHash should return Some")
    val dp = decoded.get
    check(dp.title == "LTX Session",         "decoded title should match")
    check(dp.nodes.size == 2,                "decoded nodes should match")

    // decodeHash with l= prefix
    val decoded2 = InterplanetLtx.decodeHash(hash.stripPrefix("#"))
    check(decoded2.isDefined,                "decodeHash l= form should work")

    // decodeHash with invalid input
    check(InterplanetLtx.decodeHash("").isEmpty,    "decodeHash empty should be None")
    check(InterplanetLtx.decodeHash("!!!").isEmpty, "decodeHash invalid should be None")

    // round-trip: encode then decode should recover same planId
    val decoded3 = InterplanetLtx.decodeHash(hash)
    check(decoded3.isDefined,                "round-trip decode should succeed")
    check(InterplanetLtx.makePlanId(decoded3.get) == planId,
          "round-trip planId should match original")

    // ── buildNodeUrls ─────────────────────────────────────────────────────────

    val urls = InterplanetLtx.buildNodeUrls(plan, "https://interplanet.live/ltx.html")
    check(urls.size == 2,                    "buildNodeUrls should return 2 URLs")
    check(urls.head.nodeId == "N0",          "first URL nodeId should be N0")
    check(urls.head.role == "HOST",          "first URL role should be HOST")
    check(urls.head.url.contains("node=N0"), "first URL should contain node=N0")
    check(urls.head.url.contains("#l="),     "first URL should contain hash")
    check(urls(1).nodeId == "N1",            "second URL nodeId should be N1")
    check(urls(1).url.contains("node=N1"),   "second URL should contain node=N1")

    // buildNodeUrls with empty baseUrl
    val urlsNoBase = InterplanetLtx.buildNodeUrls(plan)
    check(urlsNoBase.size == 2,              "buildNodeUrls with empty base should return 2")
    check(urlsNoBase.head.url.startsWith("?node="), "URL with empty base should start with ?node=")

    // ── generateICS ───────────────────────────────────────────────────────────

    val ics = InterplanetLtx.generateICS(plan)
    check(ics.contains("BEGIN:VCALENDAR"),   "ICS should contain BEGIN:VCALENDAR")
    check(ics.contains("END:VCALENDAR"),     "ICS should contain END:VCALENDAR")
    check(ics.contains("BEGIN:VEVENT"),      "ICS should contain BEGIN:VEVENT")
    check(ics.contains("END:VEVENT"),        "ICS should contain END:VEVENT")
    check(ics.contains("\r\n"),              "ICS should use CRLF line endings")
    check(ics.contains("LTX-PLANID:"),       "ICS should contain LTX-PLANID")
    check(ics.contains("LTX-QUANTUM:"),      "ICS should contain LTX-QUANTUM")
    check(ics.contains(s"LTX-PLANID:$planId"), "ICS should contain the correct plan ID")
    check(ics.contains(s"LTX-QUANTUM:PT${plan.quantum}M"), "ICS should contain quantum in PT format")
    check(ics.contains("SUMMARY:LTX Session"), "ICS should contain session title")
    check(ics.contains("LTX-NODE:"),         "ICS should contain LTX-NODE")
    check(ics.contains("LTX-READINESS:"),    "ICS should contain LTX-READINESS")
    check(ics.contains("VERSION:2.0"),       "ICS should contain VERSION:2.0")

    // ── formatHMS ─────────────────────────────────────────────────────────────

    check(InterplanetLtx.formatHMS(0) == "00:00",       "formatHMS(0) should be 00:00")
    check(InterplanetLtx.formatHMS(59) == "00:59",      "formatHMS(59) should be 00:59")
    check(InterplanetLtx.formatHMS(60) == "01:00",      "formatHMS(60) should be 01:00")
    check(InterplanetLtx.formatHMS(61) == "01:01",      "formatHMS(61) should be 01:01")
    check(InterplanetLtx.formatHMS(3600) == "01:00:00", "formatHMS(3600) should be 01:00:00")
    check(InterplanetLtx.formatHMS(3661) == "01:01:01", "formatHMS(3661) should be 01:01:01")
    check(InterplanetLtx.formatHMS(7200) == "02:00:00", "formatHMS(7200) should be 02:00:00")
    check(InterplanetLtx.formatHMS(-1) == "00:00",      "formatHMS(-1) should be 00:00 (clamp)")
    check(InterplanetLtx.formatHMS(90) == "01:30",      "formatHMS(90) should be 01:30")
    check(InterplanetLtx.formatHMS(3599) == "59:59",    "formatHMS(3599) should be 59:59")

    // ── formatUTC ─────────────────────────────────────────────────────────────

    val utcStr = InterplanetLtx.formatUTC(1705327200000L)  // 2024-01-15T14:00:00Z
    check(utcStr == "2024-01-15T14:00:00Z", s"formatUTC should format correctly, got: $utcStr")
    check(utcStr.endsWith("Z"),              "formatUTC should end with Z")
    check(utcStr.length == 20,               "formatUTC should be 20 chars")

    val utcStr2 = InterplanetLtx.formatUTC(0L)
    check(utcStr2 == "1970-01-01T00:00:00Z", s"formatUTC(0) should be epoch, got: $utcStr2")

    // ── Model case classes ────────────────────────────────────────────────────

    val node = LtxNode("N0", "Earth HQ", "HOST", 0, "earth")
    check(node.id == "N0",                   "LtxNode id")
    check(node.name == "Earth HQ",           "LtxNode name")
    check(node.role == "HOST",               "LtxNode role")
    check(node.delay == 0,                   "LtxNode delay")
    check(node.location == "earth",          "LtxNode location")

    val seg = LtxSegment("TX", 2, 1000L, 2000L, 6)
    check(seg.segType == "TX",               "LtxSegment segType")
    check(seg.q == 2,                        "LtxSegment q")
    check(seg.startMs == 1000L,              "LtxSegment startMs")
    check(seg.endMs == 2000L,               "LtxSegment endMs")
    check(seg.durMin == 6,                   "LtxSegment durMin")

    val nodeUrl = LtxNodeUrl("N0", "Earth HQ", "HOST", "https://example.com?node=N0#l=abc")
    check(nodeUrl.nodeId == "N0",            "LtxNodeUrl nodeId")
    check(nodeUrl.url.contains("#l="),       "LtxNodeUrl url contains hash")

    val tmpl = LtxSegmentTemplate("TX", 2)
    check(tmpl.segType == "TX",              "LtxSegmentTemplate segType")
    check(tmpl.q == 2,                       "LtxSegmentTemplate q")

    // ── escapeIcsText (Story 26.3) ────────────────────────────────────────────

    check(InterplanetLtx.escapeIcsText("") == "",               "escapeIcsText empty")
    check(InterplanetLtx.escapeIcsText("hello") == "hello",     "escapeIcsText no specials")
    check(InterplanetLtx.escapeIcsText("a;b") == "a\\;b",       "escapeIcsText semicolon")
    check(InterplanetLtx.escapeIcsText("a,b") == "a\\,b",       "escapeIcsText comma")
    check(InterplanetLtx.escapeIcsText("a\\b") == "a\\\\b",     "escapeIcsText backslash")
    check(InterplanetLtx.escapeIcsText("a\nb") == "a\\nb",      "escapeIcsText newline")
    val icsEsc = InterplanetLtx.generateICS(InterplanetLtx.createPlan(
      Map("title" -> "Hello, World; Test", "start" -> "2024-01-15T14:00:00Z",
          "nodes" -> List(
            Map("id" -> "N0", "name" -> "Earth HQ", "role" -> "HOST", "delay" -> 0, "location" -> "earth"),
            Map("id" -> "N1", "name" -> "Mars Hab-01", "role" -> "PARTICIPANT", "delay" -> 0, "location" -> "mars")
          ))
    ))
    check(icsEsc.contains("SUMMARY:Hello\\, World\\; Test"), "generateICS SUMMARY escaped")

    // ── planLockTimeoutMs / checkDelayViolation (Story 26.4) ──────────────────

    check(DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR == 2,                "DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR is 2")
    check(DELAY_VIOLATION_WARN_S == 120,                        "DELAY_VIOLATION_WARN_S is 120")
    check(DELAY_VIOLATION_DEGRADED_S == 300,                    "DELAY_VIOLATION_DEGRADED_S is 300")
    check(SESSION_STATES.size == 5,                             "SESSION_STATES has 5 entries")
    check(SESSION_STATES.contains("DEGRADED"),                  "SESSION_STATES contains DEGRADED")
    check(SESSION_STATES(3) == "DEGRADED",                      "SESSION_STATES(3) is DEGRADED")
    check(InterplanetLtx.planLockTimeoutMs(100L) == 200000L,    "planLockTimeoutMs(100) == 200000")
    check(InterplanetLtx.planLockTimeoutMs(0L) == 0L,           "planLockTimeoutMs(0) == 0")
    check(InterplanetLtx.checkDelayViolation(100L, 100L) == "ok",       "checkDelayViolation ok (same)")
    check(InterplanetLtx.checkDelayViolation(100L, 210L) == "ok",       "checkDelayViolation ok within 120")
    check(InterplanetLtx.checkDelayViolation(100L, 221L) == "violation","checkDelayViolation violation")
    check(InterplanetLtx.checkDelayViolation(100L, 401L) == "degraded", "checkDelayViolation degraded")
    check(InterplanetLtx.checkDelayViolation(0L, 120L) == "ok",         "checkDelayViolation boundary 120 ok")
    check(InterplanetLtx.checkDelayViolation(0L, 301L) == "degraded",   "checkDelayViolation boundary 301 degraded")

    // ── computeSegments quantum guard (Story 26.4) ────────────────────────────

    val badPlan = plan.copy(quantum = 0)
    var badQuantumThrew = false
    try { InterplanetLtx.computeSegments(badPlan) }
    catch case _: IllegalArgumentException => badQuantumThrew = true
    check(badQuantumThrew, "computeSegments quantum=0 throws")

    val badPlan2 = plan.copy(quantum = -1)
    var badQuantumThrew2 = false
    try { InterplanetLtx.computeSegments(badPlan2) }
    catch case _: IllegalArgumentException => badQuantumThrew2 = true
    check(badQuantumThrew2, "computeSegments quantum=-1 throws")

    // ── Summary ───────────────────────────────────────────────────────────────

    println(s"\n$passed passed  $failed failed")
    if failed > 0 then sys.exit(1)
