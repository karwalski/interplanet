#!/usr/bin/env dotnet-script
// PrefixTest.fsx --- spec/golden/plan-id-prefixes.json (issue #37, spec §4.3).
// HOSTSTR / NODESTR use JS whitespace, JS toUpperCase (full Unicode mapping
// with special casing, Upper.jsToUpper) and UTF-16 slicing. An F# string is
// UTF-16, so the exact JS id (planId, lone surrogates included) is expected on
// every path: Validate.makePlanIdFromJson (JSON text), V11.makePlanId (typed
// PlanV11) and InterplanetLtx.makePlanId (typed LtxPlan, v2 only).
// Run with: dotnet fsi tests/PrefixTest.fsx

#r "nuget: NSec.Cryptography, 24.4.0"
#load "../src/Upper.fs"
#load "../src/Models.fs"
#load "../src/Constants.fs"
#load "../src/InterplanetLtx.fs"
#load "../src/Security.fs"
#load "../src/Validate.fs"
#load "../src/V11.fs"

open System.IO
open System.Text.Json
open InterplanetLtx.Security
open InterplanetLtx.Validate
open InterplanetLtx.V11

module Typed = InterplanetLtx.InterplanetLtx

let mutable passed = 0
let mutable failed = 0

let check label cond =
    if cond then passed <- passed + 1
    else
        failed <- failed + 1
        printfn "FAIL: %s" label

let checkId label (got: string) (want: string) =
    check label (got = want)
    if got <> want then printfn "  got  %s\n  want %s" (jsonStr got) (jsonStr want)

let s (o: JsonElement) (k: string) : string option =
    match o.TryGetProperty k with
    | true, v when v.ValueKind = JsonValueKind.String -> Some (unquoteJson (v.GetRawText()))
    | _ -> None

let prefix (id: string) = id.Substring(0, id.Length - 12)

let rec findUp (dir: DirectoryInfo) =
    if isNull dir then None
    else
        let p = Path.Combine(dir.FullName, "spec", "golden", "plan-id-prefixes.json")
        if File.Exists p then Some p else findUp dir.Parent

match findUp (DirectoryInfo(__SOURCE_DIRECTORY__)) with
| None -> check "prefix: spec/golden/plan-id-prefixes.json found" false
| Some path ->
    use doc = JsonDocument.Parse(File.ReadAllText path)
    let vectors = doc.RootElement.GetProperty("vectors").EnumerateArray() |> List.ofSeq
    check "prefix: vectors present" (vectors.Length >= 18)
    for gv in vectors do
        let name = (s gv "name").Value
        let want = (s gv "planId").Value
        let plan = gv.GetProperty "plan"
        checkId ("prefix json " + name) (makePlanIdFromJson (plan.GetRawText())) want
        checkId ("prefix json text " + name) (makePlanIdFromJson (stringify plan)) want
        // Typed models write nodes before segments: the v2 hash matches only
        // for nodes-first vectors; v3 (canonical JSON) always.
        let keys = plan.EnumerateObject() |> Seq.map (fun p -> p.Name) |> List.ofSeq
        let nodesFirst = List.findIndex ((=) "nodes") keys < List.findIndex ((=) "segments") keys
        let v = plan.GetProperty("v").GetInt32()
        let typed : PlanV11 =
            { v = v
              title = (s plan "title").Value
              start = (s plan "start").Value
              quantum = plan.GetProperty("quantum").GetInt32()
              mode = (s plan "mode").Value
              nodes =
                [ for n in plan.GetProperty("nodes").EnumerateArray() ->
                    ({ id = (s n "id").Value; name = (s n "name").Value; role = (s n "role").Value
                       delay = n.GetProperty("delay").GetInt64(); location = (s n "location").Value } : NodeV11) ]
              segments =
                [ for x in plan.GetProperty("segments").EnumerateArray() ->
                    ({ segType = (s x "type").Value; q = x.GetProperty("q").GetInt32()
                       speaker = s x "speaker"; label = s x "label" } : SegV11) ]
              delays =
                match plan.TryGetProperty "delays" with
                | true, d -> Some (d.EnumerateObject() |> Seq.map (fun kv -> kv.Name, kv.Value.GetInt64()) |> Map.ofSeq)
                | _ -> None
              planVersion = (match plan.TryGetProperty "planVersion" with | true, pv -> Some (pv.GetInt32()) | _ -> None)
              prevPlanHash = s plan "prevPlanHash" }
        let v11 = makePlanId typed
        checkId ("prefix typed PlanV11 prefix " + name) (prefix v11) (prefix want)
        if nodesFirst || v >= 3 then checkId ("prefix typed PlanV11 " + name) v11 want
        if v = 2 then
            let legacy : InterplanetLtx.Models.LtxPlan =
                { v = 2; title = typed.title; start = typed.start; quantum = typed.quantum; mode = typed.mode
                  nodes = typed.nodes |> List.map (fun n ->
                    ({ id = n.id; name = n.name; role = n.role; delay = int n.delay; location = n.location } : InterplanetLtx.Models.LtxNode))
                  segments = typed.segments |> List.map (fun x ->
                    ({ segType = x.segType; q = x.q; speaker = x.speaker; label = x.label } : InterplanetLtx.Models.LtxSegmentTemplate))
                  planId = None }
            let tid = Typed.makePlanId legacy
            checkId ("prefix typed LtxPlan prefix " + name) (prefix tid) (prefix want)
            if nodesFirst then checkId ("prefix typed LtxPlan " + name) tid want

// Upper.jsToUpper spot checks (special casing ToUpperInvariant lacks).
check "jsToUpper special casing"
    (InterplanetLtx.Upper.jsToUpper "straße ﬁx ΐ ᾳ ŉ" = "STRASSE FIX Ϊ́ ΑΙ ʼN")
check "jsToUpper lone surrogate kept, astral mapped"
    (InterplanetLtx.Upper.jsToUpper "a\ud83dz𐐨" = "A\ud83dZ𐐀")

printfn "\n%d passed  %d failed" passed failed
if failed > 0 then exit 1
