# Interplanetary Timezone Conventions for Human Work Scheduling

```
Community Specification — submitted for review via GitHub. Not an IETF submission.
M. Watt
InterPlanet
Status: Draft for community review
February 2026
```

## Status of This Memo

This document is a community specification published for open review via GitHub. It is not an IETF Internet-Draft and has not been submitted to the IETF. It does not carry IETF consensus and is not on any IETF standards track.

This document may be updated, revised, or superseded at any time. It is appropriate to cite this document as a working draft of the interplanet.live project.

## Abstract

This document defines a system of timezone conventions for solar system bodies intended for human work scheduling, meeting coordination, and communications planning in interplanetary environments. It specifies timezone zone identifiers, timestamp formats, and scheduling parameters for Mars, the Moon, Mercury, Venus, Jupiter, Saturn, Uranus, and Neptune. The system separates geographic location reference (timezone zones) from work scheduling (shift patterns), reflecting the fundamental incompatibility between most planetary solar days and human circadian biology.

This document records a deployed convention. It does not define a protocol.

## Table of Contents

1. Introduction
2. Terminology
3. Time Scales
4. Coordinate Conventions
5. Planetary Timestamp Format
6. Planetary Timezone Identifier Format
7. Zone Definitions
8. Work Scheduling Model
9. Communications Latency
10. Constants Table
11. Disputed and Uncertain Values
12. IANA Considerations
13. Security Considerations
14. References
15. Acknowledgements

---

## 1. Introduction

### 1.1. Motivation

As human activity expands beyond Earth through programmes such as NASA Artemis, ESA ExoMars, and commercial ventures, the need for standardised interplanetary timekeeping becomes practical. Robotic missions already operate on Mars, the Moon, and throughout the outer solar system. Crewed missions to the Moon are underway, and crewed Mars missions are in planning. Permanent installations will require coordination of work schedules, communications windows, and meeting times across bodies with radically different day lengths.

The terrestrial timezone system, established following the 1884 International Meridian Conference, divides the Earth into 24 zones of 15 degrees longitude each, corresponding to one hour of solar time. This document extends that geometric principle to other solar system bodies while explicitly separating geographic location reference from work scheduling — a separation that is unnecessary on Earth (where all timezones share a ~24-hour day) but essential on bodies where the solar day spans days, weeks, or months.

### 1.2. Scope

This document defines:

- Timezone zone identifiers for all eight planets and the Moon (Section 6, Section 7)
- A timestamp string format for planetary local time (Section 5)
- Work scheduling models appropriate to each body's day length (Section 8)
- Light-time latency calculation conventions for scheduling (Section 9)
- A constants table with sources, revision dates, and uncertainty (Section 10)

This document does not define:

- A replacement for UTC or any existing terrestrial time standard
- A replacement for or competitor to Coordinated Lunar Time (LTC/TCL)
- A wire protocol, serialisation format, or transport mechanism
- Precision ephemeris calculations (for which NAIF SPICE or JPL Horizons SHOULD be used)

### 1.3. Relationship to Existing Standards

This document builds on and references:

| Standard | Relationship |
|---|---|
| RFC 3339 [RFC3339] | Internet timestamp format. Planetary timestamps defined here extend RFC 3339 structurally but use non-Gregorian date components for non-Earth bodies. |
| RFC 9557 [RFC9557] | Extended timestamps with suffix annotations. This document proposes a suffix key for planetary body identification (Section 12). |
| RFC 6557 [RFC6557] | IANA Time Zone Database procedures. This document does not propose additions to the tz database but defines a parallel namespace. |
| RFC 9171 [RFC9171] | Bundle Protocol Version 7 (Delay-Tolerant Networking). Relevant to interplanetary communications scheduling (Section 9). |
| CCSDS 301.0-B-4 | Time Code Formats for space data systems. This document's internal epoch differs from CCSDS epochs; conversion is noted in Section 3.3. |
| IAU WGCCRE 2015 [Archinal2018] | Prime meridian and rotation model definitions for all bodies. |
| Allison & McEwen 2000 [Allison2000] | Mars Coordinated Time formula and sol definition. |
| IAU XXXII GA 2024 | Lunar Coordinate Time (TCL) resolutions. |

## 2. Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 [RFC2119] [RFC8174] when, and only when, they appear in all capitals, as shown here.

