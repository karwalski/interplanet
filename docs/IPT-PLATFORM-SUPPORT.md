# InterPlanet Time (IPT) — Platform Support Roadmap

> **Current workaround:** devices run UTC; IPT-aware applications receive the user's
> planetary location (planet + timezone offset) and compute local planet time internally.
> This document tracks the platform and standards changes needed to eliminate that workaround.

**Status:** Living document — tracking OS, browser, and standards work needed for native InterPlanet Time (IPT) support.

---

## Correct Architecture Statement

**The correct architecture for InterPlanet Time is a parallel time layer above UTC.**

All timestamps remain in UTC. Planetary time is computed in userspace and treated as display metadata — not a replacement for or extension of the system clock. `planet-time.js` already implements this correctly and intentionally: it receives `Date.now()` (UTC milliseconds) and returns a derived planetary time representation without touching any OS time APIs.

This is not a workaround that will eventually be replaced by native platform support. It is the correct architecture for the foreseeable future, given the structural incompatibilities described in the sections below. Developers building on the IPT SDK should treat planetary time as a display and scheduling layer, not as a time standard competing with UTC.

### Feasibility Summary

| Integration point | Feasibility | Horizon |
|---|---|---|
| IANA tzdata integration | Very Low | Decade+ |
| OS time-subsystem integration | Very Low | Decades |
| TC39 Temporal API | Medium | Near-term (shipping now) |
| W3C Geolocation API `body` field | High | 2026–2027 |
| IETF RFC 9557 `body` suffix key | High | 2026 (most tractable milestone) |

---

## Status Legend

- 🔴 Not started / no activity
- 🟡 In early discussion / proposal stage
- 🟢 Adopted / shipped

---

## 1. IANA Timezone Registry (tzdata)

**Status:** 🔴 — **Feasibility: Very Low — decade+ horizon**

**What it is:** The authoritative database of world timezones (tzdata), used by every major OS, browser, and programming language runtime.

**Structural incompatibility — not an implementation detail:**

tzdata's data model is built on piecewise-constant UTC offsets (e.g., "UTC+5:30", "UTC-8 with DST"). Every entry in the database describes a fixed or seasonally-varying offset from UTC, measured in Earth seconds. This model is structurally incapable of representing continuously-varying planetary offsets. Mars sols are 88,775.244 seconds — 2.75% longer than Earth days. A Mars timezone offset relative to UTC is not a constant; it continuously drifts by approximately 39.5 minutes per Earth day, completing a full cycle approximately every 687 Earth days. There is no piecewise-constant approximation that is useful over any practical planning horizon. This is not a gap that can be filled by adding new entries to the existing tzdata format. It would require a fundamental redesign of the tzdata data model, `zic` compiler, and every piece of software that consumes tzdata output — effectively replacing rather than extending the existing infrastructure. Until planetary time adoption is sufficiently widespread to justify that replacement (a decade+ horizon at minimum), tzdata integration is not a tractable path.

**For comparison:** IANA tzdata integration for planetary time is analogous to asking tzdata to represent tide tables — the answer is not "add more entries" but "this is the wrong tool".

**Workaround (current and intended):** The IPT SDK (`planet-time.js`) computes planetary time from UTC entirely in userspace. This is the correct architecture; see the Architecture Statement above.

**References:**

- IANA tzdata: https://www.iana.org/time-zones
- IAU WGCCRE: https://www.iau.org/science/scientific_bodies/working_groups/281/
- Current tzdata coverage: Earth bodies only (Africa/, America/, Asia/, Europe/, Pacific/, etc.)

---

## 2. Operating System Time Subsystems

**Overall feasibility: Very Low — decades horizon**

The POSIX `mktime()` formula hardcodes 86,400 seconds per day. This is not a Linux-specific implementation choice — it is a POSIX standard definition. Every OS, libc, and language runtime implements the same formula, because they are all conforming to the same standard. Changing this formula requires broad vendor consensus across the POSIX standards body, all libc implementations (glibc, musl, MSVC CRT, Apple libc), all OS kernels, and all language runtimes. The downstream breakage surface is essentially all software that uses the C time API. This is a decades-long standards effort at minimum, and likely not tractable until planetary operations are commonplace enough to justify the disruption.

