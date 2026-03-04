# Interplanetary Timezone Systems
## A Reference Document for Sky Colours / InterPlanet.live

*Version 1.1 — February 2026*

---

## Abstract

As human activity expands beyond Earth, the need for standardised interplanetary timekeeping becomes increasingly practical. This document proposes and describes a system of planetary timezone conventions for the bodies of our solar system, as implemented in the `planet-time.js` library and the InterPlanet.live scheduling platform. The system is designed to be consistent with terrestrial timezone conventions wherever possible, rooted in IAU-recognised standards, and practical for human work scheduling across wildly different planetary environments.

---

## Definitions

- **Sidereal rotation period:** rotation of a body relative to the fixed stars.
- **Mean solar day:** average interval between successive local noons (synodic day with respect to the Sun).
- **TT (Terrestrial Time):** the dynamical time argument for geocentric ephemerides. TT = TAI + 32.184 s (exact).
- **TAI (International Atomic Time):** atomic time standard. UTC−TAI = −37 s since 2017-01-01.
- **ΔT = TT − UT1**: the difference between dynamical time and Earth rotation time. Relevant to high-precision calculations.
- **ΔUT1 = UT1 − UTC**: the small offset between Earth's rotational angle and civil UTC (currently kept within ±0.9 s by IERS). CGPM Resolution 4 (2022) and ITU WRC-23 (2023) direct a planned change to the UT1−UTC tolerance by or before 2035; implementation details remain pending standardisation. This will likely end the practice of inserting leap seconds, but no formal abolition has yet been adopted.
- **Julian Date (JD):** a continuous count of days since 4713 BC noon UT. In precise work, specify the time scale: JD_UTC, JD_TT, etc.
- **Planetocentric east-positive longitude:** the IAU convention for all modern planetary cartography (0–360°E). This is the convention used for all zone definitions in this document.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 [RFC 2119] [RFC 8174] when, and only when, they appear in all capitals, as shown here. Sections containing RFC 2119 keywords are normative; all other text is informative.

### Coordinate and Longitude Conventions

All zone definitions in this document use the **IAU east-positive planetocentric** convention: longitudes run 0–360°E, measured in the direction of rotation for prograde bodies. For **Venus and Uranus**, which rotate retrograde, the IAU nonetheless uses east-positive coordinates — the east-positive direction is defined by the right-hand rule relative to the body's north pole, regardless of rotation direction. This means that on Venus, the sun moves westward across the sky, but IAU longitude numbers increase eastward.

Some older USGS gazetteers, NASA mission documents, and historical literature use **planetographic** coordinates, in which positive longitude is defined in the direction opposite to rotation:
- For prograde bodies (Mars, Moon, Mercury, gas giants): planetographic positive = **west** (opposite to IAU east-positive).
- For retrograde bodies (Venus, Uranus): planetographic positive = **east** (same direction as IAU east-positive, because the rotation is reversed).

**Conversion for prograde bodies:** `longitude_IAU_east = 360° − longitude_planetographic_west`

**Example (Caloris Basin, Mercury):** USGS Gazetteer lists Caloris at 198.02°W (planetographic). Converting: 360° − 198.02° = 161.98°E (IAU east-positive), consistent with the 162.7°E figure used in this document.

If you encounter longitude values that appear to be in the wrong hemisphere relative to a known feature, check whether the source is using planetographic coordinates and apply the conversion.

Implementations that accept user-supplied coordinates SHOULD provide a conversion utility or accept both east-positive and west-positive inputs with explicit convention flags. Silently interpreting ambiguous longitude values MUST NOT occur.

## Authority and update policy

Planetary constants (orbital period, sidereal rotation, mean solar day, obliquity) are sourced from **JPL Horizons** physical data outputs and should be updated with their revision dates. Body-fixed prime meridians and rotation models follow **NAIF SPICE PCK** orientation models (IAU_\* frames) where applicable. Zone feature names are drawn from the **IAU Planetary Nomenclature** database (planetarynames.wr.usgs.gov), which is the authoritative source for all planetary feature names.

---

## Table of Contents

