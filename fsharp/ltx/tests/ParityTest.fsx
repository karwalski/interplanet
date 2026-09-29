#!/usr/bin/env dotnet-script
// ParityTest.fsx --- LTX parity cascade (issue #27): golden planId vectors
// (spec/golden/plan-ids.json), validatePlan reserved streams/branching, and
// the decision register + merge snapshot. Mirrors javascript/ltx/tests/run.js.
// Run with: dotnet fsi tests/ParityTest.fsx

#r "nuget: NSec.Cryptography, 24.4.0"
#load "../src/Security.fs"
#load "../src/Validate.fs"
#load "../src/V11.fs"

open System
open System.IO
open System.Collections.Generic
open System.Text.Json
open InterplanetLtx.Security
open InterplanetLtx.Validate
open InterplanetLtx.V11

let mutable passed = 0
let mutable failed = 0

let check label cond =
    if cond then passed <- passed + 1
    else
        failed <- failed + 1
        printfn "FAIL: %s" label

let s (o: JsonElement) (k: string) : string option =
    match o.TryGetProperty k with
    | true, v when v.ValueKind = JsonValueKind.String -> Some (v.GetString())
    | _ -> None

/// Typed v1.1 plan from the wire form (the fields PlanV11 models).
let toPlanV11 (p: JsonElement) : PlanV11 =
    { v = p.GetProperty("v").GetInt32()
      title = defaultArg (s p "title") ""
      start = defaultArg (s p "start") ""
      quantum = p.GetProperty("quantum").GetInt32()
      mode = defaultArg (s p "mode") "LTX"
      nodes =
        [ for n in p.GetProperty("nodes").EnumerateArray() ->
            { id = (s n "id").Value; name = (s n "name").Value; role = (s n "role").Value
              delay = n.GetProperty("delay").GetInt64(); location = (s n "location").Value } ]
      segments =
        [ for x in p.GetProperty("segments").EnumerateArray() ->
            { segType = (s x "type").Value; q = x.GetProperty("q").GetInt32()
              speaker = s x "speaker"; label = s x "label" } ]
      delays =
        match p.TryGetProperty "delays" with
        | true, d -> Some (d.EnumerateObject() |> Seq.map (fun kv -> kv.Name, kv.Value.GetInt64()) |> Map.ofSeq)
        | _ -> None
      planVersion = (match p.TryGetProperty "planVersion" with | true, v -> Some (v.GetInt32()) | _ -> None)
      prevPlanHash = s p "prevPlanHash" }

/// Shallow copy of a plan object with fields replaced/added (values as JSON).
let withF (plan: JsonElement) (extra: (string * string) list) : string =
    let keys = extra |> List.map fst |> set
    let kept =
        plan.EnumerateObject()
        |> Seq.filter (fun p -> not (keys.Contains p.Name))
        |> Seq.map (fun p -> jsonStr p.Name + ":" + stringify p.Value)
        |> List.ofSeq
    "{" + String.concat "," (kept @ (extra |> List.map (fun (k, v) -> jsonStr k + ":" + v))) + "}"

let codes json = (validatePlanJson json).codes

// ---- golden planId vectors ----

let rec findUp (dir: DirectoryInfo) =
    if isNull dir then None
    else
        let p = Path.Combine(dir.FullName, "spec", "golden", "plan-ids.json")
        if File.Exists p then Some p else findUp dir.Parent
let goldenPath =
    match findUp (DirectoryInfo(__SOURCE_DIRECTORY__)) with
    | Some p -> Some p
    | None -> findUp (DirectoryInfo(Directory.GetCurrentDirectory()))
check "golden: spec/golden/plan-ids.json found" goldenPath.IsSome

