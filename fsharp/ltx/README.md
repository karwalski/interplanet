# InterplanetLtx — F# SDK (Story 33.14)

Pure F# 6 (.NET 6) port of the LTX (Light-Time eXchange) SDK.

## Requirements

- .NET 6 SDK — https://dotnet.microsoft.com/download

## Run unit tests

```bash
dotnet fsi tests/UnitTest.fsx
```

Expected output: `80 passed  0 failed`

## Build library

```bash
make lint
# or: dotnet build InterplanetLtx.fsproj
```

## Usage example

```fsharp
#load "src/Models.fs"
#load "src/Constants.fs"
#load "src/InterplanetLtx.fs"

open InterplanetLtx.InterplanetLtx

// Create a plan
let plan =
    createPlanFromConfig {|
        title          = "LTX Session"
        start          = "2024-01-15T14:00:00Z"
        nodes          = [
            {| id = "N0"; name = "Earth HQ";    role = "HOST";        delay = 0; location = "earth" |}
            {| id = "N1"; name = "Mars Hab-01"; role = "PARTICIPANT"; delay = 0; location = "mars"  |}
        ]
        quantum        = 3
        mode           = "LTX"
        hostName       = ""
        hostLocation   = ""
        remoteName     = ""
        remoteLocation = ""
        delay          = 0
        segments       = []
    |}

// Compute timed segments
let segs = computeSegments plan
printfn "Total: %d min" (totalMin plan)

// Get plan ID
let planId = makePlanId plan
printfn "Plan ID: %s" planId
// => LTX-20240115-EARTHHQ-MARS-v2-cc8a7fc0

// Encode/decode URL hash
let hash    = encodeHash plan
let decoded = decodeHash hash

// Build node URLs
let urls = buildNodeUrls plan "https://interplanet.live/ltx.html"
for u in urls do printfn "%s: %s" u.nodeName u.url

// Generate ICS calendar file
let ics = generateICS plan

// Format helpers
printfn "%s" (formatHMS 3661)   // => 01:01:01
printfn "%s" (formatUTC 1705327200000L)  // => 2024-01-15T14:00:00Z
```

## API reference

| Function | Signature | Description |
|---|---|---|
| `createPlan` | `opts option -> LtxPlan` | Create default 2-node plan |
| `createPlanFromConfig` | `{\| ... \|} -> LtxPlan` | Create plan from full config record |
| `upgradeConfig` | `LtxPlan -> LtxPlan` | Upgrade v1 to v2 schema |
| `computeSegments` | `LtxPlan -> LtxSegment list` | Compute timed segments |
| `totalMin` | `LtxPlan -> int` | Total duration in minutes |
| `makePlanId` | `LtxPlan -> string` | Deterministic plan ID |
| `encodeHash` | `LtxPlan -> string` | URL hash fragment (#l=...) |
| `decodeHash` | `string -> LtxPlan option` | Decode URL hash fragment |
| `buildNodeUrls` | `LtxPlan -> string -> LtxNodeUrl list` | Per-node perspective URLs |
| `generateICS` | `LtxPlan -> string` | iCalendar (.ics) export |
| `formatHMS` | `int -> string` | Seconds to HH:MM:SS or MM:SS |
| `formatUTC` | `int64 -> string` | Epoch ms to ISO 8601 UTC |

## Key constants

- `VERSION = "1.0.0"`
- `DEFAULT_QUANTUM = 3` (minutes per quantum)
- `DEFAULT_API_BASE = "https://api.interplanet.app/ltx"`
- `SEG_TYPES = [| "PLAN_CONFIRM"; "TX"; "RX"; "CAUCUS"; "OPEN"; "BUFFER" |]`

## File layout

```
interplanet-github/fsharp-ltx/
├── src/
│   ├── Models.fs            record types
│   ├── Constants.fs         SDK constants
│   ├── InterplanetLtx.fs    11 API functions + djbHash + base64url
│   └── RestClient.fs        HTTP client (storeSession, getSession, downloadICS, submitFeedback)
├── tests/
│   └── UnitTest.fsx         standalone script, >= 80 check() calls
├── InterplanetLtx.fsproj    .NET 6 project file
├── Makefile
└── README.md
```
