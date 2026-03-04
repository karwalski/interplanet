# Celestial Body Location API

**A proposal for extending browser geolocation to support non-Earth bodies**

> **Status: Community Proposal — Not Implemented**
> This document is a design proposal intended for GitHub community discussion. No implementation exists in the InterPlanet codebase. W3C submission may follow community review. See [interplanet GitHub issues](https://github.com/karwalski/interplanet/issues) to contribute.

**Relates to:** DRAFT-STANDARD.md §9, WHITEPAPER.md §1.2 (communications), planet-time.js

---

## The Problem

The W3C Geolocation API (`navigator.geolocation`) returns a `GeolocationCoordinates` object with latitude, longitude, altitude, and accuracy. These fields implicitly assume the body is Earth. There is no field for:

- Which celestial body the device is located on
- Planetary coordinate system (which prime meridian, which pole convention)
- Orbital position (for in-transit vehicles between bodies)
- Body-relative zone or region identifier

As human activity expands to the Moon, Mars, and eventually further, and as robotic systems interacting with browser-based APIs require accurate location context, this limitation becomes a practical engineering problem rather than a hypothetical one.

The CHAPEA Mars analog habitat, the Artemis lunar surface programme, future Mars surface missions, and the growing category of autonomous robots reporting telemetry through browser-based interfaces will all encounter this gap.

---

## Current Browser Geolocation (Reference)

```webidl
interface GeolocationCoordinates {
  readonly attribute double latitude;          // Decimal degrees, WGS84
  readonly attribute double longitude;         // Decimal degrees, WGS84
  readonly attribute double? altitude;         // Metres above WGS84 ellipsoid
  readonly attribute double accuracy;          // Metres (95% confidence)
  readonly attribute double? altitudeAccuracy; // Metres
  readonly attribute double? heading;          // Degrees from true north
  readonly attribute double? speed;            // Metres per second
};
```

All coordinate values reference the WGS84 Earth ellipsoid. Non-Earth bodies are not addressable.

---

## Proposed Extension: `CelestialBodyCoordinates`

### New WebIDL interface

```webidl
interface CelestialBodyCoordinates : GeolocationCoordinates {
  // Body identification
  readonly attribute DOMString body;           // IAU body name: "Earth", "Mars", "Moon", etc.
  readonly attribute DOMString? bodyCode;      // IAU/NAIF SPICE ID: "499" (Mars), "301" (Moon)
  readonly attribute DOMString coordinateSystem; // Coordinate convention: "IAU2015", "WGS84", "MOON_ME"

  // Planetary coordinates (IAU body-fixed)
  readonly attribute double planetaryLatitude;  // Decimal degrees (positive north)
  readonly attribute double planetaryLongitude; // Decimal degrees (positive east, IAU convention)
  readonly attribute double? planetaryAltitude; // Metres above reference ellipsoid or areoid

  // Zone identifier (from DRAFT-STANDARD.md §6)
  readonly attribute DOMString? timezoneZone;   // e.g. "Mars/AMT+1", "Moon/LMT-3", "Earth/UTC+11"

  // For in-transit vehicles (no surface body)
  readonly attribute boolean inTransit;         // True when between bodies
  readonly attribute DOMString? transitFrom;    // Departure body: "Earth"
  readonly attribute DOMString? transitTo;      // Destination body: "Mars"
  readonly attribute double? heliocentricLatitude;  // J2000.0 ecliptic latitude
  readonly attribute double? heliocentricLongitude; // J2000.0 ecliptic longitude
  readonly attribute double? heliocentricDistanceAU; // Distance from Sun in AU

  // Accuracy and source
  readonly attribute DOMString locationSource; // "gps" | "gnss" | "slam" | "manual" | "orbital"
  readonly attribute double? signalDelaySeconds; // One-way Earth signal delay at time of fix
};
```

### Extended GeolocationPosition

```webidl
interface CelestialBodyPosition : GeolocationPosition {
  override readonly attribute CelestialBodyCoordinates coords;
  readonly attribute DOMString body;  // Shortcut: same as coords.body
};
```

---

## Body Identifier Conventions

Body names follow IAU nomenclature. The `bodyCode` field uses NASA/NAIF SPICE integer IDs for machine use:

| Body | `body` string | `bodyCode` | Coordinate system |
|---|---|---|---|
| Earth | `"Earth"` | `"399"` | WGS84 (existing) |
| Moon | `"Moon"` | `"301"` | MOON_ME (Mean Earth/Polar Axis) |
| Mars | `"Mars"` | `"499"` | IAU2015 (Viking Lander 1 prime meridian) |
| Mercury | `"Mercury"` | `"199"` | IAU2015 |
| Venus | `"Venus"` | `"299"` | IAU2015 (east-positive despite retrograde) |
| In-transit | `"Transit"` | `null` | Heliocentric ecliptic J2000.0 |
| Unknown | `"Unknown"` | `null` | No coordinate system |

Coordinate conventions follow IAU Working Group on Cartographic Coordinates and Rotational Elements (WGCCRE) 2015 report, published 2018. All longitudes are east-positive per IAU convention, including Venus (which has retrograde rotation but east-positive longitude by IAU convention).

---

## Proposed Chromium Feature Enhancement

### Intent

Extend the Chromium implementation of the Geolocation API to:

1. Accept `body` as an optional field in the `GeolocationOptions` dictionary (to allow applications to declare the expected body and receive an error if the device returns a different one)
2. Return `CelestialBodyCoordinates` when the underlying location provider reports a non-Earth body or in-transit state
3. Provide a manual override mechanism in `chrome://settings/location` (or equivalent) for scenarios where location cannot be determined automatically (e.g., simulated environments, analog habitats)

### Location source hierarchy (non-Earth)

For non-Earth bodies, the browser geolocation stack cannot rely on GPS/GNSS (which is Earth-specific). Proposed location sources, in priority order:

| Source | `locationSource` value | Notes |
|---|---|---|
| GNSS (Earth only) | `"gnss"` | GPS, GLONASS, Galileo, BeiDou |
| Lunar GNSS | `"gnss"` | LunaNet NavSat (NASA, 2030s target) |
| SLAM/odometry | `"slam"` | Rover dead-reckoning; lower accuracy |
| Orbital mechanics | `"orbital"` | Position computed from known trajectory + time |
| Manual entry | `"manual"` | User-specified in browser settings or app |

### New `navigator.celestialLocation` API surface

```javascript
// Check for support
if ('celestialLocation' in navigator) {
  navigator.celestialLocation.getCurrentPosition(
    (position) => {
      console.log(position.coords.body);           // "Mars"
      console.log(position.coords.planetaryLat);   // 18.4
      console.log(position.coords.planetaryLon);   // -77.5
      console.log(position.coords.timezoneZone);   // "Mars/AMT-5"
      console.log(position.coords.signalDelaySeconds); // 847.2
    },
    (error) => { /* fallback */ },
    { body: 'Mars', enableHighAccuracy: true }
  );
}
```

Fallback: if `navigator.celestialLocation` is not available, applications fall back to `navigator.geolocation` for Earth-only context.

---

## Manual JSON Location Input (interplanet.live implementation)

While the browser API proposal is under development, interplanet.live implements manual celestial location input via the settings panel.

### JSON schema for manual location

```json
{
  "body": "mars",
  "lat": 18.4,
  "lon": -77.5,
  "altitude_m": -7152,
  "zone": "AMT-5",
  "label": "Hellas Planitia Base Alpha",
  "source": "manual",
  "accuracy_m": 1000
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `body` | string | Yes | `"earth"`, `"mars"`, `"moon"`, `"mercury"`, `"venus"`, `"jupiter"`, `"saturn"`, `"uranus"`, `"neptune"`, `"transit"` |
| `lat` | number | Yes | Decimal degrees, positive north. IAU east-positive for non-Earth bodies. |
| `lon` | number | Yes | Decimal degrees, positive east. |
| `altitude_m` | number | No | Metres above reference surface (areoid for Mars, geoid for Earth, mean radius for others) |
| `zone` | string | No | Timezone zone identifier per DRAFT-STANDARD.md §6: `"AMT+0"`, `"LMT-3"`, `"UTC+11"` |
| `label` | string | No | Human-readable location name for display |
| `source` | string | No | `"manual"` (default), `"slam"`, `"orbital"` |
| `accuracy_m` | number | No | Estimated position accuracy in metres |

### Effects on interplanet.live when location is set

- **Earth cities**: Round-trip propagation delay calculated from user's body/coordinates to each displayed city, not from a generic Earth position
- **Planet cards**: One-way propagation delay calculated from user's body to the displayed planet. If user is already on that planet, shows local propagation delay
- **Meeting scheduler**: Marks the user's body in the schedule grid; highlights conjunction windows from the user's current body rather than defaulting to Earth
- **DTN estimates**: Calculates nearest relay geometry and optimal bundle routing from the user's stated position

---

## Signal Delay Computation from Non-Earth Locations

When `STATE.userBody` is set to a non-Earth body:

### Earth city ping

When user is at Mars AMT-5:
```
User at Mars AMT-5 → London, Earth
One-way: ~14.2 min (current Earth-Mars distance)
Round-trip: ~28.4 min
```

### Planet card propagation delay

When user body matches the card body (e.g., user on Mars, viewing Mars card):
```
Same body — local comms (~speed of light across surface)
```

When user body differs:
```
14.2 min propagation delay (Earth → Mars)
```

### DTN relay path estimate

When user is in transit between bodies:
```
~8.3 min (current position) → Mars: 6.1 min, Earth: 9.2 min
Nearest relay: MRO at Mars orbit — contact window in 47 min
```

---

## Chromium Feature Proposal — Submission Path

1. Submit an **Intent to Prototype** on the `blink-dev@chromium.org` mailing list with this document as supporting specification
2. File a Chromium issue in the `Internals > Location` component referencing the Artemis Accords, CHAPEA program, and IAU Lunar Coordinate Time adoption as motivation
3. Reference DRAFT-STANDARD.md as the planetary coordinate and timezone convention the API would implement
4. Propose a new `body` field in the Geolocation API spec via the W3C Geolocation Working Group (GitHub: w3c/geolocation-api)
5. Engage ESA (which has existing browser geolocation work for spacecraft telemetry) and NASA JPL (which uses web-based ground support tools) as co-proponents

The minimum viable browser change is small: adding a `body` string field to `GeolocationCoordinates` that defaults to `"Earth"` when not set by the underlying platform. Existing Earth applications are unaffected; non-Earth platforms set the field appropriately.

---

## References

- W3C Geolocation API Specification: https://www.w3.org/TR/geolocation/
- IAU WGCCRE 2015 Report (Archinal et al. 2018): *Celestial Mechanics and Dynamical Astronomy* 130:22
- DRAFT-STANDARD.md §4 (Coordinate Conventions) — this repository
- NASA LunaNet Architecture: https://esc.gsfc.nasa.gov/projects/LunaNet
- NAIF SPICE Body IDs: https://naif.jpl.nasa.gov/pub/naif/toolkit_docs/FORTRAN/src/spicelib/zzbodtrn.f
- CCSDS 301.0-B-4: Time Code Formats (reference for non-Earth time tagging)

---

*Matthew Watt — interplanet.live — February 2026*