let doc = JsonDocument.Parse(File.ReadAllText goldenPath.Value)
let vectors = doc.RootElement.GetProperty("vectors").EnumerateArray() |> List.ofSeq
check "golden: vectors present" (vectors.Length >= 9)
let byName = vectors |> List.map (fun v -> (s v "name").Value, v) |> dict
let mutable typedCovered = 0
for gv in vectors do
    let name = (s gv "name").Value
    let plan = gv.GetProperty("plan")
    let json = stringify plan
    let planId = (s gv "planId").Value
    check (sprintf "golden planId %s" name) (makePlanIdFromJson json = planId)
    match s gv "planHash" with
    | Some ph -> check (sprintf "golden planHash %s" name) (planHashFromJson json = ph)
    | None -> ()
    // The typed PlanV11 serialises v2 plans in the fixed order v, title,
    // start, quantum, mode, nodes, segments and drops unmodelled fields, so
    // its planId is only comparable when that projection is lossless.
    let typed = toPlanV11 plan
    let lossless =
        if typed.v >= 3 then canonicalJson (box (planToDict typed)) = canonicalJson (toObj plan)
        else toJsonV2 typed = json
    if lossless then
        typedCovered <- typedCovered + 1
        check (sprintf "golden typed planId %s" name) (makePlanId typed = planId)
check (sprintf "golden: typed makePlanId covers %d vectors" typedCovered) (typedCovered >= 3)
check "golden v2 freeze anchor" (s byName.["v2-freeze-check"] "planId" = Some "LTX-20260801-EARTHHQ-MARS-v2-d132e85d")
check "golden v2 unicode anchor" (s byName.["v2-unicode-title"] "planId" = Some "LTX-20261231-EARTHHQ-MARS-v2-7bc93af8")
check "golden v2 order-sensitive"
    (s byName.["v2-createPlan-default"] "planId" <> s byName.["v2-key-order-sensitive"] "planId")
check "golden v3 order-insensitive"
    (s byName.["v3-upgrade-delays"] "planId" = s byName.["v3-key-order-insensitive"] "planId")
check "golden v3 amendment chain hash"
    (s (byName.["v3-amendment"].GetProperty("plan")) "prevPlanHash" = s byName.["v3-upgrade-delays"] "planHash")
check "canonical JSON escapes control chars like JSON.stringify"
    (canonicalJson (box (dict [ "t", box "a\b\012\001&<é>" ])) = "{\"t\":\"a\\b\\f\\u0001&<é>\"}")

// ---- validatePlan: reserved streams / branching (§3.5, §7) ----

for gv in vectors do
    check (sprintf "validatePlan accepts golden %s" (s gv "name").Value) (validatePlan (gv.GetProperty("plan"))).valid
let vpBase = byName.["v3-upgrade-delays"].GetProperty("plan")
let vpV2 = byName.["v2-freeze-check"].GetProperty("plan")
check "validatePlan v3 empty streams ok" (validatePlanJson (withF vpBase [ "streams", "[]" ])).valid
let vpStreams = validatePlanJson (withF vpBase [ "streams", "[{\"id\":\"S1\"}]" ])
check "validatePlan non-empty streams" (not vpStreams.valid && List.contains "reserved_streams" vpStreams.codes)
check "validatePlan streams error path"
    ((vpStreams.errors |> List.find (fun e -> e.code = "reserved_streams")).path = "streams")
check "validatePlan streams non-array" (List.contains "reserved_streams" (codes (withF vpBase [ "streams", "\"S1\"" ])))
check "validatePlan segment stream"
    (List.contains "reserved_streams" (codes (withF vpBase [ "segments", "[{\"type\":\"TX\",\"q\":1,\"stream\":\"S1\"}]" ])))
check "validatePlan branches" (List.contains "reserved_branching" (codes (withF vpBase [ "branches", "[]" ])))
check "validatePlan branching"
    (List.contains "reserved_branching" (codes (withF vpBase [ "branching", "{\"mode\":\"local\"}" ])))
let vpSegBranch = validatePlanJson (withF vpBase [ "segments", "[{\"type\":\"CAUCUS\",\"q\":1,\"branch\":\"B1\"}]" ])
check "validatePlan segment branch"
    (List.contains "reserved_branching" vpSegBranch.codes && vpSegBranch.errors.Head.path = "segments[0].branch")
