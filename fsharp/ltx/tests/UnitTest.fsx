#!/usr/bin/env dotnet-script
// UnitTest.fsx --- Unit tests for InterplanetLtx F# library (Story 33.14)
// >= 80 check() assertions covering all public API functions.
// Run with: dotnet fsi tests/UnitTest.fsx

#load "../src/Models.fs"
#load "../src/Constants.fs"
#load "../src/InterplanetLtx.fs"

open System
open InterplanetLtx.Models
open InterplanetLtx.Constants
open InterplanetLtx.InterplanetLtx

let mutable passed = 0
let mutable failed = 0

let check (cond: bool) (msg: string) =
    if cond then
        passed <- passed + 1
        printfn "PASS: %s" msg
    else
        failed <- failed + 1
        printfn "FAIL: %s" msg

// ── VERSION / Constants ───────────────────────────────────────────────────────

check (VERSION = "1.0.0")                                   "VERSION is 1.0.0"
check (DEFAULT_QUANTUM = 3)                                 "DEFAULT_QUANTUM is 3"
check (DEFAULT_SEGMENTS.Length = 7)                         "DEFAULT_SEGMENTS has 7 entries"
check (SEG_TYPES.Length = 6)                                "SEG_TYPES has 6 entries"
check (SEG_TYPES.[0] = "PLAN_CONFIRM")                      "SEG_TYPES[0] is PLAN_CONFIRM"
check (SEG_TYPES.[1] = "TX")                                "SEG_TYPES[1] is TX"
check (SEG_TYPES.[2] = "RX")                                "SEG_TYPES[2] is RX"
check (SEG_TYPES.[3] = "CAUCUS")                            "SEG_TYPES[3] is CAUCUS"
check (SEG_TYPES.[5] = "BUFFER")                            "SEG_TYPES[5] is BUFFER"
check (DEFAULT_API_BASE = "https://api.interplanet.app/ltx") "DEFAULT_API_BASE is correct"
check (DEFAULT_API_BASE.Contains("interplanet"))            "DEFAULT_API_BASE has domain"

// DEFAULT_SEGMENTS content
check (DEFAULT_SEGMENTS.[0].segType = "PLAN_CONFIRM")       "DEFAULT_SEGMENTS[0]=PLAN_CONFIRM"
check (DEFAULT_SEGMENTS.[0].q = 2)                          "DEFAULT_SEGMENTS[0] q=2"
check (DEFAULT_SEGMENTS.[1].segType = "TX")                 "DEFAULT_SEGMENTS[1]=TX"
check (DEFAULT_SEGMENTS.[2].segType = "RX")                 "DEFAULT_SEGMENTS[2]=RX"
check (DEFAULT_SEGMENTS.[3].segType = "CAUCUS")             "DEFAULT_SEGMENTS[3]=CAUCUS"
check (DEFAULT_SEGMENTS.[6].segType = "BUFFER")             "DEFAULT_SEGMENTS[6]=BUFFER"
check (DEFAULT_SEGMENTS.[6].q = 1)                          "DEFAULT_SEGMENTS[6] q=1"

// ── createPlanFromConfig (golden plan) ───────────────────────────────────────

let goldenPlan =
    createPlanFromConfig {|
        title          = "LTX Session"
        start          = "2024-01-15T14:00:00Z"
        nodes          = [
            {| id = "N0"; name = "Earth HQ";    role = "HOST";        delay = 0; location = "earth" |}
            {| id = "N1"; name = "Mars Hab-01"; role = "PARTICIPANT"; delay = 0; location = "mars"  |}
        ]
        quantum        = 3
        mode           = "LTX"
        hostName       = ""
        hostLocation   = ""
        remoteName     = ""
        remoteLocation = ""
        delay          = 0
        segments       = []
    |}

