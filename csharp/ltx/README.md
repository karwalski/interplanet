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

## Build & Test

```
make build   # dotnet build
make test    # dotnet run (runs ≥80 unit tests)
make lint    # dotnet build --no-restore
make clean   # rm -rf bin/ obj/
```

Requires .NET 6+. Tests run without dotnet installed but print a skip message.
