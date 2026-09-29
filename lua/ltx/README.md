# interplanet-ltx (Lua)

Lua implementation of the **LTX (Light-Time eXchange)** protocol SDK.

Part of the [InterPlanet](https://interplanet.live) project — see `LANGUAGE-SUPPORT.md` for the full cross-language matrix.

## Requirements

- Lua 5.3 or newer (no external dependencies)

## Usage

```lua
local LTX = require("src.interplanet_ltx")

-- Create a plan
local plan = LTX.create_plan({
  title       = "Mars Mission Debrief",
  host_name   = "Earth HQ",
  remote_name = "Olympus Base",
  delay       = 840,   -- one-way signal delay in seconds
})

-- Compute timed segment schedule
local segs = LTX.compute_segments(plan)
for _, seg in ipairs(segs) do
  print(seg.type, seg.start_iso, seg.dur_min .. " min")
end

-- Generate plan ID
print(LTX.make_plan_id(plan))
-- → "LTX-20260315-EARTHHQ-OLYM-v2-a1b2c3d4"

-- Encode/decode URL hash
local hash    = LTX.encode_hash(plan)   -- "#l=eyJ2Ijoy..."
local decoded = LTX.decode_hash(hash)   -- recovers original plan table

-- Build per-node join URLs
local urls = LTX.build_node_urls(plan, "https://interplanet.live/ltx.html")
for _, u in ipairs(urls) do
  print(u.role, u.url)
end

-- Generate ICS calendar file
local ics = LTX.generate_ics(plan)
```

## API

### `LTX.create_plan(opts)` → table

Creates a new v2 LTX plan config. Options:

| Field | Type | Default |
|---|---|---|
| `title` | string | `"LTX Session"` |
| `start` | string (ISO 8601) | 5 min from now |
| `quantum` | number | `5` |
| `mode` | string | `"LTX"` |
| `host_name` | string | `"Earth HQ"` |
| `host_location` | string | `"earth"` |
| `remote_name` | string | `"Mars Hab-01"` |
| `remote_location` | string | `"mars"` |
| `delay` | number (seconds) | `0` |
| `nodes` | table | auto-generated 2-node |
| `segments` | table | default 7-segment template |

### `LTX.upgrade_config(cfg)` → table

Upgrades a v1 config to v2 schema. v2 configs are returned unchanged.

### `LTX.compute_segments(cfg)` → table

Returns array of timed segments: `{ type, q, start_iso, end_iso, dur_min }`.

### `LTX.total_min(cfg)` → number

Total session duration in minutes.

### `LTX.make_plan_id(cfg)` → string

Deterministic plan ID: `LTX-{YYYYMMDD}-{HOST}-{DEST}-v2-{HASH8}` (v3 plans: `-v3-`).
A plan decoded with `require("src.json").decode_ordered(text)` keeps its key
order and is hashed exactly as `JSON.stringify` emits it; `LTX.plan_id_from_json(text)`
does both steps. The v2 hash runs over UTF-16 code units, as in ltx-sdk.js.

### `LTX.validate_plan(plan)` → table

`{ valid = bool, errors = { { code, path, message }, ... } }` with the error
codes of `validatePlan` in `javascript/ltx/ltx-sdk.js`, including
`reserved_streams` (non-empty `streams`, segment `stream`) and
`reserved_branching` (`branches`, `branching`, segment `branch`).
`V11.upgrade_plan_to_v3(cfg, extras)` and `V11.create_session(plan, id, opts)`
raise `{ code = ..., errors = ..., message = ... }` on reserved fields (use `pcall`).

### `V11.reduce_decisions(entries)` → table

Decision register (`decision` / `decision_update` entries), with the same
conflict rules as `reduce_questions` / `reduce_actions`.

### `LTX.encode_hash(cfg)` → string

Base64url-encodes the config as `#l=<token>` for URL sharing.

### `LTX.decode_hash(hash)` → table|nil

Decodes a `#l=…` hash fragment back to a config table.

### `LTX.build_node_urls(cfg, base_url)` → table

Builds per-node perspective URLs for sharing.

### `LTX.build_delay_matrix(plan)` → table

Flat delay matrix for all ordered node pairs; every entry is
`V11.pair_delay(plan, from, to)`: a v3 `delays` entry wins, HOST pairs use the
node's delay, and non-HOST pairs the sum (not the max) of both HOST-relative delays.

### `LTX.generate_ics(cfg)` → string

RFC 5545 iCalendar output with LTX extension properties.

### `LTX.format_hms(seconds)` → string

Formats a duration as `HH:MM:SS` or `MM:SS`.

## Running tests

```bash
make test
# or directly:
cd test && lua unit_test.lua
```

## Segment types

| Type | Description |
|---|---|
| `PLAN_CONFIRM` | Opening sync — all nodes confirm readiness |
| `TX` | Host transmits to all participants |
| `RX` | Host receives replies from participants |
| `CAUCUS` | Private internal deliberation (no cross-party transmission) |
| `BUFFER` | Timing buffer to absorb jitter |
| `MERGE` | Joint collaborative activity (low-delay sessions) |

## License

GPL-3.0 — see `LICENSE` in the project root.