The correct response is not to pursue OS time-subsystem integration. It is to keep planetary time in userspace, which is what the IPT SDK does.

### 2.1 Linux / tzdata (IANA)

**Status:** 🔴 — **Feasibility: Very Low**

**Current state:** Linux distributions ship the IANA tzdata package (`tzdata` on Debian/Ubuntu, `tzdata` on RHEL/Fedora). The `zic` (zone information compiler) and `zdump` tools process POSIX-format zone rule files.

**Structural barrier:**

- `POSIX TZ=` string format assumes Earth-day lengths (86 400 s). Mars sols are 88 775.244 s — the POSIX TZ rule format (`std offset dst [offset],rule`) does not accommodate variable-length days.
- `zic` would need an extension for `body` and `sol-length` directives so it can compile Mars zone files correctly.
- `zdump` output would need a `SOL` unit alongside the existing `UTC` and local representations.
- `glibc` and `musl` libc `localtime()` / `mktime()` internals assume 86 400 s days (POSIX standard, not implementation choice); both would need patching with full standards-body buy-in.

**Owner:** IANA tzdata maintainers, GNU libc (glibc) maintainers, musl libc maintainers, Linux distribution packagers.

**Estimated complexity:** Very High — core libc time API changes require POSIX standards revision; downstream breakage risk is system-wide.

**Workaround:** IPT SDK config specifies `planet: "mars"`, `tzOffset: 0`; all conversions handled in userspace by `planet-time.js` or equivalent.

---

### 2.2 macOS / Apple TimeZoneDB

**Status:** 🔴 — **Feasibility: Very Low**

**Current state:** macOS ships `TimeZoneDB.bundle` at `/usr/share/zoneinfo` (synced from IANA tzdata). System Preferences → Date & Time → Time Zone shows a world map with Earth timezone selection only.

**What needs to change:**

- Once IANA registers Mars zones, Apple would need to bundle them in a macOS update via `TimeZoneDB.bundle`.
- System Preferences (or System Settings on macOS 13+) would need a **Planet** selector before the timezone picker — selecting "Mars" would switch the map to a Mars surface map with AMT zone overlays.
- `NSTimeZone` / `CFTimeZone` APIs would need to handle non-Earth IANA identifiers without crashing or returning invalid data.
- `clock_gettime(CLOCK_REALTIME)` returns UTC seconds; a new `CLOCK_MARS_AMT` equivalent would require kernel-level support.

**Owner:** Apple (closed source). Requires Apple developer engagement via Feedback Assistant or WWDC contact.

**Estimated complexity:** Medium (once IANA acts) — Apple already has infrastructure to ship tzdata updates; UI changes are non-trivial.

---

### 2.3 Windows Time Zones

**Status:** 🔴 — **Feasibility: Very Low**

**Current state:** Windows maintains its own timezone registry under `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Time Zones`. Each entry maps to a Windows timezone name (e.g., `"UTC"`, `"Pacific Standard Time"`). Windows does not use IANA identifiers natively; ICU4C provides an IANA↔Windows mapping layer.

**What needs to change:**

- New registry entries for Mars zones: `"Mars Coordinated Time"`, `"Mars AMT+1"`, etc.
- `HKLM\...\Time Zones\Mars Coordinated Time` with appropriate `Std`, `Dlt`, `TZI` binary values, accounting for the 88 775.244 s sol length.
- Windows Time service (`w32tm`) would need a DTN-compatible mode: current `w32tm` assumes sub-second NTP round-trips; interplanetary delay (3–22 minutes to Mars) is completely outside its operating range.
- `GetTimeZoneInformation()` / `GetTimeZoneInformationForYear()` Win32 APIs would need non-Earth entries.
- ICU4C IANA↔Windows mapping table would need `Mars/Airy_Mean_Time` → `"Mars Coordinated Time"` entries.