check (goldenPlan.v = 2)                                    "goldenPlan v=2"
check (goldenPlan.title = "LTX Session")                    "goldenPlan title=LTX Session"
check (goldenPlan.start = "2024-01-15T14:00:00Z")           "goldenPlan start correct"
check (goldenPlan.quantum = 3)                              "goldenPlan quantum=3"
check (goldenPlan.mode = "LTX")                             "goldenPlan mode=LTX"
check (goldenPlan.nodes.Length = 2)                         "goldenPlan has 2 nodes"
check (goldenPlan.segments.Length = 7)                      "goldenPlan has 7 segments"
check (goldenPlan.nodes.[0].id = "N0")                      "goldenPlan node0 id=N0"
check (goldenPlan.nodes.[0].name = "Earth HQ")              "goldenPlan node0 name=Earth HQ"
check (goldenPlan.nodes.[0].role = "HOST")                  "goldenPlan node0 role=HOST"
check (goldenPlan.nodes.[0].delay = 0)                      "goldenPlan node0 delay=0"
check (goldenPlan.nodes.[0].location = "earth")             "goldenPlan node0 location=earth"
check (goldenPlan.nodes.[1].id = "N1")                      "goldenPlan node1 id=N1"
check (goldenPlan.nodes.[1].name = "Mars Hab-01")           "goldenPlan node1 name=Mars Hab-01"
check (goldenPlan.nodes.[1].role = "PARTICIPANT")           "goldenPlan node1 role=PARTICIPANT"
check (goldenPlan.nodes.[1].location = "mars")              "goldenPlan node1 location=mars"

// ── createPlanFromConfig with custom args ─────────────────────────────────────

let plan2 =
    createPlanFromConfig {|
        title          = "My Session"
        start          = "2024-06-01T10:00:00Z"
        nodes          = []
        quantum        = 5
        mode           = "ASYNC"
        hostName       = "Ground Control"
        hostLocation   = "earth"
        remoteName     = "Lunar Base"
        remoteLocation = "moon"
        delay          = 1200
        segments       = []
    |}

check (plan2.title = "My Session")                          "plan2 title=My Session"
check (plan2.start = "2024-06-01T10:00:00Z")                "plan2 start correct"
check (plan2.quantum = 5)                                   "plan2 quantum=5"
check (plan2.mode = "ASYNC")                                "plan2 mode=ASYNC"
check (plan2.nodes.[0].name = "Ground Control")             "plan2 node0 name=Ground Control"
check (plan2.nodes.[1].name = "Lunar Base")                 "plan2 node1 name=Lunar Base"
check (plan2.nodes.[1].delay = 1200)                        "plan2 node1 delay=1200"
check (plan2.nodes.[1].location = "moon")                   "plan2 node1 location=moon"

// ── computeSegments ───────────────────────────────────────────────────────────

let segs = computeSegments goldenPlan
check (segs.Length = 7)                                     "computeSegments count=7"
check (segs.[0].segType = "PLAN_CONFIRM")                   "segs[0] type=PLAN_CONFIRM"
check (segs.[0].q = 2)                                      "segs[0] q=2"
check (segs.[0].durationMs = 6 * 60 * 1000)                 "segs[0] durationMs=360000"
check (segs.[0].startMs = 1705327200000L)                   "segs[0] startMs=1705327200000"
check (segs.[1].segType = "TX")                             "segs[1] type=TX"
check (segs.[2].segType = "RX")                             "segs[2] type=RX"
check (segs.[3].segType = "CAUCUS")                         "segs[3] type=CAUCUS"
check (segs.[6].segType = "BUFFER")                         "segs[6] type=BUFFER"
check (segs.[6].q = 1)                                      "segs[6] q=1"
check (segs.[6].durationMs = 3 * 60 * 1000)                 "segs[6] durationMs=180000"
// end of session: 14:00 + 39 min = 14:39
let expectedEndMs = 1705327200000L + 39L * 60L * 1000L
check (segs.[6].endMs = expectedEndMs)                      "segs[6] endMs=14:39"

