# interplanet-ltx (C#)

Pure .NET 6+ C# port of the [InterPlanet LTX SDK](https://interplanet.live).

All algorithms match `ltx-sdk.js` exactly: same polynomial hash, same base64url encoding, same JSON key order.

## Usage

```csharp
using InterplanetLtx;

// Create a session plan
var plan = InterplanetLTX.CreatePlan(
    title: "Q3 Review",
    start: "2026-06-01T14:00:00Z",
    delay: 1240);

// Compute timed segments
var segments = InterplanetLTX.ComputeSegments(plan);

// Generate plan ID
string planId = InterplanetLTX.MakePlanId(plan);

// Encode to URL hash
string hash = InterplanetLTX.EncodeHash(plan);   // "#l=eyJ2Ij..."

// Generate ICS
string ics = InterplanetLTX.GenerateICS(plan);

// Build node URLs
var urls = InterplanetLTX.BuildNodeUrls(plan, "https://interplanet.live/ltx.html");
```

### Wire-form plans, validation and registers

- `LtxPlanJson.MakePlanIdFromJson(json)` / `PlanHashFromJson(json)`: planId and
  planHash over plan JSON with key order preserved, matching
  `spec/golden/plan-ids.json`. The typed `MakePlanId` methods serialise v2 plans
  in the fixed order `v, title, start, quantum, mode, nodes, segments`.
- `LtxPlanJson.ValidatePlan(json | JsonElement | PlanV11)`: `PlanValidation`
  with `Code`, `Path`, `Message` per error, including `reserved_streams` and
  `reserved_branching`. `LtxV11.CreateSession` throws `ReservedFieldException`
  for those fields.
- `LtxV11.ReduceDecisions` (`decision`, `decision_update`),
  `CreateRegisterEntry`, `MergeLogs` and `RunMergeSegment` (the merge_snapshot
  carries `questionRegister`, `actionRegister` and `decisionRegister`).

## Build & Test

```
make build   # dotnet build InterplanetLTX.csproj (the library)
make test    # dotnet run --project tests (unit, security, v1.1, golden planId and prefix tests)
make lint    # library and test runner built with -warnaserror
make pack    # dotnet pack: library-only NuGet package in bin/pkg/
make clean   # rm -rf bin/ obj/ tests/bin/ tests/obj/
```

`InterplanetLTX.csproj` is the library. `tests/InterplanetLTX.Tests.csproj`
is a console test runner that references it.

Requires .NET 6+. Tests run without dotnet installed but print a skip message.