Additional definitions:

- **Sol:** A mean solar day on Mars, equal to 88,775.244 SI seconds [Allison2000].
- **Mean solar day:** The average interval between successive local noons on a body (synodic day with respect to the Sun).
- **Sidereal rotation period:** The time for one rotation relative to the fixed stars.
- **Planetary timezone zone:** A 15-degree-wide longitude band on a solar system body, analogous to a terrestrial UTC offset zone. A timezone zone is a geographic location identifier, not necessarily a scheduling reference.
- **Work period:** A contiguous interval during which a human crew member is scheduled to work. On Mars, a work period is measured in sol-hours. On bodies with incompatible solar days (Moon, Mercury, Venus), work periods are measured in Earth hours.
- **Light-time:** The one-way signal propagation delay between two bodies, equal to the distance divided by the speed of light in vacuum (c = 299,792.458 km/s, exact by SI definition).

## 3. Time Scales

### 3.1. UTC as Civil Reference

All civil time inputs and outputs in this system MUST be expressed in UTC [RFC3339]. UTC is the time scale used by terrestrial computing systems, network protocols, and human scheduling.

### 3.2. TT for Ephemeris Calculations

Where planetary time algorithms require a dynamical time argument (e.g. the Allison & McEwen Mars formula), implementations MUST use Terrestrial Time (TT).

TT is defined as:

```
TT = TAI + 32.184 s    (exact, by definition)
```

Therefore:

```
TT - UTC = (TAI - UTC) + 32.184 s
```

The value (TAI - UTC) is an integer number of seconds, determined by the cumulative count of leap seconds applied since 1972-01-01. As of 2017-01-01, TAI - UTC = 37 s, giving TT - UTC = 69.184 s. Implementations MUST maintain a leap-second table sourced from IERS Bulletin C [IERS-C].

### 3.3. Epoch Compatibility

Different systems use different time epochs. Implementations that exchange timestamps with external systems SHOULD document epoch conversions:

| System | Epoch | Notes |
|---|---|---|
| Unix / JavaScript | 1970-01-01T00:00:00Z | Used by this specification's reference implementation |
| CCSDS CUC [CCSDS301] | 1958-01-01 (TAI) | Standard for spacecraft telemetry |
| DTN Bundle Protocol [RFC9171] | 2000-01-01T00:00:00Z | DTN Time |
| Julian Date | 4713 BC Jan 1 12:00 UT | Continuous day count |
| Mars Sol Date [Allison2000] | 1873-12-29T12:00:00 (approx) | Continuous sol count |

### 3.4. Leap Second Governance

CGPM Resolution 4 (November 2022) and ITU WRC-23 (December 2023) direct a planned change to the UT1-UTC tolerance by or before 2035, with a new maximum tolerance of not less than 100 seconds. Implementation details remain pending standardisation. No formal abolition of leap seconds has been adopted.

Implementations SHOULD treat the leap-second table as potentially finalised after 2035. Implementations MUST NOT assume no further leap seconds will occur before a formal ITU decision is published.

### 3.5. Julian Date Time Scale Tagging

When Julian Dates are used, the time scale MUST be specified:

- **JD_UTC:** Julian Date computed from UTC (discontinuous at leap seconds)
- **JD_TT:** Julian Date computed from TT (continuous)
- **JD_TDB:** Julian Date computed from Barycentric Dynamical Time (for solar system ephemerides)

The Mars time formula [Allison2000] uses JD_TT. Implementations MUST NOT pass JD_UTC to functions expecting JD_TT without applying the leap-second correction.

## 4. Coordinate Conventions

### 4.1. Longitude Convention

All zone definitions in this document use **IAU east-positive planetocentric** coordinates: longitudes run 0-360 degrees East, measured in the direction defined by the right-hand rule relative to the body's IAU-defined north pole.

For **Venus and Uranus**, which rotate retrograde, the IAU nonetheless defines east-positive coordinates using the same right-hand rule. On Venus, the Sun moves westward across the sky, but IAU longitude numbers increase eastward.

### 4.2. Conversion from Planetographic Coordinates

Some historical sources, USGS gazetteers, and mission documents use **planetographic** coordinates, in which positive longitude is defined opposite to rotation direction.

For prograde bodies (Mars, Moon, Mercury, gas giants):

