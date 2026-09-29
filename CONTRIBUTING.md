# Contributing to InterPlanet

InterPlanet is an open-source interplanetary time and meeting scheduler. It converts Earth UTC to local time on any planet in the solar system, finds overlapping work hours across worlds, models communications delay and solar conjunction blackouts, and implements the LTX structured high-latency meeting protocol. See [docs/WHITEPAPER.md](docs/WHITEPAPER.md) for background on the project's goals and scientific basis.

This is an unusual project at the intersection of astronomy, networking, and human factors. Contributions are welcome at every level — corrections to planetary constants, new language ports, bug fixes, test coverage, documentation, and ideas.

---

## Where to Start

- **Issues** — Bug reports, feature requests, and questions live in [GitHub Issues](../../issues). Check for existing issues before opening a new one.
- **Discussions** — For open-ended ideas, design questions, or anything that isn't a clear bug or feature request, use [GitHub Discussions](../../discussions) once the maintainer enables it (it is currently disabled); until then, open an Issue.
- **Pull Requests** — All code changes go through PRs. Fork the repo, make your change on a branch, and open a PR against `main`.

---

## Contribution Entry Points

If you are not sure where to start, these are the areas where help is most useful. Each one links to the files to read first.

**Interoperability and new ports**
- The [Conformance section of LANGUAGE-SUPPORT.md](LANGUAGE-SUPPORT.md#conformance) lists which ports pass `c/planet-time/fixtures/reference.json`. Open items on 29 Sep 2026: the Java and Ruby ports fail Saturn checks, the PHP port fails 64 of 150 checks, the Kotlin fixture runner crashes on `null` light-travel values, and the C port has no `reference.json` runner.
- Swift, Scala, Julia and Elixir could not be run in the 29 Sep 2026 local check; the [Conformance workflow](.github/workflows/conformance.yml) will show their first CI results.
- LTX ports share no single conformance runner yet. Compare the per-port copies of `v11.json` with [docs/LTX-SPECIFICATION.md](docs/LTX-SPECIFICATION.md).
- Keep [`versions.json`](versions.json) in step with any manifest you change (`node scripts/check-versions.js`).

**Scheduling research**
- LTX is a structured protocol for meetings under long signal delay. Start with [docs/LTX-SPECIFICATION.md](docs/LTX-SPECIFICATION.md) and [docs/RFC5545-EXTENSION.md](docs/RFC5545-EXTENSION.md).
- The research notes in `docs/research/` summarise related human-factors work (Fischer and Mosier on communication protocols under delay) and propose stories such as protocol templates and a replication study kit. Topic and threading features are deliberately limited to design work until a patent question is reviewed; read those notes before proposing them.

**Scientific validation**
- Check the orbital mechanics and planetary time definitions against independent sources (for example NASA GISS Mars24 and the IAU WGCCRE reports). The reference implementation is [`javascript/planet-time/planet-time.js`](javascript/planet-time/planet-time.js); the definitions and their sources are in [docs/TIMEZONES.md](docs/TIMEZONES.md), [docs/DRAFT-STANDARD.md](docs/DRAFT-STANDARD.md) and [docs/WHITEPAPER.md](docs/WHITEPAPER.md).
- New reference dates or bodies go into [`c/planet-time/tests/generate_fixtures.js`](c/planet-time/tests/generate_fixtures.js), which regenerates the shared fixtures.

**Documentation**
- Every install command must work or be marked "not yet published" with a tested source command: see [README.md](README.md#installation) and [docs/RELEASING.md](docs/RELEASING.md).
- Per-port READMEs, [docs/API.md](docs/API.md) and [docs/GLOSSARY.md](docs/GLOSSARY.md) need examples checked against the current code.

**Accessibility**
- The web app in [`demo/`](demo/) targets WCAG 2.1 AA. Keyboard-only use, screen-reader announcements for the live clocks and the LTX session view ([`demo/ltx.html`](demo/ltx.html)), and colour contrast in both themes are all worth testing and reporting.

---

## Repository Structure

```
interplanet-github/
├── demo/               Web application (index.html, sky.js, assets/)
├── js/                 JavaScript library (planet-time.js)
│                         demo/planet-time.js is a symlink to ../js/planet-time.js
├── python/             Python library (interplanet-time package, interplanet-ltx)
├── c/                  C library (libinterplanet; planet-time and LTX)
│   └── fixtures/       Cross-language reference fixtures (reference.json)
├── typescript/         TypeScript ports (planet-time, ltx)
├── go/                 Go port
├── rust/               Rust port
├── java/               Java port
├── kotlin/             Kotlin port (LTX)
├── swift/              Swift port
├── ruby/               Ruby port
├── php/                PHP port
├── r/                  R port (planet-time)
├── csharp/             C# port (LTX)
├── dart/               Dart port (LTX)
├── elixir/             Elixir port
├── fsharp/             F# port (LTX)
├── scala/              Scala port (LTX)
├── lua/                Lua port (LTX)
├── ocaml/              OCaml port (LTX)
├── zig/                Zig port (LTX)
├── julia/              Julia port (backlog)
├── javascript/         JavaScript LTX library (separate from js/)
├── node/               Node.js utilities
├── servicenow/         ServiceNow integration
├── docs/               Public-facing documentation
│   ├── GLOSSARY.md
│   ├── IPT-PLATFORM-SUPPORT.md
│   ├── TIMEZONES.md
│   ├── DRAFT-STANDARD.md
│   ├── WHITEPAPER.md
│   ├── LTX-SPECIFICATION.md
│   ├── RFC5545-EXTENSION.md
│   ├── API.md
│   └── LOCATION-API.md
└── tests/
    └── e2e/            Playwright end-to-end tests (CJS, workers: 1)
        └── helpers/    page-helpers.js loads demo/index.html
```

Internal documents (not in `docs/`) — STANDARDS.md, TESTING.md, FEATURES.md, DEVELOPMENT-PLAN.md — are in the working directory and not published with the repository.

---

## Development Setup

### Web app and JavaScript library

```bash
# Install dependencies (Playwright and test tooling)
npm install

# Run E2E tests
npx playwright test

# Run unit tests for planet-time.js
node test-planet-time.js
```

The E2E tests use Playwright with `workers: 1`. Tests load the app directly from the filesystem via `file://` protocol. See the notes in `tests/e2e/helpers/page-helpers.js` for the `gotoApp` helper.

### Python library

```bash
cd python/planet-time
pip install -e .
pytest
```

### C library

```bash
cd c/planet-time
make
./test_planet_time
```

Each language port contains its own README with build and test instructions.

---

## Adding a New Language Port

The existing ports (Python, Go, Rust, Java, Swift, Ruby, PHP, and the LTX ports in Kotlin, C#, Dart, Elixir, F#, Scala, Lua, OCaml, Zig) are good references. Look at a port whose idioms are closest to your target language.

A planet-time port must:

1. Implement the core time conversion functions: `getPlanetTime`, `getMTC` (Mars), `lightTravelSeconds`, `findMeetingWindows`, and the `PLANETS` / `ZONES` data.
2. Use the Allison & McEwen (2000) formula for Mars with `JDTT` (not `JDUTC`).
3. Pass all cross-language fixture tests in `c/planet-time/fixtures/reference.json`, and add the port to the matrix in [`.github/workflows/conformance.yml`](.github/workflows/conformance.yml). These fixtures define authoritative input/output pairs for all supported planets and cover edge cases.
4. Include a README that documents installation, usage, and how to run the tests.
5. Be stdlib-only or as close to it as the language ecosystem allows. No heavy external dependencies.

An LTX port must:

1. Implement the SessionPlan data model from [docs/LTX-SPECIFICATION.md](docs/LTX-SPECIFICATION.md).
2. Support JSON serialisation with lexicographically sorted keys and SHA-256 planId hashing.
3. Pass the LTX v1.1 conformance vectors (`v11.json`, copied in `go/ltx/testdata/`, `rust/ltx/tests/` and `zig/ltx/src/`).

See `LANGUAGE-SUPPORT.md` in the repository root for the current support matrix and backlog.

---

## Documentation

Public-facing documentation lives in `docs/`. If your change affects the public API, the timezone definitions, the LTX protocol, or the RFC 5545 extension, update or note the relevant document.

The internal documents (STANDARDS.md, TESTING.md, FEATURES.md) are not in `docs/`. Refer to STANDARDS.md for versioning rules, naming conventions, A11y requirements, and i18n guidelines.

---

## Code Style

Read STANDARDS.md before submitting a PR. Key points:

- Versioning: query-string `?v=X.Y.Z` on local assets; bump the minor version whenever any JS or CSS file changes before pushing. The `VERSION` constant in `planet-time.js`, `CACHE_VERSION` in `sw.js`, and the LTX `PRODID` must all match.
- The JavaScript library is zero-dependency. Do not add external runtime dependencies.
- Accessibility: WCAG 2.1 AA minimum. No `opacity` on text elements (use `rgba` on `color` instead).
- Tests: every new feature needs a test. E2E tests use Playwright; unit tests use the Node.js test runner.

---

## Submitting Changes

1. Fork the repository and create a branch from `main`.
2. Make your change. Keep commits focused; one logical change per commit is preferred.
3. Make sure the tests pass: `npx playwright test` for E2E, and the unit/language tests for anything you've touched.
4. Open a pull request against `main`. There is no formal PR template yet — just describe what changed and why, and reference any related issues.
5. A maintainer will review and may request changes before merging.

For significant changes (new language ports, changes to the timezone definitions or LTX protocol, changes to the API surface), it is worth opening a Discussion or Issue first to agree on the approach before writing code.

---

## Community

This project lives at the intersection of planetary astronomy, software engineering, and human factors for space operations. Contributors come from a wide range of backgrounds. Please be respectful and constructive in all interactions.

There is no formal code of conduct document yet, but the expectation is simple: treat people well, engage in good faith, and focus on making the project better. If something feels off, contact the maintainers.
