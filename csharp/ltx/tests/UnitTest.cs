// UnitTest.cs — Unit tests for InterplanetLtx C# library (Story 33.10)
// ≥80 Check() assertions covering all public API methods.

using InterplanetLtx;

int passed = 0, failed = 0;

void Check(bool condition, string label)
{
    if (condition) { passed++; Console.WriteLine($"PASS: {label}"); }
    else           { failed++; Console.WriteLine($"FAIL: {label}"); }
}

// ── VERSION ────────────────────────────────────────────────────────────────

Check(InterplanetLTX.VERSION == "1.0.0",                 "VERSION is 1.0.0");
Check(Constants.VERSION == "1.0.0",                      "Constants.VERSION is 1.0.0");
Check(Constants.DEFAULT_QUANTUM == 3,                    "DEFAULT_QUANTUM is 3");
Check(Constants.DEFAULT_SEGMENTS.Count == 7,             "DEFAULT_SEGMENTS has 7 entries");
Check(Constants.SEG_TYPES.Length == 6,                   "SEG_TYPES has 6 entries");
Check(Constants.SEG_TYPES[0] == "PLAN_CONFIRM",          "SEG_TYPES[0] is PLAN_CONFIRM");
Check(Constants.SEG_TYPES[5] == "MERGE",                 "SEG_TYPES[5] is MERGE");
Check(Constants.DEFAULT_API_BASE.Contains("interplanet.live"), "DEFAULT_API_BASE has domain");

// ── CreatePlan defaults ────────────────────────────────────────────────────

var plan = InterplanetLTX.CreatePlan();
Check(plan.V == 2,                                       "CreatePlan v=2");
Check(plan.Title == "LTX Session",                       "CreatePlan default title");
Check(plan.Quantum == 3,                                 "CreatePlan quantum=3");
Check(plan.Mode == "LTX",                                "CreatePlan mode=LTX");
Check(plan.Nodes.Count == 2,                             "CreatePlan 2 nodes");
Check(plan.Segments.Count == 7,                          "CreatePlan 7 segments");
Check(plan.Nodes[0].Id == "N0",                          "CreatePlan node0 id=N0");
Check(plan.Nodes[0].Name == "Earth HQ",                  "CreatePlan node0 name=Earth HQ");
Check(plan.Nodes[0].Role == "HOST",                      "CreatePlan node0 role=HOST");
Check(plan.Nodes[0].Delay == 0.0,                        "CreatePlan node0 delay=0");
Check(plan.Nodes[0].Location == "earth",                 "CreatePlan node0 location=earth");
Check(plan.Nodes[1].Id == "N1",                          "CreatePlan node1 id=N1");
Check(plan.Nodes[1].Name == "Mars Hab-01",               "CreatePlan node1 name=Mars Hab-01");
Check(plan.Nodes[1].Role == "PARTICIPANT",               "CreatePlan node1 role=PARTICIPANT");
Check(plan.Nodes[1].Location == "mars",                  "CreatePlan node1 location=mars");
Check(plan.Start.Length > 0,                             "CreatePlan start is non-empty");
Check(plan.Start.EndsWith("Z"),                          "CreatePlan start ends with Z");

// ── CreatePlan with explicit args ──────────────────────────────────────────

var plan2 = InterplanetLTX.CreatePlan(
    title: "My Session",
    start: "2024-06-01T10:00:00Z",
    quantum: 5,
    mode: "ASYNC",
    delay: 840.0);
Check(plan2.Title == "My Session",                       "CreatePlan explicit title");
Check(plan2.Start == "2024-06-01T10:00:00Z",             "CreatePlan explicit start");
Check(plan2.Quantum == 5,                                "CreatePlan explicit quantum");
Check(plan2.Mode == "ASYNC",                             "CreatePlan explicit mode");
Check(plan2.Nodes[1].Delay == 840.0,                     "CreatePlan explicit delay");

