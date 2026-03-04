# InterplanetTime — F# (.NET 6) port

F# port of [planet-time.js](../../javascript/planet-time/planet-time.js) v1.1.0.
Story **18.14** — Epic 18 language ports.

## Structure

```
InterplanetTime/
├── Library.fs               — library: constants, orbital mechanics, time, formatting
├── InterplanetTime.fsproj   — .NET 6 class library project
FixtureTest/
├── Program.fs               — standalone fixture runner (54 cross-language entries)
├── FixtureTest.fsproj       — exe project (references InterplanetTime project)
Makefile
README.md
```

## Quick start

```bash
# Build the library
dotnet build InterplanetTime

# Run fixture cross-validation
dotnet run --project FixtureTest ../../c/fixtures/reference.json
```

## API

```fsharp
open InterplanetTime

// Planet local time
let pt = getPlanetTime "mars" utcMs 0.0
printfn "%s" pt.TimeStr       // "14:32"
printfn "%b" pt.IsWorkHour    // true/false

// Mars Coordinated Time
let mtc = getMtc utcMs
printfn "%s" mtc.MtcStr       // "14:32"

// Light travel between bodies
let secs = lightTravelSeconds "earth" "mars" utcMs
printfn "%s" (formatLightTime secs)   // "14.3min"

// Heliocentric position
let pos = helioPos "mars" utcMs
printfn "r=%.4f AU" pos.R
```

## Constants

- `J2000_MS` — J2000.0 epoch in Unix ms
- `MARS_EPOCH_MS` — MY0 epoch in Unix ms
- `MARS_SOL_MS` — Mars solar day in ms (88,775,244)
- `AU_KM` — AU in kilometres (IAU 2012)
- `C_KMS` — speed of light in km/s
- `AU_SECONDS` — light travel time per AU in seconds

## Fixture validation

```
Fixture entries checked: 54
162 passed  0 failed
```

All 54 entries from `reference.json` pass: hour/minute exact match,
light-travel within ±2 s of the JS reference.
