# Interplanet Time — ServiceNow Script Includes

This directory contains the two server-side **Script Include** artifacts for the
**Interplanet Time (IPT)** and **Light Time Exchange (LTX)** features, deployed in
the `x_snc_ipt` scoped application.

> **Note:** Client Scripts, Service Portal widgets, and UI Builder components are
> archived separately and not yet deployed. Only the Script Includes are active.

---

## Files

| File | Script Include | Purpose |
|------|----------------|---------|
| `script-includes/x_snc_ipt_PlanetTime.js` | `x_snc_ipt.PlanetTime` | Computes planet-specific time offsets, light-travel delay between solar system bodies, Mars Coordinated Time (MTC), and formatting helpers. ES5 compatible. |
| `script-includes/x_snc_ipt_LightTimeExchange.js` | `x_snc_ipt.LightTimeExchange` | Builds and manages LTX communication plans: segment scheduling, plan ID generation, total-minute calculation, and JSON serialisation. ES5 compatible. |

---

## Deployment

1. Open or create the `x_snc_ipt` scoped application in Studio.
2. Create a new **Script Include** for each file:
   - Name: `x_snc_ipt_PlanetTime` → paste contents of `x_snc_ipt_PlanetTime.js`
   - Name: `x_snc_ipt_LightTimeExchange` → paste contents of `x_snc_ipt_LightTimeExchange.js`
3. Set **Accessible from** = *All application scopes* for each Script Include.
4. Save and publish via Update Set.

---

## API

### `x_snc_ipt.PlanetTime`

```js
var pt = new x_snc_ipt.PlanetTime();

// Current planet time record
var rec = pt.getPlanetTime('mars');
// rec.planetKey, rec.hour, rec.minute, rec.second, rec.localMs, rec.lightTimeFormatted

// One-way light travel (seconds)
var sec = pt.lightTravelSeconds('earth', 'mars');

// Mars Coordinated Time
var mtc = pt.getMTC(); // "HH:MM:SS" string

// Heliocentric distance (AU)
var au = pt.bodyDistanceAu('jupiter'); // e.g. 5.2

// Human-readable duration
var str = pt.formatLightTime(1320); // "22 min"
```

### `x_snc_ipt.LightTimeExchange`

```js
var ltx = new x_snc_ipt.LightTimeExchange();

// Build a full plan
var sendTime = new GlideDateTime();
var plan = ltx.createPlan('earth', 'mars', sendTime, 60);
// plan.planId, plan.segments[], plan.totalMin, plan.oneWayLightFormatted

// Deterministic plan ID
var id = ltx.makePlanId('earth', 'mars', sendTime);
// e.g. "LTX-EARTH-MARS-202603041030"

// Compute segments only
var segs = ltx.computeSegments('earth', 'mars', sendTime, ltx._planetTime.lightTravelSeconds('earth', 'mars'));

// Total minutes across segments
var total = ltx.totalMin(segs);

// JSON for storage
var json = ltx.planToJson(plan);
```

---

## Related

- `/js/planet-time.js` — browser JS library (planet time core)
- `/demo/ltx.html` — LTX web demo
- `FEATURES.md` — Full feature list and backlog
- `STANDARDS.md` — Coding standards
