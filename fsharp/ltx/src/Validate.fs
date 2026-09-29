// Validate.fs --- plan validation (LTX-SPECIFICATION.md §3.5, §4, §7) and
// planId over the wire form of a plan (spec/golden/plan-ids.json).
//
// F# port of validatePlan / _reservedFieldErrors / _assertNoReservedFields
// and makePlanId(JSON.parse(json)) in javascript/ltx/ltx-sdk.js. Works on
// System.Text.Json elements, which keep object key order. Load after
// Security.fs and before V11.fs:
//   #r "nuget: NSec.Cryptography, 24.4.0"
//   #load "Security.fs"
//   #load "Validate.fs"
//   #load "V11.fs"

module InterplanetLtx.Validate

open System
open System.Collections.Generic
open System.Globalization
open System.Text
open System.Text.Json
open System.Text.RegularExpressions
open InterplanetLtx.Security

/// One validation failure: a stable code, the JSON path and a message.
type PlanValidationError = { code: string; path: string; message: string }

/// Result of validatePlan.
type PlanValidation =
    { valid: bool
      errors: PlanValidationError list }
    member this.codes = this.errors |> List.map (fun e -> e.code)

/// Raised when a plan uses the reserved streams (§3.5) or branching (§7)
/// fields. code is the first violation's code; errors lists all.
exception ReservedFieldError of code: string * message: string * errors: PlanValidationError list

/// Core segment types (§3.4) plus the auxiliary types the SDKs handle.
let PLAN_SEGMENT_TYPES =
    set [ "PLAN_CONFIRM"; "TX"; "RX"; "CAUCUS"; "BUFFER"; "MERGE"; "SPEAK"; "REST"; "PAD"; "OPEN"; "RELAY" ]
let PLAN_MODES = [ "LTX"; "LTX-LIVE"; "LTX-RELAY"; "LTX-ASYNC" ]
/// Fields that exist only in v3 plans (§4.4); MUST NOT appear in v2 (§4.3).
let V3_ONLY_FIELDS = [ "delays"; "planVersion"; "prevPlanHash"; "questions"; "actions"; "streams" ]
let private RESERVED_BRANCH_PLAN_FIELDS = [ "branches"; "branching" ]
let private RESERVED_BRANCH_SEGMENT_FIELDS = [ "branch" ]
let private RESERVED_STREAM_SEGMENT_FIELDS = [ "stream" ]
let private ROLES = set [ "HOST"; "PARTICIPANT"; "OBSERVER" ]

// ---- JSON helpers ----

let private get (o: JsonElement) (key: string) : JsonElement option =
    if o.ValueKind = JsonValueKind.Object then
        match o.TryGetProperty key with
        | true, v -> Some v
        | _ -> None
    else None

let private has o key = (get o key).IsSome

let private num (v: JsonElement option) : float option =
    match v with
    | Some e when e.ValueKind = JsonValueKind.Number -> Some (e.GetDouble())
    | _ -> None

let private isInteger (v: JsonElement option) =
    match num v with
    | Some d -> not (Double.IsInfinity d) && Math.Floor d = d
    | None -> false

let private str (v: JsonElement option) : string option =
    match v with
    | Some e when e.ValueKind = JsonValueKind.String -> Some (unquoteJson (e.GetRawText()))
    | _ -> None

let private parse (json: string) : JsonElement =
    use doc = JsonDocument.Parse(json)
    doc.RootElement.Clone()

/// JavaScript Number-to-String for a JSON number element.
let jsNumber (e: JsonElement) : string =
    match e.TryGetInt64() with
    | true, l -> l.ToString(CultureInfo.InvariantCulture)
    | _ ->
        let d = e.GetDouble()
        if Math.Floor d = d && abs d < 1e21 then d.ToString("F0", CultureInfo.InvariantCulture)
        else d.ToString("R", CultureInfo.InvariantCulture)

