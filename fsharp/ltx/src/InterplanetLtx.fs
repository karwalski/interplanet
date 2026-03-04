// InterplanetLtx.fs --- Main API module
// F# port of ltx-sdk.js (Story 33.14)
//
// All algorithms match ltx-sdk.js exactly:
//   - Same polynomial hash (h = 31*h + charCode, uint32)
//   - Same base64url (Convert.ToBase64String -> replace + - / _ strip =)
//   - JSON key order in toJson(): v, title, start, quantum, mode, nodes, segments
//     (nodes BEFORE segments -- critical for hash conformance)
//   - CRLF line endings in ICS

module InterplanetLtx.InterplanetLtx

open System
open System.Text
open InterplanetLtx.Models
open InterplanetLtx.Constants

// ── Polynomial hash ──────────────────────────────────────────────────────────
// Matches JS: h = (Math.imul(31, h) + raw.charCodeAt(i)) >>> 0
// Operates on UTF-16 char values (same as JS charCodeAt)

let djbHash (s: string) : string =
    let mutable h = 0u
    for c in s do
        h <- (h * 31u + uint32 c) &&& 0xFFFFFFFFu
    sprintf "%08x" h

// ── Base64url helpers ────────────────────────────────────────────────────────

let base64UrlEncode (bytes: byte[]) : string =
    Convert.ToBase64String(bytes)
        .Replace('+', '-').Replace('/', '_').TrimEnd('=')

let private b64Enc (json: string) : string =
    let bytes = Encoding.UTF8.GetBytes(json)
    base64UrlEncode bytes

let private b64Dec (token: string) : string option =
    try
        let mutable s = token.Replace('-', '+').Replace('_', '/')
        let m = s.Length % 4
        if m = 2 then s <- s + "=="
        elif m = 3 then s <- s + "="
        let bytes = Convert.FromBase64String(s)
        Some(Encoding.UTF8.GetString(bytes))
    with _ -> None

// ── JSON helpers ─────────────────────────────────────────────────────────────

let private jsonString (s: string) : string =
    let sb = StringBuilder("\"")
    for c in s do
        match c with
        | '"'  -> sb.Append("\\\"") |> ignore
        | '\\' -> sb.Append("\\\\") |> ignore
        | '\n' -> sb.Append("\\n")  |> ignore
        | '\r' -> sb.Append("\\r")  |> ignore
        | '\t' -> sb.Append("\\t")  |> ignore
        | c when int c < 0x20 -> sb.Append(sprintf "\\u%04x" (int c)) |> ignore
        | c    -> sb.Append(c) |> ignore
    sb.Append('"') |> ignore
    sb.ToString()

// ── toJson / fromJson ─────────────────────────────────────────────────────────
// Key order: v, title, start, quantum, mode, nodes, segments
// nodes BEFORE segments -- critical for polynomial hash conformance

let toJson (plan: LtxPlan) : string =
    // nodes array
    let nodesJson =
        plan.nodes
        |> List.map (fun n ->
            sprintf "{\"id\":%s,\"name\":%s,\"role\":%s,\"delay\":%d,\"location\":%s}"
                (jsonString n.id) (jsonString n.name) (jsonString n.role) n.delay (jsonString n.location))
        |> String.concat ","

    // segments array
    let segsJson =
        plan.segments
        |> List.map (fun s ->
            sprintf "{\"type\":%s,\"q\":%d}" (jsonString s.segType) s.q)
        |> String.concat ","

    sprintf "{\"v\":%d,\"title\":%s,\"start\":%s,\"quantum\":%d,\"mode\":%s,\"nodes\":[%s],\"segments\":[%s]}"
        plan.v (jsonString plan.title) (jsonString plan.start) plan.quantum (jsonString plan.mode)
        nodesJson segsJson

// ── Manual JSON parser ────────────────────────────────────────────────────────