// ── UpgradeConfig ──────────────────────────────────────────────────────────

var cfg1 = new Dictionary<string, object>
{
    ["txName"] = "Mission Control",
    ["rxName"] = "Mars Outpost",
    ["delay"]  = 1200.0,
};
var upgraded = InterplanetLTX.UpgradeConfig(cfg1);
Check(upgraded.V == 2,                                   "UpgradeConfig v=2");
Check(upgraded.Nodes.Count == 2,                         "UpgradeConfig 2 nodes");
Check(upgraded.Nodes[0].Name == "Mission Control",       "UpgradeConfig node0 name");
Check(upgraded.Nodes[0].Role == "HOST",                  "UpgradeConfig node0 role=HOST");
Check(upgraded.Nodes[1].Name == "Mars Outpost",          "UpgradeConfig node1 name");
Check(upgraded.Nodes[1].Role == "PARTICIPANT",           "UpgradeConfig node1 role");
Check(upgraded.Nodes[1].Delay == 1200.0,                 "UpgradeConfig node1 delay");
Check(upgraded.Nodes[1].Location == "mars",              "UpgradeConfig node1 location=mars");

// UpgradeConfig: moon location
var cfgMoon = new Dictionary<string, object> { ["rxName"] = "Moon Base" };
var upgMoon = InterplanetLTX.UpgradeConfig(cfgMoon);
Check(upgMoon.Nodes[1].Location == "moon",               "UpgradeConfig moon location");

// ── ComputeSegments ────────────────────────────────────────────────────────

var canonical = InterplanetLTX.CreatePlan(start: "2024-01-15T14:00:00Z");
var segs = InterplanetLTX.ComputeSegments(canonical);
Check(segs.Count == 7,                                   "ComputeSegments count=7");
Check(segs[0].Type == "PLAN_CONFIRM",                    "ComputeSegments[0] type=PLAN_CONFIRM");
Check(segs[0].Q == 2,                                    "ComputeSegments[0] q=2");
Check(segs[0].DurMin == 6,                               "ComputeSegments[0] durMin=6");
Check(segs[0].Start == "2024-01-15T14:00:00Z",           "ComputeSegments[0] start");
Check(segs[0].End == "2024-01-15T14:06:00Z",             "ComputeSegments[0] end");
Check(segs[0].StartMs == 1705327200000L,                 "ComputeSegments[0] startMs");
Check(segs[1].Type == "TX",                              "ComputeSegments[1] type=TX");
Check(segs[6].Type == "BUFFER",                          "ComputeSegments[6] type=BUFFER");
Check(segs[6].Q == 1,                                    "ComputeSegments[6] q=1");
Check(segs[6].DurMin == 3,                               "ComputeSegments[6] durMin=3");
// End of last segment: 14:00 + (2+2+2+2+2+2+1)*3 = 14:00 + 39 min = 14:39
Check(segs[6].End == "2024-01-15T14:39:00Z",             "ComputeSegments[6] end=14:39");

// ── TotalMin ───────────────────────────────────────────────────────────────

Check(InterplanetLTX.TotalMin(canonical) == 39,          "TotalMin=39 (default plan)");
var plan3 = InterplanetLTX.CreatePlan(quantum: 5);
Check(InterplanetLTX.TotalMin(plan3) == 65,              "TotalMin=65 (quantum=5)");

// ── MakePlanId — golden hash test ─────────────────────────────────────────
// Golden value from JS reference (nodes-before-segments canonical order):
// LTX-20240115-EARTHHQ-MARS-v2-cc8a7fc0

var goldenPlan = InterplanetLTX.CreatePlan(
    title: "LTX Session",
    start: "2024-01-15T14:00:00Z");
string planId = InterplanetLTX.MakePlanId(goldenPlan);