check "validatePlan v2 streams is v3 field" (List.contains "v3_field_in_v2" (codes (withF vpV2 [ "streams", "[]" ])))
check "validatePlan v2 branching" (List.contains "reserved_branching" (codes (withF vpV2 [ "branching", "true" ])))
check "validatePlan non-object" (List.contains "not_an_object" (codes "null"))
check "validatePlan bad version" (List.contains "invalid_version" (codes (withF vpV2 [ "v", "7" ])))
let reversedNodes =
    "[" + (vpV2.GetProperty("nodes").EnumerateArray() |> Seq.rev |> Seq.map stringify |> String.concat ",") + "]"
check "validatePlan host not first" (List.contains "invalid_host" (codes (withF vpV2 [ "nodes", reversedNodes ])))
check "validatePlan unsorted delays key"
    (List.contains "invalid_delays" (codes (withF vpBase [ "delays", "{\"N1|N0\":860}" ])))
check "validatePlan unknown speaker"
    (List.contains "unknown_speaker" (codes (withF vpV2 [ "segments", "[{\"type\":\"TX\",\"q\":1,\"speaker\":\"N9\"}]" ])))
check "validatePlan quantum out of range" (List.contains "invalid_quantum" (codes (withF vpV2 [ "quantum", "0" ])))
let typedBase = toPlanV11 vpBase
check "validatePlan typed PlanV11 projection valid" (validatePlanV11 typedBase).valid
let sessionOk =
    try createSession typedBase "id" All |> ignore; true
    with ReservedFieldError _ -> false
check "createSession accepts typed plan" sessionOk
let reservedRaised =
    try
        use bad = JsonDocument.Parse(withF vpBase [ "streams", "[1]" ])
        assertNoReservedFields bad.RootElement "createSession"
        None
    with ReservedFieldError (code, msg, errs) -> Some (code, msg, errs)
check "assertNoReservedFields raises with code and errors"
    (match reservedRaised with
     | Some (code, msg, errs) -> code = "reserved_streams" && msg.StartsWith "createSession:" && errs.Length = 1
     | None -> false)

// ---- decision register (§10.3) + merge snapshot ----

let host = generateNik 365 "HOST"
let mars = generateNik 365 "MARS"
let cache =
    dict [ "N0", { nodeId = "N0"; publicKeyB64 = host.PublicKeyB64; validUntil = host.ExpiresAt }
           "N1", { nodeId = "N1"; publicKeyB64 = mars.PublicKeyB64; validUntil = mars.ExpiresAt } ]
let content (kvs: (string * obj) list) : IDictionary<string, obj> =
    let d = Dictionary<string, obj>()
    for (k, v) in kvs do d.[k] <- v
    d :> IDictionary<string, obj>
let mk t c nodeId seq ts priv = createRegisterEntry t (content c) "LTX-DEC-TEST" nodeId seq ts priv None
let dec1 = mk "decision" [ "text", box "Proceed with EVA-3"; "rationale", box "Weather window"; "originWindow", box "W2" ]
              "N0" 1 "2026-08-01T12:00:00.000Z" host.PrivateKeyB64
check "decision id prefix DEC" (dec1.entryId = "DEC-N0-1")
check "decision entry verifies" (fst (verifyRegisterEntry dec1 cache))
let r1, _ = reduceDecisions [ dec1 ]
check "decision RECORDED" (r1.["DEC-N0-1"].status = "RECORDED" && r1.["DEC-N0-1"].version = 1)
check "decision fields"
    (r1.["DEC-N0-1"].text = "Proceed with EVA-3" && r1.["DEC-N0-1"].recordedBy = "N0"
     && r1.["DEC-N0-1"].rationale = Some "Weather window")
let decRev = mk "decision_update" [ "did", box "DEC-N0-1"; "text", box "Proceed with EVA-3 at 14:00"; "version", box 2 ]
                "N1" 1 "2026-08-01T12:10:00.000Z" mars.PrivateKeyB64
check "decision_update id prefix DEC" (decRev.entryId = "DEC-N1-1")
let decRes = mk "decision_update" [ "did", box "DEC-N0-1"; "status", box "RESCINDED"; "version", box 3 ]
                "N0" 2 "2026-08-01T12:20:00.000Z" host.PrivateKeyB64
