# interplanet-ltx — Zig SDK

Zig port of the LTX (Light-Time eXchange) session planning library for the InterPlanet project.

## Requirements

- Zig 0.15 (CI uses 0.15.1)

## Build

```sh
zig build
```

## Test

```sh
zig build test
# or
make test
```

## Lint

```sh
make lint
```

## API

### Constants

```zig
pub const VERSION        = "1.1.0";
pub const DEFAULT_QUANTUM: u32 = 5;        // minutes per quantum
pub const DEFAULT_API_BASE = "https://api.interplanettime.net/ltx/v1";
pub const SEG_TYPES      = [_][]const u8{ "TX", "RX", "BUFFER", "HOLD", "PREP" };
pub const DEFAULT_SEGMENTS: [5]SegmentTemplate = ...;   // TX/3, RX/1, TX/2, RX/1, BUFFER/2
```

### Types

```zig
pub const SegmentTemplate = struct { seg_type: []const u8, duration: u32 };

pub const Node = struct {
    id:       []const u8,
    name:     []const u8,
    location: []const u8,
    is_host:  bool,
};

pub const Segment = struct {
    id:           []const u8,
    seg_type:     []const u8,
    speaker:      ?[]const u8,  // null for BUFFER / HOLD / PREP
    duration:     u32,          // minutes
    start_offset: u32,          // minutes from plan start
};

pub const NodeUrl = struct {
    node_id:     []const u8,
    base_url:    []const u8,
    session_url: []const u8,
};

pub const Plan = struct {
    v:        []const u8,   // "2"
    title:    []const u8,
    start:    []const u8,   // ISO 8601 UTC
    quantum:  u32,
    mode:     []const u8,   // "LTX"
    nodes:    []const Node,
    segments: []const Segment,
};
```

### Functions

| Function | Description |
|---|---|
| `createPlan(allocator, opts)` | Build a new Plan from CreatePlanOpts |
| `upgradeConfig(allocator, plan)` | Ensure plan is v2 (adds default nodes if missing) |
| `totalMin(plan)` | Sum of all segment durations in minutes |
| `computeSegments(allocator, nodes, template, quantum)` | Compute timed Segment array |
| `makePlanId(allocator, plan)` | Deterministic plan ID string |
| `encodeHash(allocator, plan)` | Base64url encode plan as `#l=…` fragment |
| `decodeHash(allocator, encoded)` | Decode `#l=…` or raw base64url back to JSON |
| `buildNodeUrls(allocator, plan, base_url)` | Per-node session URLs |
| `buildDelayMatrix(allocator, plan)` | Legacy N×N placeholder matrix from the quantum only (the struct `Node` carries no delay). Not the spec §3.7 matrix: use `ltx_v11.buildDelayMatrixJson` |
| `generateIcs(allocator, plan)` | iCalendar (.ics) string with CRLF endings |
| `formatHms(allocator, total_minutes)` | Format minutes as "Xh Ym" / "Xh" / "Ym" / "0m" |
| `planToJson(allocator, plan)` | Serialise Plan to canonical JSON |

All allocating functions take an `std.mem.Allocator` and return `!T`. The caller owns all returned memory.

### Wire-format plans (`src/ltx_v11.zig`)

These operate on plans and register entries as parsed `std.json.Value`
trees (object maps keep key insertion order, which the frozen v2 planId hash
depends on) and mirror `javascript/ltx/ltx-sdk.js`.

| Function | Description |
|---|---|
| `makePlanIdJson(alloc, plan)` / `planHashJson(alloc, plan)` | planId (v2 imul31 over UTF-16 code units of the insertion-order JSON; v3 SHA-256 of canonical JSON) and planHash. Checked against `spec/golden/plan-ids.json` |
| `validatePlanJson(alloc, plan)` | `validatePlan`: schema checks plus `reserved_streams` / `reserved_branching` (LTX-SPECIFICATION §3.5, §7) |
| `reservedFieldCode(plan)` / `assertNoReservedFields(plan)` | Reserved-field check; `createSession` refuses such plans with `error.ReservedStreams` / `error.ReservedBranching` |
| `pairDelayJson(alloc, plan, a, b)` | One-way pair delay (§3.7): v3 `delays` entry, else HOST-relative delay, else the sum of both |
| `buildDelayMatrixJson(alloc, plan)` | `buildDelayMatrix`: `pairDelayJson` over all ordered node pairs (sum, never max; symmetric) |
| `reduceQuestionsJson` / `reduceActionsJson` / `reduceDecisionsJson` | Register reducers (§9.4, §10.2, §10.3) with the §8.2 conflict rule |
| `createRegisterEntryJson(arena, type, content, opts)` | Signed register entry (`decision_update` uses the `DEC-` prefix) |
| `mergeLogsJson` / `runMergeSegmentJson` | §8.2 merge and the §8.4 `merge_snapshot` (question, action and decision registers) |

## Conformance vector v001

```
title:   "Test Meeting Alpha"
start:   "2040-01-15T14:00:00Z"
quantum: 5
host:    { id: "EARTH_HQ", name: "Earth HQ",   location: "earth", is_host: true  }
remote:  { id: "MARS",     name: "Mars Base",   location: "mars",  is_host: false }
template: TX/3, RX/1, TX/2, RX/1, BUFFER/2  →  totalMin = 45

planId: "LTX-20400115-EARTH_HQ-MARS-v2-8f812845"
```

## Plan ID format

```
LTX-{YYYYMMDD}-{HOST_ID}-{REMOTE_ID}-v2-{HASH8}
```

`HASH8` is the first 8 hex digits of a DJB polynomial hash over the canonical JSON (`h = h *% 31 +% c`, wrapping u32 arithmetic).

## JSON key order

`planToJson` always emits: `v`, `title`, `start`, `quantum`, `mode`, `nodes`, `segments`.
