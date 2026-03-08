# planet-time.js — API Reference

*Version 1.9.0 — March 2026*

---

## Overview

`planet-time.js` is a zero-dependency JavaScript library for interplanetary time calculations. Given any Earth UTC date, it can compute the local time on any planet in the solar system, determine whether crews at a given location are currently in work hours, find meeting windows that suit participants on multiple worlds, and calculate the communications latency imposed by the finite speed of light.

**Supported environments:** Browser (`window.PlanetTime`) and Node.js (`require` / CommonJS).

**Dependencies:** None. The library uses only JavaScript built-ins and hardcoded astronomical constants. No network requests are made.

**Accuracy:** Simplified Keplerian orbital mechanics give arc-minute positional accuracy over a span of decades, which is sufficient for scheduling purposes. Mars time is computed using the Allison & McEwen (2000) formula. See [Accuracy Notes](#accuracy-notes) for details.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 [RFC 2119] [RFC 8174] when, and only when, they appear in all capitals, as shown here. Sections containing RFC 2119 keywords are normative; all other text is informative.

---

## Time Scales

This library accepts and returns civil timestamps in UTC (JavaScript `Date` objects).

Where a planetary algorithm requires Terrestrial Time (TT):
- TAI − UTC is obtained from the internal `LEAP_SECONDS` table (IERS Bulletin C is the authority).
- TT = TAI + 32.184 seconds (exact, by definition).
- Therefore TT − UTC = (TAI − UTC) + 32.184 seconds.

Defined quantities:
- **ΔUT1 = UT1 − UTC**: requires external Earth orientation data (IERS); not computed by this library.
- **ΔT = TT − UT1**: varies over time; relevant to high-precision astronomical work. Not computed.
- **Current UTC − TAI**: −37 s since 2017-01-01. CGPM Resolution 4 (2022) and ITU WRC-23 (2023) direct a planned change to the UT1−UTC tolerance by or before 2035; implementation details remain pending standardisation.

The Mars time formula (Allison & McEwen 2000 / NASA Mars24) explicitly uses JDTT. The library derives JDTT from the input UTC timestamp using the leap-second table.

### Epoch Compatibility

This library uses JavaScript `Date` objects (milliseconds since 1970-01-01T00:00:00Z) internally. External systems use different epochs:

| System | Epoch | Offset from Unix epoch |
|--------|-------|------------------------|
| CCSDS CUC (CCSDS 301.0-B-4) | 1958-01-01 TAI | −378,691,200 s |
| DTN Bundle Protocol (RFC 9171) | 2000-01-01T00:00:00Z | +946,684,800 s |
| Julian Date (JD) | 4713 BC Jan 1 12:00 UT | −210,866,760,000 s (approx.) |
| Mars Sol Date (MSD) | ~1873-12-29T12:00:00Z TT | varies by definition |

Conversion between these epochs is not provided by this library but MAY be added in a future version. The offsets above are approximate; precise conversion MUST account for leap seconds when converting between UTC-based and TAI-based epochs.

---

## Table of Contents

1. [Installation](#installation)
2. [Quick Start](#quick-start)
3. [Data Structures](#data-structures)
   - [Planet Keys](#planet-keys)
   - [PlanetTime Object](#planettime-object)
   - [Zone Object](#zone-object)
4. [Core Functions](#core-functions)
   - [getPlanetTime](#getplanettime)
   - [earthToPlanetTime](#earthtoplanettime)
   - [nextPlanetTime](#nextplanettime)
   - [formatPlanetTime](#formatplanettime)
   - [formatPlanetTimeISO](#formatplanettimeiso)
   - [getMTC](#getmtc)
   - [getMarsTimeAtOffset](#getmarstimeatoffset)
   - [getPlanetHourlySchedule](#getplanethourlyschedule)
   - [planetTimezoneOffsetMs](#planettimezoneoffsetms)
5. [Orbital Mechanics](#orbital-mechanics)
   - [planetHelioXY](#planethelioXY)
   - [bodyDistance](#bodydistance)
   - [lightTravelSeconds](#lighttravelseconds)
   - [formatLightTime](#formatlighttime)
   - [checkLineOfSight](#checklineofsight)
   - [lowerQuartileLightTime](#lowerquartilighttime)
   - [nextFavourableLightTime](#nextfavourablelighttime)
6. [Meeting Windows](#meeting-windows)
   - [findMeetingWindows](#findmeetingwindows)
   - [findNextMeetingSlot](#findnextmeetingslot)
   - [calculateFairnessScore](#calculatefairnessscore)
7. [SDK Aliases](#sdk-aliases)
   - [convertUTCToPlanet](#convertutctoplanet)
   - [convertPlanetToUTC](#convertplanettoutc)
   - [calculateLightDelay](#calculatelightdelay)
8. [Constants](#constants)
9. [Zone Data](#zone-data)
   - [MARS_ZONES](#mars_zones)
   - [MOON_ZONES](#moon_zones)
   - [MERCURY_ZONES](#mercury_zones)
   - [VENUS_ZONES](#venus_zones)
   - [PLANET_ZONES](#planet_zones)
10. [Extending / Custom Bodies](#extending--custom-bodies)
11. [Planetary Datetime Formats](#planetary-datetime-formats)
12. [Accuracy Notes](#accuracy-notes)

---

## Installation

### Browser

Include the script tag before any code that uses it. The library exposes itself as `window.PlanetTime`.

```html
<script src="planet-time.js"></script>
<script>
  const PT = window.PlanetTime;

  const mars = PT.getPlanetTime('mars', new Date());
  console.log(PT.formatPlanetTime(mars));
  // → "Mars ♂  14:32  Wed  Sol 221 of Year 43  [🟢 work]"
</script>
```

For ES module environments, if you have converted or bundled the library:

```html
<script type="module">
  import PT from './planet-time.js';
  const mars = PT.getPlanetTime('mars', new Date());
</script>
```

### Node.js

```js
const PT = require('./planet-time.js');

const mars = PT.getPlanetTime('mars', new Date());
console.log(PT.formatPlanetTime(mars));
// → "Mars ♂  14:32  Wed  Sol 221 of Year 43  [🟢 work]"
```

---

## Quick Start

A brief tour of the most commonly used functions:

```js
const PT = require('./planet-time.js');

// --- Local times ---

// What time is it on Mars right now?
const mars = PT.getPlanetTime('mars', new Date());
console.log(
  `Sol ${mars.solInfo.solInYear}, ` +
  `${String(mars.hour).padStart(2, '0')}:` +
  `${String(mars.minute).padStart(2, '0')} AMT`
);
// → Sol 221, 14:32 AMT

// What time is it at a specific Martian timezone (Olympus Mons, AMT-9)?
const olympus = PT.getPlanetTime('mars', new Date(), -9);
console.log(`Olympus Mons local: ${olympus.timeString}`);
// → 05:32

// Is it work hours on Jupiter right now?
const jup = PT.getPlanetTime('jupiter', new Date());
console.log(jup.isWorkHour ? 'Work period active' : 'Rest period');

// --- Communications ---

// How long does a signal take to reach Mars from Earth right now?
const secs = PT.lightTravelSeconds('earth', 'mars', new Date());
console.log(`One-way latency: ${PT.formatLightTime(secs)}`);
// → One-way latency: 4.3min

// Is Earth currently in solar conjunction with Mars? (i.e. is the Sun in the way?)
const los = PT.checkLineOfSight('earth', 'mars', new Date());
if (!los.clear) {
  console.log(`Signal blocked: ${los.message}`);
}

// When is the next time Earth–Mars distance will be low enough (< 1200 s)?
const nextClose = PT.nextFavourableLightTime('earth', 'mars', 1200);
console.log(`Next good window: ${nextClose.toDateString()}`);

// --- Meetings ---

// Find meeting windows in the next 7 Earth days that work for Earth and Mars (AMT+4):
const windows = PT.findMeetingWindows('earth', 'mars', 7, new Date());
windows.slice(0, 3).forEach(w => {
  console.log(
    `${new Date(w.startMs).toUTCString()} — ` +
    `duration: ${Math.round(w.durationMinutes)} min`
  );
});
```

---

## Data Structures

### Planet Keys

Planet keys are lowercase strings. Pass them as the first argument to most functions.

| Key | Planet | Notes |
|-----|--------|-------|
| `'mercury'` | Mercury | Earth-clock scheduling (MMT = location reference only) |
| `'venus'` | Venus | Earth-clock scheduling (VMT = location reference only) |
| `'earth'` | Earth | Uses UTC |
| `'moon'` | Moon | Orbital position same as Earth for heliocentric calculations |
| `'mars'` | Mars | Full AMT zone system; sol-based scheduling |
| `'jupiter'` | Jupiter | System III reference |
| `'saturn'` | Saturn | Deep interior rotation (Mankovich, Marley, Fortney & Mozshovitz 2023) |
| `'uranus'` | Uranus | Lamy et al. 2025 period |
| `'neptune'` | Neptune | Voyager 2 period |

> **Note on `'moon'`:** The Moon is tidally locked; work schedules run on Earth time. For `getPlanetTime` and `getPlanetHourlySchedule`, `'moon'` is internally redirected to `'earth'`. For heliocentric distance calculations, `'moon'` uses Earth's orbital position.

---

### PlanetTime Object

The object returned by `getPlanetTime` and `earthToPlanetTime`.

```ts
{
  // Identity
  planet: string,           // Planet display name, e.g. 'Mars'
  symbol: string,           // Unicode symbol, e.g. '♂'

  // Decoded time-of-day
  localHour: number,        // Fractional hour of the local planet day, 0–24
  hour: number,             // Integer hour (floor of localHour), 0–23
  minute: number,           // Integer minute, 0–59
  second: number,           // Integer second, 0–59
  dayFraction: number,      // Fractional part of the current planet day (0–1)

  // Calendar
  dayNumber: number,        // Total planet days elapsed since epoch
  dayInYear: number,        // Day-of-year (integer, 0-based)
  yearNumber: number,       // Planet year number since epoch (integer)
  solInfo: null | {         // Mars only; null for all other planets
    solInYear: number,      // Sol within the Mars year (0-based)
    solsPerYear: number,    // Approximate sols per Mars year
  },

  // Work-period tracking
  periodInWeek: number,     // Index of the current period within the planet week (0-based)
  isWorkPeriod: boolean,    // true if this is a designated work period (not a rest day/period)
  isWorkHour: boolean,      // true if the current hour is within work hours

  // Day name (Earth day names used for the planet-week cycle)
  dowName: string,          // 'Monday', 'Tuesday', … 'Sunday'
  dowShort: string,         // 'Mon', 'Tue', … 'Sun'

  // Work schedule parameters (from PLANETS definition)
  solarDayMs: number,       // Duration of one planet solar day in milliseconds
  daysPerPeriod: number,    // Planet days per work period (e.g. 2.5 for Jupiter)
  periodsPerWeek: number,   // Total periods in one planet week (always 7)
  workPeriodsPerWeek: number, // Work periods per week (always 5)

  // Formatted strings
  timeString: string,       // 'HH:MM' (zero-padded)
  timeStringFull: string,   // 'HH:MM:SS' (zero-padded)
}
```

---

### Zone Object

The structure used in zone arrays (`MARS_ZONES`, `MOON_ZONES`, etc.).

```ts
{
  id: string,           // Zone identifier, e.g. 'AMT+3', 'LMT-2', 'MMT+11', 'AMT+0'
  name: string,         // Human-readable zone name, e.g. 'Hellas Planitia'
  offsetHours: number,  // Integer offset in planet-hours from prime meridian (-11 to +12)
}
```

---

## Core Functions

### `getPlanetTime`

```ts
getPlanetTime(planetKey: string, date?: Date, tzOffsetHours?: number): PlanetTime
```

Computes the local time on the specified planet at the given UTC date, optionally shifted by a timezone offset.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `planetKey` | string | Yes | One of the planet keys listed above |
| `date` | Date | No | Any JavaScript `Date` object (interpreted as UTC). Defaults to `new Date()`. |
| `tzOffsetHours` | number | No | Timezone offset in local planet-hours from the prime meridian (-11 to +12). Defaults to 0. |

**Returns:** `PlanetTime` object.

**Throws:** `Error` if `planetKey` is not recognised.

---

### `earthToPlanetTime`

```ts
earthToPlanetTime(planetKey: string, date?: Date, tzOffsetHours?: number): PlanetTime
```

Alias for `getPlanetTime`. Identical signature and behaviour.

---

### `nextPlanetTime`

```ts
nextPlanetTime(planetKey: string, targetHour: number, targetMinute?: number, fromDate?: Date): Date
```

Find the next Earth `Date` when the specified planet's local time (at the prime meridian) reaches the given hour and minute.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `planetKey` | string | Yes | Planet key |
| `targetHour` | number | Yes | Local planet hour to find (0–23) |
| `targetMinute` | number | No | Local planet minute (0–59). Defaults to 0. |
| `fromDate` | Date | No | Search start. Defaults to `new Date()`. |

**Returns:** `Date` (Earth UTC).

---

### `formatPlanetTime`

```ts
formatPlanetTime(pt: PlanetTime): string
```

Returns a short human-readable string summarising the planet time result.

**Example output:**
- Mars: `"Mars ♂  14:32  Wed  Sol 221 of Year 43  [🟢 work]"`
- Jupiter: `"Jupiter ♃  08:15  Mon  Day 12 of Year 7  [🟢 work]"`
- Rest period: `"Saturn ♄  03:44  Sat  Day 5 of Year 2  [🔴 rest]"`
- Off-shift: `"Mars ♂  21:10  Fri  Sol 220 of Year 43  [🟡 off-shift]"`

---

### `formatPlanetTimeISO`

```ts
formatPlanetTimeISO(
  pt: PlanetTime,
  planetKey: string,
  offsetHours: number,
  earthDate: Date
): string
```

Returns a machine-parseable planetary timestamp per the format defined in `DRAFT-STANDARD.md` §5.2:

```
{planet-date}T{HH}:{MM}:{SS}/{utc-ref}[{Body}/{TZ-id}]
```

Example output:
- Mars: `"MY43-221T14:32:07/2026-02-19T09:15:23Z[Mars/AMT+4]"`
- Moon: `"2026-02-19T14:32:07/2026-02-19T14:32:07Z[Moon/LMT+1]"`

---

### `getMTC`

```ts
getMTC(date?: Date): { sol: number, hour: number, minute: number, second: number, mtcString: string }
```

Computes Mars Coordinated Time (MTC) — the Martian equivalent of UTC — at the prime meridian (Airy-0).

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `date` | Date | No | UTC instant to convert. Defaults to `new Date()`. |

**Returns:**

| Field | Type | Description |
|-------|------|-------------|
| `sol` | number | Total Martian sols elapsed since the MY0 epoch (24 May 1953) |
| `hour` | number | MTC hour (0–23) |
| `minute` | number | MTC minute (0–59) |
| `second` | number | MTC second (0–59) |
| `mtcString` | string | `'HH:MM'` formatted string |

---

### `getMarsTimeAtOffset`

```ts
getMarsTimeAtOffset(date: Date, offsetHours: number): {
  sol: number,
  hour: number,
  minute: number,
  second: number,
  timeString: string,
  offsetHours: number
}
```

Computes the local Mars time at a given AMT timezone offset.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `date` | Date | Yes | UTC instant |
| `offsetHours` | number | Yes | AMT timezone offset in Mars local hours (-11 to +12) |

**Returns:**

| Field | Type | Description |
|-------|------|-------------|
| `sol` | number | Local sol number (MTC sol ± 1 depending on offset) |
| `hour` | number | Local hour (0–23) |
| `minute` | number | Local minute (0–59) |
| `second` | number | Local second (0–59) |
| `timeString` | string | `'HH:MM'` formatted string |
| `offsetHours` | number | The offset applied |

---

### `getPlanetHourlySchedule`

```ts
getPlanetHourlySchedule(planetKey: string, now?: Date): Array<{
  localHour: number,
  isWork: boolean,
  earthTimeMs: number
}>
```

Returns an array of 24 objects describing the work/non-work status for each hour of the planet's current solar day.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `planetKey` | string | Yes | Planet key |
| `now` | Date | No | Reference UTC instant. Defaults to `new Date()`. |

**Returns:** Array of 24 objects, one per local planet hour:

| Field | Type | Description |
|-------|------|-------------|
| `localHour` | number | Local hour index (0–23) |
| `isWork` | boolean | `true` if this hour is a work hour |
| `earthTimeMs` | number | Earth UTC timestamp (ms) corresponding to the start of this local hour |

---

### `planetTimezoneOffsetMs`

```ts
planetTimezoneOffsetMs(planetKey: string, offsetLocalHours: number): number
```

Converts a timezone offset expressed in local planet-hours to milliseconds.

**Returns:** Number of milliseconds corresponding to `offsetLocalHours` × (solar day / 24).

---

## Orbital Mechanics

### `planetHelioXY`

```ts
planetHelioXY(planetKey: string, date: Date): { x: number, y: number, r: number, lon: number }
```

Heliocentric ecliptic x/y position of a planet and its distance from the Sun (AU), computed using simplified Keplerian elements (Meeus Table 31.a).

**Returns:**

| Field | Type | Description |
|-------|------|-------------|
| `x` | number | Heliocentric x position (AU, ecliptic plane) |
| `y` | number | Heliocentric y position (AU, ecliptic plane) |
| `r` | number | Distance from the Sun (AU) |
| `lon` | number | Heliocentric ecliptic longitude (radians) |

> **Note on `'moon'`:** For heliocentric calculations, `'moon'` is treated as `'earth'`.

---

### `bodyDistance`

```ts
bodyDistance(keyA: string, keyB: string, date: Date): number
```

Straight-line distance between two solar system bodies in AU.

---

### `lightTravelSeconds`

```ts
lightTravelSeconds(keyA: string, keyB: string, date: Date): number
```

One-way light travel time between two bodies in seconds.

---

### `formatLightTime`

```ts
formatLightTime(seconds: number): string
```

Formats a duration in seconds as a human-readable string.

**Examples:**
- `formatLightTime(0.0005)` → `'<1ms'`
- `formatLightTime(0.5)` → `'500ms'`
- `formatLightTime(45)` → `'45.0s'`
- `formatLightTime(258)` → `'4.3min'`
- `formatLightTime(14520)` → `'4h 2m'`

---

### `checkLineOfSight`

```ts
checkLineOfSight(keyA: string, keyB: string, date: Date): {
  clear: boolean,
  blocked: boolean,
  degraded: boolean,
  closestSunAU: number,
  elongDeg: number,
  message: string
}
```

Checks whether the Sun lies close to the line of sight between two bodies, indicating solar conjunction or degraded communications.

**Returns:**

| Field | Type | Description |
|-------|------|-------------|
| `clear` | boolean | `true` if neither blocked nor degraded |
| `blocked` | boolean | `true` if line of sight passes within 0.01 AU of the Sun |
| `degraded` | boolean | `true` if line of sight passes within 0.05 AU (but not 0.01 AU) of the Sun |
| `closestSunAU` | number | Closest approach of the line segment to the Sun (AU) |
| `elongDeg` | number | Solar elongation angle at body A (degrees) |
| `message` | string | Human-readable status description |

---

### `lowerQuartileLightTime`

```ts
lowerQuartileLightTime(keyA: string, keyB: string, date?: Date): number
```

Approximate 25th-percentile one-way light travel time between two bodies (seconds), sampled over one Earth year from the given date. This is a useful target for "favourable transmission window" planning.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `keyA` | string | Yes | First body key |
| `keyB` | string | Yes | Second body key |
| `date` | Date | No | Start of the one-year sampling window. Defaults to `new Date()`. |

**Returns:** Seconds (number).

---

### `nextFavourableLightTime`

```ts
nextFavourableLightTime(keyA: string, keyB: string, thresholdSeconds: number, fromDate?: Date): Date | null
```

Finds the next date at which the one-way light travel time from `keyA` to `keyB` drops at or below `thresholdSeconds`. Scans forward in 6-hour steps for up to 2 years.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `keyA` | string | Yes | First body key |
| `keyB` | string | Yes | Second body key |
| `thresholdSeconds` | number | Yes | Target maximum one-way light time (seconds) |
| `fromDate` | Date | No | Search start date. Defaults to `new Date()`. |

**Returns:** `Date` if a qualifying instant is found within 2 years, or `null` if none is found.

---

## Meeting Windows

### `findMeetingWindows`

```ts
findMeetingWindows(
  planetA: string,
  planetB: string,
  earthDays?: number,
  start?: Date
): Array<{ startMs: number, endMs: number, durationMinutes: number }>
```

Scans a time range in 15-minute steps and returns all windows during which both planets are simultaneously in work hours.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `planetA` | string | Yes | First planet key |
| `planetB` | string | Yes | Second planet key |
| `earthDays` | number | No | Number of Earth days to scan. Defaults to 7. |
| `start` | Date | No | Start of scan. Defaults to `new Date()`. |

**Returns:** Array of overlap windows:

| Field | Type | Description |
|-------|------|-------------|
| `startMs` | number | Window start (UTC milliseconds) |
| `endMs` | number | Window end (UTC milliseconds) |
| `durationMinutes` | number | Window duration in minutes |

---

### `findNextMeetingSlot`

```ts
findNextMeetingSlot(locations: Array<LocationDescriptor>, opts?: Options): Result
```

Find the next available meeting slot(s) across multiple locations — Earth cities and/or planets. Designed for AI-agent use: returns ranked overlap windows with per-location local times.

**LocationDescriptor** (one of):

```ts
// Earth city location
{
  type: 'earth',
  tz: string,            // IANA timezone, e.g. 'America/New_York'
  workWeek?: string,     // 'mon-fri' | 'sun-thu' | 'sat-thu' | 'mon-sat'. Default: 'mon-fri'
  workStart?: number,    // Work start hour (0–23). Default: 9
  workEnd?: number,      // Work end hour (0–23). Default: 17
  label?: string,        // Display name
}

// Planet location
{
  type: 'planet',
  planet: string,        // Planet key, e.g. 'mars'
  tzOffset?: number,     // Planet local hours from prime meridian. Default: 0
  label?: string,        // Display name
}
```

**Options:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `from` | Date | `new Date()` | UTC start of search window |
| `maxDays` | number | 14 | Maximum Earth days to scan |
| `stepMinutes` | number | 30 | Time resolution in minutes |
| `minDurationMinutes` | number | 30 | Minimum acceptable overlap duration |
| `maxOptions` | number | 3 | Maximum number of slot options to return |

**Returns:**

```ts
{
  found: boolean,
  message: string,
  searchedDays: number,
  slots: Array<{
    startIso: string,          // UTC ISO-8601 start
    endIso: string,            // UTC ISO-8601 end
    startMs: number,
    endMs: number,
    durationMinutes: number,
    localTimes: Array<{
      label: string,
      timeStr: string,         // Human-readable local time + weekday at slot midpoint
      isWorkHour: boolean,
    }>,
  }>,
}
```

---

### `calculateFairnessScore`

```ts
calculateFairnessScore(
  meetingSeries: Array<Date | number | string>,
  participants: Array<string | { tz: string, workWeek?: string }>
): { overall: number, perParticipant: Array<object>, fairness: 'good' | 'ok' | 'poor' }
```

Calculate scheduling fairness across a recurring meeting series by measuring how evenly the off-hours burden is distributed among participants.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `meetingSeries` | Array | UTC meeting instants (Date objects, ms timestamps, or ISO strings) |
| `participants` | Array | Participant timezones: IANA tz strings, or objects with `tz` and optional `workWeek` |

**Returns:**

| Field | Type | Description |
|-------|------|-------------|
| `overall` | number | Fairness score 0–100 (100 = perfectly fair) |
| `perParticipant` | Array | Per-participant breakdown: `{ index, tz, offHourCount, pct }` |
| `fairness` | string | `'good'` (≥75), `'ok'` (≥40), or `'poor'` (<40) |

---

## SDK Aliases

### `convertUTCToPlanet`

```ts
convertUTCToPlanet(utcTimestamp: number | Date, planet: string, longitude?: number): PlanetTime
```

Convert a UTC timestamp to planetary time at a given surface longitude. The longitude (degrees) is rounded to the nearest 15° to derive a timezone offset in local hours.

---

### `convertPlanetToUTC`

```ts
convertPlanetToUTC(planetTimestamp: number | string | Date): number
```

Return the UTC millisecond value underlying any Date-like value. Thin wrapper around `new Date(planetTimestamp).getTime()`.

---

### `calculateLightDelay`

```ts
calculateLightDelay(bodyA: string, bodyB: string, date: number | string | Date): number
```

Light-travel delay in seconds between two named bodies at a given date. Alias for `lightTravelSeconds` with automatic Date coercion.

---

## Constants

### Scalar Constants

| Export | Value | Description |
|--------|-------|-------------|
| `VERSION` | `'1.9.0'` | Library version (semver) |
| `C_KMS` | `299792.458` | Speed of light, km/s (exact SI definition) |
| `AU_KM` | `149597870.7` | 1 AU in kilometres (IAU 2012 Resolution B2, exact) |
| `AU_SECONDS` | `≈ 499.0048` | Light travel time for 1 AU, seconds (derived: `AU_KM / C_KMS`) |
| `EARTH_DAY_MS` | `86400000` | Milliseconds in one Earth day |
| `MARS_SOL_MS` | `88775244` | Milliseconds in one Martian sol (Allison & McEwen 2000) |
| `MARS_EPOCH_MS` | (see note) | Unix ms timestamp of MY0 epoch (24 May 1953 09:03:58.464 UTC) |
| `J2000_MS` | (see note) | Unix ms timestamp of J2000.0 epoch (2000-01-01T12:00:00Z) |
| `J2000_JD` | `2451545.0` | Julian Day number of J2000.0 |

### `PLANETS`

Object containing one entry per planet key. Each entry has:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Display name |
| `symbol` | string | Unicode symbol |
| `color` | string | Suggested hex colour |
| `solarDayMs` | number | Solar day duration (ms) |
| `siderealYrMs` | number | Sidereal year duration (ms) |
| `daysPerPeriod` | number | Planet days per work period |
| `periodsPerWeek` | number | Total periods per week (7) |
| `workPeriodsPerWeek` | number | Work periods per week (5) |
| `workHoursStart` | number | Work start (local hour, 0–23) |
| `workHoursEnd` | number | Work end (local hour, 0–23) |
| `localHourMs` | number | Duration of one local hour (ms) — computed getter |
| `epochMs` | number | Reference epoch (Unix ms) |
| `notes` | string | Scheduling convention notes |

**Saturn note:** `solarDayMs` uses `10.578 * 3600000` (≈ 10 h 34 m 42 s), the 2023 refined ring-seismology value from Mankovich, Marley, Fortney & Mozshovitz (2023). The older Mankovich et al. (2019) value was 10.5606 h.

### `CONSTANTS`

Object of annotated astronomical constants with source metadata. Each entry:

```ts
{
  value: number,
  unit: string,
  source: string,
  exact?: boolean,
  revision?: string,
  uncertainty?: string | null,
  disputeNote?: string,
}
```

Keys: `C_KMS`, `AU_KM`, `AU_SECONDS`, `MARS_SOL_S`, `MERCURY_SOLAR_DAY_D`, `VENUS_SOLAR_DAY_D`, `JUPITER_ROTATION_H`, `SATURN_ROTATION_H`, `URANUS_ROTATION_H`, `NEPTUNE_ROTATION_H`.

`SATURN_ROTATION_H.value` is `10.578` h (Mankovich, Marley, Fortney & Mozshovitz 2023).

### `CONSTANTS_EPOCH`

ISO date string (`'2025-06-01'`) indicating when the constants were last reviewed. Consumers MAY warn if this date is stale.

### `ZONE_PREFIXES`

Object mapping planet keys to their 3-letter timezone zone prefix:

```ts
{
  mars: 'AMT', moon: 'LMT', mercury: 'MMT', venus: 'VMT',
  jupiter: 'JMT', saturn: 'SMT', uranus: 'UMT', neptune: 'NMT',
}
```

---

## Zone Data

### `MARS_ZONES`

Array of 24 Zone objects for the Airy Mean Time (AMT) system. Zones cover AMT−11 through AMT+12 (antimeridian). Prime meridian at Sinus Meridiani / Airy-0 crater.

### `MOON_ZONES`

Array of 24 Zone objects for the Lunar Mean Time (LMT) system. Prime meridian at Sinus Medii.

### `MERCURY_ZONES`

Array of 24 Zone objects for the Mercury Mean Time (MMT) system. Prime meridian at Hun Kal crater (IAU 2009).

### `VENUS_ZONES`

Array of 24 Zone objects for the Venus Mean Time (VMT) system. Prime meridian at Ariadne Crater.

### `PLANET_ZONES`

Object mapping planet keys to their zone arrays:

```ts
PT.PLANET_ZONES: {
  moon:    Zone[],   // 24 LMT zones
  mercury: Zone[],   // 24 MMT zones
  venus:   Zone[],   // 24 VMT zones
  mars:    Zone[],   // 24 AMT zones
  jupiter: Zone[],   // 24 JMT zones
  saturn:  Zone[],   // 24 SMT zones
  uranus:  Zone[],   // 24 UMT zones
  neptune: Zone[],   // 24 NMT zones
}
```

Individual arrays are also exported: `JUPITER_ZONES`, `SATURN_ZONES`, `URANUS_ZONES`, `NEPTUNE_ZONES`.

---

## Extending / Custom Bodies

Add custom bodies to `PT.PLANETS` to enable `getPlanetTime`, `bodyDistance`, and `lightTravelSeconds` to work with them. The minimum required fields are:

```js
PT.PLANETS['ceres'] = {
  name: 'Ceres',
  symbol: '⚳',
  solarDayMs: 32667 * 1000,           // ~9.07 Earth hours
  siderealYrMs: 1681.63 * 86400000,   // ~4.6 Earth years
  daysPerPeriod: 1,
  periodsPerWeek: 7,
  workPeriodsPerWeek: 5,
  workHoursStart: 8,
  workHoursEnd: 16,
  shiftHours: 8,
  epochMs: Date.UTC(2000, 0, 1, 12, 0, 0),
  notes: 'Custom body.',
};

// Also add orbital elements if you need distance/light-time calculations:
PT.ORBITAL_ELEMENTS['ceres'] = {
  L0: 291.412, dL: 214.459, om0: 72.522, e0: 0.0760, a: 2.7675,
};
```

---

## Planetary Datetime Formats

Three levels of output are available:

| Format | Function | Example output |
|---|---|---|
| Human-readable | `formatPlanetTime(pt)` | `Mars ♂  14:32  Wed  Sol 221 of Year 43  [🟢 work]` |
| Short string | `pt.timeString` | `14:32` |
| Full string | `pt.timeStringFull` | `14:32:07` |
| ISO / machine | `formatPlanetTimeISO(pt, key, offset, earthDate)` | `MY43-221T14:32:07/2026-02-19T09:15:23Z[Mars/AMT+4]` |

---

## Accuracy Notes

### Orbital Mechanics

Simplified Keplerian elements from Meeus *Astronomical Algorithms* 2nd ed., Table 31.a. Valid for approximately 1800–2050. Positional accuracy: arc-minutes over decades. Distance accuracy: better than 0.5% for Earth–Mars under typical conditions.

### Mars Time

Allison & McEwen (2000) formula; sub-second accuracy. Sol = 88,775.244 seconds. Mars Year epoch: MY0 Sol 0 = 09:03:58.464 UTC, 24 May 1953 (Piqueux backward extension of Clancy et al. MY1 convention). Prime meridian anchored to Airy-0 / Viking Lander 1 (IAU WGCCRE 2018).

### Saturn Rotation

The library uses `10.578 h` (Mankovich, Marley, Fortney & Mozshovitz 2023 ring-seismology refinement). The NASA Planetary Fact Sheet and many legacy references still cite the Voyager System III value (~10.656 h), which tracks magnetospheric current periodicity rather than core rotation.

### Leap Seconds

Current offset: UTC − TAI = −37 s since 2017-01-01. After the planned 2035 change, the leap-second table may no longer grow.

---

## REST HTTP API

> **Status:** Planned. Not yet deployed.

### `GET /api/time/planet`

Compute the current local time on any planet or moon.

**Query parameters:** `body`, `at` (ISO 8601, optional), `tz_offset` (optional)

**Response:**
```json
{
  "body": "mars",
  "at_utc": "2026-02-27T14:00:00Z",
  "local_time": "14:23",
  "sol": 47832,
  "is_work_hour": true,
  "light_minutes": 14.2,
  "conjunction_in_days": 182
}
```

### `GET /api/time/distance`

One-way light travel time between two bodies.

**Query parameters:** `from`, `to`, `at` (optional)

### `POST /api/time/windows`

Find overlapping work-hour windows across multiple locations. Equivalent to `findMeetingWindows()`.

### `POST /api/ltx/session`

Create or validate an LTX SessionPlan. Returns a canonical plan with a computed `planId` (SHA-256).

### `GET /api/ltx/session/{plan_id}`

Retrieve a previously created SessionPlan.

### `POST /api/ltx/session/{plan_id}/ics`

Generate an LTX-extended `.ics` iCalendar file (RFC 5545 + LTX-* extensions).

### `POST /api/ltx/feedback`

Submit post-meeting telemetry for ML-based scheduling optimisation.

---

*planet-time.js is part of the InterPlanet project.*
*Report issues and contribute at the project repository.*