Check(planId == "LTX-20240115-EARTHHQ-MARS-v2-cc8a7fc0", "MakePlanId golden hash matches JS");
Check(planId.StartsWith("LTX-"),                          "MakePlanId starts with LTX-");
Check(planId.Contains("20240115"),                        "MakePlanId contains date");
Check(planId.Contains("EARTHHQ"),                         "MakePlanId contains EARTHHQ");
Check(planId.Contains("MARS"),                            "MakePlanId contains MARS");
Check(planId.Contains("-v2-"),                            "MakePlanId contains -v2-");
Check(planId.EndsWith("cc8a7fc0"),                        "MakePlanId ends with golden hash");

// Another plan with different start
var plan4 = InterplanetLTX.CreatePlan(start: "2026-03-01T10:00:00Z");
string pid4 = InterplanetLTX.MakePlanId(plan4);
Check(pid4.StartsWith("LTX-20260301"),                    "MakePlanId date from start");
Check(pid4.Length > 20,                                   "MakePlanId reasonable length");

// ── ToJson / FromJson round-trip ──────────────────────────────────────────

string json = goldenPlan.ToJson();
Check(json.Contains("\"v\":2"),                           "ToJson has v:2");
Check(json.Contains("\"title\":\"LTX Session\""),         "ToJson has title");
Check(json.Contains("\"start\":\"2024-01-15T14:00:00Z\""), "ToJson has start");
Check(json.Contains("\"quantum\":3"),                     "ToJson has quantum");
Check(json.Contains("\"mode\":\"LTX\""),                  "ToJson has mode");
Check(json.Contains("\"segments\":["),                    "ToJson has segments");
Check(json.Contains("\"nodes\":["),                       "ToJson has nodes");
// Key order: segments before nodes (critical for hash)
Check(json.IndexOf("\"nodes\"") < json.IndexOf("\"segments\""),    "ToJson nodes before segments");

var rt = LtxPlan.FromJson(json);
Check(rt != null,                                         "FromJson returns non-null");
Check(rt!.V == 2,                                         "FromJson v=2");
Check(rt.Title == "LTX Session",                          "FromJson title");
Check(rt.Start == "2024-01-15T14:00:00Z",                 "FromJson start");
Check(rt.Quantum == 3,                                    "FromJson quantum");
Check(rt.Nodes.Count == 2,                                "FromJson 2 nodes");
Check(rt.Segments.Count == 7,                             "FromJson 7 segments");
Check(rt.Nodes[1].Name == "Mars Hab-01",                  "FromJson node1 name");

// ── EncodeHash / DecodeHash round-trip ────────────────────────────────────

string hash = InterplanetLTX.EncodeHash(goldenPlan);
Check(hash.StartsWith("#l="),                             "EncodeHash starts with #l=");
Check(hash.Length > 5,                                    "EncodeHash non-trivial length");
// No standard base64 chars
Check(!hash.Contains('+'),                                "EncodeHash no + char");
Check(!hash.Contains('/'),                                "EncodeHash no / char");
Check(!hash.Substring(3).Contains('='),                   "EncodeHash no = padding");

var decoded = InterplanetLTX.DecodeHash(hash);
Check(decoded != null,                                    "DecodeHash non-null");
Check(decoded!.Title == "LTX Session",                    "DecodeHash title matches");
Check(decoded.Start == "2024-01-15T14:00:00Z",            "DecodeHash start matches");
Check(decoded.Nodes.Count == 2,                           "DecodeHash 2 nodes");
Check(decoded.Nodes[0].Name == "Earth HQ",                "DecodeHash node0 name");
Check(decoded.Nodes[1].Name == "Mars Hab-01",             "DecodeHash node1 name");

// DecodeHash variants
Check(InterplanetLTX.DecodeHash(hash.Substring(1)) != null, "DecodeHash accepts l=... form");
string rawToken = hash.Substring(3); // strip #l=
Check(InterplanetLTX.DecodeHash(rawToken) != null,        "DecodeHash accepts raw token");
Check(InterplanetLTX.DecodeHash("invalid!!!") == null,    "DecodeHash invalid returns null");
Check(InterplanetLTX.DecodeHash("") == null,              "DecodeHash empty returns null");

