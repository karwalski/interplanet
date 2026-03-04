# InterPlanet — Glossary of Key Terms and Acronyms

This document defines terms, acronyms, and concepts introduced or formalised by
the InterPlanet project. It focuses on novel or project-specific definitions —
particularly those relevant to proposed standards extensions, RFCs, and new
interoperability protocols. It does not re-define general computing or
astronomical terms except where the project assigns them specialised meaning.

---

## Acronyms

| Acronym | Full Name | Context |
|---|---|---|
| **AMT** | Airy Mean Time | Mars reference meridian timezone |
| **AU** | Astronomical Unit | 149,597,870.7 km — distance unit |
| **DTN** | Delay-Tolerant Networking | RFC 4838 store-and-forward transport |
| **HDTN** | High-Rate DTN | NASA implementation achieving 900 Mbps |
| **ICS** | iCalendar / Internet Calendar Scheduling | RFC 5545 calendar file format |
| **IPT** | Interplanetary Time | The planet-time library and calculation engine |
| **IWS** | Interplanetary Work Scheduling | The domain of scheduling human work across solar system distances |
| **J2000** | Julian epoch 2000.0 | Astronomical reference epoch (2000-01-01T12:00:00 TT) |
| **JDE** | Julian Ephemeris Day | Continuous day count from J2000 in TT |
| **LMT** | Lunar Mean Time | Lunar timezone prefix (proposed) |
| **LOS** | Line of Sight | Direct radio-frequency path between two bodies (may be blocked by Sun) |
| **LTC / TCL** | Lunar Coordinate Time | IAU-adopted lunar timescale (2024); +56.02 µs/day vs TAI |
| **LTX** | Light-Time eXchange | The interplanetary meeting protocol defined by this project |
| **MMT** | Mars Mean Time | General Mars timezone prefix (cf. AMT for Airy meridian) |
| **MTC** | Mars Coordinated Time | Time at the Airy Mean Time meridian (Mars prime meridian clock) |
| **RFC** | Request for Comments | IETF standards document |
| **RT** | Round-Trip | Time for a signal to travel from A to B and back (2× one-way) |
| **TT** | Terrestrial Time | Relativistic time standard used for orbital ephemeris calculations |

---

## A

### Airy Mean Time (AMT)
The Mars timezone anchored to the Airy-0 crater on Mars (0° longitude by
convention, analogous to Greenwich on Earth). AMT is used as the reference
meridian for MTC. Named after the Airy crater, which is itself named after
British Astronomer Royal George Biddell Airy. AMT offset = 0.

### Async Send Window
A communication window in which a message sent by Party A will arrive at
Party B during Party B's work hours. Distinct from a meeting window: only
one direction of transmission is constrained. Used in the "Can I send now?"
feature of the InterPlanet scheduler. Part of the IWS domain.

### Astronomical Unit (AU)
The mean Earth–Sun distance: 149,597,870.7 km exactly (IAU 2012).
Used throughout IPT as the unit for interplanetary distances.
Light travel time across 1 AU ≈ 499.0 seconds (≈ 8.3 minutes).

---

## B

### BUFFER segment
An LTX session segment type. A scheduled time block at the end of a
session to absorb timing variance, transmission jitter, or unexpected
delay. Typically 1–2 quanta. Does not carry active content.

---

## C

### CAUCUS segment
An LTX session segment type. A period of private internal deliberation —
no cross-party transmission occurs. Each node works independently (drafts
a reply, confers internally, processes received content). Analogous to
a caucus recess in diplomacy or labour negotiation.

### Conjunction (Solar Conjunction)
A period during which a planet passes through the same line of sight as
the Sun from Earth's perspective, causing signal degradation or loss.
X-band command moratoriums typically last 14 days per Martian synodic
period. LOS is classified as `degraded` in the approach phase and
`blocked` at the disk centre. See also: **Line of Sight (LOS)**.

---

## D

### Delay (LTX node delay)
The one-way signal propagation delay from the HOST node to a given
participant node, in seconds. The authoritative value used for all
segment scheduling calculations within an LTX plan. Typically calculated
from ephemeris and encoded in the plan config at session creation time.

### DTN (Delay-Tolerant Networking)
The IETF/CCSDS networking architecture (RFC 4838, Bundle Protocol RFC 9171)
designed for environments with intermittent connectivity and long delays.
Used as the transport substrate for LTX in deep space deployments. The
HDTN (High-Rate DTN) implementation by NASA Glenn achieves 900 Mbps over
laser links.

---

## E

### Elongation
The angular separation between a planet and the Sun as seen from Earth.
Used in LOS calculations: elongation below ~2–3° indicates proximity to
solar disk (conjunction zone).

---

## F

### Fairness Score
A metric quantifying how equitably a proposed meeting time distributes
schedule disruption across parties in different time zones (or on different
planets). Calculated from the fraction of each party's work hours consumed
by the meeting, travel time, and whether the meeting falls outside standard
work hours. Part of the IWS domain.

---

## H