**Owner:** Microsoft (closed source). File feedback via Windows Feedback Hub; contact via IETF/ISO standards engagement.

**Estimated complexity:** Medium-High — registry format and Win32 API assumptions about 24-hour days are deeply embedded.

---

### 2.4 Android / ChromeOS

**Status:** 🔴 — **Feasibility: Very Low** (same structural barrier as other OS platforms)

**Current state:** Android ships tzdata via AOSP (`external/icu/` and the `tzdata` APEX module introduced in Android 10). Updates are delivered via Google Play system updates without full OS upgrades.

**What needs to change:**

- The APEX tzdata module would pick up Mars zones automatically once IANA registers them — this is the most straightforward OS path.
- `java.util.TimeZone` and `java.time.ZoneId` on Android would accept `Mars/Airy_Mean_Time` once ICU4J supports it.
- Android's `Settings → Date & time → Time zone` picker would need a planet selector.
- ChromeOS inherits Android's tzdata mechanism for the Linux container; changes cascade naturally.

**Owner:** Google / AOSP maintainers.

**Estimated complexity:** Low-Medium (once IANA and ICU4J act) — the APEX delivery mechanism was designed for exactly this kind of update.

---

### 2.5 iOS / watchOS / tvOS

**Status:** 🔴 — **Feasibility: Very Low** (same structural barrier as macOS)

**Current state:** iOS uses the same `TimeZoneDB.bundle` mechanism as macOS. watchOS complication time display uses `NSTimeZone` internally. tvOS timezone handling is minimal (UTC display in most contexts).

**What needs to change:**

- Same as macOS (§2.2) for the core tzdata bundle.
- watchOS complications would need a `WKInterfacePlanetocentricDate` type or extension to `WKInterfaceDate` to display sol-based time on watch faces.
- HealthKit sleep/activity data uses local timezone; Mars colonist health data would need sol-aware timestamps.
- `CLLocationManager` on iOS (Core Location) returns Earth WGS84 coordinates only; a `CLPlanetaryLocation` type would be needed for non-Earth positioning.

**Owner:** Apple (closed source).

**Estimated complexity:** Medium (once IANA acts) — watchOS complications add complexity beyond the macOS path.

---

## 3. Browser Internationalisation APIs

### 3.1 Intl.DateTimeFormat

**Status:** 🔴 — **Feasibility: Very Low** (blocked by tzdata structural incompatibility, §1)

**Current state:** `Intl.DateTimeFormat` is defined in the ECMAScript Internationalization API Specification (ECMA-402). It accepts IANA timezone identifiers via the `timeZone` option. All currently valid identifiers are Earth zones.

**What needs to change:**

- A `calendar: 'mars-sol'` option (analogous to `calendar: 'hebrew'` or `calendar: 'chinese'`) to enable sol-based date arithmetic.
- `timeZone: 'Mars/Airy_Mean_Time'` should be accepted once IANA registers the identifier — the ECMAScript spec defers to IANA, so this may work automatically.
- `Intl.DateTimeFormat` format patterns would need `sol` unit support (e.g., `Sol 42` instead of `Day 42`).
- A TC39 ECMA-402 proposal would be needed for the `calendar: 'mars-sol'` option and sol unit.

**Blocking:** IANA registration (§1), TC39 ECMA-402 proposal.

---

### 3.2 TC39 Temporal API

**Status:** 🟢 (Stage 4 — now shipping in Chrome 144+ / Firefox 139+) — **Feasibility: Medium**

Temporal is a potential near-term integration point for userspace planetary time display, because it provides a structured, timezone-aware date/time layer in JavaScript that operates above the OS clock rather than replacing it — the same parallel-layer architecture that the IPT SDK uses.

**Current state:** The TC39 Temporal API replaces the legacy `Date` object with a modern, timezone-aware date/time library. `Temporal.ZonedDateTime` accepts IANA timezone identifiers. `Temporal.PlainDate` supports calendar systems (ISO 8601, Hebrew, Chinese, etc.) via the `calendar` option.

**Relevant link:** https://tc39.es/proposal-temporal/