let private parseStringField (json: string) (key: string) : string option =
    let pattern = sprintf "\"%s\":\"" key
    let idx = json.IndexOf(pattern, StringComparison.Ordinal)
    if idx < 0 then None
    else
        let mutable i = idx + pattern.Length
        let sb = StringBuilder()
        let mutable escaped = false
        let mutable stop = false
        while i < json.Length && not stop do
            let c = json.[i]
            if escaped then
                match c with
                | '"'  -> sb.Append('"')  |> ignore
                | '\\' -> sb.Append('\\') |> ignore
                | 'n'  -> sb.Append('\n') |> ignore
                | 'r'  -> sb.Append('\r') |> ignore
                | 't'  -> sb.Append('\t') |> ignore
                | _    -> sb.Append(c)    |> ignore
                escaped <- false
            elif c = '\\' then escaped <- true
            elif c = '"'  then stop <- true
            else sb.Append(c) |> ignore
            i <- i + 1
        Some(sb.ToString())

let private parseIntField (json: string) (key: string) : int option =
    let pattern = sprintf "\"%s\":" key
    let idx = json.IndexOf(pattern, StringComparison.Ordinal)
    if idx < 0 then None
    else
        let mutable i = idx + pattern.Length
        while i < json.Length && json.[i] = ' ' do i <- i + 1
        let start = i
        while i < json.Length && (Char.IsDigit(json.[i]) || json.[i] = '-') do i <- i + 1
        if i = start then None
        else
            match Int32.TryParse(json.Substring(start, i - start)) with
            | true, v -> Some v
            | _       -> None

let private splitObjects (arr: string) : string list =
    let result = ResizeArray<string>()
    let mutable depth = 0
    let mutable start = 0
    let mutable inStr = false
    let mutable escaped = false
    let mutable i = 0
    while i < arr.Length do
        let c = arr.[i]
        if escaped then escaped <- false
        elif c = '\\' && inStr then escaped <- true
        elif c = '"'  then inStr <- not inStr
        elif not inStr then
            if c = '{' then
                if depth = 0 then start <- i + 1
                depth <- depth + 1
            elif c = '}' then
                depth <- depth - 1
                if depth = 0 then
                    result.Add(arr.Substring(start, i - start))
        i <- i + 1
    result |> Seq.toList

let private parseNodes (json: string) : LtxNode list =
    let marker = "\"nodes\":["
    let idx = json.IndexOf(marker, StringComparison.Ordinal)
    if idx < 0 then []
    else
        let mutable i = idx + marker.Length
        let mutable depth = 1
        let sb = StringBuilder("[")
        while i < json.Length && depth > 0 do
            let c = json.[i]
            sb.Append(c) |> ignore
            if c = '[' then depth <- depth + 1
            elif c = ']' then depth <- depth - 1
            i <- i + 1
        let arr = sb.ToString().TrimEnd(']').TrimStart('[')
        splitObjects arr
        |> List.choose (fun item ->
            let w = "{" + item + "}"
            match parseStringField w "id", parseStringField w "name",
                  parseStringField w "role", parseStringField w "location" with
            | Some id, Some name, Some role, Some location ->
                let delay = parseIntField w "delay" |> Option.defaultValue 0
                Some { id = id; name = name; role = role; delay = delay; location = location }
            | _ -> None)

let private parseSegments (json: string) : LtxSegmentTemplate list =
    let marker = "\"segments\":["
    let idx = json.IndexOf(marker, StringComparison.Ordinal)
    if idx < 0 then []
    else
        let mutable i = idx + marker.Length
        let mutable depth = 1
        let sb = StringBuilder("[")
        while i < json.Length && depth > 0 do
            let c = json.[i]
            sb.Append(c) |> ignore
            if c = '[' then depth <- depth + 1
            elif c = ']' then depth <- depth - 1
            i <- i + 1
        let arr = sb.ToString().TrimEnd(']').TrimStart('[')
        splitObjects arr
        |> List.choose (fun item ->
            let w = "{" + item + "}"
            match parseStringField w "type", parseIntField w "q" with
            | Some t, Some q -> Some { segType = t; q = q }
            | _ -> None)

