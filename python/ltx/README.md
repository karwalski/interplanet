# interplanet-ltx (Python)

Python SDK for the **LTX (Light-Time eXchange)** protocol — a deterministic structured meeting format designed for interplanetary sessions where signal propagation delay prevents real-time interaction.

Mirrors the [JavaScript LTX SDK](../../javascript/ltx/README.md) API. Optionally integrates with `interplanet-time` for automatic delay lookup by planet name.

## Installation

`interplanet-ltx` and `interplanet-time` are **not yet published** to PyPI, so
`pip install interplanet-ltx` and `pip install "interplanet-ltx[time]"` do not work
yet. Install from source instead (tested 29 Sep 2026 with Python 3.11):

```bash
pip install "git+https://github.com/karwalski/interplanet.git#subdirectory=python/ltx"

# With interplanet-time integration for automatic delay lookup, install
# interplanet-time from source as well:
pip install "git+https://github.com/karwalski/interplanet.git#subdirectory=python/planet-time"
```

Or from a clone of the repository: `pip install ./python/planet-time ./python/ltx`.

## Quick start

```python
from interplanet_ltx import create_plan, compute_segments, generate_ics

# Create a plan
plan = create_plan(
    host_name='Earth HQ',
    remote_name='Mars Hab-01',
    delay=800,                # one-way signal delay in seconds
    title='Weekly sync',
    start_iso='2026-03-15T14:00:00Z',
    quantum=5,                # scheduling quantum in minutes
    mode='LTX-ASYNC',
)

# Compute segment timeline
segs = compute_segments(plan)
for s in segs:
    print(s.type, s.start_ms, s.dur_min, 'min')

# Export to .ics
ics_text = generate_ics(plan)
with open('meeting.ics', 'w') as f:
    f.write(ics_text)
```

### Automatic delay from planet names

```python
from interplanet_ltx import delay_from_planets

# Requires interplanet-time (not yet on PyPI; install from source as above)
delay_sec = delay_from_planets('earth', 'mars')  # current one-way light delay
plan = create_plan(host_name='Earth HQ', remote_name='Mars Hab-01', delay=delay_sec)
```

### Encode / decode URL hash

```python
from interplanet_ltx import encode_hash, decode_hash

hash_str = encode_hash(plan)          # URL-safe base64
url = f'https://interplanet.live/ltx.html#{hash_str}'

restored = decode_hash(hash_str)      # back to LtxPlan
```

### Build per-node share URLs

```python
from interplanet_ltx import build_node_urls

urls = build_node_urls(plan, 'https://interplanet.live/ltx.html')
for node_url in urls:
    print(node_url.name, node_url.url)
# Earth HQ   https://interplanet.live/ltx.html?node=N0#...
# Mars Hab-01  https://interplanet.live/ltx.html?node=N1#...
```

## REST client

```python
import asyncio
from interplanet_ltx import store_session, get_session

async def main():
    # Store a session (returns plan ID)
    result = await store_session(plan, 'https://api.interplanet.live')
    plan_id = result['planId']

    # Retrieve a session
    loaded = await get_session(plan_id, 'https://api.interplanet.live')

asyncio.run(main())
```

## API reference

| Function | Description |
|----------|-------------|
| `create_plan(**opts)` | Build a validated LTX plan (`LtxPlan`) |
| `compute_segments(plan)` | Compute segment timeline (`List[LtxSegment]`) |
| `encode_hash(plan)` | Encode plan to URL-safe base64 hash |
| `decode_hash(hash)` | Restore `LtxPlan` from hash |
| `build_node_urls(plan, base_url)` | Generate per-node perspective URLs |
| `total_min(plan)` | Total session duration in minutes |
| `make_plan_id(plan)` | Deterministic plan ID (v2 frozen imul31 hash, v3 SHA-256); reproduces `spec/golden/plan-ids.json` |
| `validate_plan(plan)` | `{'valid', 'errors': [{code, path, message}]}` against `spec/ltx-schema.json`; codes include `reserved_streams` and `reserved_branching` |
| `upgrade_plan_to_v3(plan, **extras)` | Explicit v3 upgrade; raises `ReservedFieldError` for non-empty `streams` or branching fields (also enforced by `create_amendment` and `create_session`) |
| `SequenceTracker(plan_id, storage=None, reorder_window=64)` | Replay protection with a reorder window: late-but-new seqs are accepted with `late: True`, duplicates are `replay`, non-integers are `invalid_seq`; `missing_seqs(node_id)` lists gaps |
| `reduce_questions / reduce_actions / reduce_decisions(entries)` | Register reducers (§9, §10); `run_merge_segment` snapshots all three |
| `delay_from_planets(a, b)` | Current one-way light delay between two bodies (requires `[time]`) |
| `generate_ics(plan)` | iCalendar string for calendar import |
| `store_session(plan, api_base)` | POST plan to REST API (async) |
| `get_session(plan_id, api_base)` | GET plan from REST API (async) |
| `download_ics(plan_id, api_base)` | Download .ics from REST API (async) |
| `format_hms(sec)` | Format seconds as H:MM:SS string |
| `format_utc(dt)` | Format datetime as UTC string |

### Data models

```python
from interplanet_ltx import LtxPlan, LtxNode, LtxSegment, LtxSegmentSpec, LtxNodeUrl

# LtxNode: id, name, role ('HOST'|'PARTICIPANT'), delay, location
# LtxSegmentSpec: type, q (quanta count)
# LtxSegment: type, start_ms, end_ms, dur_min
# LtxNodeUrl: name, url, node_id
```

## Requirements

- Python 3.10+
- No required dependencies (stdlib only)
- Optional: `interplanet-time>=0.1.0` for planet-based delay lookup

## License

GPL-3.0 — [interplanet.live](https://interplanet.live)