/// Compact serialisation identical to JavaScript JSON.stringify (key order kept).
let rec stringify (e: JsonElement) : string =
    match e.ValueKind with
    | JsonValueKind.Object ->
        "{" + (e.EnumerateObject() |> Seq.map (fun p -> jsonStr p.Name + ":" + stringify p.Value) |> String.concat ",") + "}"
    | JsonValueKind.Array -> "[" + (e.EnumerateArray() |> Seq.map stringify |> String.concat ",") + "]"
    | JsonValueKind.String -> jsonStr (unquoteJson (e.GetRawText()))
    | JsonValueKind.Number -> jsNumber e
    | JsonValueKind.True -> "true"
    | JsonValueKind.False -> "false"
    | _ -> "null"

/// Convert a JSON element to the obj tree canonicalJson understands.
let rec toObj (e: JsonElement) : obj =
    match e.ValueKind with
    | JsonValueKind.Object ->
        let d = Dictionary<string, obj>()
        for p in e.EnumerateObject() do d.[p.Name] <- toObj p.Value
        box (d :> IDictionary<string, obj>)
    | JsonValueKind.Array -> box (e.EnumerateArray() |> Seq.map toObj |> List.ofSeq |> List<obj>)
    | JsonValueKind.String -> box (unquoteJson (e.GetRawText()))
    | JsonValueKind.Number ->
        match e.TryGetInt64() with
        | true, l -> box l
        | _ -> box (e.GetDouble())
    | JsonValueKind.True -> box true
    | JsonValueKind.False -> box false
    | _ -> null

// ---- reserved fields ----

/// Reserved-field violations only (§3.5 streams, §7 branching).
let reservedFieldErrors (plan: JsonElement) : PlanValidationError list =
    let errors = List<PlanValidationError>()
    if plan.ValueKind = JsonValueKind.Object then
        match get plan "streams" with
        | Some st when not (st.ValueKind = JsonValueKind.Array && st.GetArrayLength() = 0) ->
            errors.Add { code = "reserved_streams"; path = "streams"
                         message = "streams[] is reserved (§3.5) and MUST be absent or empty" }
        | _ -> ()
        for f in RESERVED_BRANCH_PLAN_FIELDS do
            if has plan f then
                errors.Add { code = "reserved_branching"; path = f
                             message = sprintf "%s is reserved for branching (§7, not yet implemented) and MUST be absent" f }
        match get plan "segments" with
        | Some segs when segs.ValueKind = JsonValueKind.Array ->
            segs.EnumerateArray() |> Seq.iteri (fun i s ->
                if s.ValueKind = JsonValueKind.Object then
                    for f in RESERVED_STREAM_SEGMENT_FIELDS do
                        if has s f then
                            errors.Add { code = "reserved_streams"; path = sprintf "segments[%d].%s" i f
                                         message = sprintf "segment %s is reserved (§3.5) and MUST be absent" f }
                    for f in RESERVED_BRANCH_SEGMENT_FIELDS do
                        if has s f then
                            errors.Add { code = "reserved_branching"; path = sprintf "segments[%d].%s" i f
                                         message = sprintf "segment %s is reserved for branching (§7) and MUST be absent" f })
        | _ -> ()
    List.ofSeq errors

/// Raise ReservedFieldError if a plan uses reserved stream/branch fields.
let assertNoReservedFields (plan: JsonElement) (fnName: string) : unit =
    match reservedFieldErrors plan with
    | [] -> ()
    | (first :: _) as errors ->
        raise (ReservedFieldError(first.code, sprintf "%s: %s" fnName first.message, errors))

/// Same check on a dictionary projection (e.g. of a typed plan).
let assertNoReservedFieldsDict (plan: IDictionary<string, obj>) (fnName: string) : unit =
    assertNoReservedFields (parse (canonicalJson (box plan))) fnName

// ---- validatePlan ----