### Hash Prefix (`#l=`)
The URL fragment prefix used to encode a serialised LTX plan config.
`#l=<base64url>` is the canonical form. Example:
`https://interplanet.live/ltx.html?node=N0#l=eyJ2IjoyLC4uLn0=`.
The `l` stands for "LTX". The fragment is never sent to a server,
ensuring the plan config remains client-side only.

### HDTN (High-Rate DTN)
NASA's open-source implementation of the Bundle Protocol for delay-tolerant
networking. Achieves ~900 Mbps over optical links in ground testing (2023).
Designated as the transport infrastructure target for LTX in production
interplanetary deployments.

### HOST (LTX node role)
The node in an LTX session that initiates the session, sends first in
each TX/RX pair, and whose reference time governs segment scheduling.
Equivalent to "chair" in formal meeting protocols.

---

## I

### Interplanetary Time (IPT)
The planet-time calculation library and API developed by this project.
Provides orbital mechanics, planetary clock calculations, MTC, light-travel
delay, LOS, meeting window detection, and fairness scoring for all nine
major solar system bodies plus the Moon. Implemented in 11+ languages.
API documented at `api.html`.

### Interplanetary Work Scheduling (IWS)
The domain of theory and practice concerned with scheduling human work,
meetings, communications, and collaborative activity across solar system
distances. IWS encompasses: planetary timezone conventions, communications
delay compensation, solar conjunction planning, fairness in schedule design,
legal frameworks for off-Earth labour standards, and the LTX protocol.

### ICS (iCalendar, RFC 5545)
The IETF standard calendar format used by Outlook, Google Calendar, and
all major calendar clients. LTX extends ICS with two custom X-properties:
- `X-LTX-PLANID`: the canonical LTX plan ID for the event
- `X-LTX-QUANTUM`: the quantum duration for the session

These extensions are proposed as part of the RFC 5545 Extension for LTX
(see `ICS for LTX.md` and `RF5545 EXTENSION.md`).

---

## J

### J2000 Epoch
The astronomical reference epoch: 2000-01-01T12:00:00 TT (Julian Date
2451545.0). IPT uses J2000 as the zero point for all orbital element
computations. The corresponding Unix timestamp is 946,728,000,000 ms.

### JDE (Julian Ephemeris Day)
A continuous day count in Terrestrial Time (TT) from J2000. Used for all
orbital element lookups in IPT's Kepler equation solver.

---

## L

### Light-Travel Delay
The one-way time for a signal (radio or laser) to travel between two
solar system bodies at the speed of light (299,792.458 km/s). The
fundamental constraint driving all IWS and LTX design. Ranges from
~1.28 s (Earth–Moon) to ~87 min (Earth–Saturn near conjunction).

### Line of Sight (LOS)
The direct radio-frequency path between two solar system bodies. LOS has
three states in IPT:
- **clear**: path unobstructed, full-bandwidth communication available
- **degraded**: planet within ~2–5° of solar disk; signal attenuation
- **blocked**: planet within solar exclusion zone; communication unreliable
LOS state is computed from heliocentric positions and solar elongation.

### Lunar Coordinate Time (LTC / TCL)
A relativistic timescale adopted by the IAU at its 32nd General Assembly
(Cape Town, August 2024) for use in lunar surface operations and navigation.
Runs 56.02 µs/day faster than TAI due to lower gravitational potential on
the lunar surface. NASA is mandated to deliver a full specification by
December 31, 2026 (OSTP White House directive, April 2024).

### LTX (Light-Time eXchange)
The interplanetary meeting protocol defined by this project.
LTX structures multi-party sessions with large signal delays into
deterministic alternating TX/RX/CAUCUS/BUFFER segments, each lasting
a whole number of **quanta**, so that every participant can plan transmission
windows without risk of transmitting over an in-flight message.
LTX plans are encoded as v2 JSON configs and identified by a canonical
**Plan ID**.

### LTX Plan ID
A deterministic identifier for an LTX session plan. Canonical form:
```
LTX-{YYYYMMDD}-{HOSTNODE}-{DESTNODE}-v{VERSION}-{HASH8}
```
Example: `LTX-20400115-EARTHHQ-MARS-v2-9844a312`

Where:
- `{YYYYMMDD}` — session start date in UTC
- `{HOSTNODE}` — up to 8 alphanumeric chars from HOST node name
- `{DESTNODE}` — up to 4 chars from primary non-HOST node location
- `v{VERSION}` — plan schema version (currently `v2`)
- `{HASH8}` — 8 hex chars from a DJB-style polynomial hash of the
  canonical JSON serialisation

### LTX Quantum
The base time unit for an LTX session, in minutes. All segment durations
are expressed as whole-number multiples of the quantum. The default quantum
is **3 minutes**. The quantum must be set to at least the round-trip
propagation delay between the two most distant nodes to ensure no
transmitted content can arrive during the same segment that sent it.

---

## M

