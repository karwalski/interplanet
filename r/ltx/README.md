# InterplanetLtx — R Package

R implementation of the LTX (Light-Time eXchange) interplanetary meeting protocol.
Port of [ltx-sdk.js](../javascript/ltx/ltx-sdk.js).

**Requirements:** R >= 4.0. No mandatory external packages (uses `base64enc`, `openssl`, or `jsonlite` if available; falls back to pure-R implementations).

## Installation

```r
source("R/constants.R")
source("R/ltx.R")
```

## Usage

```r
source("R/constants.R")
source("R/ltx.R")

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

## File Layout

```
r/ltx/
  R/
    constants.R   LTX constants (PROTOCOL_VERSION, modes, segment types)
    ltx.R         All core functions
  test/
    test_unit.R   >= 50 check() assertions
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

MIT