1. [Introduction: Why Interplanetary Timezones?](#1-introduction)
2. [Sources and References](#2-sources-and-references)
3. [Earth — The Baseline](#3-earth)
4. [Mars — Airy Mean Time (AMT)](#4-mars)
5. [Moon — Lunar Mean Time (LMT)](#5-moon)
6. [Mercury — Mercury Mean Time (MMT)](#6-mercury)
7. [Venus — Venus Mean Time (VMT)](#7-venus)
8. [Jupiter — Jupiter Mean Time (JMT)](#8-jupiter)
9. [Saturn — Saturn Mean Time (SMT)](#9-saturn)
10. [Uranus — Uranus Mean Time (UMT)](#10-uranus)
11. [Neptune — Neptune Mean Time (NMT)](#11-neptune)
12. [Design Philosophy](#12-design-philosophy)

---

## 1. Introduction

### Why Interplanetary Timezones?

The history of standardised timekeeping on Earth is, at its heart, a history of coordination problems. Before the railway age, every town kept its own local solar time — noon was when the sun was highest, and the clocks in Bristol ran ten minutes behind those in London. This was tolerable when the fastest message travelled at the speed of a horse. It became untenable when trains began running between cities on published schedules. The confusion of dozens of local times led directly to the adoption of standardised timezone systems: first by the British railway companies in the 1840s, then nationally, and eventually internationally through the 1884 International Meridian Conference that established Greenwich as the prime meridian for a system of 24 one-hour zones.

We are now at an analogous inflection point, extended to interplanetary scales. Robotic missions already operate on Mars, the Moon, the asteroids, and the outer solar system. Crewed missions to the Moon are underway, and crewed Mars missions are in serious planning. Permanent installations — research stations, industrial outposts, eventually settlements — will follow. People on these worlds will need to coordinate with each other and with Earth: scheduling communications windows, planning joint operations, trading goods and services, and simply arranging a call.

The challenge is considerably more complex than the terrestrial one. On Earth, all timezones share the same 24-hour day; a timezone is simply a fixed offset from UTC. On other worlds, the local day has a completely different length. Mars's sol is 24 hours, 39 minutes, and 35.244 seconds — close enough to Earth's day that human crews can adapt with minimal disruption, but different enough to accumulate significant drift over weeks and months. Mercury's solar day is 175.94 Earth days long. Venus's is 116.75 Earth days. These are not amenable to circadian scheduling in the same way.

The InterPlanet.live timezone system addresses this by treating *location reference* and *work scheduling* as separate concerns. Every body in the solar system receives a system of 24 timezone zones, each spanning 15 degrees of longitude, analogous to Earth's system. These zones tell you *where on the planet* you are, expressed as an offset from that planet's prime meridian. The question of when humans on that planet actually sleep and work is handled separately, calibrated to human biology rather than local astronomy.

---

## 2. Sources and References

The following sources inform the conventions used in this document and in `planet-time.js`.

| Source | Used For |
|--------|----------|
| **IAU Planetary Nomenclature** (planetarynames.wr.usgs.gov) | All planetary feature names; naming conventions by body |
| **NASA GSFC Planetary Fact Sheet** | Sidereal and solar day lengths; orbital periods; axial tilts |
| **JPL Horizons physical data outputs** | Authoritative planetary constants with revision dates |
| **NAIF SPICE PCK kernels (pck00011.tpc)** | Body-fixed frames; prime meridian rotation models |
| **Allison & McEwen (2000)** — *Planetary and Space Science* 48, 215–235 | Mars Coordinated Time (MTC) formula; Martian sol = 88,775.244 s |
| **Clancy et al. (2000); Piqueux et al. (2015)** | Mars Year epoch: MY0 = May 24, 1953; MY1 = April 11, 1955 |
| **Gangale, T. — The Darian Calendar** | 7-sol Mars week; 668.6 sols/year; Martian calendar validation |
| **IAU WGCCRE (2015 ed., published 2018)** — Archinal et al., *CMDA* 130:22 | Prime meridian definitions; VL1-based Mars prime meridian |
| **USGS Astrogeology Science Center** | Feature mapping; crater and basin coordinates |
| **Magellan Mission (NASA, 1990–1994)** | Venus surface radar mapping; topography and feature identification |
| **MESSENGER Mission (NASA, 2011–2015)** | Mercury surface mapping; feature identification and coordinates |
| **Mankovich et al. (2019)** — *ApJ* 871:1 | Saturn rotation: 10h 33m 38s from ring seismology |
| **Margot et al. (2021)** — *Nature Astronomy* | Venus sidereal rotation: 243.0226 ±0.0013 days |
| **Lamy et al. (2025)** — *Nature Astronomy* | Uranus rotation: 17.247864 ±0.000010 h |
| **Meeus, J. — *Astronomical Algorithms*, 2nd ed. (1998)** | Orbital elements; heliocentric coordinate calculations |
| **IERS Bulletin C** | Leap second table; UTC−TAI = −37 s since 2017-01-01 |
| **CGPM Resolution 4 (2022)** | Leap second abolition pathway; new UT1−UTC tolerance by 2035 |
| **IAU XXXII General Assembly (2024)** | Lunar Coordinate Time (TCL) resolutions adopted August 2024 |
| **NASA rover operations (MER, MSL, Perseverance)** | Precedent for Mars sol-based scheduling in practice |
| **International Meridian Conference (1884)** | Historical basis for 24-zone, 15°-per-hour system |

---

## 3. Earth

### Standard IANA Timezone System

Earth's timezone system is the reference and template for all systems described in this document. The core structure, established internationally following the 1884 Washington conference, divides the Earth into 24 primary zones, each spanning 15 degrees of longitude, corresponding to one hour of solar time. The prime meridian was fixed at the Royal Observatory, Greenwich, England — a choice that reflected British naval dominance at the time and the widespread use of Greenwich-based nautical charts.

In practice, political boundaries cause significant deviations from the clean 15-degree geometry. India, for example, uses UTC+5:30; Nepal uses UTC+5:45; China applies a single timezone (UTC+8) across a territory that spans five natural zones. The IANA timezone database (the "Olson database") codifies these real-world zones, including their historical changes, and is the authoritative source used by all modern operating systems and programming environments.

Key parameters:

| Parameter | Value |
|-----------|-------|
| Solar day | 86,400 seconds (by definition of the SI second) |
| Zones | 24 primary zones, ±30-minute and ±45-minute variants in practice |
| Prime meridian | Greenwich, England (0° longitude) |
| Timezone designation | UTC±HH or UTC±HH:MM |
| Leap seconds | Applied by IERS; UTC−TAI = −37 s as of 2017-01-01 |

For InterPlanet.live purposes, Earth times are always expressed in UTC or a named IANA timezone (e.g., `Europe/London`, `America/New_York`). The planet key `'earth'` in `planet-time.js` uses UTC as its reference.

---

## 4. Mars

### Airy Mean Time (AMT)

Mars is the most natural first extension of the terrestrial timezone model. Its sol — the Martian solar day — is 88,775.244 seconds, or 24 hours, 39 minutes, and 35.244 seconds (Allison & McEwen 2000). This is only 2.75% longer than an Earth day. Human circadian rhythms, which have a natural free-running period of approximately 24.5 hours, adapt to a Martian sol with considerably less difficulty than to any other planetary day length in the solar system. NASA's rover operations teams on MER, MSL (Curiosity), and Perseverance have all demonstrated this in practice: mission controllers have repeatedly adopted Mars-time scheduling for extended periods, carrying dedicated sol-corrected wristwatches.

### Prime Meridian

The Martian prime meridian is defined by the centre of **Airy-0**, a small impact crater approximately 0.5 km in diameter located in Sinus Meridiani at approximately 5° South latitude, 0° West longitude. The crater is named after the same George Biddell Airy, Astronomer Royal, whose transit instrument at Greenwich defines the Earth's prime meridian — a deliberate historical echo. The IAU Working Group on Cartographic Coordinates and Rotational Elements (2009 report) establishes this as the formal standard.

The Mars Year epoch used by InterPlanet.live is **May 24, 1953**, which corresponds to **Mars Year 0 (MY0)** in the Piqueux et al. (2015) backward extension of the Clancy system. Note: the primary Clancy et al. (2000) convention defines **MY1 Sol 1 = April 11, 1955** (when Ls = 0°). The May 24, 1953 date (MY0) is used here for historical continuity with interplanet.live v1 and the existing sol-count calendar. Sol counts are internally consistent regardless of which epoch label is used; the underlying epoch timestamp is unchanged. Neither convention has been formally adopted by the IAU. Mars Year numbering increments at each subsequent northern vernal equinox.

The Martian prime meridian was anchored to the Viking Lander 1 (VL1) landing site by the **IAU WGCCRE 2015 report** (published 2018, Archinal et al., *CMDA* 130:22). VL1's longitude is fixed at exactly 47.95137°W, reducing timing uncertainty for Airy Mean Time from ~20 seconds (crater-centre based) to **&lt;1 second** (radiometric precision of VL1).

### Zone Structure

AMT is divided into 24 zones of 15° each, designated AMT±N, where N is the integer offset in Mars sol-hours from the prime meridian. All longitudes use **IAU 0–360°E east-positive planetocentric coordinates**. Zone centre longitude = N × 15°E (positive) or 360° − (N × 15°)E (negative). Feature assignments have been corrected against the USGS Planetary Nomenclature Database; a previous version of this table contained a systematic west-to-east longitude label error in the positive half. Full verification against the USGS database is recommended for production use.

| Offset | Centre Longitude (IAU E°) | Representative Feature |
|--------|--------------------------|----------------------|
| AMT 0  | 0° (Sinus Meridiani) | Airy-0 Crater (prime meridian) |
| AMT+1  | 15°E | Arabia Terra |
| AMT+2  | 30°E | Arabia Terra (eastern) |
| AMT+3  | 45°E | Hellas Planitia (western rim) |
| AMT+4  | 60°E | Hellas Planitia (centre, ~70°E) |
| AMT+5  | 75°E | Malea Planum |
| AMT+6  | 90°E | Promethei Terra |
| AMT+7  | 105°E | Hesperia Planum |
| AMT+8  | 120°E | Tyrrhena Terra (eastern) |
| AMT+9  | 135°E | Elysium Planitia (western approach) |
| AMT+10 | 150°E | Elysium Mons (~147°E) |
| AMT+11 | 165°E | Elysium Planitia (eastern) |
| AMT+12 | 180° | Elysium–Amazonis antimeridian |
| AMT−1  | 345°E (15°W) | Meridiani Planum (western) |
| AMT−2  | 330°E (30°W) | Margaritifer Terra |
| AMT−3  | 315°E (45°W) | Valles Marineris (eastern) |
| AMT−4  | 300°E (60°W) | Valles Marineris (central) |
| AMT−5  | 285°E (75°W) | Valles Marineris (western) |
| AMT−6  | 270°E (90°W) | Tharsis Plateau |
| AMT−7  | 255°E (105°W) | Ascraeus Mons |
| AMT−8  | 240°E (120°W) | Pavonis Mons / Arsia Mons |
| AMT−9  | 225°E (135°W) | Olympus Mons / Daedalia Planum (NASA Mars24 convention: Olympus Mons at 226.2°E) |
| AMT−10 | 210°E (150°W) | Terra Sirenum |
| AMT−11 | 195°E (165°W) | Amazonis Planitia |
| AMT−12 | 180°W | (same as +12, antimeridian) |

Feature names follow IAU Planetary Nomenclature conventions. Martian features use Latin-derived terms (Planitia = plain, Mons = mountain, Valles = valley, Terra = land) with names drawn from classical geography, mythology, and the names of Mars-observing astronomers.

### Work Schedule

The Martian work week follows the Darian Calendar convention of 7 sols (Thomas Gangale), with 5 work sols and 2 rest sols. This mirrors the terrestrial work week almost exactly. A Mars year contains approximately 668.6 sols (Gangale, validated against the IAU sidereal period), divided into 24 months of approximately 27–28 sols.

| Parameter | Value |
|-----------|-------|
| Sol length | 88,775.244 s (Allison & McEwen 2000; JPL Horizons: 88,775.24415 s) |
| Work hours | 09:00–17:00 AMT (configurable) |
| Work sols per week | 5 |
| Rest sols per week | 2 |
| Sols per Mars year | 668.59 sols (tropical/vernal equinox year; sidereal year = 668.60 sols) |
| Mars Year 0 epoch | MY0 Sol 1 = 00:00 UTC, 24 May 1953 (Piqueux/interplanet.live convention) |
| Mars Year 1 epoch | MY1 Sol 1 = Ls=0°, April 11, 1955 (Clancy et al. 2000 primary convention) |

### Justification

The case for a sol-synchronised schedule on Mars is strong. Human circadian biology can adapt to the 24h 39m sol with relatively minor chronobiological disruption — far less than adapting to, say, a six-month polar night on Earth. The 2.75% difference in day length means that a Martian "work morning" drifts by only about 39 minutes per day relative to an Earth UTC clock, an effect that accumulates noticeably over weeks but is easily managed with sol-corrected timekeeping devices.

The existing NASA precedent — multiple teams of engineers working full Mars schedules for months at a time — validates this approach empirically. AMT is therefore the most Earth-analogous of the interplanetary timezone systems, and the most straightforwardly implementable.

---

## 5. Moon

### Lunar Mean Time (LMT)

The Moon presents a situation superficially similar to Mars — a rocky body orbiting relatively close to Earth — but its timekeeping is radically different. The Moon's synodic period (the lunar month, from new moon to new moon) is 29.53 Earth days. This is the Moon's solar day: the time from one lunar noon to the next. The Moon is tidally locked to Earth, meaning it rotates once per orbit: the same hemisphere always faces Earth.

### Prime Meridian

The Lunar prime meridian passes through **Sinus Medii** ("Sea of the Middle"), the IAU-designated reference point located at approximately 1°E, 2°N on the Earth-facing side. This point sits at the geometric centre of the lunar disc as seen from Earth, making it an intuitive choice for the zero meridian of a body whose most important property — from the human perspective — is its relationship to Earth.

### Zone Structure

LMT divides the Moon into 24 zones of 15° longitude each, designated LMT±N.

The near side (Earth-facing hemisphere, LMT−6 to LMT+6) contains the mare regions familiar from naked-eye observation and from Apollo missions. The far side (LMT±7 to LMT±12) contains heavily cratered terrain and several large impact basins, named after Soviet-era explorers and space pioneers.

**Near Side Zones (LMT−6 to LMT+6):**

| Offset | Approximate Longitude | Representative Feature |
|--------|-----------------------|----------------------|
| LMT 0 | 0° (Sinus Medii) | Sinus Medii (prime meridian) |
| LMT+1 | 15°E | Mare Tranquillitatis (Apollo 11 site) |
| LMT+2 | 30°E | Mare Crisium |
| LMT+3 | 45°E | Mare Marginis |
| LMT+4 | 60°E | Mare Smythii |
| LMT+5 | 75°E | Mare Australe |
| LMT+6 | 90°E | Near-side/far-side limb (south pole region, Artemis target) |
| LMT−1 | 15°W | Oceanus Procellarum |
| LMT−2 | 30°W | Mare Imbrium |
| LMT−3 | 45°W | Sinus Roris |
| LMT−4 | 60°W | Mare Orientale (western limb) |
| LMT−5 | 75°W | Far-side western limb |
| LMT−6 | 90°W | Near-side/far-side limb |

**Far Side Zones (LMT±7 to LMT±12):**

| Offset | Approximate Longitude | Representative Feature |
|--------|-----------------------|----------------------|
| LMT+7 | 105°E | Hertzsprung Basin |
| LMT+8 | 120°E | Korolev Crater |
| LMT+9 | 135°E | Moscoviense Basin |
| LMT+10 | 150°E | Tsiolkovsky Crater |
| LMT+11 | 165°E | Jules Verne Crater |
| LMT+12 | 180° | Antimeridian (far-side centre) |
| LMT−7 | 105°W | Mendeleev Crater |
| LMT−8 | 120°W | Daedalus Crater |
| LMT−9 | 135°W | Apollo Basin |
| LMT−10 | 150°W | Poincaré Basin |
| LMT−11 | 165°W | Planck Basin |
| LMT−12 | 180°W | (same as +12, antimeridian) |

### Special Considerations

**Tidal locking and the far side.** Because the Moon is tidally locked, the far side never faces Earth. Relay satellites in L2 halo orbits (as proposed for the Lunar Gateway) are required for communications with far-side installations. This has significant operational implications: far-side bases are communication-isolated from Earth by the lunar body itself, and must rely on relay infrastructure. LMT zone designations for the far side should be understood to carry this implicit caveat.

**Work scheduling.** The 29.53-day lunar solar day is entirely incompatible with human circadian biology. Lunar surface crews SHOULD NOT attempt to synchronise their sleep-wake cycles to the local solar day. Instead, crews follow Earth-clock shifts: the standard model is an 8-hour work shift, 8-hour personal time, 8-hour sleep — a three-shift rotation. LMT zones serve as *location designators* (telling you where on the Moon something is) rather than as scheduling references.

**Key sites.** The Apollo 11 landing site (Tranquility Base, 0.67°N, 23.47°E) falls correctly within the LMT+1 zone (15–30°E). The primary Artemis III landing zone targets the **Shackleton Crater** rim (89.66°S, ~130°E). At this extreme south polar latitude, all longitudes converge and standard longitude-based timezone zones become meaningless. Shackleton Crater should be treated as a **polar exception zone** (LMT Polar South) rather than being assigned a specific LMT number. The same applies to any installation within approximately 5° of either pole.

**Coordinated Lunar Time (LTC / TCL).** The **IAU XXXII General Assembly** (Cape Town, August 2024) adopted resolutions establishing **Lunar Coordinate Time (TCL)** and a Lunar Celestial Reference System. The White House OSTP directive (April 2, 2024) mandated NASA develop an equivalent Coordinated Lunar Time (LTC) by December 31, 2026. In December 2025, China's Purple Mountain Observatory published **LTE440** — the first ready-to-use lunar timekeeping software, with ~0.15 ns accuracy through 2050. The Artemis Accords now have 61 signatories (January 2026).

**Important note on LMT zones:** LTC/TCL will be a **single unified time standard** for the entire Moon, not a system of geographic timezone zones. NIST's framework establishes LTC as a coordinate reference (analogous to UTC on Earth) from which zones could theoretically be derived, but no plan for geographic lunar timezone zones currently exists. The LMT zone system in this document is a **project-specific location-reference convention** — useful for describing where on the Moon something is (just as GPS coordinates are), but not an emerging standard, and not a precursor to LTC. InterPlanet.live reserves compatibility space for LTC integration when the final specification is published.

---

## 6. Mercury

### Mercury Mean Time (MMT)

Mercury occupies a unique position in the solar system: it is locked into a 3:2 spin-orbit resonance with the Sun, meaning it rotates exactly three times for every two orbits it completes. This is not tidal locking (which would produce a 1:1 ratio, as the Moon exhibits), but a higher-order resonance. The consequence is a solar day of 175.94 Earth days — nearly 6 Earth months. A Hermean year (orbital period) is 87.97 Earth days, so Mercury's solar day is almost exactly two Mercurian years.

### Prime Meridian

The Mercurian prime meridian is defined by **Hun Kal**, a small crater approximately 1.5 km in diameter, per the IAU 2009 Working Group report. "Hun Kal" means "20" in the Mayan language — the crater was chosen partly because it lies near the 20°W longitude used in earlier Mariner 10-based mapping systems, and the name reflects that numerical echo. The Hun Kal definition superseded earlier reference systems and provides a stable anchor for MMT zone calculations.

### Zone Structure

MMT uses the standard 24 zones of 15° longitude each. Feature names follow the IAU convention for Mercury: craters are named after deceased artists, musicians, writers, and other contributors to the arts. Larger features (planitia, montes, rupes) use names from classical mythology and the works of Shakespeare.

All longitudes use **IAU 0–360°E east-positive planetocentric coordinates**. A full audit against MESSENGER/MDIS data is RECOMMENDED for production use.

| Offset | Centre Longitude | Representative Feature |
|--------|-----------------|----------------------|
| MMT 0  | 0° (Hun Kal) | Hun Kal Crater (prime meridian) |
| MMT+1  | 15°E | Northern plains region |
| MMT+2  | 30°E | Intercrater plains (northern hemisphere) |
| MMT+3  | 45°E | Odin Planitia |
| MMT+4  | 60°E | Budh Planitia |
| MMT+5  | 75°E | Beethoven Basin |
| MMT+6  | 90°E | Tolstoj Basin |
| MMT+7  | 105°E | Bach Basin |
| MMT+8  | 120°E | Michelangelo Crater |
| MMT+9  | 135°E | Shakespeare Crater |
| MMT+10 | 150°E | Caloris Basin (western rim, ~152°E) |
| MMT+11 | 165°E | **Caloris Basin (centre, 162.7°E)** — faces sun at 180° hot pole |
| MMT+12 | 180° | Antimeridian (180° hot pole) |

### The 3:2 Resonance and "Hot Poles"

The 3:2 spin-orbit resonance has a striking geometric consequence: Mercury's perihelion passage (closest approach to the Sun, when solar heating is most intense) occurs when the sub-solar point is at one of exactly two longitudes — approximately 0° and 180°. These are called the "hot poles." The **Caloris Basin**, one of the largest impact craters in the solar system at approximately 1,550 km in diameter, is centred at **31.5°N, 162.7°E** (MESSENGER/MDIS definitive coordinates; Ernst et al. 2015, Fassett et al. 2009). This places it near the **180° hot pole** (within ~17°), which is consistent with the hypothesis that it was formed by a very large impactor arriving from a direction influenced by the resonant geometry. Caloris corresponds to the MMT+11 zone.

This means the thermal environment on Mercury's surface is strongly bimodal: the hot poles experience extreme temperature peaks during perihelion, while the "warm poles" at 90° and 270° have more moderate peak temperatures. Infrastructure placement needs to account for this.

### Work Schedule

With a solar day of 175.94 Earth days, Mercury time is purely a location designation system. Human crews MUST NOT schedule their circadian rhythms around the local solar day. Instead, the operational model uses Earth-standard 8-hour shifts, with a 5-shift work / 2-shift rest pattern per week. MMT zone designations appear in infrastructure databases, site coordinates, and communications addresses — not in daily scheduling.

| Parameter | Value |
|-----------|-------|
| Solar day | 175.94 Earth days |
| Sidereal rotation period | 58.65 Earth days |
| Spin-orbit resonance | 3:2 (3 rotations per 2 orbits) |
| Work schedule | Earth 8-hour shifts (5 on / 2 off per week) |
| MMT use | Location reference only |

Feature mapping was substantially advanced by the MESSENGER mission (NASA, 2011–2015), which orbited Mercury and produced the first complete photographic map of the surface. Earlier data from Mariner 10 (1974–1975) covered approximately 45% of the surface.

---

## 7. Venus

### Venus Mean Time (VMT)

Venus is, in several respects, the most alien of the inner planets. Its surface temperature is approximately 465°C — hot enough to melt lead — maintained by a dense atmosphere of carbon dioxide with sulphuric acid cloud layers. Its surface pressure is about 92 times Earth sea level. No lander has survived more than about two hours on the surface. Direct optical imaging of the surface from orbit is impossible through the clouds; all detailed surface mapping has been done by radar.

Venus also rotates retrograde — that is, in the opposite direction to its orbital motion. If you could stand on Venus and see through the clouds, the Sun would rise in the west and set in the east. Its solar day (the time from one noon to the next) is 116.75 Earth days.

### Prime Meridian

The Venusian prime meridian is defined by the central peak of **Ariadne Crater**, as established by the IAU Working Group on Cartographic Coordinates (IAU WGCCRE). This follows the same principle as other bodies: the prime meridian is anchored to a specific, identifiable surface feature. The entire surface coordinate system of Venus was established using Magellan radar data, since no optical reference is available.

### Zone Structure

VMT uses 24 zones of 15° longitude each. The IAU naming convention for Venusian features is: craters are named after famous women (historical figures, artists, scientists); large features (terrae, planitiae, montes) are named after goddesses from world mythologies. The principal exception is **Maxwell Montes**, the highest mountain on Venus at approximately 11 km above mean planetary radius, which was named before the women-only convention was adopted for Venusian features.

All longitudes use **IAU 0–360°E east-positive planetocentric coordinates**. Feature assignments have been corrected and verified against the USGS Planetary Nomenclature Database (February 2026). A previous version of this table contained systematic coordinate errors in which features were misplaced by up to 160°. Zones marked [†] are assigned to researcher-recommended features pending full USGS Gazetteer verification; a complete audit is RECOMMENDED before production use.

| Offset | Centre Longitude (IAU E°) | Representative Feature |
|--------|--------------------------|----------------------|
| VMT 0  | 0° (Ariadne)             | Ariadne Crater (prime meridian) |
| VMT+1  | 15°E                     | Maxwell Montes (~3–6°E); Ishtar Terra (western edge, ~0–30°E) |
| VMT+2  | 30°E                     | Ishtar Terra (eastern) / Lada Terra (~20°E) |
| VMT+3  | 45°E                     | Eistla Regio (western highland tessera, ~22–50°E) |
| VMT+4  | 60°E                     | Aphrodite Terra (western edge, ~60°E) |
| VMT+5  | 75°E                     | Aphrodite Terra / Niobe Planitia (~83°E) |
| VMT+6  | 90°E                     | Ovda Regio (equatorial tessera highland, ~85–100°E) |
| VMT+7  | 105°E                    | Aphrodite Terra (central, ~100–120°E) |
| VMT+8  | 120°E                    | Thetis Regio (plateau tessera, ~120–140°E) |
| VMT+9  | 135°E                    | **Artemis Corona** (~135°E) — largest corona on Venus |
| VMT+10 | 150°E                    | Diana Chasma (rift valley, ~155°E) |
| VMT+11 | 165°E                    | **Atalanta Planitia** (northern lowland, ~165°E) |
| VMT+12 | 180°                     | Antimeridian |
| VMT−1  | 345°E (15°W)             | Sedna Planitia (~340–350°E) |
| VMT−2  | 330°E (30°W)             | Lavinia Planitia (southern plains, ~315–355°E) |
| VMT−3  | 315°E (45°W)             | **Guinevere Planitia** (northern lowland, ~317°E) |
| VMT−4  | 300°E (60°W)             | Aino Planitia (~300–330°E; southern lowland) [†] |
| VMT−5  | 285°E (75°W)             | **Beta Regio** (volcanic highland, Rhea Mons, ~283°E) |
| VMT−6  | 270°E (90°W)             | Themis Regio (southern highland tessera region, ~270°E) [†] |
| VMT−7  | 255°E (105°W)            | Helen Planitia (southern plains, ~255–260°E) |
| VMT−8  | 240°E (120°W)            | Laimdota Planitia (southern lowland plains, ~240°E) [†] |
| VMT−9  | 225°E (135°W)            | Mugazo Planitia (highland–lowland transition zone, ~220°E) [†] |
| VMT−10 | 210°E (150°W)            | Rusalka Planitia (southern lowland plains, ~210°E) [†] |
| VMT−11 | 195°E (165°W)            | Navka Planitia (lowland volcanic plains, ~195°E) [†] |
| VMT−12 | 180°W                    | (same as +12, antimeridian) |

### Magellan and Surface Knowledge

The Magellan spacecraft (NASA, 1990–1994) used synthetic aperture radar to map approximately 98% of Venus's surface at resolutions of 100–200 metres. This remains the primary basis for all Venusian cartography. The mission revealed a world dominated by volcanic plains, large shield volcanoes, unique "corona" structures (large oval volcanic features), and highland "terrae" that may be analogous to Earth's continents. The absence of obvious large-scale tectonic plate boundaries has led to competing hypotheses about Venus's geological history.

### Work Schedule

Like Mercury, Venus's solar day is incompatible with human circadian scheduling. VMT zones are location designators. Crews on Venus (most plausibly in high-altitude atmospheric habitats, where temperatures and pressures are roughly Earth-like at around 50–55 km altitude) would follow Earth-standard 8-hour shift schedules regardless of local solar time.

---

## 8. Jupiter

### Jupiter Mean Time (JMT)

Jupiter is a gas giant with no solid surface. Defining "timezones" on Jupiter therefore requires a different approach: zones are defined by atmospheric longitude bands rather than surface geography. Jupiter has three rotation reference systems:

- **System I**: Equatorial atmosphere (within approximately ±10° latitude), period 9h 50m 30s
- **System II**: Temperate atmosphere (outside ±10°), period 9h 55m 41s
- **System III**: Magnetic field rotation (interior rotation rate), period 9h 55m 29.7s

**JMT uses System III** as the reference frame for the prime meridian and zone definitions. System III is the most stable reference, tied to the planet's deep interior via the magnetic field rather than the fluid atmosphere. This is consistent with IAU convention.

Jupiter's mean solar day (for zone-width purposes) is approximately **9.925 hours** (System III period corrected for solar synodic motion).

### Zone Structure

Twenty-four zones of 15° each are defined using System III longitude. Zone names reference atmospheric features visible in Jupiter's banded cloud structure. The Great Red Spot is the most famous feature: a persistent anticyclonic storm larger than Earth, located at approximately 23°S in System II coordinates.

| Offset | Approximate S-III Longitude | Representative Feature |
|--------|----------------------------|----------------------|
| JMT 0 | 0° | System III prime meridian |
| JMT+1 | 15° | North Equatorial Belt |
| JMT+2 | 30° | North Temperate Belt |
| JMT+3 | 45° | North Polar Region |
| JMT+4 | 60° | North Polar Vortex |
| JMT+5 | 75° | South Polar Region |
| JMT+6 | 90° | South Temperate Belt |
| JMT+7 | 105° | South Equatorial Belt |
| JMT+8 | 120° | Equatorial Zone |
| JMT+9 | 135° | Great Red Spot vicinity |
| JMT+10 | 150° | South Equatorial Belt (GRS following) |
| JMT+11 | 165° | White Ovals region |
| JMT+12 | 180° | Antimeridian |

### Work Schedule

The Jovian system is of interest primarily for operations at or near the Galilean moons (Io, Europa, Ganymede, Callisto), which will have their own separate scheduling needs. JMT zones apply to Jovian atmospheric operations (e.g., robotic or crewed atmospheric probes).

Jupiter's System III period of approximately 9.925 hours suggests a natural work unit of 2.5 Jovian days (approximately 24.8 Earth hours), which closely approximates an Earth day. The proposed schedule is 5 such periods on, 2 off per "week" — giving a Jovian work week of approximately 17.4 Earth days.

---

## 9. Saturn

### Saturn Mean Time (SMT)

Saturn's rotation period is more difficult to determine than Jupiter's, because its magnetic field is nearly perfectly aligned with its rotation axis (unlike Jupiter's tilted field). The historical System III value (Voyager-era Saturn Kilometric Radiation) was **10h 39m 22s**, but this is now known to track magnetospheric current periodicity rather than core rotation. The most robust modern measurement comes from **ring seismology**: Mankovich et al. (2019, *ApJ* 871:1) used density waves in Saturn's C ring (driven by internal oscillation modes) to derive **10h 33m 38s (38,018 s = 10.5606 h)** for the interior rotation. This is the value used in `planet-time.js`.

SMT zones are defined analogously to JMT: 24 zones of 15° each, referenced to the deep interior rotation rate. Zone names reference Saturn's atmospheric features, including:

- The **North Polar Hexagon**: a persistent hexagonal wave pattern in Saturn's north polar atmosphere, approximately 25,000 km across, discovered by Voyager and extensively studied by Cassini
- The **Great White Spot**: a periodic large-scale storm that erupts roughly every 30 years (one Saturnian year); last observed in 2010–2011
- The equatorial and temperate belt structure, analogous to but less vivid than Jupiter's

Saturn's polar regions feature an eye-wall storm structure at the centres of the hexagonal polar pattern. The rings (primarily composed of water ice) are in the equatorial plane and would be of significant interest for operations, but are not incorporated into the SMT zone system, which concerns the planet body itself.

The proposed Saturnian work period follows the same logic as Jupiter: 2.25 Saturnian days ≈ 23.76 Earth hours, approximating an Earth day. Five such periods on, two off.

The Mankovich ring seismology value (10h 33m 38s) is the RECOMMENDED default for scheduling applications. Implementations MAY offer a configuration option to use the System III value (10h 39m 22s) for compatibility with historical data products.

---

## 10. Uranus

### Uranus Mean Time (UMT)

Uranus is unusual in its extreme axial tilt of 97.77°. The planet rotates nearly on its side relative to the solar system's orbital plane. This means that, over the course of a Uranian year (84 Earth years), each pole spends approximately 42 years in continuous sunlight followed by 42 years in continuous darkness. The seasonal implications for any long-duration operations are extreme.

Uranus's rotation period has been substantially refined by **Lamy et al. (2025, *Nature Astronomy*)** to **17.247864 ±0.000010 hours** (17h 14m 52.3s), using Hubble Space Telescope UV auroral observations spanning 2011–2022. This is a 1,000× improvement in precision over the Voyager 2 magnetometer estimate of 17.24 ±0.01 hours. The new value is 28 seconds longer than the Voyager estimate but within its original uncertainty. Uranus rotates retrograde (axial tilt 97.77°). `planet-time.js` uses 17.2479 h.

UMT zones follow the standard 24 × 15° system. Feature naming on Uranus follows a unique IAU convention: the moons are named after characters from the works of William Shakespeare and Alexander Pope; Uranus itself and its atmospheric features take their names from Shakespeare characters and mythological figures.

Key moons that serve as reference points for Uranian system operations (though having their own separate timezone systems):
- **Miranda** — heavily varied terrain; one of the most geologically diverse small bodies known
- **Ariel** — extensive valley systems and bright plains
- **Umbriel** — dark, ancient surface
- **Titania** — largest Uranian moon; canyons and impact craters
- **Oberon** — dark crater floors, mountainous regions

Uranus's extreme tilt means that UMT zones do not correspond to any intuitive relationship with solar illumination over human-relevant timescales. UMT zones are purely geographic/location identifiers.

---

## 11. Neptune

### Neptune Mean Time (NMT)

Neptune has a sidereal rotation period of **16.11 hours**, established by Voyager 2 magnetometer measurements during its 1989 flyby — the only spacecraft to have visited the Neptunian system. Neptune's magnetic field is significantly offset from its rotation axis (by about 47°), similar to Uranus.

Neptune's most notable atmospheric feature is the **Great Dark Spot**, observed by Voyager 2 in 1989, which appeared to be a large anticyclonic storm analogous to Jupiter's Great Red Spot. However, subsequent Hubble Space Telescope observations in 1994 found that the original spot had disappeared and a new one had formed in the northern hemisphere. Neptune's atmospheric features appear to be less persistent than Jupiter's.

NMT zones use 24 × 15° segments as with all other bodies. Zone names reference atmospheric features and the system of moons, which are named after water deities and sea creatures from Greek mythology:

- **Triton**: the largest Neptunian moon (2,706 km diameter), notable for orbiting retrograde — it orbits in the opposite direction to Neptune's rotation, strongly suggesting it is a captured Kuiper Belt object. Triton will eventually spiral inward and be disrupted by tidal forces.
- **Proteus**: second-largest moon, dark and irregular
- **Nereid**: highly eccentric orbit

NMT, like UMT, is primarily a location-reference system given the long-duration nature of any Neptune missions.

---

## 12. Design Philosophy

### Consistency

All interplanetary timezone systems in InterPlanet.live use the same underlying geometric principle: **24 zones of 15° longitude each**, with zone offset expressed as an integer number of local planet-hours from the prime meridian. This consistency means that anyone familiar with the terrestrial UTC system can immediately understand the offset notation of any planetary system. AMT+3 means "three Martian sol-hours east of the Martian prime meridian," exactly as UTC+3 means three Earth hours east of Greenwich.

### IAU Standards

Prime meridians follow IAU Working Group on Cartographic Coordinates and Rotational Elements (WGCCRE) definitions wherever they exist. These are the internationally recognised scientific standards, updated periodically (most recent applicable reports: 2009, 2015). Where the IAU standard is a specific feature (Airy-0 for Mars, Hun Kal for Mercury, Ariadne for Venus, Sinus Medii for the Moon), that feature anchors the prime meridian. This grounds the coordinate system in observable reality rather than arbitrary convention.

### Human Biology First

The most important design decision in this system is the explicit separation of *location reference* from *work scheduling* for bodies with solar days incompatible with human circadian rhythms.

On Mars, the sol is close enough to 24 hours that sol-synchronised scheduling is biologically reasonable and operationally practical. Mars crews work Mars time.

On the Moon, Mercury, and Venus, the solar day is days or months long. Attempting to schedule human activities around the local solar day would be biologically harmful and operationally absurd. Crews on these bodies work Earth-clock shifts. The timezone zone designations (LMT, MMT, VMT) tell you *where* something is on the planet — not *when* to have meetings.

For the outer gas giants, the question is largely academic for near-term operations, but the same principle applies: zone designations are for location, and any actual human operations would follow Earth-based scheduling.

### Relativistic Time Dilation

Relativistic time dilation on Mars (~20 μs/day faster than Earth's surface due to weaker gravitational potential) and on other bodies is negligible for scheduling purposes and is not corrected for in this specification. Lunar time dilation (~56 μs/day) is addressed by the emerging LTC/TCL standard.

### Zone Names as Geographic Anchors

Zone names are chosen to reflect the most significant and recognisable geographic or atmospheric feature within that longitude band. This serves both a practical purpose (engineers and mission planners can immediately relate a zone name to a location they know from maps) and a cultural one (the names celebrate the diversity of planetary nomenclature, which draws on mythologies, classical languages, and the history of science and art from many cultures).

### Extensibility

The `planet-time.js` library implements all of the above systems in a consistent way that allows extension to additional bodies (dwarf planets, large asteroids, major moons) using the same data structure. As humanity's presence in the solar system grows, the system is designed to accommodate new worlds without requiring architectural changes.

---

*This document is maintained as part of the Sky Colours / InterPlanet.live project. Corrections, additions, and proposals for additional bodies are welcomed via the project repository.*

*All feature names used in zone designations are as listed in the IAU Planetary Nomenclature database (planetarynames.wr.usgs.gov) at time of writing. Feature names are subject to ongoing IAU review and update.*