// ── BuildNodeUrls ─────────────────────────────────────────────────────────

var urls = InterplanetLTX.BuildNodeUrls(goldenPlan, "https://interplanet.live/ltx.html");
Check(urls.Count == 2,                                    "BuildNodeUrls 2 entries");
Check(urls[0].NodeId == "N0",                             "BuildNodeUrls[0] nodeId=N0");
Check(urls[0].Name == "Earth HQ",                         "BuildNodeUrls[0] name");
Check(urls[0].Role == "HOST",                             "BuildNodeUrls[0] role=HOST");
Check(urls[0].Url.Contains("node=N0"),                    "BuildNodeUrls[0] url has node=N0");
Check(urls[0].Url.Contains("#l="),                        "BuildNodeUrls[0] url has hash");
Check(urls[1].NodeId == "N1",                             "BuildNodeUrls[1] nodeId=N1");
Check(urls[1].Url.Contains("node=N1"),                    "BuildNodeUrls[1] url has node=N1");

// Without baseUrl
var urlsNoBase = InterplanetLTX.BuildNodeUrls(goldenPlan);
Check(urlsNoBase.Count == 2,                              "BuildNodeUrls no base: 2 entries");
Check(urlsNoBase[0].Url.StartsWith("?node="),             "BuildNodeUrls no base: starts with ?node=");

// ── GenerateICS ───────────────────────────────────────────────────────────

string ics = InterplanetLTX.GenerateICS(goldenPlan);
Check(ics.Contains("BEGIN:VCALENDAR"),                    "ICS has BEGIN:VCALENDAR");
Check(ics.Contains("END:VCALENDAR"),                      "ICS has END:VCALENDAR");
Check(ics.Contains("BEGIN:VEVENT"),                       "ICS has BEGIN:VEVENT");
Check(ics.Contains("END:VEVENT"),                         "ICS has END:VEVENT");
Check(ics.Contains("VERSION:2.0"),                        "ICS has VERSION:2.0");
Check(ics.Contains("PRODID:-//InterPlanet//LTX"),         "ICS has PRODID");
Check(ics.Contains("DTSTART:20240115T140000Z"),           "ICS has DTSTART");
Check(ics.Contains("DTEND:20240115T143900Z"),             "ICS has DTEND (39 min)");
Check(ics.Contains($"LTX-PLANID:{planId}"),               "ICS has LTX-PLANID");
Check(ics.Contains("LTX-QUANTUM:PT3M"),                   "ICS has LTX-QUANTUM:PT3M");
Check(ics.Contains("LTX-SEGMENT-TEMPLATE:"),              "ICS has LTX-SEGMENT-TEMPLATE");
Check(ics.Contains("LTX-MODE:LTX"),                       "ICS has LTX-MODE");
Check(ics.Contains("LTX-NODE:ID=EARTH-HQ"),               "ICS has LTX-NODE earth");
Check(ics.Contains("LTX-NODE:ID=MARS-HAB-01"),            "ICS has LTX-NODE mars");
Check(ics.Contains("SUMMARY:LTX Session"),                "ICS has SUMMARY");
Check(ics.Contains("CALSCALE:GREGORIAN"),                 "ICS has CALSCALE");
Check(ics.Contains("METHOD:PUBLISH"),                     "ICS has METHOD:PUBLISH");
// CRLF line endings
Check(ics.Contains("\r\n"),                               "ICS uses CRLF line endings");
// Verify: splitting by CRLF then checking no stray \r or \n
string[] icsLines = ics.Split("\r\n");
Check(icsLines.Length > 10,                               "ICS has >10 CRLF-delimited lines");
// LTX-LOCALTIME for mars node
Check(ics.Contains("LTX-LOCALTIME:NODE=MARS-HAB-01"),     "ICS has LTX-LOCALTIME for mars");