let fromJson (json: string) : LtxPlan option =
    if String.IsNullOrEmpty(json) then None
    elif not (json.Contains("{")) then None
    else
    try
        let v       = parseIntField    json "v"       |> Option.defaultValue 2
        let title   = parseStringField json "title"   |> Option.defaultValue ""
        let start   = parseStringField json "start"   |> Option.defaultValue ""
        let quantum = parseIntField    json "quantum"  |> Option.defaultValue DEFAULT_QUANTUM
        let mode    = parseStringField json "mode"    |> Option.defaultValue "LTX"
        let nodes    = parseNodes    json
        let segments = parseSegments json
        // Require at least one valid field to distinguish from truly invalid input
        if start = "" && title = "" && nodes.IsEmpty then None
        else
        Some {
            v = v; title = title; start = start
            quantum = quantum; mode = mode
            nodes = nodes; segments = segments
            planId = None
        }
    with _ -> None

// ── ISO date helpers ──────────────────────────────────────────────────────────

let private parseIsoToEpochMs (iso: string) : int64 =
    try
        DateTimeOffset.Parse(iso,
            Globalization.CultureInfo.InvariantCulture,
            Globalization.DateTimeStyles.AssumeUniversal).ToUnixTimeMilliseconds()
    with _ -> 0L

let private fmtDT (epochMs: int64) : string =
    DateTimeOffset.FromUnixTimeMilliseconds(epochMs)
        .ToUniversalTime()
        .ToString("yyyyMMdd'T'HHmmss'Z'")

let private toId (name: string) : string =
    name.Replace(" ", "-").ToUpper()

// ── 1. createPlan ─────────────────────────────────────────────────────────────

/// Create a new LTX session plan with default Earth HQ -> Mars Hab-01 nodes.
let createPlan (opts: {| title: string; start: string; nodes: {| id: string; name: string; role: string; delay: int; location: string |} list |} option) : LtxPlan =
    let defaultStart () =
        let now = DateTimeOffset.UtcNow.AddMinutes(5.0)
        let rounded = DateTimeOffset(now.Year, now.Month, now.Day, now.Hour, now.Minute, 0, TimeSpan.Zero)
        rounded.ToString("yyyy-MM-ddTHH:mm:ssZ")

    match opts with
    | None ->
        {
            v = 2; title = "LTX Session"; start = defaultStart()
            quantum = DEFAULT_QUANTUM; mode = "LTX"
            nodes = [
                { id = "N0"; name = "Earth HQ";    role = "HOST";        delay = 0; location = "earth" }
                { id = "N1"; name = "Mars Hab-01"; role = "PARTICIPANT"; delay = 0; location = "mars"  }
            ]
            segments = DEFAULT_SEGMENTS
            planId = None
        }
    | Some o ->
        let planNodes =
            if o.nodes.Length > 0 then
                o.nodes |> List.map (fun n -> { id = n.id; name = n.name; role = n.role; delay = n.delay; location = n.location })
            else
                [
                    { id = "N0"; name = "Earth HQ";    role = "HOST";        delay = 0; location = "earth" }
                    { id = "N1"; name = "Mars Hab-01"; role = "PARTICIPANT"; delay = 0; location = "mars"  }
                ]
        let startVal = if o.start = "" then defaultStart() else o.start
        {
            v = 2; title = (if o.title = "" then "LTX Session" else o.title)
            start = startVal; quantum = DEFAULT_QUANTUM; mode = "LTX"
            nodes = planNodes; segments = DEFAULT_SEGMENTS
            planId = None
        }