/// Validate a v2 or v3 plan (wire form) against spec/ltx-schema.json and the
/// reserved-field rules (§3.5 streams, §7 branching). v1 configs must be
/// upgraded first. Pure; never raises.
/// Error codes: not_an_object, invalid_version, missing_field, invalid_field,
/// invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
/// duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
/// invalid_delays, reserved_streams, reserved_branching.
let validatePlan (plan: JsonElement) : PlanValidation =
    let errors = List<PlanValidationError>()
    let err code path message = errors.Add { code = code; path = path; message = message }
    if plan.ValueKind <> JsonValueKind.Object then
        err "not_an_object" "" "plan must be an object"
        { valid = false; errors = List.ofSeq errors }
    else
    let v = num (get plan "v")
    if v <> Some 2.0 && v <> Some 3.0 then err "invalid_version" "v" "v must be 2 or 3"
    for f in [ "title"; "start"; "quantum"; "mode"; "nodes"; "segments" ] do
        if not (has plan f) then err "missing_field" f (sprintf "%s is required" f)
    if has plan "title" && (str (get plan "title")).IsNone then
        err "invalid_field" "title" "title must be a string"
    if has plan "start" then
        let ok =
            match str (get plan "start") with
            | Some s ->
                fst (DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal))
            | None -> false
        if not ok then err "invalid_field" "start" "start must be an ISO 8601 UTC timestamp"
    if has plan "quantum" then
        let q = get plan "quantum"
        if not (isInteger q && num q >= Some 1.0 && num q <= Some 60.0) then
            err "invalid_quantum" "quantum" "quantum must be an integer 1..60 minutes (§3.2)"
    if has plan "mode" then
        match str (get plan "mode") with
        | Some m when List.contains m PLAN_MODES -> ()
        | _ -> err "invalid_mode" "mode" ("mode must be one of " + String.Join(", ", PLAN_MODES))

    let ids = HashSet<string>(StringComparer.Ordinal)
    match get plan "nodes" with
    | Some nodes ->
        if nodes.ValueKind <> JsonValueKind.Array || nodes.GetArrayLength() = 0 then
            err "invalid_nodes" "nodes" "nodes must be a non-empty array"
        else
            let mutable hosts = 0
            nodes.EnumerateArray() |> Seq.iteri (fun i n ->
                let id = str (get n "id")
                let role = str (get n "role")
                let delay = num (get n "delay")
                let ok =
                    n.ValueKind = JsonValueKind.Object
                    && (match id with Some s -> s <> "" && not (s.Contains "|") | None -> false)
                    && (str (get n "name")).IsSome
                    && (match role with Some r -> ROLES.Contains r | None -> false)
                    && (match delay with Some d -> d >= 0.0 | None -> false)
                if not ok then
                    err "invalid_nodes" (sprintf "nodes[%d]" i)
                        "node needs id (no \"|\"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0"
                else
                    if ids.Contains id.Value then
                        err "duplicate_node_id" (sprintf "nodes[%d].id" i) (sprintf "duplicate node id %s" id.Value)
                    ids.Add id.Value |> ignore
                    if role = Some "HOST" then hosts <- hosts + 1)
            let h = nodes.[0]
            if hosts <> 1 || h.ValueKind <> JsonValueKind.Object
               || str (get h "role") <> Some "HOST" || num (get h "delay") <> Some 0.0 then
                err "invalid_host" "nodes[0]" "exactly one HOST, first in nodes[], with delay 0 (§3.1)"
    | None -> ()

    match get plan "segments" with
    | Some segs ->
        if segs.ValueKind <> JsonValueKind.Array then
            err "invalid_segment" "segments" "segments must be an array"
        else
            segs.EnumerateArray() |> Seq.iteri (fun i s ->
                let q = get s "q"
                let typeOk = match str (get s "type") with Some t -> PLAN_SEGMENT_TYPES.Contains t | None -> false
                if s.ValueKind <> JsonValueKind.Object || not typeOk || not (isInteger q && num q >= Some 1.0) then
                    err "invalid_segment" (sprintf "segments[%d]" i) "segment needs a known type and integer q >= 1"
                else
                    match get s "speaker" with
                    | Some sp ->
                        match str (Some sp) with
                        | Some spId when ids.Contains spId -> ()
                        | spId ->
                            err "unknown_speaker" (sprintf "segments[%d].speaker" i)
                                (sprintf "speaker %s is not a node id" (defaultArg spId (sp.GetRawText())))
                    | None -> ())
    | None -> ()

    if v = Some 2.0 then
        for f in V3_ONLY_FIELDS do
            if has plan f then
                err "v3_field_in_v2" f (sprintf "%s is a v3 field and MUST NOT appear in a v2 plan (§4.3)" f)
    elif v = Some 3.0 then
        match get plan "delays" with
        | Some d when d.ValueKind <> JsonValueKind.Object -> err "invalid_delays" "delays" "delays must be an object"
        | Some d ->
            for p in d.EnumerateObject() do
                let parts = p.Name.Split('|')
                let value = num (Some p.Value)
                if parts.Length <> 2 || String.CompareOrdinal(parts.[0], parts.[1]) >= 0
                   || (ids.Count > 0 && (not (ids.Contains parts.[0]) || not (ids.Contains parts.[1])))
                   || (match value with Some x -> not (x >= 0.0) | None -> true) then
                    err "invalid_delays" ("delays." + p.Name)
                        "key must be two known node ids joined by \"|\" in sorted order; value >= 0 (§3.7.2)"
        | None -> ()
        if has plan "planVersion" then
            let pv = get plan "planVersion"
            if not (isInteger pv && num pv >= Some 1.0) then
                err "invalid_field" "planVersion" "planVersion must be an integer >= 1"
        if has plan "prevPlanHash" then
            match str (get plan "prevPlanHash") with
            | Some h when Regex.IsMatch(h, "^[0-9a-f]{64}$") -> ()
            | _ -> err "invalid_field" "prevPlanHash" "prevPlanHash must be 64 lowercase hex characters"
        for f in [ "questions"; "actions" ] do
            match get plan f with
            | Some x when x.ValueKind <> JsonValueKind.Array -> err "invalid_field" f (sprintf "%s must be an array" f)
            | _ -> ()

    errors.AddRange(reservedFieldErrors plan)
    { valid = errors.Count = 0; errors = List.ofSeq errors }