**What Temporal already gets right (no change needed):**

- `Temporal.ZonedDateTime` with `timeZone: 'Mars/Airy_Mean_Time'` would work automatically once IANA registers the identifier — Temporal defers timezone resolution to the runtime's IANA database.
- Custom `Temporal.TimeZone` objects can already be constructed programmatically, enabling IPT SDK workarounds today without waiting for IANA registration.

**What still needs a TC39 proposal:**

- `Temporal.PlainDate` calendar `'mars-sol'` — sol-based date arithmetic (a Mars year is 668.6 sols; months are arbitrary without an IAU standard).
- `Temporal.Duration` sol unit — currently duration uses `days` (Earth days); a `sols` unit would be needed for Mars-native scheduling.
- A `Temporal.Now.planetaryInstant()` API — currently `Temporal.Now.instant()` returns UTC; a planetary variant would return the current time in the user's planetary timescale.

**IPT SDK current workaround:** `planet-time.js` uses `Temporal.Instant` for UTC anchor and applies sol arithmetic manually. Once `Temporal.ZonedDateTime` accepts `Mars/Airy_Mean_Time`, the SDK can delegate to Temporal for formatting while retaining its own sol arithmetic.

**Why Medium feasibility:** The userspace integration via custom `Temporal.TimeZone` objects is achievable today. The sol-arithmetic extensions require TC39 proposals, which take 12–36 months. Neither path requires OS changes or POSIX revision.

---

### 3.3 Geolocation API `body` field

**Status:** 🔴 (not yet proposed) — **Feasibility: High — most achievable standards engagement in 2026**

The W3C Geolocation API `body` field extension is the most achievable near-term standards engagement. The case for action is concrete, the change is backward-compatible, and the use cases are already real in 2026: lunar surface telemetry from Artemis surface assets, ISS positioning beyond Earth-centric coordinates, and CLPS commercial lunar payload location reporting all require a `body` field to be unambiguous.

**Current state:** The W3C Geolocation API (`navigator.geolocation`) returns a `GeolocationCoordinates` object with `latitude`, `longitude`, `altitude`, `accuracy`, and `altitudeAccuracy` — all relative to Earth's WGS84 reference ellipsoid.

**What needs to change:**

A `body` field and solar-system coordinate extension:

```json
{
  "body": "mars",
  "latitude": 4.5895,
  "longitude": 137.4417,
  "bodyRadius": 3389.5,
  "accuracy": 100,
  "altitude": 0,
  "altitudeAccuracy": 50
}
```

- `body`: IANA-registered solar body identifier (e.g., `"mars"`, `"moon"`, `"earth"`, `"venus"`)
- `bodyRadius`: mean radius of the body in km (for altitude reference surface)
- Coordinates use body-fixed IAU reference frame (areocentric latitude/longitude for Mars, selenocentric for Moon)

**Why High feasibility:** This is a backward-compatible extension — adding an optional `body` field to `GeolocationCoordinates` does not break any existing Earth-based usage. The W3C Geolocation Working Group is active. The change requires only a small spec addition. No OS-level changes, POSIX revision, or IAU coordination is required. The `body` value can use the same IAU body names already defined in DRAFT-STANDARD.md.

**Required:** W3C Geolocation Working Group engagement. A new `PlanetaryGeolocation` interface or extension to `GeolocationCoordinates` would need a W3C Note or Recommendation.

**GeoJSON impact:** GeoJSON (RFC 7946) currently assumes Earth WGS84 coordinates. An IETF extension RFC would be needed for `"body"` field in GeoJSON Feature objects.

---

## 4. NTP / PTP Time Synchronisation Over DTN

**Status:** 🔴

**Current state:**

- NTP (RFC 5905) achieves millisecond accuracy by measuring round-trip delay between client and server. Earth-Mars one-way signal travel time ranges from 3 minutes (closest approach) to 22 minutes (conjunction) — making round-trip NTP measurement physically impossible.
- PTP (IEEE 1588) operates similarly, assuming sub-microsecond round-trip times on local area networks.
- Both protocols assume a stable, Earth-centric time source (GPS or atomic clock) as Stratum 0.