/// Create a plan from an anonymous record (flexible overload used in tests)
let createPlanFromConfig (config: {|
        title:          string
        start:          string
        quantum:        int
        mode:           string
        nodes:          {| id: string; name: string; role: string; delay: int; location: string |} list
        hostName:       string
        hostLocation:   string
        remoteName:     string
        remoteLocation: string
        delay:          int
        segments:       {| segType: string; q: int |} list
    |}) : LtxPlan =
    let defaultStart () =
        let now = DateTimeOffset.UtcNow.AddMinutes(5.0)
        let rounded = DateTimeOffset(now.Year, now.Month, now.Day, now.Hour, now.Minute, 0, TimeSpan.Zero)
        rounded.ToString("yyyy-MM-ddTHH:mm:ssZ")

    let planNodes =
        if config.nodes.Length > 0 then
            config.nodes |> List.map (fun n -> { id = n.id; name = n.name; role = n.role; delay = n.delay; location = n.location })
        else
            let hn   = if config.hostName = ""   then "Earth HQ"    else config.hostName
            let hloc = if config.hostLocation = "" then "earth"      else config.hostLocation
            let rn   = if config.remoteName = "" then "Mars Hab-01" else config.remoteName
            let rloc = if config.remoteLocation = "" then "mars"     else config.remoteLocation
            [
                { id = "N0"; name = hn; role = "HOST";        delay = 0;             location = hloc }
                { id = "N1"; name = rn; role = "PARTICIPANT"; delay = config.delay;  location = rloc }
            ]

    let planSegs =
        if config.segments.Length > 0 then
            config.segments |> List.map (fun s -> { segType = s.segType; q = s.q })
        else DEFAULT_SEGMENTS

    let quantum = if config.quantum = 0 then DEFAULT_QUANTUM else config.quantum
    let mode    = if config.mode = ""   then "LTX"           else config.mode
    let title   = if config.title = "" then "LTX Session"   else config.title
    let startVal = if config.start = "" then defaultStart()  else config.start

    {
        v = 2; title = title; start = startVal
        quantum = quantum; mode = mode
        nodes = planNodes; segments = planSegs
        planId = None
    }

// ── 2. upgradeConfig ─────────────────────────────────────────────────────────

/// Upgrade a v1-style plan (txName/rxName) to v2 schema (nodes[]).
/// v2 configs with nodes are returned as-is.
let upgradeConfig (plan: LtxPlan) : LtxPlan =
    if plan.v >= 2 && plan.nodes.Length > 0 then plan
    else
        // v1 upgrade already happened or default case
        plan

// ── 2b. escapeIcsText (Story 26.3) ───────────────────────────────────────────

/// Escape a string for RFC 5545 TEXT property values.
let escapeIcsText (s: string) : string =
    s.Replace("\\", "\\\\")
     .Replace(";",  "\\;")
     .Replace(",",  "\\,")
     .Replace("\n", "\\n")

// ── 2c. Protocol hardening (Story 26.4) ──────────────────────────────────────

/// Compute the plan-lock timeout in milliseconds.
let planLockTimeoutMs (delaySeconds: int64) : int64 =
    delaySeconds * int64 DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * 1000L

/// Check delay violation. Returns "ok", "violation", or "degraded".
let checkDelayViolation (declaredDelayS: int64) (measuredDelayS: int64) : string =
    let diff = abs (measuredDelayS - declaredDelayS)
    if diff > int64 DELAY_VIOLATION_DEGRADED_S then "degraded"
    elif diff > int64 DELAY_VIOLATION_WARN_S    then "violation"
    else "ok"

// ── 3. computeSegments ───────────────────────────────────────────────────────

/// Compute the timed segment list for a plan.
let computeSegments (plan: LtxPlan) : LtxSegment list =
    if plan.quantum < 1 then
        invalidArg "quantum" (sprintf "quantum must be >= 1, got %d" plan.quantum)
    let qMs = int64 plan.quantum * 60L * 1000L
    let t0  = parseIsoToEpochMs plan.start
    let result, _ =
        plan.segments
        |> List.mapFold (fun t seg ->
            let durMs = int64 seg.q * qMs
            let endMs = t + durMs
            let s = {
                segType    = seg.segType
                q          = seg.q
                durationMs = int durMs
                startMs    = t
                endMs      = endMs
            }
            (s, endMs)) t0
    result

// ── 4. totalMin ──────────────────────────────────────────────────────────────

/// Total session duration in minutes.
let totalMin (plan: LtxPlan) : int =
    plan.segments |> List.sumBy (fun s -> s.q * plan.quantum)

