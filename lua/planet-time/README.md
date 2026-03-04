# interplanet-time (Lua)

Lua implementation of the **Interplanetary Time** library.

Part of the [InterPlanet](https://interplanet.live) project — see `LANGUAGE-SUPPORT.md` for the full cross-language matrix.

## Requirements

- Lua 5.3 or newer (no external dependencies)

## Usage

```lua
local IPT = require("src.interplanet_time")

-- Planet time on Mars right now
local result = IPT.planet_time(IPT.MARS, os.time() * 1000)
print(result.time_str)        -- "HH:MM"
print(result.sol_in_year)     -- sol index within Mars year
print(result.mtc.sol)         -- absolute sol number since Mars epoch

-- Light travel time Earth → Mars
local lt = IPT.light_travel_time(IPT.EARTH, IPT.MARS, os.time() * 1000)
print(string.format("%.1f seconds", lt))

-- Heliocentric position
local x, y, z = IPT.heliocentric_pos(IPT.MARS, os.time() * 1000)
local r = math.sqrt(x*x + y*y)
print(string.format("Mars %.3f AU from Sun", r))
```

## API

### Planet indices

| Constant | Value | Body |
|---|---|---|
| `IPT.MERCURY` | 0 | Mercury |
| `IPT.VENUS` | 1 | Venus |
| `IPT.EARTH` | 2 | Earth |
| `IPT.MARS` | 3 | Mars |
| `IPT.JUPITER` | 4 | Jupiter |
| `IPT.SATURN` | 5 | Saturn |
| `IPT.URANUS` | 6 | Uranus |
| `IPT.NEPTUNE` | 7 | Neptune |
| `IPT.MOON` | 8 | Moon (uses Earth orbital elements) |

### `IPT.planet_time(body_idx, unix_ms)` → table

Returns a full time record for the given body at `unix_ms` (UTC milliseconds since Unix epoch):

| Field | Type | Description |
|---|---|---|
| `body` | number | Planet index |
| `jd` | number | Julian Day (TT) |
| `hour` | integer | 0–23 |
| `minute` | integer | 0–59 |
| `second` | integer | 0–59 |
| `local_hour` | number | fractional hour 0.0–24.0 |
| `day_fraction` | number | 0.0–1.0 |
| `day_number` | integer | total solar days since planet epoch |
| `day_in_year` | integer | day index within current planet year |
| `year_number` | integer | years since planet epoch |
| `period_in_week` | integer | 0–6 |
| `is_work_period` | boolean | |
| `is_work_hour` | boolean | |
| `time_str` | string | "HH:MM" |
| `time_str_full` | string | "HH:MM:SS" |
| `sol` | number | fractional sol number since planet epoch |
| `local_time_sec` | number | seconds since midnight |
| `day_length_sec` | number | planet solar day in seconds |
| `light_travel_from_earth_sec` | number or nil | one-way light travel from Earth (nil for Earth/Moon) |
| `sol_in_year` | integer or nil | Mars only |
| `sols_per_year` | integer or nil | Mars only |
| `mtc` | table or nil | Mars only: `{ sol, hour, minute, second }` |

### `IPT.light_travel_time(body1, body2, utc_ms)` → number

One-way light travel time in seconds between two bodies.

### `IPT.heliocentric_pos(body_idx, utc_ms)` → x, y, z

Heliocentric position in AU (ecliptic plane; z is always 0).

### `IPT.heliocentric_r(body_idx, utc_ms)` → number

Heliocentric distance in AU.

### `IPT.solar_day_seconds(body_idx)` → number

Length of the planet's solar day in seconds.

### `IPT.sol_number(body_idx, utc_ms)` → number

Fractional sol number since the planet's epoch.

### `IPT.local_solar_time(body_idx, utc_ms, longitude_deg)` → number

Local solar time in seconds since midnight at the given longitude (degrees east).

### `IPT.julian_day(year, month, day, hour, minute, second)` → number

Julian Day Number from calendar components.

### `IPT.mean_longitude(body_idx, utc_ms)` → number

Mean ecliptic longitude of the body in degrees (0–360).

### `IPT.ecliptic_longitude(body_idx, utc_ms)` → number

True ecliptic longitude of the body in degrees (0–360).

### `IPT.true_anomaly(mean_anomaly_deg, eccentricity)` → number

True anomaly in degrees (Newton-Raphson Kepler solver, 50 iterations).

## Running tests

```bash
make test
# or directly:
lua test/unit_test.lua

# Fixture validation (54 reference entries):
make fixture
```

## License

MIT — see `LICENSE` in the project root.
