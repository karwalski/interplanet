# InterplanetLtx.jl

Julia port of ltx-sdk.js — LTX (Light-Time eXchange) Developer SDK v1.0.0.

Provides plan creation, segment computation, URL hash encoding/decoding,
ICS calendar generation, and optional REST helpers for LTX interplanetary sessions.
No external package dependencies — uses Julia stdlib only.

## Requirements

- Julia 1.9 or later
- No external packages required (Base64 and SHA are Julia stdlib)

## Quick start

```julia
include("src/InterplanetLtx.jl")
using .InterplanetLtx

# Create a plan (Earth HQ → Mars Hab-01, 800 s one-way delay)
plan = create_plan(
    host_name   = "Earth HQ",
    remote_name = "Mars Hab-01",
    delay       = 800,
    title       = "Weekly Sync",
    start_iso   = "2026-06-01T14:00:00Z",
)

# Compute timed segments
segs = compute_segments(plan)
for seg in segs
    println("$(seg.type): $(seg.dur_min) min")
end

# URL hash encoding (for sharing via URL)
hash  = encode_hash(plan)          # "#l=..."
plan2 = decode_hash(hash)          # round-trip

# Perspective URLs for each node
urls = build_node_urls(plan, "https://interplanet.live/ltx.html")
for u in urls
    println("$(u.name): $(u.url)")
end

# Plan ID (deterministic)
id = make_plan_id(plan)            # "LTX-20260601-EARTHHQ-MARS-v2-XXXXXXXX"

# ICS calendar export
ics = generate_ics(plan)

# Duration
println("Total: $(total_min(plan)) minutes")
```

## API

### Types

| Type | Description |
|------|-------------|
| `LtxNode` | Session participant (id, name, role, delay, location) |
| `LtxSegmentSpec` | Segment template (type, q) |
| `LtxPlan` | Full session plan |
| `LtxSegmentResult` | Computed timed segment (type, start_ms, end_ms, dur_min) |
| `LtxNodeUrl` | Perspective URL for one node |

### Constants

| Name | Value | Description |
|------|-------|-------------|
| `PROTOCOL_VERSION` | "1.0.0" | SDK version |
| `DEFAULT_QUANTUM` | 5 | Default minutes per quantum |
| `SEG_TYPES` | [...] | Valid segment type strings |
| `DEFAULT_SEGMENTS` | 7 segments | PLAN_CONFIRM, TX, RX, CAUCUS, TX, RX, BUFFER |

### Functions

| Function | Description |
|----------|-------------|
| `create_plan(; ...)` | Create a new LTX plan |
| `compute_segments(plan)` | Compute timed segments |
| `total_min(plan)` | Total duration in minutes |
| `make_plan_id(plan)` | Deterministic plan ID |
| `encode_hash(plan)` | Encode to URL hash fragment |
| `decode_hash(fragment)` | Decode from URL hash fragment |
| `build_node_urls(plan, base_url)` | Build node perspective URLs |
| `generate_ics(plan)` | Generate iCalendar content |
| `format_hms(sec)` | Format seconds as MM:SS or HH:MM:SS |
| `format_utc(epoch_ms)` | Format epoch ms as HH:MM:SS UTC |
| `store_session(plan; api_base)` | Store plan on server (optional) |
| `get_session(plan_id; api_base)` | Retrieve plan from server (optional) |

### Parity with ltx-sdk.js (issue #27, `src/parity.jl`)

| Function | Description |
|----------|-------------|
| `parse_json_ordered(text)` | Decode JSON keeping object key order (`JsonObject`) |
| `make_plan_id(obj::JsonObject)` | planId of a JSON plan: v2 imul31 over the UTF-16 code units of `JSON.stringify` in the plan's own key order, v3 SHA-256 of canonical JSON; reproduces every vector in `spec/golden/plan-ids.json` |
| `plan_id_from_json(text)` | Both steps at once |
| `plan_hash(plan)` | SHA-256 hex of canonical JSON (prevPlanHash) |
| `validate_plan(plan)` | `(valid, errors)` with the error codes of `validatePlan`, incl. `reserved_streams` / `reserved_branching` |
| `upgrade_plan_to_v3(plan; extras)` | Explicit v2 to v3 upgrade; throws `ReservedFieldError` (`.code`) on reserved fields |
| `json_stringify(x; canonical)`, `canonical_json(x)`, `imul31_hex(s)` | Building blocks |

`LtxPlan` serialises nodes before segments (JS `createPlan` emits segments
first), so `create_plan` output reproduces the `v2-key-order-sensitive` vector.
`create_plan` defaults to a 5-minute quantum. This port has no sessions,
amendments or registers.

## Running tests

```bash
make test
```

## Segment types

- `PLAN_CONFIRM` — Both parties confirm plan receipt
- `TX` — Transmit window (host speaks)
- `RX` — Receive window (awaiting delayed response)
- `CAUCUS` — Internal deliberation
- `BUFFER` — Timing buffer / slack
- `MERGE` — Multi-party merge window
