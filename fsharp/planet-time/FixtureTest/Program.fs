// Program.fs — Standalone fixture runner for InterplanetTime F# library
// Story 18.14
//
// Usage: dotnet run --project FixtureTest [path/to/reference.json]
//
// Reads the 54-entry reference.json fixture, validates hour/minute and
// light-travel-seconds for each entry. Exits 0 on success, 1 on any failure.

module FixtureTest

open System
open System.IO
open System.Text.Json
open InterplanetTime

// ── JSON types ────────────────────────────────────────────────────────────────

[<CLIMutable>]
type FixtureEntry = {
    utc_ms          : int64
    planet          : string
    hour            : int
    minute          : int
    light_travel_s  : float
    period_in_week  : int
    is_work_period  : int
    is_work_hour    : int
}

[<CLIMutable>]
type FixtureFile = {
    entries : FixtureEntry array
}

// ── Main ──────────────────────────────────────────────────────────────────────

[<EntryPoint>]
let main argv =
    let defaultRelPath = "../../c/fixtures/reference.json"

    let fixturePath =
        if argv.Length > 0 then argv.[0]
        else
            let asm = IO.Path.GetDirectoryName(
                          Reflection.Assembly.GetExecutingAssembly().Location)
            Path.GetFullPath(Path.Combine(asm, defaultRelPath))

    if not (File.Exists(fixturePath)) then
        printfn "SKIP: fixture file not found at %s" fixturePath
        printfn "0 passed  0 failed  (fixtures skipped)"
        0
    else

    let json = File.ReadAllText(fixturePath)
    let opts = JsonSerializerOptions(PropertyNameCaseInsensitive = true)
    let fixture =
        try JsonSerializer.Deserialize<FixtureFile>(json, opts)
        with ex ->
            eprintfn "Failed to parse fixture: %s" ex.Message
            exit 1

    if isNull (box fixture) || fixture.entries.Length = 0 then
        eprintfn "Fixture file is empty or malformed."
        1
    else

    let mutable passed = 0
    let mutable failed = 0

    for entry in fixture.entries do
        let tag = sprintf "%s@%d" entry.planet entry.utc_ms

        // Check hour and minute
        let pt = getPlanetTime entry.planet entry.utc_ms 0.0

        if pt.Hour = entry.hour then
            passed <- passed + 1
        else
            failed <- failed + 1
            printfn "FAIL: %s hour=%d (got %d)" tag entry.hour pt.Hour

        if pt.Minute = entry.minute then
            passed <- passed + 1
        else
            failed <- failed + 1
            printfn "FAIL: %s minute=%d (got %d)" tag entry.minute pt.Minute

        // Check light travel (skip for earth and moon)
        if entry.light_travel_s <> 0.0
           && entry.planet <> "earth"
           && entry.planet <> "moon" then
            let lt = lightTravelSeconds "earth" entry.planet entry.utc_ms
            if Math.Abs(lt - entry.light_travel_s) <= 2.0 then
                passed <- passed + 1
            else
                failed <- failed + 1
                printfn "FAIL: %s lightTravel — expected %.3f, got %.3f"
                    tag entry.light_travel_s lt

        // Check period_in_week
        if pt.PeriodInWeek = entry.period_in_week then
            passed <- passed + 1
        else
            failed <- failed + 1
            printfn "FAIL: %s period_in_week=%d (got %d)" tag entry.period_in_week pt.PeriodInWeek

        // Check is_work_period
        let gotWP = if pt.IsWorkPeriod then 1 else 0
        if gotWP = entry.is_work_period then
            passed <- passed + 1
        else
            failed <- failed + 1
            printfn "FAIL: %s is_work_period=%d (got %d)" tag entry.is_work_period gotWP

        // Check is_work_hour
        let gotWH = if pt.IsWorkHour then 1 else 0
        if gotWH = entry.is_work_hour then
            passed <- passed + 1
        else
            failed <- failed + 1
            printfn "FAIL: %s is_work_hour=%d (got %d)" tag entry.is_work_hour gotWH

    printfn "Fixture entries checked: %d" fixture.entries.Length
    printfn "%d passed  %d failed" passed failed
    if failed > 0 then 1 else 0