// ── totalMin ──────────────────────────────────────────────────────────────────

check (totalMin goldenPlan = 39)                            "totalMin default plan = 39"
check (totalMin plan2 = 65)                                 "totalMin quantum=5 plan = 65"

let plan3 =
    createPlanFromConfig {|
        title = ""; start = "2025-01-01T00:00:00Z"; nodes = []; quantum = 1; mode = ""
        hostName = ""; hostLocation = ""; remoteName = ""; remoteLocation = ""; delay = 0; segments = []
    |}
check (totalMin plan3 = 13)                                 "totalMin quantum=1 = 13"

// ── makePlanId (golden hash) ──────────────────────────────────────────────────

let planId = makePlanId goldenPlan
check (planId = "LTX-20240115-EARTHHQ-MARS-v2-cc8a7fc0")    "makePlanId golden hash matches JS"
check (planId.StartsWith("LTX-"))                           "makePlanId starts with LTX-"
check (planId.Contains("20240115"))                         "makePlanId contains date"
check (planId.Contains("EARTHHQ"))                          "makePlanId contains EARTHHQ"
check (planId.Contains("MARS"))                             "makePlanId contains MARS"
check (planId.Contains("-v2-"))                             "makePlanId contains -v2-"
check (planId.EndsWith("cc8a7fc0"))                         "makePlanId ends with golden hash"

let pid2 =
    let p =
        createPlanFromConfig {|
            title = "LTX Session"; start = "2026-03-01T10:00:00Z"; nodes = []; quantum = 3; mode = "LTX"
            hostName = ""; hostLocation = ""; remoteName = ""; remoteLocation = ""; delay = 0; segments = []
        |}
    makePlanId p
check (pid2.StartsWith("LTX-20260301"))                     "makePlanId date from start field"
check (pid2.Length > 20)                                    "makePlanId reasonable length"

// ── toJson / fromJson ─────────────────────────────────────────────────────────

let json = toJson goldenPlan
check (json.Contains("\"v\":2"))                            "toJson has v:2"
check (json.Contains("\"title\":\"LTX Session\""))          "toJson has title"
check (json.Contains("\"start\":\"2024-01-15T14:00:00Z\"")) "toJson has start"
check (json.Contains("\"quantum\":3"))                      "toJson has quantum"
check (json.Contains("\"mode\":\"LTX\""))                   "toJson has mode"
check (json.Contains("\"nodes\":["))                        "toJson has nodes"
check (json.Contains("\"segments\":["))                     "toJson has segments"

// nodes BEFORE segments (critical for hash)
let nodesIdx = json.IndexOf("\"nodes\":[")
let segsIdx  = json.IndexOf("\"segments\":[")
check (nodesIdx > -1)                                       "toJson nodes array present"
check (segsIdx > -1)                                        "toJson segments array present"
check (nodesIdx < segsIdx)                                  "toJson nodes before segments"

let rt = fromJson json
check (rt.IsSome)                                           "fromJson returns Some"
let rtp = rt.Value
check (rtp.v = 2)                                           "fromJson v=2"
check (rtp.title = "LTX Session")                           "fromJson title"
check (rtp.start = "2024-01-15T14:00:00Z")                  "fromJson start"
check (rtp.quantum = 3)                                     "fromJson quantum"
check (rtp.nodes.Length = 2)                                "fromJson 2 nodes"
check (rtp.segments.Length = 7)                             "fromJson 7 segments"
check (rtp.nodes.[1].name = "Mars Hab-01")                  "fromJson node1 name"
check (rtp.nodes.[0].location = "earth")                    "fromJson node0 location"

check (fromJson "invalid json" = None)                      "fromJson invalid returns None"

// ── encodeHash / decodeHash ───────────────────────────────────────────────────