```
longitude_IAU_east = 360 - longitude_planetographic_west
```

For retrograde bodies (Venus, Uranus):

```
longitude_IAU_east = longitude_planetographic_east
```

Implementations that ingest coordinate data from external sources MUST verify the longitude convention before assigning timezone zones.

### 4.3. Prime Meridian Authorities

Prime meridians for all bodies follow IAU WGCCRE definitions [Archinal2018]:

| Body | Prime Meridian Feature | Authority |
|---|---|---|
| Earth | Greenwich transit instrument | International Meridian Conference (1884) |
| Mars | Viking Lander 1 at 47.95137 deg W | IAU WGCCRE 2015 (published 2018) |
| Moon | Mean Earth direction (Sinus Medii) | IAU WGCCRE / JPL DE421 ME frame |
| Mercury | Hun Kal crater | IAU WGCCRE 2009 |
| Venus | Ariadne crater | IAU WGCCRE |
| Jupiter | System III magnetic field | IAU convention |
| Saturn | System III (conventional; see Section 11) | IAU convention |
| Uranus | Voyager 2 magnetic field | IAU WGCCRE |
| Neptune | Voyager 2 magnetic field | IAU WGCCRE |

## 5. Planetary Timestamp Format

### 5.1. Design Principles

Planetary timestamps MUST be unambiguous, machine-parseable, and distinguishable from terrestrial RFC 3339 timestamps. They SHOULD follow the structural conventions of RFC 9557 [RFC9557] suffix annotations where possible.

### 5.2. ABNF Grammar

The following ABNF [RFC5234] defines the planetary timestamp format:

```abnf
planet-timestamp = planet-date "T" time-of-day [utc-ref] [tz-suffix]

; === Date component (body-specific) ===
planet-date      = mars-date / earth-date / generic-date

mars-date        = "MY" mars-year "-" sol-of-year
mars-year        = 1*4DIGIT               ; Mars Year number (MY0, MY1, ...)
sol-of-year      = 1*3DIGIT               ; Sol within Mars year (1-669)

earth-date       = date-fullyear "-" date-month "-" date-mday
                                           ; RFC 3339 date (Gregorian)

generic-date     = body-prefix year-count "-" day-count
body-prefix      = 1*4ALPHA               ; e.g. "LN" (Moon), "ME" (Mercury)
year-count       = 1*6DIGIT               ; Body-specific year count
day-count        = 1*6DIGIT               ; Day/sol within year

; === Time component ===
time-of-day      = 2DIGIT ":" 2DIGIT [":" 2DIGIT ["." 1*3DIGIT]]
                                           ; HH:MM[:SS[.fff]]

; === UTC reference (OPTIONAL) ===
utc-ref          = "/" rfc3339-timestamp   ; Corresponding UTC instant
rfc3339-timestamp = <as defined in RFC 3339, Section 5.6>

; === Timezone suffix (RECOMMENDED) ===
tz-suffix        = "[" body-tz-id "]"
body-tz-id       = body-name "/" tz-offset
body-name        = "Mars" / "Moon" / "Mercury" / "Venus" /
                   "Jupiter" / "Saturn" / "Uranus" / "Neptune"
tz-offset        = tz-prefix offset-sign offset-value
tz-prefix        = "AMT" / "LMT" / "MMT" / "VMT" /
                   "JMT" / "SMT" / "UMT" / "NMT"
offset-sign      = "+" / "-" / ""          ; "" for zero offset
offset-value     = 1*2DIGIT               ; 0-12
```

### 5.3. Examples

```
; Mars local time at Hellas Planitia (AMT+4), MY38 Sol 221
MY38-221T14:32:07/2026-02-19T09:15:23Z[Mars/AMT+4]

; Moon local time at Tranquillitatis (LMT+1)
2026-02-19T14:32:07Z[Moon/LMT+1]

; Mercury local time at Caloris Basin (MMT+11)
2026-02-19T14:32:07Z[Mercury/MMT+11]

; Earth (standard RFC 3339 / RFC 9557, included for completeness)
2026-02-19T14:32:07+11:00[Australia/Sydney]
```

The `/` separator between planet-date and rfc3339-timestamp allows any receiver to extract the UTC instant even if it cannot parse the planetary date component. This is the minimum interoperability guarantee.