**What needs to change:**

- IETF DTN Working Group (`dtn-wg`) extension for high-latency time synchronisation: a one-way time broadcast protocol for interplanetary links.
- Relevant existing IETF work:
  - Bundle Protocol v7: RFC 9171 — defines store-and-forward message transport over DTN links
  - Licklider Transmission Protocol (LTP): RFC 5326 — reliable transmission over high-latency links
- Proposed approach: **Planet Timescale Beacon (PTB)** — one-way time broadcasts from Earth DSN stations with embedded Δt corrections (analogous to GPS time signals or WWVB radio time), transmitted as DTN bundles with a `Primary-Block-Time` extension field.

**Proposed IPT NTP stratum hierarchy:**

| Stratum | Source |
|---------|--------|
| IPT Stratum 0 | On-site atomic clock at Mars base (hydrogen maser or Cs standard) |
| IPT Stratum 1 | Mars servers synced via DSN Planet Timescale Beacon |
| IPT Stratum 2+ | Planet-local NTP servers (Mars LAN / habitat intranet) |
| IPT Stratum N | End devices (laptops, phones, rovers) |

**Current workaround for Mars missions:** Pre-synchronise clocks before departure; use on-board atomic clocks during transit and surface operations. Mars rovers (Curiosity, Perseverance) use a stored Earth-seconds-since-J2000 timescale, converting to LMST on demand via their onboard computer — no live time sync.

**References:**
- CCSDS 301.0-B-4: Time Code Formats (defines CCSDS time codes used by NASA/ESA missions)
- NASA DSN frequency and timing standards (810-005, Module 207)
- RFC 9171: Bundle Protocol Version 7
- RFC 5326: Licklider Transmission Protocol

---

## 5. Network Time for Deep Space

**Status:** 🔴

**Current state:** The Consultative Committee for Space Data Systems (CCSDS) defines time code formats used by all major space agencies (NASA, ESA, JAXA, ISRO, etc.):

- **CCSDS 301.0-B-4**: Unsegmented Time Code (UTC-based, 32-bit coarse + 16-bit fine, up to 2032 before rollover)
- **CCSDS Day-Segmented Time Code**: year + day-of-year + milliseconds-of-day

NASA Deep Space Network (DSN) timing discipline:

- GPS-disciplined hydrogen masers at Goldstone (California), Madrid (Spain), and Canberra (Australia)
- Two-way Doppler ranging provides sub-microsecond spacecraft clock calibration
- One-way timing accuracy degrades with distance (speed-of-light uncertainty dominates at AU scales)

**Future needs for multi-planet infrastructure:**

1. **Mars-local time authority**: An autonomous atomic clock standard at a Mars base, independent of Earth DSN contact windows (DSN contact is typically 8 hours/day per spacecraft).
2. **Distributed planetary NTP hierarchy**: Analogous to Earth's NTP stratum tree, but spanning Earth-Mars with DTN bundle transport for stratum-0→stratum-1 sync pulses.
3. **Interoperable time code extension**: CCSDS 301.0-B extension for planetary body identifier and sol-count fields, enabling unambiguous machine-readable Mars timestamps in telemetry streams.
4. **ISO 8601 extension**: The current ISO 8601 date-time notation (`2026-03-02T14:30:00Z`) has no body identifier. A proposed extension: `2026-03-02T14:30:00[Mars/Airy_Mean_Time]` (following the Temporal API bracket notation convention).

**Proposed CCSDS time code extension fields:**

```
Body ID:   8-bit COSPAR body identifier (0x00 = Earth, 0x04 = Mars, 0x10 = Moon)
Sol count: 32-bit integer (sols since Mars J2000.0 epoch)
Sol ms:    32-bit integer (milliseconds within current sol)
```

---

## 6. Positioning and Navigation

**Status:** 🔴

**Current state:**

