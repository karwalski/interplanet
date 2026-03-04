# InterPlanet

[![CI](https://github.com/interplanet/interplanet/actions/workflows/ci.yml/badge.svg)](https://github.com/interplanet/interplanet/actions/workflows/ci.yml)

Time zones on Earth are complex. Now imagine scheduling a meeting when your
colleague is on another planet entirely — where the local day is a different
length, the speed of light imposes a one-way signal delay of minutes to hours,
and the Sun can block communications altogether.

**[interplanet.live](https://interplanet.live)** — try it live

> Whitepapers on the LTX protocol and orbital time standards will be published
> soon. Watch the repository for updates.

---

## Table of contents

- [Web app](#web-app)
- [planet-time.js — JavaScript library](#planet-timejs--javascript-library)
- [Language ports](#language-ports)
- [LTX meeting protocol](#ltx-meeting-protocol)
- [LTX SDKs](#ltx-sdks)
- [Cross-language support matrix](#cross-language-support-matrix)
- [REST API](#rest-api)
- [CLI](#cli)
- [Algorithm notes](#algorithm-notes)
- [Licence](#licence)

---

## Web app

InterPlanet is a multi-planet meeting scheduler and time zone dashboard.
Add Earth cities and planets side-by-side to see the current local time on
each world and find the best communication windows — accounting for
light-speed transmission delay.

### Features

| Feature | Description |
|---------|-------------|
| **Planet & city clocks** | Live time for any Earth city (5 000+ locations) or solar-system body |
| **Mars Sol calendar** | Airy Mean Time + 25 named Mars time zones |
| **Light-time delay** | One-way signal delay and round-trip time for every planet pair |
| **LOS blackouts** | Solar conjunction detection — flags when the Sun blocks the signal path |
| **Meeting planner** | Finds overlapping work hours across cities and planets |
| **AI meeting assistant** | LLM-powered slot recommendations and dual-agent auto-negotiation |
| **LTX meeting runner** | Structured interplanetary meeting protocol with timed TX/RX segments |
| **Async send window** | "Can I send now?" — checks if a message will arrive during work hours |
| **Conjunction calendar** | 90-day blackout calendar for each planet pair |
| **Fairness score** | Quantifies whose work hours are most disrupted by a meeting time |
| **ICS / calendar export** | Standard .ics + Google Calendar / Outlook quick-add links |
| **Recurring meetings** | 4-week rotation preview with ICS series export |
| **Solar system orrery** | Live heliocentric canvas view with planet positions |
| **Time Travel** | Scrub any moment in time; all clocks and gradients update |
| **Drag-to-reorder** | HTML5 drag-and-drop city card reordering (desktop + touch) |
| **Shareable URL** | One-click board link (`#c=` hash) with copy-to-clipboard |
| **Keyboard shortcuts** | Full keyboard navigation; `?` opens shortcuts reference |
| **Embeddable widget** | `?widget=1` hides chrome for iframe embedding; postMessage API |
| **PWA / offline** | Service worker caches all assets; works without network |
| **i18n** | English, Spanish, German, French, Japanese + more |
| **WCAG 2.1 AA** | Fully accessible; screen-reader tested |
| **Dark / light mode** | System-aware with manual override |
| **Easter eggs** | Konami code, Pluto toggle, Y2K38 chip, Kerbal mode, Apollo 11 badge |

---

## planet-time.js — JavaScript library

The core calculation engine. Used directly by the web app and as the
reference implementation for all language ports.

```html
<!-- CDN / IIFE -->
<script src="https://interplanet.live/js/dist/planet-time.iife.js"></script>
<script>
  const pt = PlanetTime.getPlanetTime('mars', Date.now());
  console.log(pt.timeString);                    // "21:03"
  console.log(pt.isWorkHour);                    // true | false

  const lt = PlanetTime.lightTravelSeconds('earth', 'mars', new Date());
  console.log(PlanetTime.formatLightTime(lt));   // "14 min 22 s"
</script>
```

```js
// Node.js / CommonJS
const PT = require('./js/planet-time.js');
const wins = PT.findMeetingWindows('earth', 'mars', 7, new Date());
wins.forEach(w => console.log(w.startUtc, w.durationMin + ' min'));
```

**ESM (npm):**

```bash
npm install @interplanet/time   # TypeScript-native ESM/CJS package
```

```ts
import { getPlanetTime, lightTravelSeconds, findMeetingWindows } from '@interplanet/time';
```

### Core API

| Function | Returns |
|----------|---------|
| `getPlanetTime(planet, date, tzOffsetH?)` | `PlanetTime` — HMS, work status, sol info |
| `getMTC(date)` | `MTC` — Mars Coordinated Time |
| `getMarsTimeAtOffset(date, offsetH)` | `PlanetTime` at a Mars timezone offset |
| `lightTravelSeconds(from, to, date)` | `number` — one-way delay in seconds |
| `bodyDistanceAU(from, to, date)` | `number` — distance in AU |
| `checkLineOfSight(from, to, date)` | `LineOfSight` — blocked / degraded / clear |
| `lowerQuartileLightTime(from, to, ref)` | `number` — p25 delay over one Earth year |
| `findMeetingWindows(a, b, days, start?)` | `MeetingWindow[]` — overlapping work-hour windows |
| `calculateFairnessScore(windows, tzA, tzB)` | `object` — fairness metrics |
| `formatLightTime(seconds)` | `string` — "3 min 14 s" |
| `planetHelioXY(planet, date)` | `HelioPos` — heliocentric x, y, r, lon in AU |

**Planets:** `mercury` `venus` `earth` `mars` `jupiter` `saturn` `uranus` `neptune` `moon`

---

## Language ports

All ports implement the same API surface as `planet-time.js` and are
cross-validated against `c/fixtures/reference.json` (54 entries).

### JavaScript / TypeScript (native)

| Package | Location | Install |
|---------|----------|---------|
| `planet-time.js` (IIFE) | `javascript/planet-time/` | CDN or copy |
| `@interplanet/time` (npm, TS) | `typescript/planet-time/` | `npm install @interplanet/time` |

```ts
import { getPlanetTime } from '@interplanet/time';
const pt = getPlanetTime('mars', Date.now());
console.log(pt.timeString, pt.isWorkHour);
```

### Python

```bash
pip install interplanet-time
```

```python
from interplanet_time import get_planet_time, light_travel_seconds, Planet

pt = get_planet_time(Planet.MARS, int(time.time() * 1000))
print(pt.time_str, pt.is_work_hour)
```

Source: `python/planet-time/` · Python ≥ 3.10 · stdlib only

### Java

```bash
cd java && make && make test
```

```java
import com.interplanet.time.InterplanetTime;
import com.interplanet.time.Planet;

var pt = InterplanetTime.getPlanetTime(Planet.MARS, System.currentTimeMillis(), 0);
System.out.println(pt.timeStr() + "  work=" + pt.isWorkHour());

double lt = InterplanetTime.lightTravelSeconds(Planet.EARTH, Planet.MARS,
    System.currentTimeMillis());
System.out.println(InterplanetTime.formatLightTime(lt));
```

Source: `java/planet-time/` · Java 16+ · no Maven/Gradle (javac only)

### C / C++ / C# / Unity

```bash
cd c && make all    # builds libinterplanet.{a,dylib/so}, runs 224 unit tests
```

```c
#include "include/libinterplanet.h"

ipt_planet_time_t pt;
ipt_get_planet_time(IPT_MARS, utc_ms, 0, &pt);
printf("%s  work=%d\n", pt.time_str, pt.is_work_hour);

double lt = ipt_light_travel_s(IPT_EARTH, IPT_MARS, utc_ms);
```

```cpp
// C++17
#include "bindings/cpp/interplanet.hpp"
auto pt = ipt::getPlanetTime(ipt::Planet::Mars, utc_ms, 4);
```

```csharp
// C# / .NET
using Interplanet;
var pt = Api.GetPlanetTime(Planet.Mars, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(), 0);
```

Source: `c/planet-time/` · C99, C++17 · See [`c/planet-time/README.md`](c/planet-time/README.md)

### PHP

```php
use InterplanetTime\InterplanetTime as IPT;

$pt = IPT::getPlanetTime('mars', intval(microtime(true) * 1000));
echo $pt->timeStr . ($pt->isWorkHour ? ' (work)' : ' (rest)') . PHP_EOL;

$lt = IPT::lightTravelSeconds('earth', 'mars', intval(microtime(true) * 1000));
echo IPT::formatLightTime($lt) . PHP_EOL;
```

Source: `php/planet-time/` · PHP 8.1+ · PSR-4 autoloading

### Ruby

```ruby
require 'interplanet_time'

pt = InterplanetTime.get_planet_time(:mars, (Time.now.to_f * 1000).to_i)
puts "#{pt.time_str}  work=#{pt.is_work_hour}"
```

Source: `ruby/planet-time/` · Ruby 2.6+

### Go

```go
import ipt "github.com/interplanet/time"

pt := ipt.GetPlanetTime(ipt.Mars, time.Now().UnixMilli(), 0)
fmt.Println(pt.TimeStr, pt.IsWorkHour)

lt := ipt.LightTravelSeconds(ipt.Earth, ipt.Mars, time.Now().UnixMilli())
fmt.Println(ipt.FormatLightTime(lt))
```

Source: `go/planet-time/` · Go 1.21+

### Swift

```swift
import InterplanetTime

let pt = InterplanetTime.getPlanetTime(.mars, utcMs: Date().unixMs, tzOffsetH: 0)
print(pt.timeStr, pt.isWorkHour)
```

Source: `swift/planet-time/` · Swift 5.9+ · 237 tests (87 unit + 150 fixture)

### Rust

```rust
use interplanet_time::{get_planet_time, light_travel_seconds, Planet};

let pt = get_planet_time(Planet::Mars, 946_728_000_000, 0.0);
println!("{} work={}", pt.time_str, pt.is_work_hour);
```

Source: `rust/planet-time/` · Rust 1.70+ · no external dependencies

### R

```r
library(interplanet.time)

pt <- get_planet_time("mars", as.numeric(Sys.time()) * 1000)
cat(pt$time_str, pt$is_work_hour, "\n")
```

Source: `r/planet-time/` · R 4.1+ · base R only

### Port comparison

| Port | Language | Min version | Stdlib only | Fixture tested |
|------|----------|:-----------:|:-----------:|:--------------:|
| `planet-time.js` | JavaScript | Node ≥ 16 | ✅ | ✅ 54 |
| `@interplanet/time` | TypeScript | Node ≥ 16 | ✅ | ✅ 54 |
| `interplanet-time` | Python | 3.10+ | ✅ | ✅ 54 |
| `InterplanetTime` | Java | 16+ | ✅ | ✅ 54 |
| `libinterplanet` | C / C++ | C99 / C++17 | ✅ | ✅ 54 |
| `interplanet/time` | PHP | 8.1+ | ✅ | ✅ 54 |
| `interplanet_time` | Ruby | 2.6+ | ✅ | ✅ 54 |
| `github.com/interplanet/time` | Go | 1.21+ | ✅ | ✅ 54 |
| `InterplanetTime` | Swift | 5.9+ | ✅ | ✅ 54 |
| `interplanet-time` | Rust | 1.70+ | ✅ | ✅ 54 |
| `interplanet.time` | R | 4.1+ | ✅ | ✅ 54 |

---

## LTX meeting protocol

**LTX (Light-Time eXchange)** is a structured meeting protocol for
multi-party sessions with significant signal delays. It coordinates
who is transmitting, who is receiving, and when, so that no one talks
over a delayed signal.

### Segment types

| Segment | Description |
|---------|-------------|
| `PLAN_CONFIRM` | All parties confirm the plan and signal readiness |
| `TX` | Host transmits; participants listen and compose a reply |
| `RX` | Participants' replies arrive and are processed |
| `CAUCUS` | Private deliberation — no cross-party transmission |
| `BUFFER` | Scheduling buffer for delay variance |
| `MERGE` | Multi-party merge / collaborative work |

### Default session (3 min quantum = 39 min total)

```
PLAN_CONFIRM  6 min
TX            6 min   ← Earth sends
RX            6 min   ← Earth receives Mars reply (after 2× delay)
CAUCUS        6 min
TX            6 min
RX            6 min
BUFFER        3 min
```

### Plan config (v2 schema)

```json
{
  "v": 2,
  "title": "Q3 Mission Review",
  "start": "2026-03-01T14:00:00Z",
  "quantum": 3,
  "mode": "LTX",
  "nodes": [
    { "id": "N0", "name": "Earth HQ",    "role": "HOST",        "delay": 0,   "location": "earth" },
    { "id": "N1", "name": "Mars Hab-01", "role": "PARTICIPANT", "delay": 860, "location": "mars"  }
  ],
  "segments": [
    { "type": "PLAN_CONFIRM", "q": 2 },
    { "type": "TX",  "q": 2 },
    { "type": "RX",  "q": 2 },
    { "type": "CAUCUS", "q": 2 },
    { "type": "TX",  "q": 2 },
    { "type": "RX",  "q": 2 },
    { "type": "BUFFER", "q": 1 }
  ]
}
```

The config is URL-encoded as `#l=<base64>` and each participant
receives a perspective URL:

```
https://interplanet.live/ltx.html?node=N0#l=eyJ2IjoyLC4uLn0
https://interplanet.live/ltx.html?node=N1#l=eyJ2IjoyLC4uLn0
```

Labels flip automatically based on the viewer's node role.

---

## LTX SDKs

Each SDK is **independent of the planet-time library** and implements
the full LTX API: plan creation, segment computation, URL hash
encoding/decoding, ICS generation, and a REST client.

### JavaScript SDK

```js
const LtxSdk = require('./javascript/ltx/ltx-sdk.js');   // Node.js
// or window.LtxSdk after loading ltx-sdk.js in a browser

const plan = LtxSdk.createPlan({
  title: 'Q3 Mission Review',
  remoteName: 'Mars Hab-01',
  delay: 860,
  remoteLocation: 'mars',
});

const segs  = LtxSdk.computeSegments(plan);
const hash  = LtxSdk.encodeHash(plan);        // "#l=eyJ2Ij..."
const urls  = LtxSdk.buildNodeUrls(plan, 'https://interplanet.live/ltx.html');
const ics   = LtxSdk.generateICS(plan);
const id    = LtxSdk.makePlanId(plan);        // "LTX-20260301-EARTHHQ-MARSHA-v2-a3b2c1d0"
```

Source: `javascript/ltx/ltx-sdk.js` · TypeScript declarations: `javascript/ltx/dist/ltx-sdk.d.ts`

### TypeScript SDK

```bash
npm install @interplanet/ltx
```

```ts
import { createPlan, computeSegments, encodeHash, generateICS } from '@interplanet/ltx';
```

Source: `typescript/ltx/` · TypeScript 5+ · stdlib only

### Python SDK

```bash
pip install interplanet-ltx
```

```python
from interplanet_ltx import create_plan, compute_segments, encode_hash, generate_ics

plan = create_plan(title='Q3 Mission Review', delay=860, remote_name='Mars Hab-01')
segs = compute_segments(plan)
ics  = generate_ics(plan)
```

Source: `python/ltx/` · Python ≥ 3.10 · stdlib only

### LTX SDK API surface

| Function | Description |
|----------|-------------|
| `createPlan(opts)` | Create a new v2 plan config |
| `upgradeConfig(cfg)` | Migrate v1 config to v2 |
| `computeSegments(cfg)` | Return timed segment array with start/end `Date` |
| `totalMin(cfg)` | Total session duration in minutes |
| `makePlanId(cfg)` | Deterministic plan ID string |
| `encodeHash(cfg)` | Encode config to URL hash `#l=<base64>` |
| `decodeHash(hash)` | Decode config from URL hash |
| `buildNodeUrls(cfg, baseUrl)` | Perspective URL for each node |
| `generateICS(cfg)` | LTX-extended iCalendar content |
| `formatHMS(sec)` | Format seconds as `HH:MM:SS` / `MM:SS` |
| `formatUTC(dt)` | Format a date as `HH:MM:SS UTC` |
| `storeSession(cfg, apiBase?)` | POST plan to REST API |
| `getSession(planId, apiBase?)` | GET plan from REST API |
| `downloadICS(planId, opts, apiBase?)` | Download ICS from REST API |
| `submitFeedback(payload, apiBase?)` | Submit session feedback |

### All LTX SDK ports

| Language | Package | Location | Status |
|----------|---------|----------|--------|
| JavaScript | `ltx-sdk.js` | `javascript/ltx/` | ✅ 1.1.0 |
| TypeScript | `@interplanet/ltx` | `typescript/ltx/` | ✅ 1.0.0 |
| Python | `interplanet-ltx` | `python/ltx/` | ✅ 1.0.0 |
| Java | `interplanet-ltx` | `java/ltx/` | ✅ 1.0.0 |
| C | `libitx` | `c/ltx/` | ✅ 1.0.0 |
| PHP | `interplanet/ltx` | `php/ltx/` | ✅ 1.0.0 |
| Ruby | `interplanet_ltx` | `ruby/ltx/` | ✅ 1.0.0 |
| Go | `github.com/interplanet/ltx` | `go/ltx/` | ✅ 1.0.0 |
| Swift | `InterplanetLTX` | `swift/ltx/` | ✅ 1.0.0 |
| Rust | `interplanet-ltx` | `rust/ltx/` | ✅ 1.0.0 |
| C# | `InterplanetLTX` | `csharp/ltx/` | ✅ 1.0.0 |
| Dart | `interplanet_ltx` | `dart/ltx/` | ✅ 1.0.0 |
| Elixir | `interplanet_ltx` | `elixir/ltx/` | ✅ 1.0.0 |
| F# | `InterplanetLTX` | `fsharp/ltx/` | ✅ 1.0.0 |
| Kotlin | `interplanet-ltx` | `kotlin/ltx/` | ✅ 1.0.0 |
| Scala | `interplanet-ltx` | `scala/ltx/` | ✅ 1.0.0 |
| Lua | `interplanet_ltx` | `lua/ltx/` | ✅ 1.0.0 |
| OCaml | `interplanet_ltx` | `ocaml/ltx/` | ✅ 1.0.0 |
| Zig | `interplanet_ltx` | `zig/ltx/` | ✅ 1.0.0 |
| CLI | `interplanet ltx` subcommands | `cli/` | — (backlog 22.3) |

All SDKs are validated by the cross-SDK conformance suite (see `conformance/` in the project root).

---

## Cross-language support matrix

See **[LANGUAGE-SUPPORT.md](LANGUAGE-SUPPORT.md)** for the full matrix of
planet-time and LTX support across all 17 languages, directory paths,
versions, and backlog items for planet-time ports pending.

---

## REST API

Hosted at `https://interplanet.live/api/`. All timestamps are Unix
milliseconds (`int64`).

### Planet time — `api/time.php`

```
GET  /api/time.php?planet=mars&utc_ms=946728000000
GET  /api/time.php?from=earth&to=mars&utc_ms=946728000000
POST /api/time.php   { "planets": ["earth","mars"], "utc_ms": 946728000000 }
```

**Response:**
```json
{
  "planet": "mars", "utc_ms": 946728000000,
  "hour": 15, "minute": 45, "second": 34,
  "time_str": "15:45", "is_work_hour": false,
  "light_travel_s": 243.7
}
```

### LTX sessions — `api/ltx.php`

```
POST /api/ltx.php?action=session            Store a plan; returns plan_id
GET  /api/ltx.php?action=session&plan_id=…  Retrieve a stored plan
POST /api/ltx.php?action=ics&plan_id=…      Download ICS for a stored plan
POST /api/ltx.php?action=feedback           Submit session feedback
```

```bash
curl -X POST https://interplanet.live/api/ltx.php?action=session \
  -H 'Content-Type: application/json' \
  -d '{ "v":2, "title":"Test", "start":"2026-03-01T14:00:00Z",
         "quantum":3, "mode":"LTX",
         "nodes":[{"id":"N0","name":"Earth HQ","role":"HOST","delay":0,"location":"earth"},
                  {"id":"N1","name":"Mars Hab","role":"PARTICIPANT","delay":860,"location":"mars"}],
         "segments":[{"type":"TX","q":2},{"type":"RX","q":2}] }'
```

---

## CLI

```bash
npm install -g interplanet-time-cli
interplanet --help
```

| Command | Example | Description |
|---------|---------|-------------|
| `time <planet>` | `interplanet time mars` | Current local time on a planet |
| `mtc` | `interplanet mtc` | Mars Coordinated Time |
| `light-travel <from> <to>` | `interplanet light-travel earth mars` | One-way signal delay |
| `distance <from> <to>` | `interplanet distance earth jupiter` | Current distance in AU |
| `los <from> <to>` | `interplanet los earth mars` | Line-of-sight status |
| `windows <from> <to>` | `interplanet windows earth mars --days 7` | Meeting windows |
| `planets` | `interplanet planets` | List all supported planets |

Source: `cli/` · Node.js ≥ 16

---

## Algorithm notes

### Planetary time

Each body's local clock is computed from its solar day length and a
body-specific epoch. Orbital positions use Keplerian elements (Meeus 2nd ed.);
Kepler's equation is solved via Newton–Raphson to 1 × 10⁻¹² tolerance.

**Transmission delay** — one-way signal delay is `distance_AU × AU_SECONDS`
(AU_SECONDS = 149 597 870.7 / 299 792.458 s). Earth–Mars delay varies from
approximately 3 to 22 minutes; Earth–Jupiter from ~35 to ~52 minutes.
Solar conjunction (elongation < 3°) is flagged as a blackout.

### Mars-specific

There is no single agreed standard for Mars date and time.

**Time algorithm** — primarily based on NASA/GISS Mars24 Sunclock:
<https://www.giss.nasa.gov/tools/mars24/help/algorithm.html>

**Mars year** — sidereal year (one orbit of the Sun). Year 1 begins with
the great dust storm of 1956 as documented by Clancy et al.:
<https://ui.adsabs.harvard.edu/abs/2000JGR...105.9553C/abstract>

**Sols of the week** — derived from Julian Date (Sunday start) with Mars
Year 0 starting on Monday. No clear standard exists, but day names are
essential for a meeting planner.

---

## Licence

MIT — see [LICENSE](LICENSE).