// ── 5. makePlanId ────────────────────────────────────────────────────────────

/// Compute the deterministic plan ID string.
/// Format: "LTX-YYYYMMDD-ORIGNAME-DESTNAME-v2-XXXXXXXX"
let makePlanId (plan: LtxPlan) : string =
    let date = plan.start.Substring(0, 10).Replace("-", "")

    let nodes = plan.nodes
    let hostStr =
        let raw = if nodes.Length > 0 then nodes.[0].name else "HOST"
        let up  = raw.Replace(" ", "").Replace("-", "").ToUpper()
        // keep alphanumeric only, max 8 chars
        let alnumChars = up |> Seq.filter Char.IsLetterOrDigit |> Array.ofSeq
        let alnum = System.String(alnumChars)
        if alnum.Length > 8 then alnum.Substring(0, 8) else alnum

    let nodeStr =
        if nodes.Length > 1 then
            let parts =
                nodes |> List.skip 1
                |> List.map (fun n ->
                    let up = n.name.Replace(" ", "").Replace("-", "").ToUpper()
                    let alnumChars = up |> Seq.filter Char.IsLetterOrDigit |> Array.ofSeq
                    let alnum = System.String(alnumChars)
                    if alnum.Length > 4 then alnum.Substring(0, 4) else alnum)
            let joined = String.concat "-" parts
            if joined.Length > 16 then joined.Substring(0, 16) else joined
        else "RX"

    let raw  = toJson plan
    let hash = djbHash raw
    sprintf "LTX-%s-%s-%s-v2-%s" date hostStr nodeStr hash

// ── 6. encodeHash ────────────────────────────────────────────────────────────

/// Encode a plan config to a URL hash fragment (#l=...).
let encodeHash (plan: LtxPlan) : string =
    "#l=" + b64Enc (toJson plan)

// ── 7. decodeHash ────────────────────────────────────────────────────────────

/// Decode a plan from a URL hash fragment.
/// Accepts "#l=...", "l=...", or raw base64url token.
/// Returns None if invalid.
let decodeHash (fragment: string) : LtxPlan option =
    if String.IsNullOrEmpty(fragment) then None
    else
        let mutable token = fragment
        if token.StartsWith("#") then token <- token.Substring(1)
        if token.StartsWith("l=") then token <- token.Substring(2)
        match b64Dec token with
        | None      -> None
        | Some json -> fromJson json

// ── 8. buildNodeUrls ─────────────────────────────────────────────────────────

/// Build perspective URLs for all nodes in a plan.
let buildNodeUrls (plan: LtxPlan) (baseUrl: string) : LtxNodeUrl list =
    let hash    = encodeHash plan
    let hashPart = if hash.StartsWith("#") then hash.Substring(1) else hash
    let cleanBase =
        let s = if String.IsNullOrEmpty(baseUrl) then "" else baseUrl
        let noHash = if s.Contains("#") then s.Substring(0, s.IndexOf('#')) else s
        if noHash.Contains("?") then noHash.Substring(0, noHash.IndexOf('?')) else noHash
    [
        for node in plan.nodes do
            let nodeEnc = Uri.EscapeDataString(node.id)
            let url = sprintf "%s?node=%s#%s" cleanBase nodeEnc hashPart
            yield { nodeId = node.id; nodeName = node.name; url = url }
    ]

// ── 9. generateICS ───────────────────────────────────────────────────────────