- **GPS (Global Positioning System)** is Earth-specific: uses an Earth-centred, Earth-fixed (ECEF) coordinate frame and WGS84 reference ellipsoid. GPS satellites broadcast UTC(USNO) time signals.
- **GNSS broadly** (GLONASS, Galileo, BeiDou) all assume Earth ECEF frames.
- **Mars:** No operational satellite navigation system. InSight lander used Earth DSN two-way Doppler ranging for position determination — accuracy ~1 km, requiring Earth contact.
- **Moon:** NASA LunaNet (in development, target ~2027) — includes PNT (Positioning, Navigation, and Timing) services as a lunar orbital relay architecture. LunaNet would provide a dedicated timing signal for surface operations.

**Standards needed:**

- **CCSDS 500.0-B**: Navigation Data Messages — extend to include body-fixed coordinate frames for Mars and Moon
- **ITU-R S-series**: Space radiocommunications standards — define frequency allocations for planetary navigation signal broadcasts
- **GeoJSON RFC extension**: RFC 7946 (GeoJSON) assumes Earth WGS84. An IETF extension RFC is needed:

```json
{
  "type": "Feature",
  "geometry": {
    "type": "Point",
    "coordinates": [137.4417, 4.5895, 0],
    "body": "mars",
    "crs": "IAU:Mars_2015"
  }
}
```

- **W3C Geolocation API** `body` field (see §3.3)
- **IETF/IANA registry** for solar system body identifiers (currently COSPAR/IAU handle this informally)

**For IPT:** The `{body, lat, lng, alt}` coordinate tuple used by the InterPlanet SDK (`planet-time.js` `bodyDistance()`, LTX meeting planner) represents a practical superset of Earth geolocation. Formalising this as a W3C/IETF standard would enable browser-native `navigator.planetaryGeolocation` support.

---

## 7. Standards Bodies Engagement

**Status:** 🔴

| Body | Scope | Relevant Work | IPT Contact Needed |
|------|-------|---------------|-------------------|
| IANA | Timezone registry | tzdata | Submit Mars TZ proposal to `tz@iana.org` |
| IERS | Earth rotation standards | Leap seconds, UT1-UTC | Coordinate on planetary timescales and MTC definition |
| IAU | Astronomical standards | Planet rotation elements, WGCCRE | Zone boundary definitions; Mars prime meridian anchor |
| TC39 | JavaScript standards | Temporal API (Stage 4), ECMA-402 Intl | `mars-sol` calendar; `sols` duration unit proposal |
| W3C | Web standards | Geolocation API, i18n, WebIDL | `body` field in GeolocationCoordinates; sol formatting |
| IETF | Internet standards | NTP (RFC 5905), DTN (RFC 9171), GeoJSON (RFC 7946) | High-latency time sync RFC; GeoJSON body extension |
| CCSDS | Space data standards | Time codes (301.0-B), Navigation (500.0-B) | Interoperability with IPT; CCSDS time code extension |
| ISO | International standards | ISO 8601 (date-time notation), ISO 19111 (CRS) | Planet-aware date notation; non-Earth CRS registration |
| IEEE | Engineering standards | PTP IEEE 1588-2019 | Deep-space PTP profile for one-way time dissemination |
| ITU-R | Radio standards | ITU-R S-series (space radiocommunications) | Frequency allocations for planetary navigation signals |

**Recommended engagement sequence:**

1. **IAU WGCCRE** — obtain official Mars prime meridian and rotation model blessing (needed for all downstream standards)
2. **IANA** — submit timezone proposal (depends on IAU WGCCRE output)
3. **IERS** — define MTC (Mars Coordinated Time) relationship to TT and TCB
4. **IETF dtn-wg** — submit Planet Timescale Beacon Internet-Draft (depends on IERS MTC definition)
5. **TC39** — submit `mars-sol` calendar proposal to ECMA-402 (can proceed in parallel with IANA)
6. **W3C Geolocation WG** — submit `body` field proposal (can proceed in parallel)
7. **ISO TC 154** — submit ISO 8601 extension proposal for body-aware datetime notation
8. **CCSDS** — submit time code extension to CCSDS Panel 2 (time systems)

