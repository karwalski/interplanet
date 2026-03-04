# InterPlanet Time — OCaml Library

OCaml implementation of the Interplanetary Time library.
Story 18.18 — OCaml port of planet-time.

## Requirements

- OCaml 4.13 or later
- `ocamlfind` (`opam install ocamlfind`)
- No third-party packages — uses only OCaml stdlib

## Build

```sh
make build
```

## Test

```sh
make test
```

Runs the unit test suite and validates all 54 reference fixture entries.

## Lint

```sh
make lint
```

Type-checks the library sources without producing an executable.

## Module Layout

```
lib/
  constants.ml        — orbital constants, planet data, leap-second table
  orbital.ml          — julian_day, mean_longitude, true_anomaly,
                        ecliptic_longitude, heliocentric_pos, light_travel_time
  time_calc.ml        — solar_day_seconds, local_solar_time, sol_number,
                        planet_time, get_planet_time (full, for fixture)
  interplanet_time.ml — public API module
test/
  unit_test.ml        — 80+ assertions, fixture validation (54 entries)
```

## Public API

All functions are in the `Interplanet_time` module:

| Function | Description |
|---|---|
| `body_name body` | Display name for body index 0–8 |
| `julian_day ~year ~month ~day ~hour ~minute ~second` | Gregorian date to Julian Day |
| `mean_longitude ~body ~jd` | Mean longitude in degrees |
| `true_anomaly ~mean_anomaly ~eccentricity` | True anomaly via Newton-Raphson |
| `ecliptic_longitude ~body ~jd` | Heliocentric ecliptic longitude in degrees |
| `heliocentric_pos ~body ~jd` | Heliocentric (x, y, z) in AU |
| `light_travel_time ~body1 ~body2 ~jd` | One-way light travel time in seconds |
| `solar_day_seconds ~body` | Solar day length in seconds |
| `local_solar_time ~body ~jd ~longitude` | Local solar time (seconds since midnight) |
| `sol_number ~body ~jd` | Fractional sol/day number since planet epoch |
| `planet_time ~body ~unix_ms` | Full planet_time record |

## Bodies

| Index | Body |
|---|---|
| 0 | Mercury |
| 1 | Venus |
| 2 | Earth |
| 3 | Mars |
| 4 | Jupiter |
| 5 | Saturn |
| 6 | Uranus |
| 7 | Neptune |
| 8 | Moon |

## Version

1.0.0