/// Validate plan JSON text.
let validatePlanJson (json: string) : PlanValidation =
    try validatePlan (parse json)
    with :? JsonException ->
        { valid = false; errors = [ { code = "not_an_object"; path = ""; message = "plan must be an object" } ] }

// ---- planId over the wire form ----

let private compactUpper (s: string) = stripJsSpaceUpper s

let private slice (s: string) (n: int) = if s.Length > n then s.Substring(0, n) else s

/// SHA-256 hex of the canonical JSON of a plan element.
let planHashOf (plan: JsonElement) : string =
    sha256 (Encoding.UTF8.GetBytes(canonicalJson (toObj plan)))
    |> Array.map (sprintf "%02x") |> String.concat ""

/// SHA-256 hex of the canonical JSON of plan JSON text.
let planHashFromJson (json: string) : string = planHashOf (parse json)

/// makePlanId over plan JSON text with key order preserved. Mirrors
/// ltx-sdk.js makePlanId(JSON.parse(json)) for v2 and v3 plans with nodes:
/// the FROZEN v2 hash is imul31 over the UTF-16 code units of JSON.stringify
/// in insertion order, including fields the typed models do not carry
/// (relay, key order); v3 hashes SHA-256 over the RFC 8785 canonical JSON.
let makePlanIdFromJson (json: string) : string =
    let plan = parse json
    let start =
        DateTimeOffset.Parse((str (get plan "start")).Value, CultureInfo.InvariantCulture,
                             DateTimeStyles.AssumeUniversal).UtcDateTime
    let date = start.ToString("yyyyMMdd", CultureInfo.InvariantCulture)
    let names =
        match get plan "nodes" with
        | Some n when n.ValueKind = JsonValueKind.Array ->
            n.EnumerateArray() |> Seq.map (fun x -> defaultArg (str (get x "name")) "") |> List.ofSeq
        | _ -> []
    // (nodes[0]?.name || 'HOST') as in ltx-sdk.js: an empty name is HOST too.
    let hostStr = slice (compactUpper (match names with h :: _ when h <> "" -> h | _ -> "HOST")) 8
    let nodeStr =
        if names.Length > 1 then
            slice (names.Tail |> List.map (fun n -> slice (compactUpper n) 4) |> String.concat "-") 16
        else "RX"
    if num (get plan "v") >= Some 3.0 then
        sprintf "LTX-%s-%s-%s-v3-%s" date hostStr nodeStr ((planHashOf plan).Substring(0, 8))
    else
        let mutable h = 0u
        for c in stringify plan do h <- h * 31u + uint32 c
        sprintf "LTX-%s-%s-%s-v2-%08x" date hostStr nodeStr h
