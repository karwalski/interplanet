# InterplanetTime.jl

Julia port of the [planet-time.js](../../javascript/planet-time/planet-time.js) library — Interplanetary Time Library v1.1.0.

Provides time, calendar, work-schedule, orbital mechanics, and light-speed calculations for every planet in the Solar System. Fully cross-validated against the 54-entry `reference.json` fixture shared by all language ports.

## Requirements

- Julia 1.9 or later
- JSON3 package (auto-installed via `Pkg.instantiate`)

## Quick start

```julia
using InterplanetTime

# Current time on Mars
pt = get_planet_time(MARS, round(Int64, time() * 1000))
println("Mars time: $(pt.time_str)  Sol $(pt.sol_in_year)/$(pt.sols_per_year)")

# Light travel time Earth → Mars right now
lt = light_travel_seconds(EARTH, MARS, round(Int64, time() * 1000))
println("Light travel: $(format_light_time(lt))")

# Mars Coordinated Time
mtc = get_mtc(round(Int64, time() * 1000))
println("MTC: $(mtc.mtc_str)  Sol $(mtc.sol)")
```

## API

### Planet enum

```julia
@enum Planet MERCURY VENUS EARTH MARS JUPITER SATURN URANUS NEPTUNE MOON

planet_from_string("mars")  # → MARS (case-insensitive)
```

### Constants

| Name | Value | Description |
|------|-------|-------------|
| `J2000_MS` | 946728000000 | J2000.0 epoch (UTC ms) |
| `MARS_EPOCH_MS` | -524069761536 | Mars MY0 epoch |
| `MARS_SOL_MS` | 88775244 | Mars solar day (ms) |
| `AU_SECONDS` | ≈499.004 | Light-seconds per AU |

### Functions

| Function | Description |
|----------|-------------|
| `get_planet_time(planet, utc_ms[, tz_offset_h])` | Local time on a planet |
| `get_mtc(utc_ms)` | Mars Coordinated Time |
| `light_travel_seconds(from, to, utc_ms)` | One-way light travel time |
| `body_distance_au(a, b, utc_ms)` | Distance between bodies (AU) |
| `helio_pos(planet, utc_ms)` | Heliocentric position (x, y, r, lon) |
| `format_light_time(seconds)` | Human-readable light travel time |
| `find_meeting_windows(a, b, from_ms[; earth_days, step_min])` | Overlapping work windows |

## Running tests

```bash
# Install dependencies (first time only)
make instantiate

# Run unit tests (100+ assertions)
make test

# Validate against cross-language fixtures
make fixtures
```

## Cross-language fixtures

The `fixture_runner.jl` script validates this library against `../../c/fixtures/reference.json` — a shared set of 54 entries (6 timestamps × 9 planets) used by all language ports (Go, Python, C, Rust, TypeScript, etc.).

## Orbital mechanics

Uses Keplerian elements from Meeus "Astronomical Algorithms" Table 31.a, with Newton-Raphson Kepler equation solver (tolerance 1e-12). Terrestrial Time (TT) conversion uses the 28-entry IERS leap second table.

## Work schedules

Each planet has a 5-on/2-off work cycle based on its solar day:

- **Mercury/Venus**: 8 local-hour shifts (solar day ≈ 176/117 Earth days)
- **Earth/Mars/Moon**: Standard 9–17 schedule, 5-day week
- **Jupiter/Saturn**: 2.5/2.25 day work periods (≈24 Earth hours each)
- **Uranus/Neptune**: 8 local-hour shifts, 5-day week
