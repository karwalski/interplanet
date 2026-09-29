// Interop driver for fsharp/ltx (see scripts/interop/run.js).
// Usage: dotnet fsi driver.fsx <main|v11> <inDir> <outDir>
//   main  InterplanetLtx.createPlan / encodeHash / makePlanId (LtxPlan)
//   v11   V11 model: PlanV11 / toJsonV2 / makePlanId, plus v3
#r "nuget: NSec.Cryptography, 24.4.0"
#load "../../../../fsharp/ltx/src/Models.fs"
#load "../../../../fsharp/ltx/src/Constants.fs"
#load "../../../../fsharp/ltx/src/InterplanetLtx.fs"
#load "../../../../fsharp/ltx/src/Security.fs"
#load "../../../../fsharp/ltx/src/Validate.fs"
#load "../../../../fsharp/ltx/src/V11.fs"

open System
open System.IO
open System.Text
open InterplanetLtx

let args = fsi.CommandLineArgs |> Array.skip 1
let mode, inDir, outDir = args.[0], args.[1], args.[2]
let title = "Réunion Mars 🚀"
let start = "2026-03-15T14:00:00.000Z"
let utf8 = UTF8Encoding(false)

/// The #l= token of a typed plan, decoded to its wire JSON bytes.
let wire (plan: Models.LtxPlan) : byte[] =
    let token = (InterplanetLtx.encodeHash plan).Substring(3).Replace('-', '+').Replace('_', '/')
    Convert.FromBase64String(token.PadRight(token.Length + (4 - token.Length % 4) % 4, '='))

if mode = "main" then
    let basePlan = InterplanetLtx.createPlan None
    let plan : Models.LtxPlan =
        { basePlan with
            title = title; start = start; quantum = 3; mode = "LTX-ASYNC"
            nodes = [
                { id = "N0"; name = "Earth HQ"; role = "HOST"; delay = 0; location = "earth" }
                { id = "N1"; name = "Mars Hab-01"; role = "PARTICIPANT"; delay = 840; location = "mars" }
                { id = "N2"; name = "L-1 Gateway"; role = "PARTICIPANT"; delay = 2; location = "moon" } ]
            segments = [
                Models.segment "PLAN_CONFIRM" 2
                { Models.segment "TX" 3 with speaker = Some "N0"; label = Some "Ouverture: état de la mission" }
                Models.segment "RX" 3
                { Models.segment "TX" 2 with speaker = Some "N1"; label = Some "Réponse 🔴" }
                Models.segment "BUFFER" 1 ] }
    printfn "NOTE LtxPlan: no v3"
    File.WriteAllBytes(Path.Combine(outDir, "wire-v2.json"), wire plan)
    printfn "ID_V2 %s" (InterplanetLtx.makePlanId plan)

    // Issue #36 extra case (not a run.js column): control characters, a lone
    // surrogate and JS \s whitespace (tab, NBSP, U+3000, U+2028, BOM, LF) in
    // the title and node names, plus a speaker-only and a label-only segment.
    // The typed wire JSON must be exactly what JSON.stringify writes for it,
    // and the typed planId must equal the JSON-based planId of that wire and
    // the JS reference id (ltx-sdk.js makePlanId on the same plan object).
    let ctl : Models.LtxPlan =
        { v = 2
          // an F# literal turns a lone surrogate into U+FFFD, so build it
          title = "Ctl\u0001\b\f\n\r\t\"\\\u001f\u007f" + string (char 0xd800) + " \ud83d\ude80"
          start = start; quantum = 3; mode = "LTX-ASYNC"
          nodes = [
            { id = "N0"; name = "Earth\tHQ"; role = "HOST"; delay = 0; location = "earth" }
            { id = "N1"; name = "Ma\u00a0r\u3000s\u2009Hab-01"; role = "PARTICIPANT"; delay = 840; location = "mars" }
            { id = "N2"; name = "L-1\u2028Gate\ufeffway\n"; role = "PARTICIPANT"; delay = 2; location = "moon" } ]
          segments = [
            Models.segment "PLAN_CONFIRM" 2
            { Models.segment "TX" 3 with speaker = Some "N0"; label = Some "Opening\tremarks" }
            Models.segment "RX" 3
            { Models.segment "TX" 2 with speaker = Some "N1" }
            { Models.segment "TX" 1 with label = Some "Q&A \ud83d\udd34" }
            Models.segment "BUFFER" 1 ]
          planId = None }
    let reference = "LTX-20260315-EARTHHQ-MARS-L-1G-v2-39d48c2a"
    let ctlWire = wire ctl
    File.WriteAllBytes(Path.Combine(outDir, "wire-ctl.json"), ctlWire)
    let ctlJson = Encoding.UTF8.GetString ctlWire
    let ctlId = InterplanetLtx.makePlanId ctl
    let ctlJsonId = Validate.makePlanIdFromJson ctlJson
    let ok =
        Validate.stringify (Json.JsonDocument.Parse(ctlJson).RootElement) = ctlJson
        && ctlId = ctlJsonId && ctlId = reference
    printfn "NOTE ctl/whitespace case: typed %s, JSON %s, JS %s%s" ctlId ctlJsonId reference (if ok then " (ok)" else " (MISMATCH)")
    if not ok then exit 1
else
    let seg t q sp lb : V11.SegV11 = { segType = t; q = q; speaker = sp; label = lb }
    let plan : V11.PlanV11 =
        { v = 2; title = title; start = start; quantum = 3; mode = "LTX-ASYNC"
          nodes = [
            { id = "N0"; name = "Earth HQ"; role = "HOST"; delay = 0L; location = "earth" }
            { id = "N1"; name = "Mars Hab-01"; role = "PARTICIPANT"; delay = 840L; location = "mars" }
            { id = "N2"; name = "L-1 Gateway"; role = "PARTICIPANT"; delay = 2L; location = "moon" } ]
          segments = [
            seg "PLAN_CONFIRM" 2 None None
            seg "TX" 3 (Some "N0") (Some "Ouverture: état de la mission")
            seg "RX" 3 None None
            seg "TX" 2 (Some "N1") (Some "Réponse 🔴")
            seg "BUFFER" 1 None None ]
          delays = None; planVersion = None; prevPlanHash = None }
    File.WriteAllText(Path.Combine(outDir, "wire-v2.json"), V11.toJsonV2 plan, utf8)
    printfn "ID_V2 %s" (V11.makePlanId plan)
    // No upgrade function: build the v3 plan with a record copy.
    let v3 = { plan with v = 3; planVersion = Some 1; delays = Some (Map.ofList [ "N1|N2", 842L ]) }
    File.WriteAllText(Path.Combine(outDir, "wire-v3.json"), Security.canonicalJson (box (V11.planToDict v3)), utf8)
    printfn "ID_V3 %s" (V11.makePlanId v3)
    printfn "NOTE PlanV11: v2 wire via toJsonV2, v3 wire via canonicalJson(planToDict); v3 via record copy"

for v in [ "2"; "3" ] do
    let json = File.ReadAllText(Path.Combine(inDir, sprintf "js-v%s.json" v), Encoding.UTF8)
    printfn "JS_V%s %s" v (Validate.makePlanIdFromJson json)