### 5.4. Conformance Requirements

Generators of planetary timestamps:
- MUST include the body-tz-id suffix when the timestamp is intended for interchange
- SHOULD include the UTC reference (`/` rfc3339-timestamp) when the receiving system may not implement planetary time conversion
- MUST use IAU east-positive planetocentric longitude conventions for all zone offset calculations

Consumers of planetary timestamps:
- MUST accept timestamps with or without the UTC reference
- MUST reject timestamps where the body-name is unrecognised, unless configured to accept experimental bodies
- SHOULD validate that the tz-offset is within the range -12 to +12

## 6. Planetary Timezone Identifier Format

### 6.1. Structure

Each planetary timezone zone is identified by a string of the form:

```
{PREFIX}{SIGN}{OFFSET}
```

Where:
- **PREFIX** is a three-letter abbreviation identifying the body and time system (Table 1)
- **SIGN** is `+`, `-`, or empty (for offset zero, written as `{PREFIX} 0` with a space)
- **OFFSET** is an integer 0-12 representing the number of local planet-hours from the prime meridian

### 6.2. Registered Prefixes

| Prefix | Body | Full Name | Reference Frame |
|---|---|---|---|
| AMT | Mars | Arean Mean Time | Airy-0 / VL1 prime meridian |
| LMT | Moon | Lunar Mean Time | Sinus Medii (mean Earth direction) |
| MMT | Mercury | Mercury Mean Time | Hun Kal crater |
| VMT | Venus | Venus Mean Time | Ariadne crater |
| JMT | Jupiter | Jupiter Mean Time | System III magnetic |
| SMT | Saturn | Saturn Mean Time | Deep interior (Mankovich, Marley, Fortney & Mozshovitz 2019; see §11.1) |
| UMT | Uranus | Uranus Mean Time | Voyager 2 magnetic |
| NMT | Neptune | Neptune Mean Time | Voyager 2 magnetic |

### 6.3. Zone Geometry

Each body is divided into 24 zones of 15 degrees longitude each. The zone centre for offset N is:

- Positive offsets: N * 15 degrees East
- Negative offsets: 360 - (|N| * 15) degrees East
- Offset zero: 0 degrees (prime meridian)
- Offset +12 and -12: 180 degrees (antimeridian, identical zone)

### 6.4. Relationship to IANA Time Zone Database

The identifiers defined here are NOT entries in the IANA Time Zone Database [RFC6557]. They occupy a separate namespace. Implementations MUST NOT attempt to resolve planetary timezone identifiers through the tz database.

A future document MAY propose registration of planetary timezone identifiers in the IANA tz database or in a dedicated IANA registry.

### 6.5. Relationship to Coordinated Lunar Time (LTC/TCL)

The IAU XXXII General Assembly (August 2024) adopted resolutions establishing Lunar Coordinate Time (TCL). NASA's Coordinated Lunar Time (LTC) initiative has a specification deadline of December 31, 2026. LTC/TCL will be a single unified reference time standard for the Moon, analogous to UTC on Earth.

LMT zones as defined in this document are geographic location identifiers, not a competing time standard. LMT zones MAY be redefined as offsets from LTC once the strategy for LTC implementation is published and stable. Until then, LMT zones carry no normative relationship to LTC.

### 6.6. Polar Exception Zones

At latitudes within approximately 5 degrees of either pole, longitude-based timezone zones become geometrically meaningless (all longitudes converge). Implementations SHOULD define polar exception zones:

```
{PREFIX}-Polar-N    ; North polar exception
{PREFIX}-Polar-S    ; South polar exception
```

The Artemis III landing target (Shackleton Crater, 89.66 deg S) falls within the LMT Polar-S exception zone.

## 7. Zone Definitions

### 7.1. Mars (AMT)

Mars is the most Earth-analogous body for timezone purposes. The Martian sol (88,775.244 s) is 2.75% longer than an Earth day, and human circadian rhythms can adapt to this length with engineered lighting support [Scheer2007].

Zone assignments use IAU 0-360 degrees East planetocentric coordinates. Feature names follow IAU Planetary Nomenclature conventions. The complete zone table with verified USGS coordinates is provided in Appendix A.

Representative zones:

| Zone | Centre (IAU E deg) | Feature |
|---|---|---|
| AMT 0 | 0 | Airy-0 Crater (prime meridian) |
| AMT+4 | 60 | Hellas Planitia |
| AMT+10 | 150 | Elysium Mons |
| AMT-4 | 300 | Valles Marineris (central) |
| AMT-6 | 270 | Tharsis Plateau |
| AMT-9 | 225 | Olympus Mons |

### 7.2. Moon (LMT)

The Moon's synodic period (29.530589 days) is entirely incompatible with human circadian biology. LMT zones are geographic identifiers only. See Section 8.2 for scheduling.

### 7.3. Mercury (MMT)

Mercury's 3:2 spin-orbit resonance produces a solar day of 175.94 Earth days. MMT zones are geographic identifiers only. The Caloris Basin (31.5 deg N, 162.7 deg E) is in the MMT+11 zone, near the 180-degree "hot pole."

### 7.4. Venus (VMT)

Venus rotates retrograde with a solar day of 116.75 Earth days. VMT zones are geographic identifiers only. Venus zone assignments MUST use IAU east-positive coordinates, noting that the Sun rises in the west on Venus.

### 7.5. Gas Giants (JMT, SMT, UMT, NMT)

Gas giants have no solid surface. Zones are defined by atmospheric longitude bands using the body's conventional rotation reference system (System III for Jupiter; Mankovich, Marley, Fortney & Mozshovitz 2019 ring seismology value for Saturn; Voyager 2 Planetary Radio Astronomy (PRA) experiment periods for Uranus and Neptune).

"Local time" on gas giants SHOULD be treated as a convention, not a physically strict clock. Atmospheric features drift relative to the interior rotation.

## 8. Work Scheduling Model

### 8.1. Sol-Synchronised Bodies (Mars)

On Mars, the sol is sufficiently close to 24 Earth hours that sol-synchronised scheduling is biologically feasible with appropriate lighting support.

Default Mars work schedule:

| Parameter | Value |
|---|---|
| Work period | 8 sol-hours (09:00-17:00 AMT, configurable) |
| Work sols per week | 5 |
| Rest sols per week | 2 |
| Week length | 7 sols (per Darian Calendar [Gangale2006]) |

Implementations SHOULD allow configuration of work hours, work days per week, and week length. The 5-on/2-off pattern is a RECOMMENDED default, not a mandate.

### 8.2. Earth-Clock-Shift Bodies (Moon, Mercury, Venus)

On bodies where the solar day exceeds approximately 48 Earth hours, human crews MUST NOT be scheduled according to the local solar day. Instead, crews follow Earth-clock scheduling anchored to UTC.

For Mercury and Venus specifically, the deployed scheduling convention is:

| Parameter | Value |
|---|---|
| Work days | Monday–Friday |
| Work hours | UTC 09:00–17:00 |
| Shift length | 8 Earth hours |
| Rest days | Saturday–Sunday |

Mercury's solar day is approximately 176 Earth days (3:2 spin-orbit resonance). Venus's solar day is approximately 117 Earth days. In both cases, local solar time has no practical relationship to a human work cycle.

MMT (Mercury Mean Time) and VMT (Venus Mean Time) zone designations identify geographic locations and appear in infrastructure databases and communications addressing. They are NOT used for daily work scheduling.

For the Moon, the same Earth-clock scheduling principle applies (29.53-day synodic period). Lunar crews follow UTC-anchored shifts; LMT zone designations serve as location identifiers only.

### 8.3. Grouped-Period Bodies (Gas Giants)

For bodies with very short rotation periods (~10 hours), multiple rotations are grouped into an approximately 24-Earth-hour work period:

| Body | Rotations per work period | Approximate Earth hours |
|---|---|---|
| Jupiter | 2.5 | 24.8 |
| Saturn | 2.25 | 23.8 |
| Uranus | 1.4 | 24.1 |
| Neptune | 1.5 | 24.2 |

### 8.4. Configurable Parameters

Implementations SHOULD expose the following scheduling parameters for per-deployment configuration:

```
workHoursStart     : integer (0-23, default 9)
workHoursEnd       : integer (0-23, default 17)
workDaysPerWeek    : integer (1-7, default 5)
daysPerWeek        : integer (1-10, default 7)
workPattern        : array of 0/1 (e.g. [1,1,1,1,1,0,0])
shiftsPerDay       : integer (1-4, default 1 for Mars, 3 for Moon)
latencyThresholdSec: integer (default 120)
```

