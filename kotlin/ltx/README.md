# kotlin-ltx

Kotlin/JVM port of the InterPlanet LTX (Light-Time eXchange) SDK.

**Package:** `com.interplanet:ltx`
**Kotlin:** 1.9+
**JVM:** 11+
**No external dependencies** (pure stdlib only)

## Installation

### Compile with kotlinc

```bash
cd kotlin-ltx
make build
```

### Run tests

```bash
make test
```

### Lint (compile library sources only)

```bash
make lint
```

## Usage

### Create a plan

```kotlin
import com.interplanet.ltx.*

val host = LtxNode("N0", "Earth HQ",    "host",        delay = 0,    location = "earth")
val mars = LtxNode("N1", "Mars Base",   "participant", delay = 1240, location = "mars")

val plan = InterplanetLTX.createPlan(
    title    = "Q3 Science Review",
    nodes    = listOf(host, mars),
    quantum  = 5,
    mode     = "async",
    start    = "2040-06-01T14:00:00Z"
)
```

### Encode/decode a URL hash

```kotlin
val hash    = InterplanetLTX.encodeHash(plan)  // "#l=eyJ2Ij..."
val decoded = InterplanetLTX.decodeHash(hash)  // LtxPlan
```

### Generate an ICS calendar file

```kotlin
val ics = InterplanetLTX.generateICS(plan)
File("meeting.ics").writeText(ics)
```

### Format durations

```kotlin
InterplanetLTX.formatHMS(3661)    // "01:01:01"
InterplanetLTX.formatHMS(90)      // "01:30"
InterplanetLTX.formatUTC(0L)      // "00:00:00 UTC"
```

### Compute segments

```kotlin
val segments = InterplanetLTX.computeSegments(plan)
for (seg in segments) {
    println("${seg.segType}: ${InterplanetLTX.formatUTC(seg.startMs)} -> ${InterplanetLTX.formatUTC(seg.endMs)}")
}
```

### Build node URLs

```kotlin
val urls = InterplanetLTX.buildNodeUrls(plan, "https://interplanet.live/ltx.html")
for (nodeUrl in urls) {
    println("${nodeUrl.name}: ${nodeUrl.url}")
}
```

## API Reference

| Method | Description |
|---|---|
| `createPlan(title, nodes, quantum, mode, start, segments)` | Create a new LTX plan |
| `upgradeConfig(map)` | Upgrade a v1/map config to LtxPlan v2 |
| `computeSegments(plan)` | Compute timed segment array |
| `totalMin(plan)` | Total session duration in minutes |
| `makePlanId(plan)` | Deterministic plan ID string |
| `encodeHash(plan)` | Encode plan to URL hash fragment |
| `decodeHash(hash)` | Decode plan from URL hash fragment |
| `buildNodeUrls(plan, baseUrl)` | Build per-node perspective URLs |
| `generateICS(plan)` | Generate iCalendar (.ics) content |
| `formatHMS(seconds)` | Format seconds as HH:MM:SS or MM:SS |
| `formatUTC(epochMs)` | Format epoch ms as HH:MM:SS UTC |