### Mars Coordinated Time (MTC)
The local solar time at the Airy Mean Time meridian on Mars. Equivalent
to "Mars UTC" — the global reference clock for Mars operations. MTC is
not an Earth-derived timescale; it is based on the Mars sol (88,775.244 s).

### Mars Sol
The mean Martian solar day: **88,775.244 seconds** (24h 39m 35.244s).
Approximately 2.75% longer than an Earth day. The fundamental time unit
for Mars surface operations. IPT uses the sol as the basis for MTC and
all Mars planetary time calculations.

### Meeting Window
A period during which two parties, on different worlds, are both within
their respective work hours simultaneously (accounting for light-travel
delay so that real-time exchange is possible). Meeting windows are the
primary output of `findMeetingWindows()` in IPT.

### MERGE segment
An LTX session segment type. A period of joint collaborative activity —
all nodes are transmitting and receiving simultaneously, treating the
exchange as a shared workspace (e.g., a joint document edit, a real-time
multi-party discussion at low-delay distances).

---

## N

### Node (LTX)
A participant in an LTX session. A node has:
- `id` — unique identifier within the session (e.g. "N0", "N1")
- `name` — display name
- `role` — HOST or PARTICIPANT
- `delay` — one-way propagation delay from HOST in seconds
- `location` — planet or body string

### Node URL
A perspective-specific join URL for a single LTX participant. Each node
receives a URL encoding the same plan config (`#l=...` hash) but with a
`?node=Nx` query parameter that controls which perspective the LTX
runner displays.

---

## P

### PARTICIPANT (LTX node role)
Any non-HOST node in an LTX session. Receives transmissions from the HOST
and sends replies during RX segments. A session may have multiple
PARTICIPANT nodes at different delays (multi-party LTX).

### Plan Config (v2)
The canonical JSON object describing an LTX session:
```json
{
  "v": 2,
  "title": "string",
  "start": "ISO8601",
  "quantum": 3,
  "mode": "LTX",
  "nodes": [...],
  "segments": [...]
}
```
Version 2 is the current standard. Version 1 configs can be upgraded
with `upgradeConfig()`. Canonical key order: `v`, `title`, `start`,
`quantum`, `mode`, `nodes`, `segments`.

### PLAN_CONFIRM segment
The opening segment of an LTX session. All nodes confirm receipt of the
plan config and signal readiness to proceed. During PLAN_CONFIRM no
substantive content is transmitted; the segment exists to synchronise
all participants to a common session state before the first TX begins.

---

## Q

### Quantum
See **LTX Quantum**.

---

## R

### RFC 5545 Extension for LTX
A proposed extension to the iCalendar standard (RFC 5545) defining
two new X-properties for LTX session events:
- `X-LTX-PLANID` — the canonical LTX plan ID
- `X-LTX-QUANTUM` — the session quantum in minutes
Documented in `RF5545 EXTENSION.md` and `ICS for LTX.md`.

### RFC 9557 (IXDTF)
The IETF standard extending ISO 8601 / RFC 3339 with timezone annotations
and calendar system suffixes. Relevant to IPT's planetary timezone
representation. Proposed planetary timezone prefixes (AMT, MMT, LMT, etc.)
are designed to be compatible with the IXDTF suffix syntax.

### RX segment
An LTX session segment type. The period during which the HOST receives
and processes replies transmitted by PARTICIPANT nodes during the
preceding transmission window. RX is always paired with a preceding TX
with sufficient inter-segment gap to accommodate the round-trip delay.

---

## S

### Signal Window
See **Async Send Window**.

### Sol
See **Mars Sol**.

### Synodic Period
The time between successive identical alignments of a planet relative to
Earth and the Sun (e.g., opposition to opposition, or conjunction to
conjunction). The Earth–Mars synodic period is approximately **779.94 days**.
Relevant to solar conjunction scheduling: each synodic period contains
exactly one solar conjunction.

---

## T

### TX segment
An LTX session segment type. The period during which the HOST transmits
to all PARTICIPANT nodes. Participants listen and compose replies. A TX
segment must be long enough for the transmitted content plus the round-trip
delay to the most distant PARTICIPANT.

---

## W

### Work Hour
A time unit within an IPT planet time calculation indicating whether
the current hour falls within a defined standard working day for that
world. The default model uses a 9–17 (09:00–17:00) local-time window
as the work period, with adjustments for Mars sol fractional day.
`is_work_hour` is a boolean field on the `PlanetTime` object.

### Work Period
A 4-hour block within a planet's 24-hour (or sol-length) day used as
the coarser scheduling granularity. Work periods are used for meeting
window detection when per-hour resolution is not required.

---

## Z

### Zero UTC Offset Timezone
A synthetic `tzinfo` implementation in IPT's Python and JavaScript
timezone helpers that anchors all planetary time calculations to UTC
rather than a terrestrial geographic timezone. Planet times are always
expressed as offsets from the planet's own reference clock, not from
Earth local time.

---

*See also: the LTX Specification, Whitepaper, proposed RFC 5545 Extension,
Draft Standard, and `LANGUAGE-SUPPORT.md`.*