// ── FormatHMS ─────────────────────────────────────────────────────────────

Check(InterplanetLTX.FormatHMS(0)     == "00:00",         "FormatHMS(0)=00:00");
Check(InterplanetLTX.FormatHMS(59)    == "00:59",         "FormatHMS(59)=00:59");
Check(InterplanetLTX.FormatHMS(60)    == "01:00",         "FormatHMS(60)=01:00");
Check(InterplanetLTX.FormatHMS(3599)  == "59:59",         "FormatHMS(3599)=59:59");
Check(InterplanetLTX.FormatHMS(3600)  == "01:00:00",      "FormatHMS(3600)=01:00:00");
Check(InterplanetLTX.FormatHMS(3661)  == "01:01:01",      "FormatHMS(3661)=01:01:01");
Check(InterplanetLTX.FormatHMS(7384)  == "02:03:04",      "FormatHMS(7384)=02:03:04");
Check(InterplanetLTX.FormatHMS(-5)    == "00:00",         "FormatHMS(-5) clamps to 00:00");
Check(InterplanetLTX.FormatHMS(90)    == "01:30",         "FormatHMS(90)=01:30");
Check(InterplanetLTX.FormatHMS(39 * 60) == "39:00",       "FormatHMS(2340)=39:00");

// ── FormatUTC ─────────────────────────────────────────────────────────────

var dt1 = new DateTimeOffset(2024, 1, 15, 14, 0, 0, TimeSpan.Zero);
Check(InterplanetLTX.FormatUTC(dt1) == "14:00:00 UTC",    "FormatUTC 14:00:00");
var dt2 = new DateTimeOffset(2026, 3, 1, 9, 5, 30, TimeSpan.Zero);
Check(InterplanetLTX.FormatUTC(dt2) == "09:05:30 UTC",    "FormatUTC 09:05:30");
var dt3 = new DateTimeOffset(2025, 12, 31, 23, 59, 59, TimeSpan.Zero);
Check(InterplanetLTX.FormatUTC(dt3) == "23:59:59 UTC",    "FormatUTC 23:59:59");
Check(InterplanetLTX.FormatUTC(dt1).EndsWith(" UTC"),     "FormatUTC ends with UTC");

// ── EscapeIcsText (Story 26.3) ────────────────────────────────────────────

Check(InterplanetLTX.EscapeIcsText("") == "",                          "EscapeIcsText empty");
Check(InterplanetLTX.EscapeIcsText("hello") == "hello",               "EscapeIcsText no specials");
Check(InterplanetLTX.EscapeIcsText("a,b") == @"a\,b",                 "EscapeIcsText comma");
Check(InterplanetLTX.EscapeIcsText("a;b") == @"a\;b",                 "EscapeIcsText semicolon");
Check(InterplanetLTX.EscapeIcsText(@"a\b") == @"a\\b",                "EscapeIcsText backslash");
Check(InterplanetLTX.EscapeIcsText("a\nb") == @"a\nb",                "EscapeIcsText newline");
Check(InterplanetLTX.EscapeIcsText("a,b;c") == @"a\,b\;c",            "EscapeIcsText comma and semicolon");

// ICS SUMMARY should contain escaped title
var escapedPlan = InterplanetLTX.CreatePlan(title: "Hello, World; Test", start: "2024-01-15T14:00:00Z");
string escapedIcs = InterplanetLTX.GenerateICS(escapedPlan);
Check(escapedIcs.Contains(@"SUMMARY:Hello\, World\; Test"),            "ICS SUMMARY escaped commas and semicolons");

// ── SessionState / SessionStateNames (Story 26.4) ─────────────────────────