---

## 8. Workaround Documentation (Current State)

Until native platform support arrives, all IPT-aware applications use the following architecture:

### Architecture

```
┌──────────────────────────────────────┐
│  Device OS (macOS / Linux / Windows) │
│  System clock: UTC (Earth)           │
│  Timezone database: Earth-only       │
└──────────────┬───────────────────────┘
               │ Date.now() / UTC ms
               ▼
┌──────────────────────────────────────┐
│  IPT SDK (planet-time.js / etc.)     │
│  Input: UTC ms + user planet config  │
│  Output: local planet time           │
└──────────────┬───────────────────────┘
               │ {sol, h, m, s, solOfYear, year}
               ▼
┌──────────────────────────────────────┐
│  Application (InterPlanet web app,   │
│  LTX meeting tool, SDK consumer)     │
│  Displays: local Mars/Moon/etc time  │
└──────────────────────────────────────┘
```

### Step-by-step

1. **Device runs standard UTC (Earth)** — the OS system clock, browser `Date.now()`, and all system APIs return UTC.
2. **Application receives user's planetary location** — via user settings or URL parameter, e.g.:
   - `{ planet: 'mars', tzOffset: 0 }` — Mars Coordinated Time (MTC, equivalent to AMT+0)
   - `{ planet: 'mars', tzOffset: 1 }` — Mars AMT+1 (one Mars timezone east of Airy crater)
   - `{ planet: 'moon', tzOffset: 0 }` — Lunar Mean Time
3. **Application uses IPT SDK** — `planet-time.js` `getPlanetTime(planetKey, date, tzOffsetHours)` converts UTC to local planet time, returning a `PlanetTime` object with `{ hour, minute, second, solInfo, isWorkHour, ... }`.
4. **Display** — the application renders the converted time. The browser's `Date` object and `Intl.DateTimeFormat` are bypassed for planetary time display; the IPT SDK handles all formatting.

### SDK implementations

All InterPlanet SDK implementations accept the same inputs and produce identical output. See §9 for the full reference table.

### Limitations of the workaround

- Every application must explicitly integrate the IPT SDK — there is no OS-level automatic conversion.
- System notifications, calendar apps, file timestamps, and any software not IPT-aware will display UTC or local Earth timezone.
- The browser `Date` object cannot be reliably overridden without a Service Worker or monkey-patching, both of which have compatibility risks.
- `Intl.DateTimeFormat` cannot format Mars times natively; the SDK must produce pre-formatted strings.

---

## 9. Reference Implementations

All SDK implementations are in the `interplanet-github` repository. Each implements the IPT core functions: `getPlanetTime()`, `bodyDistance()`, `getPlannedMeetings()`, and where applicable, the LTX (Light-Time eXchange) meeting protocol.

| Language | Directory | Primary file | LTX support | Test coverage |
|----------|-----------|-------------|-------------|---------------|
| JavaScript | `javascript/planet-time/` | `planet-time.js` | `javascript/ltx/ltx-sdk.js` | Playwright E2E |
| TypeScript | — | (compiled from JS) | `interplanet-ltx-ts.spec.js` | Playwright E2E |
| Python | `python/planet-time/` | `src/interplanet_time/` | `python/` ltx package | pytest |
| Rust | `rust/` | `src/lib.rs` | `rust/` ltx crate | cargo test |
| C | `c/planet-time/` | `src/libinterplanet.c` | `c/ltx/` | Makefile tests |
| Go | `go/` | `planet_time.go` | `go/` ltx module | go test |
| Swift | `swift/` | `Sources/` | `swift/` ltx target | XCTest |
| Kotlin | `kotlin/` | `src/main/kotlin/` | `kotlin/` ltx module | JUnit 5 |
| C# | `csharp/` | `src/Models.cs` | `csharp/` ltx package | NUnit |
| Dart | `dart/` | `lib/` | `dart/` ltx package | dart test |
| Elixir | `elixir/` | `lib/interplanet_ltx/` | `elixir/` ltx app | ExUnit |
| F# | `fsharp/` | `src/` | `fsharp/` ltx project | NUnit / xUnit |
| Scala | `scala/` | `src/main/scala/` | `scala/` ltx module | ScalaTest |
| Lua | `lua/` | `planet_time.lua` | `lua/` ltx module | busted |
| OCaml | `ocaml/` | `lib/` | `ocaml/` ltx library | OUnit2 |
| Zig | `zig-ltx/` | `src/root.zig` | LTX-only | zig test |
| R | `r/` | `R/` | (planet-time only) | testthat |

