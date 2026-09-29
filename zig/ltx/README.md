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

### Typed v2 plans (`src/interplanet_ltx.zig`)

The typed model is the v2 plan schema (LTX-SPECIFICATION.md §4.1) and mirrors
`javascript/ltx/ltx-sdk.js` `createPlan` / `makePlanId`.

```zig
pub const DEFAULT_QUANTUM: u32 = 5;  // minutes per quantum
pub const SEG_TYPES = [_][]const u8{ "PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE" };
pub const DEFAULT_SEGMENTS = ...;    // PLAN_CONFIRM/2 TX/2 RX/2 CAUCUS/2 TX/2 RX/2 BUFFER/1, as JS

pub const SegmentTemplate = struct {  // wire {"type","q"[,"speaker"][,"label"]}
    seg_type: []const u8,
    q: u32,
    speaker: ?[]const u8 = null,
    label: ?[]const u8 = null,
};

pub const Node = struct {             // wire {"id","name","role","delay","location"}
    id: []const u8,
    name: []const u8,
    role: []const u8,                 // HOST | PARTICIPANT | OBSERVER
    delay: i64 = 0,                   // one-way seconds to the HOST
    location: []const u8,
};

pub const LtxPlan = struct {
    v: u32 = 2,
    title: []const u8,
    start: []const u8,                // ISO 8601 UTC
    quantum: u32,
    mode: []const u8,                 // LTX | LTX-LIVE | LTX-RELAY | LTX-ASYNC
    nodes: []const Node,              // HOST first
    segments: []const SegmentTemplate,
};
```

| Function | Description |
|---|---|
| `createPlan(allocator, opts)` | JS `createPlan`: defaults title `LTX Session`, mode `LTX`, quantum 5, `DEFAULT_SEGMENTS`, nodes N0 `Earth HQ` (HOST) and N1 `Mars Hab-01` (PARTICIPANT, `opts.delay`), start = now at the whole minute + 5 min. Returns a deep copy; free with `deinitPlan` |
| `clonePlan` / `deinitPlan` / `planFromJson(allocator, json)` | Deep copy, free, and parse wire JSON into an `LtxPlan` |
| `planToJson(allocator, plan)` | Wire JSON, key order `v, title, start, quantum, mode, segments, nodes` (as `JSON.stringify` of a JS `createPlan` plan) |
| `makePlanId(allocator, plan)` | Frozen v2 planId (§4.3): imul31 over the UTF-16 code units of exactly `planToJson(plan)`; HOSTSTR/NODESTR from node names |
| `encodeHash` / `decodeHash` | `#l=` base64url of the wire JSON, and back to JSON text |
| `computeSegments(allocator, plan)` | Timed segments (`start_ms`, `end_ms`, `dur_min`, speaker, label) |
| `totalMin(plan)` | Sum of `q * quantum` |
| `pairDelay(plan, a, b)` / `buildDelayMatrix(allocator, plan)` | §3.7 pair delay (HOST-relative, sum between non-HOST nodes) over every ordered pair |
| `buildNodeUrls(allocator, plan, base_url)` | `{base}?node={id}#l=...` per node; free with `freeNodeUrls` |
| `generateIcs(allocator, plan)` | JS `generateICS` (organiser form), CRLF line endings |
| `escapeIcsText`, `formatHms`, `planLockTimeoutMs`, `checkDelayViolation` | Helpers |

Because the typed plan hashes what it transmits, a Zig `createPlan` plan has
the same planId as a JS `createPlan` plan built from the same values. For a
plan received as JSON text from another sender, compute the planId from that
text with `ltx_v11.makePlanIdJson`: re-serialising a parsed plan uses this
port's key order, which need not be the sender's. The typed model is v2
only; v3 plans go through the JSON API.

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

## Plan ID format

```
LTX-{YYYYMMDD}-{HOSTSTR}-{NODESTR}-v2-{HASH8}
```

`HOSTSTR` is the first node's name without whitespace, upper-cased, cut to 8
UTF-16 units; `NODESTR` is every other node name the same way cut to 4,
joined by `-` and cut to 16 (`RX` for a single-node plan). `HASH8` is
`h = imul(31, h) + c` (wrapping u32) over the UTF-16 code units of the wire
JSON, as 8 lowercase hex digits. Upper-casing covers ASCII and Latin-1.
