# interplanet-time (Python)

Pure-Python port of [planet-time.js](../javascript/planet-time/planet-time.js) v0.1.0.
Provides time, calendar, work-schedule, orbital mechanics, and light-speed
calculations for every planet in the solar system.

**Python ≥ 3.10 · stdlib only · no third-party dependencies**

## Install

```bash
pip install interplanet-time
```

Or from source:

```bash
cd python/
pip install -e .
```

## Quick start

```python
import interplanet_time as ipt

# Current time on Mars
pt = ipt.get_planet_time(ipt.Planet.MARS, utc_ms=1061991060000)
print(pt.time_str)       # "21:03"
print(pt.is_work_hour)   # False
print(pt.sol_in_year)    # 481

# Mars Coordinated Time
mtc = ipt.get_mtc(1061991060000)
print(mtc.mtc_str)       # "21:03"

# Light travel time Earth → Mars
lt = ipt.light_travel_seconds(ipt.Planet.EARTH, ipt.Planet.MARS, 1061991060000)
print(ipt.format_light_time(lt))   # "3.1min"

# Meeting windows (Earth vs Jupiter, next 30 days)
windows = ipt.find_meeting_windows(
    ipt.Planet.EARTH, ipt.Planet.JUPITER,
    from_ms=1735689600000,
    earth_days=30,
)
print(f"{len(windows)} overlap windows found")
```

## Planet enum

| Name    | Value | Solar day    | Work week  |
|---------|-------|--------------|------------|
| MERCURY | 0     | 175.9 days   | 5 shifts/7 |
| VENUS   | 1     | 116.8 days   | 5 shifts/7 |
| EARTH   | 2     | 24h 00m      | 5/7        |
| MARS    | 3     | 24h 39m 35s  | 5 sols/7   |
| JUPITER | 4     | 9h 55m       | 5 periods/7|
| SATURN  | 5     | 10h 34m      | 5 periods/7|
| URANUS  | 6     | 17h 15m      | 5/7        |
| NEPTUNE | 7     | 16h 07m      | 5/7        |
| MOON    | 8     | 24h (Earth)  | 5/7        |

## API reference

### `get_planet_time(planet, utc_ms, tz_offset_h=0) → PlanetTime`

Returns current time on a planet. `utc_ms` is milliseconds since the Unix epoch.
`tz_offset_h` is a local-hour offset from the planet's prime meridian.

### `get_mtc(utc_ms) → MTC`

Mars Coordinated Time (MTC) — equivalent of UTC for Mars.

### `light_travel_seconds(a, b, utc_ms) → float`

One-way light travel time between two planets in seconds.

### `check_line_of_sight(a, b, utc_ms) → LineOfSight`

Whether the Sun blocks the line of sight between two planets.

### `find_meeting_windows(a, b, from_ms, earth_days=30, step_min=15) → list[MeetingWindow]`

Overlapping work-hour windows between two planets.

### `format_light_time(seconds) → str`

Human-readable light travel time: `"3.1min"`, `"1h 22m"`, etc.

### `PlanetTimezone(planet, offset_h)` / `PlanetDateTime.from_utc_ms(utc_ms, planet, offset_h)`

`datetime.tzinfo` / `datetime.datetime` subclasses with `.planet_time` property.

## Development

```bash
make install    # pip install -e ".[dev]"
make test       # python -m pytest tests/ -v
make lint       # syntax check
make build-dist # python -m build
```
