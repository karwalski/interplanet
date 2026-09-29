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
make test   # runs the four check scripts in test/*.exs directly
mix test    # runs the same scripts through ExUnit (test/exunit/)
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

`create_plan/1` defaults to a 5-minute quantum (`Constants.default_quantum/0`) and mode `LTX`.

### Parity with the JS reference SDK (issue #27)

- `InterplanetLtx.Validate.validate_plan/1` returns `%{valid:, errors: [%{code:, path:, message:}]}`
  with the error codes of `validatePlan` in `javascript/ltx/ltx-sdk.js`, including
  `reserved_streams` (non-empty `streams`, segment `stream`) and `reserved_branching`
  (`branches`, `branching`, segment `branch`).
- `Segments.upgrade_plan_to_v3/2`, `Amend.create_amendment/4` and `Session.create_session/3`
  raise `InterplanetLtx.ReservedFieldError` (`code` is the first error code) on reserved fields.
- `Segments.make_plan_id/1` also accepts an insertion-ordered plan from
  `InterplanetLtx.Json.decode_ordered!/1`, and `Segments.plan_id_from_json/1` takes JSON text,
  so the frozen v2 hash covers the plan in its original key order.
  `test/parity_test.exs` checks every vector in `spec/golden/plan-ids.json`.
- `Registers.reduce_decisions/1` over `decision` / `decision_update` entries (DEC- prefix).
  This port has no merge segment, so there is no merge snapshot to carry a decision register.
- `Security.new_sequence_tracker/2` takes `reorder_window:` (default 64) and `storage:`
  (an Agent pid). `record_seq/3` accepts a late seq inside the window with `late: true` and
  rejects exact duplicates and seqs below the window as `"replay"`. Also `missing_seqs/2`,
  `last_seen_seq/2`, `current_seq/2`.

Note: `create_plan/1` structs serialise nodes before segments, whereas JS `createPlan`
emits segments before nodes, so identical inputs give different v2 planIds (compare the
`v2-createPlan-default` and `v2-key-order-sensitive` vectors).
