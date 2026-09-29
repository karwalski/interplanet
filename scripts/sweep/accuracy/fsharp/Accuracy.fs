// Accuracy harness for fsharp/planet-time (see ../gen-cases-group2.js).
//   dotnet run --project scripts/sweep/accuracy/fsharp -- scripts/sweep/accuracy/instants-group2.txt
module Accuracy

open System
open System.Globalization
open System.IO

let bodies = [ "mercury"; "venus"; "earth"; "mars"; "jupiter"; "saturn"; "uranus"; "neptune"; "moon" ]
let b v = if v then 1 else 0
let inv = CultureInfo.InvariantCulture

[<EntryPoint>]
let main argv =
    for raw in File.ReadAllLines argv.[0] do
        let line = raw.Trim()
        if line <> "" then
            let ms = Int64.Parse(line, inv)
            for body in bodies do
                try
                    let pt = InterplanetTime.getPlanetTime body ms 0.0
                    let lt = InterplanetTime.lightTravelSeconds body "earth" ms
                    printfn "%d\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s" ms body pt.Hour pt.Minute pt.Second
                        pt.DayNumber pt.DayInYear pt.YearNumber pt.PeriodInWeek (b pt.IsWorkPeriod)
                        (b pt.IsWorkHour) (lt.ToString("F6", inv))
                with e -> eprintfn "%d %s: %s" ms body e.Message
            let m = InterplanetTime.getMtc ms
            printfn "%d\tmtc\t%d\t%d\t%d\t%d" ms m.Sol m.Hour m.Minute m.Second
    0