let hash = encodeHash goldenPlan
check (hash.StartsWith("#l="))                              "encodeHash starts with #l="
check (hash.Length > 5)                                     "encodeHash non-trivial length"
check (not (hash.Contains("+")))                            "encodeHash no + char"
check (not (hash.Contains("/")))                            "encodeHash no / char"
check (not (hash.Substring(3).Contains("=")))               "encodeHash no = padding"

let decoded = decodeHash hash
check (decoded.IsSome)                                      "decodeHash returns Some"
let dp = decoded.Value
check (dp.title = "LTX Session")                            "decodeHash title matches"
check (dp.start = "2024-01-15T14:00:00Z")                   "decodeHash start matches"
check (dp.nodes.Length = 2)                                 "decodeHash 2 nodes"
check (dp.nodes.[0].name = "Earth HQ")                      "decodeHash node0 name"
check (dp.nodes.[1].name = "Mars Hab-01")                   "decodeHash node1 name"

// decodeHash variants
check ((decodeHash (hash.Substring(1))).IsSome)             "decodeHash accepts l=... form"
let rawToken = hash.Substring(3)  // strip #l=
check ((decodeHash rawToken).IsSome)                        "decodeHash accepts raw token"
check ((decodeHash "invalid!!!") = None)                    "decodeHash invalid returns None"
check ((decodeHash "") = None)                              "decodeHash empty returns None"

// ── buildNodeUrls ─────────────────────────────────────────────────────────────

let urls = buildNodeUrls goldenPlan "https://interplanet.live/ltx.html"
check (urls.Length = 2)                                     "buildNodeUrls 2 entries"
check (urls.[0].nodeId = "N0")                              "buildNodeUrls[0] nodeId=N0"
check (urls.[0].nodeName = "Earth HQ")                      "buildNodeUrls[0] nodeName"
check (urls.[0].url.Contains("node=N0"))                    "buildNodeUrls[0] url has node=N0"
check (urls.[0].url.Contains("#l="))                        "buildNodeUrls[0] url has hash"
check (urls.[1].nodeId = "N1")                              "buildNodeUrls[1] nodeId=N1"
check (urls.[1].url.Contains("node=N1"))                    "buildNodeUrls[1] url has node=N1"

let urlsNoBase = buildNodeUrls goldenPlan ""
check (urlsNoBase.Length = 2)                               "buildNodeUrls no base: 2 entries"
check (urlsNoBase.[0].url.StartsWith("?node="))             "buildNodeUrls no base: starts with ?node="

// ── generateICS ───────────────────────────────────────────────────────────────

let ics = generateICS goldenPlan
check (ics.Contains("BEGIN:VCALENDAR"))                     "ICS has BEGIN:VCALENDAR"
check (ics.Contains("END:VCALENDAR"))                       "ICS has END:VCALENDAR"
check (ics.Contains("BEGIN:VEVENT"))                        "ICS has BEGIN:VEVENT"
check (ics.Contains("END:VEVENT"))                          "ICS has END:VEVENT"
check (ics.Contains("VERSION:2.0"))                         "ICS has VERSION:2.0"
check (ics.Contains("PRODID:-//InterPlanet//LTX"))          "ICS has PRODID"
check (ics.Contains("DTSTART:20240115T140000Z"))             "ICS has DTSTART"
check (ics.Contains("DTEND:20240115T143900Z"))               "ICS has DTEND (39 min)"
check (ics.Contains(sprintf "LTX-PLANID:%s" planId))        "ICS has LTX-PLANID"
check (ics.Contains("LTX-QUANTUM:PT3M"))                    "ICS has LTX-QUANTUM:PT3M"
check (ics.Contains("LTX-SEGMENT-TEMPLATE:"))               "ICS has LTX-SEGMENT-TEMPLATE"
check (ics.Contains("LTX-MODE:LTX"))                        "ICS has LTX-MODE"
check (ics.Contains("LTX-NODE:ID=EARTH-HQ"))                "ICS has LTX-NODE earth"
check (ics.Contains("LTX-NODE:ID=MARS-HAB-01"))             "ICS has LTX-NODE mars"
check (ics.Contains("SUMMARY:LTX Session"))                 "ICS has SUMMARY"
check (ics.Contains("CALSCALE:GREGORIAN"))                  "ICS has CALSCALE"
check (ics.Contains("METHOD:PUBLISH"))                      "ICS has METHOD:PUBLISH"
check (ics.Contains("\r\n"))                                "ICS uses CRLF line endings"
let icsLines = ics.Split("\r\n")
check (icsLines.Length > 10)                                "ICS has >10 CRLF lines"
check (ics.Contains("LTX-LOCALTIME:NODE=MARS-HAB-01"))      "ICS has LTX-LOCALTIME for mars"

