# interplanet-ltx

JavaScript SDK for the **LTX (Light-Time eXchange)** protocol — a deterministic structured meeting format designed for interplanetary sessions where signal propagation delay prevents real-time interaction.

## Installation

```bash
npm install interplanet-ltx
```

## Quick start

```js
// ESM
import { createPlan, encodeHash, buildNodeUrls, generateICS } from 'interplanet-ltx';

// CJS
const { createPlan, encodeHash, buildNodeUrls, generateICS } = require('interplanet-ltx');

// Browser CDN
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

The typed variant lives in `@interplanet/ltx` (see `typescript/ltx/`). The JS package ships a `dist/ltx-sdk.d.ts` declaration file for IDE support.

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

MIT — [interplanet.live](https://interplanet.live)
