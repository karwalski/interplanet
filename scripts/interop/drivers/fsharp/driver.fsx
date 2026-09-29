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

if mode = "main" then
    let basePlan = InterplanetLtx.createPlan None
    let plan : Models.LtxPlan =
        { basePlan with
            title = title; start = start; quantum = 3; mode = "LTX-ASYNC"
            nodes = [
                { id = "N0"; name = "Earth HQ"; role = "HOST"; delay = 0; location = "earth" }
                { id = "N1"; name = "Mars Hab-01"; role = "PARTICIPANT"; delay = 840; location = "mars" }
                { id = "N2"; name = "L-1 Gateway"; role = "PARTICIPANT"; delay = 2; location = "moon" } ]
            // LtxSegmentTemplate is (segType, q) only: no speaker/label.
            segments = [
                { segType = "PLAN_CONFIRM"; q = 2 }; { segType = "TX"; q = 3 }; { segType = "RX"; q = 3 }
                { segType = "TX"; q = 2 }; { segType = "BUFFER"; q = 1 } ] }
    printfn "NOTE LtxPlan: no speaker/label, no v3"
    let token = (InterplanetLtx.encodeHash plan).Substring(3).Replace('-', '+').Replace('_', '/')
    let padded = token.PadRight(token.Length + (4 - token.Length % 4) % 4, '=')
    File.WriteAllBytes(Path.Combine(outDir, "wire-v2.json"), Convert.FromBase64String padded)
    printfn "ID_V2 %s" (InterplanetLtx.makePlanId plan)
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