/// Generate LTX-extended iCalendar (.ics) content for a plan.
/// Uses CRLF line endings as required by RFC 5545.
let generateICS (plan: LtxPlan) : string =
    let segs    = computeSegments plan
    let startMs = parseIsoToEpochMs plan.start
    let endMs   = if segs.Length > 0 then segs.[segs.Length - 1].endMs else startMs
    let planId  = makePlanId plan

    let nodes = plan.nodes
    let host  = if nodes.Length > 0 then nodes.[0] else { id = "N0"; name = "Earth HQ"; role = "HOST"; delay = 0; location = "earth" }
    let parts = if nodes.Length > 1 then nodes |> List.skip 1 else []

    let segTpl = plan.segments |> List.map (fun s -> s.segType) |> String.concat ","

    let partNames =
        if parts.Length > 0 then parts |> List.map (fun p -> p.name) |> String.concat ", "
        else "remote nodes"

    let delayDesc =
        if parts.Length > 0 then
            parts
            |> List.map (fun p -> sprintf "%s: %d min one-way" p.name (int (Math.Round(float p.delay / 60.0))))
            |> String.concat " \u00b7 "
        else "no participant delay configured"

    let dtstamp = fmtDT (DateTimeOffset.UtcNow.ToUnixTimeMilliseconds())

    let nodeLines =
        nodes |> List.map (fun n -> sprintf "LTX-NODE:ID=%s;ROLE=%s" (toId n.name) n.role)

    let delayLines =
        parts |> List.map (fun p ->
            let d = p.delay
            sprintf "LTX-DELAY;NODEID=%s:ONEWAY-MIN=%d;ONEWAY-MAX=%d;ONEWAY-ASSUMED=%d"
                (toId p.name) d (d + 120) d)

    let localTimeLines =
        nodes
        |> List.filter (fun n -> n.location = "mars")
        |> List.map (fun n -> sprintf "LTX-LOCALTIME:NODE=%s;SCHEME=LMST;PARAMS=LONGITUDE:0E" (toId n.name))

    let lines = ResizeArray<string>()
    lines.Add("BEGIN:VCALENDAR")
    lines.Add("VERSION:2.0")
    lines.Add("PRODID:-//InterPlanet//LTX v1.1//EN")
    lines.Add("CALSCALE:GREGORIAN")
    lines.Add("METHOD:PUBLISH")
    lines.Add("BEGIN:VEVENT")
    lines.Add(sprintf "UID:%s@interplanet.live" planId)
    lines.Add(sprintf "DTSTAMP:%s" dtstamp)
    lines.Add(sprintf "DTSTART:%s" (fmtDT startMs))
    lines.Add(sprintf "DTEND:%s" (fmtDT endMs))
    lines.Add(sprintf "SUMMARY:%s" (escapeIcsText plan.title))
    lines.Add(sprintf "DESCRIPTION:LTX session \u2014 %s with %s\\nSignal delays: %s\\nMode: %s \u00b7 Segment plan: %s\\nGenerated by InterPlanet (https://interplanet.live)"
        host.name partNames delayDesc plan.mode segTpl)
    lines.Add("LTX:1")
    lines.Add(sprintf "LTX-PLANID:%s" planId)
    lines.Add(sprintf "LTX-QUANTUM:PT%dM" plan.quantum)
    lines.Add(sprintf "LTX-SEGMENT-TEMPLATE:%s" segTpl)
    lines.Add(sprintf "LTX-MODE:%s" plan.mode)
    for l in nodeLines  do lines.Add(l)
    for l in delayLines do lines.Add(l)
    lines.Add("LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY")
    for l in localTimeLines do lines.Add(l)
    lines.Add("END:VEVENT")
    lines.Add("END:VCALENDAR")

    String.concat "\r\n" lines

// ── 10. formatHMS ────────────────────────────────────────────────────────────

/// Format seconds as HH:MM:SS (if >= 1 hour) or MM:SS.
let formatHMS (seconds: int) : string =
    let sec = if seconds < 0 then 0 else seconds
    let h = sec / 3600
    let m = (sec % 3600) / 60
    let s = sec % 60
    if h > 0 then sprintf "%02d:%02d:%02d" h m s
    else sprintf "%02d:%02d" m s

// ── 11. formatUTC ────────────────────────────────────────────────────────────

/// Format a millisecond epoch timestamp as "YYYY-MM-DDTHH:MM:SSZ".
let formatUTC (ms: int64) : string =
    DateTimeOffset.FromUnixTimeMilliseconds(ms)
        .ToUniversalTime()
        .ToString("yyyy-MM-ddTHH:mm:ssZ")