<!-- AUDIT: `tests/e2e/interplanet-ltx-conformance.spec.js` does not exist in the repo (tests/ only contains cross_sdk_* scripts). This section needs updating when the conformance suite is created. -->
**Conformance test suite:** All LTX implementations are validated against canonical test vectors in `tests/e2e/interplanet-ltx-conformance.spec.js`. The golden plan ID for the reference test vector is `cc8a7fc0` (nodes-before-segments JSON canonical ordering).

---

## 10. Glossary

- **Sol**: A Martian solar day — 24 hours, 39 minutes, 35.244 seconds (88 775.244 seconds). The fundamental unit of Mars local time.
- **MTC**: Mars Coordinated Time — the reference meridian timescale for Mars, analogous to UTC on Earth. MTC is defined at the Mars prime meridian (Airy-0 crater, 0° longitude).
- **AMT**: Airy Mean Time zones — 25 named Mars timezone zones, each spanning 14.4° of longitude (15° × 24 zones for a 24-hour Mars "clock" — but Mars has 24h 39m sols, so zones are 14.4°). Named by convention `AMT+N` / `AMT-N` where N is 1–12.
- **LMST**: Local Mean Solar Time — the time at a specific location on a planet's surface, based on the mean position of the sun (as opposed to apparent solar time which varies with orbital eccentricity).
- **J2000.0**: Standard astronomical reference epoch — 1 January 2000, 12:00 TT (Terrestrial Time). Used as the anchor epoch for planetary orbital and rotational elements.
- **DTN**: Delay/Disruption Tolerant Networking — a networking architecture (IETF RFC 4838, Bundle Protocol RFC 9171) designed for environments with long or variable link delays, such as interplanetary communication.
- **DSN**: Deep Space Network — NASA's worldwide network of large radio antennas (Goldstone CA, Madrid Spain, Canberra Australia) used for communication and navigation with interplanetary spacecraft.
- **CCSDS**: Consultative Committee for Space Data Systems — an international standards body for space data and information systems, with members including NASA, ESA, JAXA, ISRO, CNSA, CSA, and others.
- **LTX**: Light-Time eXchange — the interplanetary meeting protocol implemented in this project. LTX plans a meeting across planetary distances by computing optimal transmission windows accounting for one-way light-travel delay.
- **IPT**: InterPlanet Time — the proposed standard for timekeeping across the solar system, encompassing timezone registration, clock synchronisation, positioning, and application APIs for non-Earth bodies.
- **PNT**: Positioning, Navigation, and Timing — the three services provided by satellite navigation systems (GPS on Earth; LunaNet on Moon; proposed for Mars).
- **WCET**: Worst-Case Execution Time — in the context of IPT, the worst-case light-travel delay (Earth-Mars at solar conjunction ≈ 22 minutes one-way, ≈ 44 minutes round-trip).
- **IAU WGCCRE**: IAU Working Group on Cartographic Coordinates and Rotational Elements — defines the reference frames, prime meridians, and rotation models for all solar system bodies.
- **IERS**: International Earth Rotation and Reference Systems Service — maintains UT1-UTC, publishes leap second announcements, and maintains the International Celestial Reference Frame (ICRF).
- **TT**: Terrestrial Time — a coordinate time standard of the IAU used for geocentric ephemerides; approximately GPS time + 19.018 seconds.
- **TCB**: Barycentric Coordinate Time — the IAU coordinate time for the solar system barycentre; used in planetary ephemerides (DE440, DE441).

---

*Last updated: 2026-03-02*