The `latencyThresholdSec` parameter defines the one-way light-time above which the system SHOULD recommend asynchronous communication rather than real-time meetings.

## 9. Communications Latency

### 9.1. Light-Time Calculation

One-way light-time between two bodies MUST be calculated as:

```
light_time_seconds = distance_km / 299792.458
```

Where `distance_km` is the instantaneous heliocentric distance between the two bodies. The speed of light c = 299,792.458 km/s is exact by SI definition.

### 9.2. Earth-Body Latency Ranges

| Body pair | Minimum one-way | Maximum one-way | Notes |
|---|---|---|---|
| Earth-Moon | 1.21 s | 1.36 s | Perigee to apogee |
| Earth-Mars | ~186 s (3.1 min) | ~1,339 s (22.3 min) | Opposition to conjunction |
| Earth-Jupiter | ~33 min | ~53 min | |
| Earth-Saturn | ~67 min | ~87 min | |
| Earth-Uranus | ~2.4 h | ~2.8 h | |
| Earth-Neptune | ~4.0 h | ~4.2 h | |

### 9.3. Solar Conjunction

When a planet passes behind the Sun from Earth's perspective (Sun-Earth-planet angle less than approximately 2-3 degrees), radio communications are disrupted by solar corona interference.

For Mars, solar conjunction occurs every 779.94 Earth days (the synodic period). The command moratorium typically lasts approximately 14 days, with complete signal loss for approximately 1.5-2 days when Mars is directly behind the solar disk.

Implementations that display meeting availability MUST check for solar conjunction conditions and flag them as communication blackouts.

### 9.4. Sync vs Async Scheduling

When one-way light-time exceeds the configured `latencyThresholdSec` (default: 120 seconds), the system SHOULD indicate that real-time synchronous communication is impractical and SHOULD suggest asynchronous alternatives.

The threshold of 120 seconds (2 minutes) is chosen as a RECOMMENDED default because:
- Earth-Moon latency (~1.3 s) is always below threshold (real-time possible)
- Earth-Mars latency (3-22 min) is always above threshold (async recommended)
- Earth-LEO/GEO latency (<1 s) is always below threshold

## 10. Constants Table

All values are sourced from JPL Horizons physical data outputs unless otherwise noted. Implementations SHOULD store these as configurable parameters with source attribution.

| Body | Orbital period (sidereal, days) | Sidereal rotation | Mean solar day | Axial tilt (deg) | Source revision |
|---|---|---|---|---|---|
| Earth | 365.25636 | 23.9344696 h | 86,400.002 s | 23.439 | Horizons 2022-May |
| Moon | 27.321582 | 27.321582 d (locked) | 29.530589 d | 6.68 | Horizons 2018-Aug |
| Mercury | 87.969257 | 58.6463 d | 175.9421 d | 0.035 | Horizons 2024-Mar |
| Venus | 224.700799 | 243.0226 d (retro) | 116.7490 d | 177.36 | Margot 2021 |
| Mars | 686.9798 | 24.622962 h | 88,775.244 s | 25.19 | Horizons 2025-Jun |
| Jupiter | 4,332.589 | 9h 55m 29.71s (S-III) | ~9.926 h | 3.13 | Horizons 2025-Jan |
| Saturn | 10,755.698 | 10h 33m 38s | ~10.561 h | 26.73 | Mankovich, Marley, Fortney & Mozshovitz 2019 (see §11.1) |
| Uranus | ~30,687 | 17.2479 h (retro) | ~17.248 h | 97.77 | Lamy 2025 |
| Neptune | 60,189 | 16.11 h | ~16.11 h | 28.32 | Horizons 2021-May |

## 11. Disputed and Uncertain Values

The following values have significant measurement uncertainty or active scientific dispute. Implementations SHOULD expose these as configurable parameters and SHOULD document which value is in use.

### 11.1. Saturn Rotation Period

| Source | Value | Method |
|---|---|---|
| Voyager System III (1981) | 10h 39m 24s | Saturn Kilometric Radiation |
| Cassini (2004) | 10h 45m 45s +/- 36s | SKR (now known unreliable) |
| Read et al. (2009) | 10h 34m 13s +/- 20s | Atmospheric vorticity |
| Mankovich et al. (2019) | 10h 33m 38s (+1m52s/-1m19s) | Ring seismology |
| Mankovich, Marley, Fortney & Mozshovitz (2023) | 10h 34m 42s (~10.578 h) | Ring seismology (refined) |

