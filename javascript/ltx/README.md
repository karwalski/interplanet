# interplanet-ltx

JavaScript SDK for the **LTX (Light-Time eXchange)** protocol — a deterministic structured meeting format designed for interplanetary sessions where signal propagation delay prevents real-time interaction.

## Installation

`interplanet-ltx` is **not yet published** to npm, so `npm install interplanet-ltx`
and the jsDelivr CDN URL below do not work yet. Install from a clone instead
(tested 29 Sep 2026 with Node 22):

```bash
git clone https://github.com/karwalski/interplanet.git
cd /path/to/your-project
npm install /path/to/interplanet/javascript/ltx
```

Or load `ltx-sdk.js` directly with a `<script>` tag or `require('./path/to/ltx-sdk.js')`.

## Quick start

```js
// ESM (the package is CommonJS, so use the default import)
import LtxSdk from 'interplanet-ltx';
const { createPlan, encodeHash, buildNodeUrls, generateICS } = LtxSdk;

// CJS
const { createPlan, encodeHash, buildNodeUrls, generateICS } = require('interplanet-ltx');

// Browser CDN (not available until the package is published to npm)
// <script src="https://cdn.jsdelivr.net/npm/interplanet-ltx/ltx-sdk.js"></script>
// window.LtxSdk.createPlan(...)
```

### Create a plan

```js
const plan = createPlan({
  hostName:   'Earth HQ',
  remoteName: 'Mars Hab-01',
  delay:      800,          // one-way signal delay in seconds
  title:      'Weekly sync',
  startIso:   '2026-03-15T14:00:00Z',
  quantum:    5,            // scheduling quantum in minutes
  mode:       'LTX-ASYNC',
});

console.log(plan);
// { v: 2, title: 'Weekly sync', startIso: '...', quantum: 5, mode: 'LTX-ASYNC',
//   nodes: [...], segments: [...] }
```

### Compute segment timeline

```js
import { computeSegments } from 'interplanet-ltx';

const segs = computeSegments(plan);
segs.forEach(s => {
  console.log(s.type, s.startMs, s.durMin, 'min');
});
```

### Encode / decode URL hash

```js
import { encodeHash, decodeHash } from 'interplanet-ltx';

const hash = encodeHash(plan);        // URL-safe base64 string
const url  = `https://interplanet.live/ltx.html#${hash}`;

const restored = decodeHash(hash);    // back to plan object
```

### Build per-node share URLs

```js
import { buildNodeUrls } from 'interplanet-ltx';

const urls = buildNodeUrls(plan, 'https://interplanet.live/ltx.html');
urls.forEach(({ name, url }) => console.log(name, url));
// Earth HQ  https://interplanet.live/ltx.html?node=N0#...
// Mars Hab-01  https://interplanet.live/ltx.html?node=N1#...
```

### Export to calendar (.ics)

```js
import { generateICS } from 'interplanet-ltx';

const ics = generateICS(plan);
// Save as meeting.ics and open in any calendar app
```

## REST client

The SDK includes an optional REST client for storing and retrieving sessions from the InterPlanet API.

```js
import { storeSession, getSession } from 'interplanet-ltx';

// Store a session (returns plan ID)
const { planId } = await storeSession(plan, 'https://api.interplanet.live');

// Retrieve a session by ID
const loaded = await getSession(planId, 'https://api.interplanet.live');
```

## TypeScript

The typed variant lives in `@interplanet/ltx` (see `typescript/ltx/`). The JS package ships an `ltx-sdk.d.ts` declaration file for IDE support. It is generated from the JSDoc in `ltx-sdk.js` with `make types` (needs `tsc` on PATH), and `make check-types` confirms it is current and compiles under a strict TypeScript consumer (`tests/types/consumer.ts`).

## API reference

| Function | Description |
|----------|-------------|
| `createPlan(opts)` | Build a validated LTX plan object |
| `computeSegments(plan)` | Compute segment timeline with absolute start times |
| `computeSegmentsMulti(plan)` | Multi-node segment computation |
| `encodeHash(plan)` | Encode plan to URL-safe base64 hash |
| `decodeHash(hash)` | Restore plan from hash |
| `buildNodeUrls(plan, baseUrl)` | Generate per-node perspective URLs |
| `buildDelayMatrix(plan)` | Pairwise delay matrix for all nodes |
| `totalMin(plan)` | Total session duration in minutes |
| `makePlanId(plan)` | Deterministic 8-char plan ID |
| `generateICS(plan)` | iCalendar string for calendar import |
| `storeSession(plan, apiBase)` | POST plan to REST API |
| `getSession(planId, apiBase)` | GET plan from REST API |
| `formatHMS(sec)` | Format seconds as H:MM:SS string |
| `formatUTC(date)` | Format Date as UTC string |

## License

GPL-3.0 — [interplanet.live](https://interplanet.live)
