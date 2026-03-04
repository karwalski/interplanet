# interplanet-time — Scala 3

Pure Scala 3 port of the [planet-time.js](../../javascript/planet-time/planet-time.js) library (v1.1.0).

Provides time, calendar, work-schedule, orbital mechanics, and light-speed calculations for every planet in our solar system.

## Structure

```
src/main/scala/interplanet/time/
├── Constants.scala   — Planet enum, J2000_MS, MARS_EPOCH_MS, LEAP_SECS, ORB_ELEMS
├── Orbital.scala     — helio pos, body distance, light travel, line of sight
├── TimeCalc.scala    — getPlanetTime, getMtc, getMarsTimeAtOffset
├── Models.scala      — case classes
├── Scheduling.scala  — findMeetingWindows
└── Formatting.scala  — formatLightTime
fixture-runner/
└── FixtureRunner.scala — @main, reads reference.json, validates 54 cross-language entries
```

## Requirements

- JDK 11+
- sbt 1.9.3+

## Usage

```scala
import interplanet.time.*

// Get current time on Mars
val pt = getPlanetTime(Planet.Mars, System.currentTimeMillis())
println(s"Mars time: ${pt.timeStr}")  // e.g. "14:23"

// Light travel time from Earth to Jupiter
val seconds = lightTravelSeconds(Planet.Earth, Planet.Jupiter, System.currentTimeMillis())
println(formatLightTime(seconds))     // e.g. "43.2min"

// Mars Coordinated Time
val mtc = getMtc(System.currentTimeMillis())
println(s"MTC Sol ${mtc.sol} — ${mtc.mtcStr}")
```

## Build

```sh
make build    # sbt compile
make test     # sbt test (100+ assertions)
make fixtures # validate 54 cross-language fixture entries
```

## Fixture validation

```sh
sbt "run ../../c/fixtures/reference.json"
# Fixture entries checked: 54
# N passed  0 failed
```

## Algorithm notes

- Orbital mechanics: Meeus *Astronomical Algorithms* 2nd ed., Table 31.a
- Kepler equation: Newton-Raphson, tolerance 1e-12
- TT = UTC + (TAI−UTC) + 32.184 s
- Mars epoch: MY0 = 1953-05-24T09:03:58.464Z (Clancy et al. / interplanet.live)
- Moon uses Earth's orbital elements for heliocentric position
