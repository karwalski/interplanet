# interplanet-ltx (Python)

Python SDK for the **LTX (Light-Time eXchange)** protocol — a deterministic structured meeting format designed for interplanetary sessions where signal propagation delay prevents real-time interaction.

Mirrors the [JavaScript LTX SDK](../../javascript/ltx/README.md) API. Optionally integrates with `interplanet-time` for automatic delay lookup by planet name.

## Installation

```bash
pip install interplanet-ltx

# With interplanet-time integration for automatic delay lookup:
pip install "interplanet-ltx[time]"
```

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

# Requires: pip install "interplanet-ltx[time]"
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
| `make_plan_id(plan)` | Deterministic 8-char plan ID |
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

MIT — [interplanet.live](https://interplanet.live)