let r2, s2 = reduceDecisions [ decRes; dec1; decRev ]
check "decision update applied" (r2.["DEC-N0-1"].text = "Proceed with EVA-3 at 14:00")
check "decision RESCINDED v3" (r2.["DEC-N0-1"].status = "RESCINDED" && r2.["DEC-N0-1"].version = 3)
check "decision editor recorded" (r2.["DEC-N0-1"].editor = Some "N0")
check "decision older update superseded" (List.contains decRev.entryId s2)
let decA = mk "decision_update" [ "did", box "DEC-N0-1"; "text", box "From N0"; "version", box 5 ]
              "N0" 7 "2026-08-01T13:00:00.000Z" host.PrivateKeyB64
let decB = mk "decision_update" [ "did", box "DEC-N0-1"; "text", box "From N1"; "version", box 5 ]
              "N1" 7 "2026-08-01T13:00:00.000Z" mars.PrivateKeyB64
let c1, cs1 = reduceDecisions [ dec1; decB; decA ]
let c2, cs2 = reduceDecisions [ decA; dec1; decB ]
check "decision tie lowest nodeId wins" (c1.["DEC-N0-1"].text = "From N0")
check "decision tie loser superseded" (List.contains decB.entryId cs1 && not (List.contains decA.entryId cs1))
check "decision reduce order-independent" (c1 = c2 && cs1 = cs2)
let decHi = mk "decision_update" [ "did", box "DEC-N0-1"; "text", box "N1 v6"; "version", box 6 ]
               "N1" 8 "2026-08-01T12:30:00.000Z" mars.PrivateKeyB64
check "decision higher version wins" ((fst (reduceDecisions [ dec1; decA; decHi ])).["DEC-N0-1"].text = "N1 v6")
let decOrphan = mk "decision_update" [ "did", box "DEC-NOPE-1"; "version", box 2 ]
                   "N1" 9 "2026-08-01T12:40:00.000Z" mars.PrivateKeyB64
let decDup = createRegisterEntry "decision" (content [ "text", box "dup" ]) "LTX-DEC-TEST" "N1" 10
                 "2026-08-01T12:50:00.000Z" mars.PrivateKeyB64 (Some "DEC-N0-1")
let r3, s3 = reduceDecisions [ dec1; decOrphan; decDup ]
check "decision orphan update superseded" (List.contains "DEC-N1-9" s3)
check "decision duplicate create ignored"
    (r3.["DEC-N0-1"].text = "Proceed with EVA-3" && r3.["DEC-N0-1"].recordedBy = "N0")
check "decision reducer ignores others"
    ((fst (reduceDecisions [ dec1; decRev ])).Count = 1 && (fst (reduceActions [ dec1 ])).IsEmpty)
let merged, rejected, snap =
    runMergeSegment [ dec1 ] [ decRev ] cache "LTX-DEC-TEST" "N0" 99 "2026-08-01T15:00:00.000Z" host.PrivateKeyB64
let decReg = snap.content.["decisionRegister"] :?> IDictionary<string, obj>
check "snapshot decisionRegister"
    (((decReg.["DEC-N0-1"] :?> IDictionary<string, obj>).["version"] :?> int) = 2)
check "snapshot entry id and counts"
    (snap.entryId = "MRG-N0-99" && (snap.content.["entryCount"] :?> int) = 2
     && (snap.content.["rejectedCount"] :?> int) = 0 && merged.Length = 2 && rejected.IsEmpty)
check "snapshot signature verifies" (fst (verifyRegisterEntry snap cache))
let mergedR, rejectedR = mergeLogs [ dec1 ] [ decRev ] (dict [ "N0", cache.["N0"] ])
check "mergeLogs rejects unverifiable entries"
    (mergedR.Length = 1 && rejectedR.Length = 1 && snd rejectedR.Head = "key_not_in_cache")

printfn "\n%d passed  %d failed" passed failed
if failed > 0 then exit 1
