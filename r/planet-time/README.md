# interplanet.time — R Package

A pure R port of [planet-time.js](https://github.com/interplanet/planet-time.js) v1.1.0.

Provides orbital mechanics, planet time, Mars time (MTC), work-schedule calculations,
and light-speed communication timing for all planets in the solar system.

**Requirements:** R >= 4.0, no external CRAN packages.

## Installation

```r
source("R/interplanet_time.R")
```

## Usage

```r
source("R/interplanet_time.R")

# Get current time on Mars
pt <- get_planet_time(Planet["MARS"], as.numeric(Sys.time()) * 1000)
cat(sprintf("Mars time: %s
", pt$time_str))
cat(sprintf("Is work hour: %s
", pt$is_work_hour))

# Mars Coordinated Time
mtc <- get_mtc(as.numeric(Sys.time()) * 1000)
cat(sprintf("MTC: Sol %d %s
", mtc$sol, mtc$mtc_str))

# Light travel time Earth to Mars
lt <- light_travel_seconds(Planet["EARTH"], Planet["MARS"],
                            as.numeric(Sys.time()) * 1000)
cat(sprintf("Light travel Earth->Mars: %s
", format_light_time(lt)))

# Check line of sight
los <- check_line_of_sight(Planet["EARTH"], Planet["MARS"],
                             as.numeric(Sys.time()) * 1000)
cat(sprintf("Line of sight clear: %s
", los$clear))

# Find meeting windows between Earth and Mars over 30 days
now_ms <- as.numeric(Sys.time()) * 1000
windows <- find_meeting_windows(Planet["EARTH"], Planet["MARS"], now_ms, earth_days = 30)
cat(sprintf("Meeting windows found: %d
", length(windows)))

# ISO timestamp
iso <- format_planet_time_iso(Planet["MARS"], as.numeric(Sys.time()) * 1000)
cat(sprintf("Mars ISO: %s
", iso))
```

## Planet Indices

| Index | Planet  |
|-------|---------|
| 0     | Mercury |
| 1     | Venus   |
| 2     | Earth   |
| 3     | Mars    |
| 4     | Jupiter |
| 5     | Saturn  |
| 6     | Uranus  |
| 7     | Neptune |
| 8     | Moon    |

Use the `Planet` named integer vector: `Planet["MARS"]`, `Planet["EARTH"]`, etc.

## Running Tests

```sh
make test        # Unit tests (>= 100 assertions)
make fixture     # Cross-language fixture validation (requires jsonlite)
make lint        # Source check
```

## File Layout

```
r/
├── R/
│   ├── constants.R          Core constants, Planet enum, orbital elements
│   ├── orbital.R            JDE, JC, Kepler solver, helio positions, distances
│   ├── time_calc.R          get_planet_time(), get_mtc(), get_mars_time_at_offset()
│   ├── scheduling.R         find_meeting_windows()
│   ├── formatting.R         format_light_time(), format_planet_time_iso()
│   └── interplanet_time.R   Package entry point (sources all above)
├── test/
│   ├── test_unit.R          >= 100 check() assertions
│   └── test_fixtures.R      Cross-language fixture validation
├── DESCRIPTION
├── NAMESPACE
├── Makefile
└── README.md
```

## License

MIT