This document uses the Mankovich, Marley, Fortney & Mozshovitz (2019) value (10h 33m 38s) as the RECOMMENDED default. A 2023 refinement by the same authors gives ≈10 h 34 m 42 s (≈10.578 h); updating the recommended constant is deferred to a future cascade epic. The NASA Planetary Fact Sheet still lists the System III value (10h 39m 22s). Implementations MAY offer a configuration option to select between rotation models.

### 11.2. Venus Rotation Variability

Venus's rotation rate varies by approximately 61 ppm (~20 minutes peak-to-peak) due to atmospheric angular momentum exchange [Margot2021]. Venus local time SHOULD be treated as a "best-fit at epoch" approximation, not a fixed clock.

### 11.3. Neptune Rotation

Neptune's rotation period (16.11 +/- 0.01 h) is derived from data collected by the Voyager 2 Planetary Radio Astronomy (PRA) experiment during the 1989 flyby — the sole spacecraft visit to Neptune. No subsequent spacecraft has visited. The Karkoschka (2011) alternative value of 15.9663 h from atmospheric features is NOT RECOMMENDED as the default.

### 11.4. Mars Relativistic Time Dilation

Gravitational time dilation on Mars averages approximately +477 µs/day relative to Earth, with seasonal variation of ±226 µs/day (perihelion ~251 µs/day, aphelion ~703 µs/day). (Ashby & Patla 2025, *Astronomical Journal* 171:2.) This accumulates to approximately 174 ms over a Mars year. This is negligible for scheduling purposes and is NOT corrected in this specification.

## 12. IANA Considerations

### 12.1. Timestamp Suffix Tag Key Registration

This document requests registration of a suffix tag key in the "Timestamp Suffix Tag Keys" registry established by [RFC9557], Section 3.2:

```
Key Identifier:     body
Registration Status: Provisional
Description:        Identifies the solar system body for which
                    the timestamp represents local time.
                    Values are IAU-recognised body names
                    (e.g. "Mars", "Moon", "Mercury").
Change Controller:  interplanet.live project (community specification)
Reference:          [this document]
```

This enables timestamps of the form:

```
2026-02-19T14:32:07Z[body=Mars][tz=AMT+4]
```

### 12.2. Future Registry Considerations

A future document MAY propose:

- An "Interplanetary Timezone Identifiers" IANA registry with the prefixes defined in Section 6.2
- Addition of planetary zones to the IANA Time Zone Database [RFC6557]

These actions require broader community consensus and are deferred.

## 13. Security Considerations

### 13.1. Time-of-Check vs Time-of-Use

Solar conjunction status and light-time calculations are time-dependent. A conjunction check performed at meeting creation time may be invalid by the meeting time. Implementations MUST revalidate conjunction status and light-time at or near the scheduled meeting time.

### 13.2. Clock Synchronisation

In DTN environments [RFC9171], clocks on different bodies may drift. The specification of TT as the continuous time reference (Section 3.2) mitigates this for ephemeris calculations, but clock synchronisation for human scheduling depends on the availability of reliable time transfer infrastructure (e.g. LunaNet for cislunar operations).

### 13.3. Timestamp Spoofing

Planetary timestamps that include both a local time and a UTC reference (Section 5.3) may be inconsistent. Consumers SHOULD validate that the UTC reference and the local time are mutually consistent given the stated body and timezone offset. Inconsistent timestamps SHOULD be rejected or flagged.

## 14. References

### 14.1. Normative References

- [RFC2119] Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels", BCP 14, RFC 2119, March 1997.
- [RFC3339] Klyne, G. and C. Newman, "Date and Time on the Internet: Timestamps", RFC 3339, July 2002.
- [RFC5234] Crocker, D. and P. Overell, "Augmented BNF for Syntax Specifications: ABNF", STD 68, RFC 5234, January 2008.
- [RFC8174] Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words", BCP 14, RFC 8174, May 2017.
- [RFC9557] Sharma, U. and C. Bormann, "Date and Time on the Internet: Timestamps with Additional Information", RFC 9557, April 2024.
- [Allison2000] Allison, M. and M. McEwen, "A post-Pathfinder evaluation of aerocentric solar coordinates with improved timing recipes for Mars seasonal/diurnal climate studies", Planetary and Space Science 48, 215-235, 2000.
- [Archinal2018] Archinal, B.A. et al., "Report of the IAU Working Group on Cartographic Coordinates and Rotational Elements: 2015", Celestial Mechanics and Dynamical Astronomy 130:22, 2018.

