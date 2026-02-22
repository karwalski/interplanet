# InterPlanet

Time zones on Earth are hard. Now try scheduling a meeting with a colleague working from an office near the Schiaparelli crater on Mars.

**[Try the tool at interplanet.live](https://interplanet.live)**

---

## What it does

InterPlanet is a multi-planet meeting scheduler and time zone dashboard. Add Earth cities and planets (Mars, Venus, Jupiter, Saturn, …) side-by-side to see the current local time on each world and find the best communication windows accounting for light-speed transmission delay.

Key features:
- Live clock for Earth cities and solar-system planets
- Mars Sol calendar (Airy Mean Time + 25 named time zones)
- One-way light-time delay and blackout periods for each planet pair
- Meeting planner: find overlapping work hours across planets and cities
- Share a link or export/import your city/planet configuration
- Multilingual (English, Spanish, German, French, Japanese + more)
- Works offline as a PWA — no account, no tracking

---

## Notes on Mars time

There is a lot of conflicting information about date and time on Mars, and no apparent agreed standard.

**Time algorithm** — primarily based on NASA/GISS Mars24 Sunclock:
https://www.giss.nasa.gov/tools/mars24/help/algorithm.html

**Mars year** — sidereal year (one orbit of the Sun). Year 1 begins with the great dust storm of 1956 as documented by Clancy et al.:
https://ui.adsabs.harvard.edu/abs/2000JGR...105.9553C/abstract

**Sols of the week** — derived from Julian Date (Sunday start) with Mars Year 0 starting on Monday. No clear standard exists, but day names are essential for a meeting planner — even a 4-day work week needs named days.

**Transmission delay** — light-time delay between Earth and Mars varies from ~3 to ~22 minutes one-way (up to ~44 minutes round-trip). The tool shows current delay and flags communication blackouts near solar conjunction.

---

## Files

| File | Description |
|---|---|
| `index.html` | App shell and city-card rendering |
| `sky.js` | All application logic (state, clocks, search, meeting planner) |
| `sky.css` | Styles (dark/light mode, responsive layout) |
| `planet-time.js` | Planet ephemeris and time calculations |
| `i18n.js` | Internationalisation / translation strings |
| `manifest.json` | PWA manifest |
| `v1.html` | Original Mars-only v1 app (preserved for reference) |

---

## v1 → v2 changes

The original `mars.html` (now `v1.html`) was a single-page Mars clock. Version 2 (the current `index.html`) adds:

- Full solar-system planet support
- Earth city search with 5,000+ cities
- Meeting planner with overlap finder
- Light-time delay and blackout visualisation
- Multilingual UI
- Share links and config export/import
- PWA offline support
- Accessibility (WCAG 2.1 AA)

---

## Licence

See [LICENSE](LICENSE).
