# interplanet_ltx — Elixir

Pure Elixir port of the LTX (Light-Time eXchange) SDK.
Story 49.1 — No external dependencies, compatible with Elixir 1.14+.

## Usage

```elixir
Code.require_file("lib/interplanet_ltx/constants.ex")
Code.require_file("lib/interplanet_ltx/models.ex")
Code.require_file("lib/interplanet_ltx/interplanet_ltx.ex")

plan = InterplanetLtx.create_plan(title: "Q3 Review", start: "2026-03-15T14:00:00Z", delay: 860)
hash = InterplanetLtx.encode_hash(plan)
segs = InterplanetLtx.compute_segments(plan)
ics  = InterplanetLtx.generate_ics(plan)
```

## Running tests

```bash
make test
```

## API

- `create_plan/1` — Create a new LTX plan (keyword opts)
- `upgrade_config/1` — Upgrade v1 config to v2 LtxPlan
- `compute_segments/1` — Compute timed segments for a plan
- `total_min/1` — Total session duration in minutes
- `make_plan_id/1` — Deterministic plan ID string
- `encode_hash/1` — Encode plan to `#l=...` URL fragment
- `decode_hash/1` — Decode plan from URL fragment
- `build_node_urls/2` — Build per-node perspective URLs
- `generate_ics/1` — Generate iCalendar (.ics) content
- `format_hms/1` — Format seconds as MM:SS or HH:MM:SS
- `format_utc/1` — Format epoch ms as HH:MM:SS UTC
