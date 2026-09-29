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

/// JSON.stringify string quoting: quote, backslash, \b \f \n \r \t, other
/// control characters and lone surrogates as lowercase \u00XX / \uXXXX;
/// everything else (including valid surrogate pairs) raw.
let private jsonString (s: string) : string =
    let sb = StringBuilder("\"")
    let mutable i = 0
    while i < s.Length do
        let c = s.[i]
        match c with
        | '"'  -> sb.Append("\\\"") |> ignore
        | '\\' -> sb.Append("\\\\") |> ignore
        | '\b' -> sb.Append("\\b")  |> ignore
        | '\f' -> sb.Append("\\f")  |> ignore
        | '\n' -> sb.Append("\\n")  |> ignore
        | '\r' -> sb.Append("\\r")  |> ignore
        | '\t' -> sb.Append("\\t")  |> ignore
        | c when int c < 0x20 -> sb.Append(sprintf "\\u%04x" (int c)) |> ignore
        | c when Char.IsHighSurrogate c && i + 1 < s.Length && Char.IsLowSurrogate s.[i + 1] ->
            sb.Append(c).Append(s.[i + 1]) |> ignore
            i <- i + 1
        | c when Char.IsSurrogate c -> sb.Append(sprintf "\\u%04x" (int c)) |> ignore
        | c    -> sb.Append(c) |> ignore
        i <- i + 1
    sb.Append('"') |> ignore
    sb.ToString()

/// The value of a JSON string element, decoding every escape and keeping
/// lone surrogates (JsonElement.GetString throws on "\ud800").
let private jsonStringValue (e: Json.JsonElement) : string =
    let raw = e.GetRawText()
    let sb = StringBuilder(raw.Length)
    let mutable i = 1
    while i < raw.Length - 1 do
        let c = raw.[i]
        if c <> '\\' then sb.Append(c) |> ignore
        else
            i <- i + 1
            match raw.[i] with
            | 'b' -> sb.Append('\b') |> ignore
            | 'f' -> sb.Append('\f') |> ignore
            | 'n' -> sb.Append('\n') |> ignore
            | 'r' -> sb.Append('\r') |> ignore
            | 't' -> sb.Append('\t') |> ignore
            | 'u' ->
                sb.Append(char (Convert.ToInt32(raw.Substring(i + 1, 4), 16))) |> ignore
                i <- i + 4
            | n -> sb.Append(n) |> ignore
        i <- i + 1
    sb.ToString()

/// JavaScript \s: ECMAScript WhiteSpace and LineTerminator. (Char.IsWhiteSpace
/// differs: it includes U+0085 and not U+FEFF.)
let isJsSpace (c: char) : bool =
    match c with
    | '\t' | '\n' | '\v' | '\f' | '\r' | ' ' | '\u00a0' | '\u1680' | '\u2028' | '\u2029'
    | '\u202f' | '\u205f' | '\u3000' | '\ufeff' -> true
    | c -> c >= '\u2000' && c <= '\u200a'

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
            // Attributed segments (section 3.4.1): speaker and label follow
            // type and q, only when present, as ltx-sdk.js writes them.
            sprintf "{\"type\":%s,\"q\":%d%s%s}" (jsonString s.segType) s.q
                (match s.speaker with Some sp -> ",\"speaker\":" + jsonString sp | None -> "")
                (match s.label with Some lb -> ",\"label\":" + jsonString lb | None -> ""))
        |> String.concat ","

    sprintf "{\"v\":%d,\"title\":%s,\"start\":%s,\"quantum\":%d,\"mode\":%s,\"nodes\":[%s],\"segments\":[%s]}"
        plan.v (jsonString plan.title) (jsonString plan.start) plan.quantum (jsonString plan.mode)
        nodesJson segsJson

// ── JSON parser ───────────────────────────────────────────────────────────────

let fromJson (json: string) : LtxPlan option =
    if String.IsNullOrEmpty(json) then None
    else
    try
        use doc = Json.JsonDocument.Parse(json)
        let root = doc.RootElement
        let prop (o: Json.JsonElement) (k: string) =
            match o.ValueKind with
            | Json.JsonValueKind.Object ->
                match o.TryGetProperty k with
                | true, v -> Some v
                | _ -> None
            | _ -> None
        let str o k =
            match prop o k with
            | Some v when v.ValueKind = Json.JsonValueKind.String -> Some (jsonStringValue v)
            | _ -> None
        let int o k =
            match prop o k with
            | Some v when v.ValueKind = Json.JsonValueKind.Number ->
                match v.TryGetInt32() with
                | true, i -> Some i
                | _ -> None
            | _ -> None
        let arr k =
            match prop root k with
            | Some v when v.ValueKind = Json.JsonValueKind.Array -> v.EnumerateArray() |> List.ofSeq
            | _ -> []
        let nodes =
            arr "nodes" |> List.choose (fun n ->
                match str n "id", str n "name", str n "role", str n "location" with
                | Some id, Some name, Some role, Some location ->
                    Some { id = id; name = name; role = role; delay = defaultArg (int n "delay") 0; location = location }
                | _ -> None)
        let segments =
            arr "segments" |> List.choose (fun sg ->
                match str sg "type", int sg "q" with
                | Some t, Some q -> Some { segType = t; q = q; speaker = str sg "speaker"; label = str sg "label" }
                | _ -> None)
        let title = defaultArg (str root "title") ""
        let start = defaultArg (str root "start") ""
        // Require at least one valid field to distinguish from truly invalid input
        if start = "" && title = "" && nodes.IsEmpty then None
        else
        Some {
            v = defaultArg (int root "v") 2; title = title; start = start
            quantum = defaultArg (int root "quantum") DEFAULT_QUANTUM
            mode = defaultArg (str root "mode") "LTX"
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
            config.segments |> List.map (fun s -> segment s.segType s.q)
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
    // name.replace(/\s+/g, '').toUpperCase() as in ltx-sdk.js: only JS \s
    // whitespace is removed (tab, NBSP, U+2028, U+3000, BOM, ...);
    // punctuation such as '-' is kept (§4.3).
    let token (name: string) =
        Upper.jsToUpper (System.String(name.ToCharArray() |> Array.filter (isJsSpace >> not)))
    let hostStr =
        let raw = if nodes.Length > 0 && nodes.[0].name <> "" then token nodes.[0].name else "HOST"
        if raw.Length > 8 then raw.Substring(0, 8) else raw

    let nodeStr =
        if nodes.Length > 1 then
            let parts =
                nodes |> List.skip 1
                |> List.map (fun n ->
                    let up = token n.name
                    if up.Length > 4 then up.Substring(0, 4) else up)
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
