# scala-ltx

A pure Scala 3 (JVM) port of the LTX (Light-Time eXchange) SDK.

No external dependencies — uses only the Scala standard library,
`java.util.Base64`, and `java.net.HttpURLConnection`.

## Requirements

- Scala 3 (`scalac` / `scala` in PATH) for `make test`, or sbt 1.10 for `make sbt-test`
- JVM 11+ (tested with JDK 17)

## Compile and test

```sh
make test       # scalac + java
make sbt-test   # sbt, fetches Scala 3.6.4 from Maven Central
```

## Usage

```scala
import InterplanetLtx.*

// Create a session plan
val plan = InterplanetLtx.createPlan(Map(
  "title" -> "Mars Mission Briefing",
  "start" -> "2026-03-15T14:00:00Z",
  "nodes" -> List(
    Map("id" -> "N0", "name" -> "Earth HQ",    "role" -> "HOST",        "delay" -> 0,   "location" -> "earth"),
    Map("id" -> "N1", "name" -> "Mars Hab-01", "role" -> "PARTICIPANT", "delay" -> 840, "location" -> "mars")
  )
))

// Get the deterministic plan ID
val id = InterplanetLtx.makePlanId(plan)
// => "LTX-20260315-EARTHHQ-MARS-v2-xxxxxxxx"

// Encode to URL hash
val hash = InterplanetLtx.encodeHash(plan)
// => "#l=eyJ2IjoyLCJ0aXRsZSI6..."

// Decode from URL hash
val decoded: Option[LtxPlan] = InterplanetLtx.decodeHash(hash)

// Compute timed segments
val segments: List[LtxSegment] = InterplanetLtx.computeSegments(plan)

// Generate ICS calendar file
val ics: String = InterplanetLtx.generateICS(plan)

// Build node perspective URLs
val urls: List[LtxNodeUrl] = InterplanetLtx.buildNodeUrls(plan, "https://interplanet.live/ltx.html")

// Total duration in minutes
val mins: Int = InterplanetLtx.totalMin(plan)  // 65 (13 quanta x 5 min)

// Format helpers
val hms: String = InterplanetLtx.formatHMS(3661)  // "01:01:01"
val utc: String = InterplanetLtx.formatUTC(System.currentTimeMillis())
```

## API

| Method | Description |
|--------|-------------|
| `createPlan(config)` | Create a new LTX session plan |
| `upgradeConfig(plan)` | Upgrade a v1 plan to v2 schema |
| `computeSegments(plan)` | Compute timed segments with startMs/endMs |
| `totalMin(plan)` | Total session duration in minutes |
| `makePlanId(plan)` | Deterministic plan ID string |
| `encodeHash(plan)` | Base64url URL hash fragment |
| `decodeHash(b64)` | Decode plan from URL hash |
| `buildNodeUrls(plan, baseUrl)` | Perspective URLs for all nodes |
| `generateICS(plan)` | iCalendar (.ics) content |
| `formatHMS(seconds)` | Format seconds as HH:MM:SS or MM:SS |
| `formatUTC(ms)` | Format UTC ms as YYYY-MM-DDTHH:MM:SSZ |

## Plan maps, validation and registers

| Method | Description |
|--------|-------------|
| `LtxPlans.makePlanId(map)` / `LtxPlans.planHash(map)` | planId and plan hash over a plain JSON plan map (insertion order kept, as ltx-sdk.js); passes `spec/golden/plan-ids.json` |
| `LtxPlans.validatePlan(value)` | `PlanValidation(valid, errors)` with every ltx-sdk.js code, including `reserved_streams` / `reserved_branching` (spec §3.5, §7) |
| `LtxJson.parse` / `stringify` / `canonical` | JSON parse, `JSON.stringify` and canonical JSON equivalents |
| `V11.createSession(plan, planId)` / `V11.createSessionFromMap(map, planId)` | Throw `LtxPlanException` (code `reserved_streams` / `reserved_branching`) for reserved fields |
| `V11.reduceDecisions(entries)` | Decision register (`decision` / `decision_update`, spec §10.3) |
| `V11.runMergeSegment(...)` | MERGE: verified merge + signed `merge_snapshot` with question, action and decision registers |

## REST client (RestClient object)

| Method | Description |
|--------|-------------|
| `storeSession(plan, apiBase?)` | Store plan on server |
| `getSession(planId, apiBase?)` | Retrieve plan by ID |
| `downloadICS(planId, optsJson, apiBase?)` | Download ICS from server |
| `submitFeedback(payloadJson, apiBase?)` | Submit feedback |
