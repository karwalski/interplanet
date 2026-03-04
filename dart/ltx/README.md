# interplanet_ltx — Dart SDK

Pure Dart 3 port of the InterPlanet LTX (Light-Time eXchange) meeting protocol SDK.

## Requirements

- Dart SDK >= 3.0.0
- No external dependencies (stdlib only: dart:convert, dart:io, dart:core)

## Usage

```dart
import 'package:interplanet_ltx/interplanet_ltx.dart';

// Create a plan
final plan = createPlan(
  title: 'Mars Session',
  start: '2024-01-15T14:00:00Z',
  delay: 800.0,
);

// Compute timed segments
final segs = computeSegments(plan);
print('Total: ${totalMin(plan)} minutes');

// Get plan ID
final id = makePlanId(plan);
print(id); // LTX-20240115-EARTHHQ-MARS-v2-xxxxxxxx

// URL hash encoding
final hash = encodeHash(plan);
final decoded = decodeHash(hash);

// Generate ICS calendar
final ics = generateIcs(plan);

// Node URLs
final urls = buildNodeUrls(plan, baseUrl: 'https://interplanet.live/ltx.html');
```

## API

### Constants
- `kVersion` — SDK version string
- `kDefaultQuantum` — default quantum in minutes (3)
- `kDefaultApiBase` — default API URL
- `kDefaultSegments` — default segment template list
- `kSegTypes` — valid segment type strings

### Core functions
- `createPlan({...})` → `LtxPlan`
- `upgradeConfig(LtxPlan)` → `LtxPlan`
- `computeSegments(LtxPlan)` → `List<LtxSegment>`
- `totalMin(LtxPlan)` → `int`
- `makePlanId(LtxPlan)` → `String`
- `encodeHash(LtxPlan)` → `String`
- `decodeHash(String)` → `LtxPlan?`
- `buildNodeUrls(LtxPlan, {baseUrl})` → `List<LtxNodeUrl>`
- `generateIcs(LtxPlan)` → `String`
- `formatHms(int)` → `String`
- `formatUtc(DateTime)` → `String`

### REST client (async, dart:io)
- `storeSession(LtxPlan, {apiBase})` → `Future<Map>`
- `getSession(String, {apiBase})` → `Future<Map>`
- `downloadIcs(String, Map, {apiBase})` → `Future<String>`
- `submitFeedback(Map, {apiBase})` → `Future<Map>`

## Running tests

```bash
make test
```

## Lint

```bash
make lint
```