Check(SessionState.Degraded == SessionState.Degraded,                  "SessionState.Degraded exists");
Check(SessionState.Init == SessionState.Init,                          "SessionState.Init exists");
Check(SessionState.Locked == SessionState.Locked,                      "SessionState.Locked exists");
Check(SessionState.Running == SessionState.Running,                    "SessionState.Running exists");
Check(SessionState.Complete == SessionState.Complete,                  "SessionState.Complete exists");
Check(SessionStateNames.All.Length == 5,                               "SessionStateNames.All has 5 entries");
Check(SessionStateNames.All[3] == "DEGRADED",                          "SessionStateNames.All[3] is DEGRADED");
Check(SessionStateNames.All[0] == "INIT",                              "SessionStateNames.All[0] is INIT");
Check(SessionStateNames.All[4] == "COMPLETE",                          "SessionStateNames.All[4] is COMPLETE");
Check(Constants.SESSION_STATES.Length == 5,                            "Constants.SESSION_STATES has 5 entries");
Check(Constants.SESSION_STATES[3] == "DEGRADED",                       "Constants.SESSION_STATES[3] is DEGRADED");
Check(Array.IndexOf(Constants.SESSION_STATES, "DEGRADED") >= 0,        "Constants.SESSION_STATES contains DEGRADED");

// ── planLockTimeoutMs / DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR (Story 26.4) ─────

Check(Constants.DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR == 2,                 "DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR is 2");
Check(InterplanetLTX.PlanLockTimeoutMs(100) == 200000,                 "PlanLockTimeoutMs(100) == 200000");
Check(InterplanetLTX.PlanLockTimeoutMs(0) == 0,                        "PlanLockTimeoutMs(0) == 0");
Check(InterplanetLTX.PlanLockTimeoutMs(60) == 120000,                  "PlanLockTimeoutMs(60) == 120000");

// ── checkDelayViolation (Story 26.4) ──────────────────────────────────────

Check(Constants.DELAY_VIOLATION_WARN_S == 120,                         "DELAY_VIOLATION_WARN_S is 120");
Check(Constants.DELAY_VIOLATION_DEGRADED_S == 300,                     "DELAY_VIOLATION_DEGRADED_S is 300");
Check(InterplanetLTX.CheckDelayViolation(100, 100) == "ok",            "CheckDelayViolation ok (same)");
Check(InterplanetLTX.CheckDelayViolation(100, 210) == "ok",            "CheckDelayViolation ok (within 120)");
Check(InterplanetLTX.CheckDelayViolation(100, 221) == "violation",     "CheckDelayViolation violation (>120)");
Check(InterplanetLTX.CheckDelayViolation(100, 401) == "degraded",      "CheckDelayViolation degraded (>300)");
Check(InterplanetLTX.CheckDelayViolation(0, 120) == "ok",              "CheckDelayViolation boundary 120 ok");
Check(InterplanetLTX.CheckDelayViolation(0, 301) == "degraded",        "CheckDelayViolation boundary 301 degraded");

// ── ComputeSegments quantum guard (Story 26.4) ────────────────────────────

var badPlan = InterplanetLTX.CreatePlan(start: "2024-01-15T14:00:00Z");
badPlan.Quantum = 0;
bool badQuantumThrew = false;
try { InterplanetLTX.ComputeSegments(badPlan); } catch (ArgumentException) { badQuantumThrew = true; }
Check(badQuantumThrew,                                                  "ComputeSegments quantum=0 throws");

var badPlan2 = InterplanetLTX.CreatePlan(start: "2024-01-15T14:00:00Z");
badPlan2.Quantum = -1;
bool badQuantumThrew2 = false;
try { InterplanetLTX.ComputeSegments(badPlan2); } catch (ArgumentException) { badQuantumThrew2 = true; }
Check(badQuantumThrew2,                                                 "ComputeSegments quantum=-1 throws");

SecurityTests.Run(Check);

// ── Summary ───────────────────────────────────────────────────────────────

Console.WriteLine();
Console.WriteLine($"{passed} passed  {failed} failed");
Environment.Exit(failed > 0 ? 1 : 0);