// ── formatHMS ─────────────────────────────────────────────────────────────────

check (formatHMS 0     = "00:00")                           "formatHMS(0)=00:00"
check (formatHMS 59    = "00:59")                           "formatHMS(59)=00:59"
check (formatHMS 60    = "01:00")                           "formatHMS(60)=01:00"
check (formatHMS 3599  = "59:59")                           "formatHMS(3599)=59:59"
check (formatHMS 3600  = "01:00:00")                        "formatHMS(3600)=01:00:00"
check (formatHMS 3661  = "01:01:01")                        "formatHMS(3661)=01:01:01"
check (formatHMS 7384  = "02:03:04")                        "formatHMS(7384)=02:03:04"
check (formatHMS -5    = "00:00")                           "formatHMS(-5) clamps to 00:00"
check (formatHMS 90    = "01:30")                           "formatHMS(90)=01:30"
check (formatHMS (39 * 60) = "39:00")                       "formatHMS(2340)=39:00"
check (formatHMS 86399 = "23:59:59")                        "formatHMS(86399)=23:59:59"

// ── formatUTC ─────────────────────────────────────────────────────────────────

check (formatUTC 1705327200000L = "2024-01-15T14:00:00Z")   "formatUTC 2024-01-15T14:00:00Z"
check (formatUTC 0L             = "1970-01-01T00:00:00Z")   "formatUTC epoch zero"
check ((formatUTC 1705327200000L).EndsWith("Z"))             "formatUTC ends with Z"

// ── djbHash ───────────────────────────────────────────────────────────────────

check (djbHash "" = "00000000")                             "djbHash empty string"
check ((djbHash "hello").Length = 8)                        "djbHash length=8"
// The golden hash is produced by toJson of goldenPlan
let goldenJson = toJson goldenPlan
let goldenHash = djbHash goldenJson
check (goldenHash = "cc8a7fc0")                             "djbHash golden value cc8a7fc0"

// ── base64url round-trip ──────────────────────────────────────────────────────

// Test base64url via encodeHash (public API)
let encHash = encodeHash goldenPlan
let b64part = encHash.Substring(3)  // strip #l=
check (not (b64part.Contains("+")))                         "base64url no +"
check (not (b64part.Contains("/")))                         "base64url no /"
check (not (b64part.Contains("=")))                         "base64url no ="
check (b64part.Length > 0)                                  "base64url non-empty"

// ── escapeIcsText (Story 26.3) ────────────────────────────────────────────────

check (escapeIcsText "" = "")                                   "escapeIcsText empty string"
check (escapeIcsText "hello" = "hello")                         "escapeIcsText no specials"
check (escapeIcsText "a,b" = "a\\,b")                           "escapeIcsText escapes comma"
check (escapeIcsText "a;b" = "a\\;b")                           "escapeIcsText escapes semicolon"
check (escapeIcsText "a\\b" = "a\\\\b")                         "escapeIcsText escapes backslash"
check (escapeIcsText "a\nb" = "a\\nb")                          "escapeIcsText escapes newline"
check (escapeIcsText "a,b;c\\d\ne" = "a\\,b\\;c\\\\d\\ne")     "escapeIcsText all specials"

