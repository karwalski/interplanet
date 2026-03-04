# interplanet-time — Zig library

Story 18.17 — Zig port of the InterplanetTime planet-time library.

Direct port of `libinterplanet.c` / `planet-time.js` v1.0.0.

## Structure

```
zig/planet-time/
  src/interplanet_time.zig    ← core library (no allocation)
  test/unit_test.zig          ← unit + fixture tests (≥100 assertions)
  test/fixture_runner.zig     ← standalone fixture runner (reads reference.json)
  build.zig                   ← zig build system
  Makefile                    ← targets: build test lint clean fixture
```

## Requirements

Zig 0.13.0 or later (tested with 0.15.x).

## Build

```sh
zig build
```

## Test

```sh
make test
# or
zig build test
```

## Fixture runner

```sh
make fixture
# or
zig run test/fixture_runner.zig -- \
  --fixture ../../c/planet-time/fixtures/reference.json
```

## API

```zig
const ipt = @import("src/interplanet_time.zig");

// Body constants
ipt.BODY_EARTH    // 2
ipt.BODY_MARS     // 3
ipt.bodyName(3)   // "Mars"

// Orbital elements
ipt.ORBELEMS[3].a      // Mars semi-major axis (AU)
ipt.solarDaySeconds(3) // Mars solar day in seconds

// Julian Day
const jd = ipt.julianDayFromMs(utc_ms);

// Heliocentric position
const pos = ipt.heliocentricPositionMs(3, utc_ms); // ?HelioPos

// Light travel time
const lt = ipt.lightTravelSeconds(2, 3, utc_ms); // ?f64 seconds

// Planet time
const pt = ipt.getPlanetTime(3, utc_ms, 0.0); // ?PlanetTimeResult

// MTC (Mars Coordinated Time)
const mtc = ipt.getMtc(utc_ms); // MtcResult

// High-level API
const result = ipt.planetTime(3, utc_ms); // PlanetTime
```

## Body indices

| Index | Body    |
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
