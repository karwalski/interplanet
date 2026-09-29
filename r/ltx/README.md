# InterplanetLtx — R Package

R implementation of the LTX (Light-Time eXchange) interplanetary meeting protocol.
Port of [ltx-sdk.js](../javascript/ltx/ltx-sdk.js).

**Requirements:** R >= 4.0. No mandatory external packages (uses `base64enc`, `openssl`, or `jsonlite` if available; falls back to pure-R implementations).

## Installation

```r
source("R/constants.R")
source("R/ltx.R")
source("R/parity.R")
```

## Usage

```r
source("R/constants.R")
source("R/ltx.R")
source("R/parity.R")

# Create a plan
plan <- create_plan(
  host_name   = "Earth HQ",
  remote_name = "Mars Hab-01",
  delay       = 800,        # seconds one-way
  title       = "Weekly Sync",
  start_iso   = "2026-06-01T14:00:00Z"
)

# Total session duration
cat(total_min(plan), "minutes\n")

# Compute timed segments
segs <- compute_segments(plan)

# Encode to URL hash
hash <- encode_hash(plan)

# Build node-specific URLs
urls <- build_node_urls(plan, "https://interplanet.live/ltx.html")

# Generate .ics calendar file
ics <- generate_ics(plan)

# Get deterministic plan ID
pid <- make_plan_id(plan)

# Decode plan from hash
plan2 <- decode_hash(hash)

# Format helpers
format_hms(3661)   # "01:01:01"
format_utc("2026-01-01T14:30:00Z")  # "14:30:00 UTC"
```

## Parity with ltx-sdk.js (issue #27)

- `make_plan_id(plan)`: v2 is the frozen imul31 hash over the UTF-16 code units
  of `json_stringify(plan)` in the plan's own key order, exactly like
  `makePlanId`; v3 plans (`v >= 3`) use SHA-256 over `canonical_json(plan)`.
  A plan parsed with `jsonlite::fromJSON(x, simplifyVector = FALSE)` keeps its
  key order, so `test/test_parity.R` reproduces every vector in
  `spec/golden/plan-ids.json`. `create_plan()` lists are ordered
  v, title, start, quantum, mode, nodes, segments (nodes before segments, unlike
  JS `createPlan`), which matches the `v2-key-order-sensitive` vector.
- `validate_plan(plan)` returns `list(valid, errors)` with the error codes of
  `validatePlan`, including `reserved_streams` and `reserved_branching`.
- `upgrade_plan_to_v3(plan, extras)` stops with an `ltx_reserved_field_error`
  condition (`$code`, `$errors`) on reserved fields. This port has no sessions
  or amendments.
- `build_delay_matrix(plan)` uses `pair_delay()` for every entry: a v3
  `delays` entry wins, HOST pairs use the node's delay, and non-HOST pairs the
  sum (not the max) of both HOST-relative delays.
- `plan_hash(plan)`, `sha256_hex(s)` (base R), `canonical_json(x)`,
  `json_stringify(x)`, `imul31_hex(s)`.
- `create_plan()` defaults to a 5-minute quantum (`DEFAULT_QUANTUM`).

## File Layout

```
r/ltx/
  R/
    constants.R   LTX constants (PROTOCOL_VERSION, modes, segment types)
    ltx.R         All core functions
    parity.R      JSON.stringify/canonical JSON, SHA-256, validate_plan,
                  upgrade_plan_to_v3, pair_delay
  test/
    test_unit.R   >= 50 check() assertions
    test_parity.R parity with ltx-sdk.js (needs jsonlite)
  DESCRIPTION
  NAMESPACE
  Makefile
  README.md
```

## Running Tests

```sh
make test    # Unit tests
make lint    # Source check
```

## Protocol

LTX is an asynchronous interplanetary meeting protocol built on signal-delay-aware
segment scheduling. Each session plan contains:

- **Nodes**: participants with their one-way signal delays
- **Segments**: typed time slots (TX, RX, CAUCUS, BUFFER, etc.)
- **Quantum**: minimum time unit in minutes

See [LTX Protocol](https://interplanet.live/ltx.html) for full documentation.

## License

GPL-3.0