// ICS SUMMARY uses escapeIcsText on plan title
let icsTitle = "Mars,Earth;Session"
let specialPlan =
    createPlanFromConfig {|
        title = icsTitle; start = "2024-01-15T14:00:00Z"; nodes = []; quantum = 3; mode = "LTX"
        hostName = ""; hostLocation = ""; remoteName = ""; remoteLocation = ""; delay = 0; segments = []
    |}
let icsSpecial = generateICS specialPlan
check (icsSpecial.Contains("SUMMARY:Mars\\,Earth\\;Session"))   "generateICS SUMMARY escapes title specials"

// ── Story 26.4 — Protocol hardening ──────────────────────────────────────────

// Constants
check (DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR = 2)                    "DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR is 2"
check (DELAY_VIOLATION_WARN_S = 120)                            "DELAY_VIOLATION_WARN_S is 120"
check (DELAY_VIOLATION_DEGRADED_S = 300)                        "DELAY_VIOLATION_DEGRADED_S is 300"

// SESSION_STATES
check (SESSION_STATES.Length = 5)                               "SESSION_STATES has 5 entries"
check (SESSION_STATES.[0] = "INIT")                             "SESSION_STATES[0]=INIT"
check (SESSION_STATES.[1] = "LOCKED")                           "SESSION_STATES[1]=LOCKED"
check (SESSION_STATES.[2] = "RUNNING")                          "SESSION_STATES[2]=RUNNING"
check (SESSION_STATES.[3] = "DEGRADED")                         "SESSION_STATES[3]=DEGRADED"
check (SESSION_STATES.[4] = "COMPLETE")                         "SESSION_STATES[4]=COMPLETE"
check (SESSION_STATES |> Array.contains "DEGRADED")             "SESSION_STATES contains DEGRADED"

// planLockTimeoutMs
check (planLockTimeoutMs 0L   = 0L)                             "planLockTimeoutMs(0)=0"
check (planLockTimeoutMs 100L = 200000L)                        "planLockTimeoutMs(100)=200000"
check (planLockTimeoutMs 60L  = 120000L)                        "planLockTimeoutMs(60)=120000"
check (planLockTimeoutMs 1000L = 2000000L)                      "planLockTimeoutMs(1000)=2000000"

// checkDelayViolation
check (checkDelayViolation 100L 100L = "ok")                    "checkDelayViolation same=ok"
check (checkDelayViolation 100L 200L = "ok")                    "checkDelayViolation diff=100=ok"
check (checkDelayViolation 100L 220L = "ok")                    "checkDelayViolation diff=120=ok (boundary)"
check (checkDelayViolation 100L 221L = "violation")             "checkDelayViolation diff=121=violation"
check (checkDelayViolation 100L 400L = "violation")             "checkDelayViolation diff=300=violation (boundary)"
check (checkDelayViolation 100L 401L = "degraded")              "checkDelayViolation diff=301=degraded"
check (checkDelayViolation 500L 100L = "degraded")              "checkDelayViolation negative diff=degraded"
check (checkDelayViolation 0L 0L = "ok")                        "checkDelayViolation both zero=ok"

// computeSegments quantum guard
let badPlan0 =
    { goldenPlan with quantum = 0 }
let mutable badQuantumThrew0 = false
try
    computeSegments badPlan0 |> ignore
with
| :? ArgumentException -> badQuantumThrew0 <- true
| _ -> ()
check badQuantumThrew0                                          "computeSegments quantum=0 throws ArgumentException"

let badPlanNeg =
    { goldenPlan with quantum = -1 }
let mutable badQuantumThrewNeg = false
try
    computeSegments badPlanNeg |> ignore
with
| :? ArgumentException -> badQuantumThrewNeg <- true
| _ -> ()
check badQuantumThrewNeg                                        "computeSegments quantum=-1 throws ArgumentException"

// ── Summary ───────────────────────────────────────────────────────────────────

printfn ""
printfn "%d passed  %d failed" passed failed
if failed > 0 then exit 1
