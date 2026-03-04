# InterplanetTime — C# (.NET 6) port

C# port of [planet-time.js](../../javascript/planet-time/planet-time.js) v1.1.0.
Story **18.11** — Epic 18 language ports.

## Structure

```
InterplanetTime/
├── InterplanetTime.cs       — library: constants, orbital mechanics, time, formatting
├── InterplanetTime.csproj   — .NET 6 class library project
FixtureTest/
├── FixtureTest.cs           — standalone fixture runner (54 cross-language entries)
├── FixtureTest.csproj       — exe project (references InterplanetTime.cs directly)
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

```csharp
using InterplanetTime;

// Planet local time
PlanetTime pt = Ipt.GetPlanetTime("mars", utcMs, tzOffsetH: 0.0);
Console.WriteLine(pt.TimeStr);       // "14:32"
Console.WriteLine(pt.IsWorkHour);    // true/false

// Mars Coordinated Time
MtcResult mtc = Ipt.GetMtc(utcMs);
Console.WriteLine(mtc.MtcStr);       // "14:32"

// Light travel between bodies
double secs = Ipt.LightTravelSeconds("earth", "mars", utcMs);
Console.WriteLine(Ipt.FormatLightTime(secs));  // "14.3min"

// Heliocentric position
HelioPos pos = Ipt.HelioPos("mars", utcMs);
Console.WriteLine($"r={pos.R:F4} AU");
```

## Constants

- `Ipt.J2000_MS` — J2000.0 epoch in Unix ms
- `Ipt.MARS_EPOCH_MS` — MY0 epoch in Unix ms
- `Ipt.MARS_SOL_MS` — Mars solar day in ms (88,775,244)
- `Ipt.AU_KM` — AU in kilometres (IAU 2012)
- `Ipt.C_KMS` — speed of light in km/s
- `Ipt.AU_SECONDS` — light travel time per AU in seconds

## Fixture validation

```
Fixture entries checked: 54
162 passed  0 failed
```

All 54 entries from `reference.json` pass: hour/minute exact match,
light-travel within ±2 s of the JS reference.