### 14.2. Informative References

- [RFC6557] Lear, E. and P. Eggert, "Procedures for Maintaining the Time Zone Database", BCP 175, RFC 6557, February 2012.
- [RFC9171] Burleigh, S., Fall, K., and E. Birrane, "Bundle Protocol Version 7", RFC 9171, January 2022.
- [CCSDS301] CCSDS, "Time Code Formats", CCSDS 301.0-B-4, November 2010.
- [IERS-C] IERS, "Bulletin C", https://www.iers.org/IERS/EN/Publications/Bulletins/bulletins.html
- [Mankovich2019] Mankovich, C., Marley, M., Fortney, J. and Mozshovitz, N., "A diffuse core in Saturn from ring seismology", The Astrophysical Journal 871:1, 2019.
- [Mankovich2023] Mankovich, C., Marley, M., Fortney, J. and Mozshovitz, N., Saturn ring seismology refinement, 2023. Refined rotation period: ≈10 h 34 m 42 s (≈10.578 h). Constant update to reference implementation deferred to cascade epic; current default remains 2019 value (10h 33m 38s).
- [Margot2021] Margot, J.-L. et al., "Spin state and moment of inertia of Venus", Nature Astronomy 5, 676-683, 2021.
- [AshbyPatla2025] Ashby, N. and Patla, B., "Relativistic time dilation for Mars", Astronomical Journal 171:2, 2025. (Mars drift: 477 µs/day average, ±226 µs/day seasonal.)
- [Lamy2025] Lamy, L. et al., "A new rotation period and longitude system for Uranus", Nature Astronomy, 2025.
- [Gangale2006] Gangale, T., "The Architecture of Time, Part 2: The Darian System for Mars", SAE Technical Paper 2006-01-2249, 2006.
- [Scheer2007] Scheer, F.A.J.L. et al., "Plasticity of the Intrinsic Period of the Human Circadian Timing System", PLOS ONE, 2007.

## 15. Acknowledgements

This document draws on the work of Michael Allison and Megan McEwen (Mars solar time), Thomas Gangale (Darian Calendar), Bruce Archinal and the IAU WGCCRE (prime meridian definitions), Christopher Mankovich (Saturn ring seismology), Laurent Lamy (Uranus rotation), and Jean-Luc Margot (Venus rotation).

The interplanet.live project and planet-time.js library serve as the reference implementation.

---

## Appendix A. Complete Zone Tables

Complete zone tables for all bodies, with verified USGS Planetary Nomenclature Database coordinates, are maintained in the TIMEZONES.md file of the interplanet.live project repository.

## Appendix B. Test Vectors

| Test Case | Input (UTC) | Expected Output | Tolerance |
|---|---|---|---|
| JD_UTC | 2000-01-06T00:00:00Z | 2451549.5 | exact |
| JD_TT | 2000-01-06T00:00:00Z | 2451549.500743 | +/- 1e-6 d |
| TT-UTC | 2026-02-19T00:00:00Z | 69.184 s | exact |
| Mars MSD | 2000-01-06T00:00:00Z | 44795.9998 | +/- 1e-4 sol |
| Mars MTC | 2000-01-06T00:00:00Z | 23:59:39 | +/- 20 s |
| TAI-UTC (pre-2017) | 2016-12-31T23:59:59Z | 36 s | exact |
| TAI-UTC (post-2017) | 2017-01-01T00:00:00Z | 37 s | exact |
| Light-time (min E-M) | d = 55.76 Mkm | 186.0 s | +/- 1 s |
| Light-time (max E-M) | d = 401.3 Mkm | 1338.6 s | +/- 1 s |
| Light-time (E-Moon) | d = 384.4 kkm | 1.28 s | +/- 0.01 s |

---

Matthew Watt
interplanet.live
mr.matthew.watt at gmail.com
