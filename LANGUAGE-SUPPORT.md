# InterPlanet — Language Support Matrix

This document lists all languages for which InterPlanet SDK libraries exist,
their support status for **planet-time** (orbital mechanics, planet clocks,
meeting windows) and **LTX** (Light-Travel Xchange session protocol), and
the current version of each.

## Parity Policy

Both **planet-time** and **LTX** must be implemented in exactly the same set of languages.
If a language has one, it must have both. Any gap is a tracked backlog item.

## Support Matrix

The version columns come from each port's manifest (or, where a port has no
manifest version, the source constant named in [`versions.json`](versions.json)).
`versions.json` is the single list of port versions; `node scripts/check-versions.js`
fails if a manifest, `versions.json`, this table or the README LTX table disagree,
and the [Versions workflow](.github/workflows/versions.yml) runs it on every push
and pull request.

| Language | planet-time | LTX | Min version | Fixtures (local, 29 Sep 2026) | Notes |
|---|:---:|:---:|---|:---:|---|
| **JavaScript** | ✓ 1.10.0 | ✓ 1.1.0 | Node ≥ 16 | ✅ 54 | `javascript/planet-time/`, `javascript/ltx/` |
| **TypeScript** | ✓ 1.1.0 | ✓ 1.1.0 | Node ≥ 16 | ✅ 54 | Native TS types; `typescript/planet-time/`, `typescript/ltx/` |
| **Python** | ✓ 0.1.0 | ✓ 1.1.0 | Python ≥ 3.10 | ✅ 54 | PyPI names `interplanet-time` / `interplanet-ltx` (not yet published) |
| **Java** | ✓ 1.1.0 | ✓ 1.0.0 | Java 16+ | ❌ 9 of 150 checks fail | stdlib-only; `java/planet-time/`, `java/ltx/` |
| **C** | ✓ 1.0.0 | ✓ 1.0.0 | C99 | no runner | `libinterplanet`; no external deps |
| **PHP** | ✓ 0.1.0 | ✓ 1.0.0 | PHP 8.1+ | ❌ 64 of 150 checks fail | Packagist (not yet published); PSR-4; stdlib-only |
| **Ruby** | ✓ 0.1.0 | ✓ 1.0.0 | Ruby 2.6+ | ❌ 9 of 150 checks fail | RubyGems (not yet published); stdlib-only |
| **Go** | ✓ 1.0.0 | ✓ 1.1.0 | Go 1.21+ | ✅ 54 | Go modules (module path not yet fetchable); stdlib-only |
| **Swift** | ✓ 1.0.0 | ✓ 1.1.0 | Swift 5.9+ | not run | Swift Package Index (not yet listed); Foundation-only |
| **Rust** | ✓ 0.1.0 | ✓ 1.1.0 | Rust 1.70+ | ✅ 54 | crates.io (not yet published); stdlib-only |
| **R** | ✓ 0.1.0 | ✓ 1.0.0 | R 4.1+ | ✅ 54 | base R only; `r/planet-time/`, `r/ltx/` |
| **C#** | ✓ 1.0.0 | ✓ 1.1.0 | .NET 8+ | ✅ 54 | NuGet (not yet published); `csharp/planet-time/`, `csharp/ltx/` |
| **Dart** | ✓ 0.1.0 | ✓ 1.1.0 | Dart 3+ | ✅ 54 | pub.dev (not yet published); `dart/planet-time/`, `dart/ltx/` |
| **Elixir** | ✓ 0.1.0 | ✓ 1.1.0 | Elixir 1.14+ | not run | Hex (not yet published); Mix; `elixir/planet-time/`, `elixir/ltx/` |
| **F#** | ✓ 1.0.0 | ✓ 1.1.0 | .NET 8+ | ✅ 54 | NuGet (not yet published); `fsharp/planet-time/`, `fsharp/ltx/` |
| **Kotlin** | ✓ 1.0.0 | ✓ 1.1.0 | Kotlin 1.9+ JVM | ❌ runner error | Maven Central (not yet published); `kotlin/planet-time/`, `kotlin/ltx/` |
| **Scala** | ✓ 0.1.0 | ✓ 1.1.0 | Scala 3 JVM | not run | Maven Central (not yet published); `scala/planet-time/`, `scala/ltx/` |
| **Lua** | ✓ 1.0.0 | ✓ 1.1.0 | Lua 5.3+ | ✅ 54 | stdlib-only; `lua/planet-time/`, `lua/ltx/` |
| **OCaml** | ✓ 1.0.0 | ✓ 1.1.0 | OCaml 4.13+ | ✅ 54 | ocamlfind; `ocaml/planet-time/`, `ocaml/ltx/` |
| **Zig** | ✓ 1.0.0 | ✓ 1.1.0 | Zig 0.12+ | ✅ 54 | stdlib-only; `zig/planet-time/`, `zig/ltx/` |
| **Julia** | ✓ 0.1.0 | ✓ 1.0.0 | Julia 1.9+ | not run | stdlib-only; `julia/planet-time/`, `julia/ltx/` |

**Legend:** ✓ = implemented · ✅ 54 = all 54 cross-language fixture entries pass · ❌ = the fixture runner reported failures or crashed · not run = no toolchain was available for the local run · no runner = the port has no reference.json runner · — = not yet implemented · unversioned = the port declares no version. Fixture results are from a local run on 29 September 2026; see [Conformance](#conformance).

## Package registry status

**No port is published to a package registry yet.** Registry names in this
document are the names declared in each port's manifest, not packages you can
install. On 29 September 2026 these lookups all returned 404: PyPI
`interplanet-time`, `interplanet-ltx`; npm `@interplanet/time`, `@interplanet/ltx`,
`interplanet-ltx`, `interplanet-planet-time`, `interplanet-time-cli`; crates.io
`interplanet-time`, `interplanet-ltx`; RubyGems `interplanet_time`, `interplanet_ltx`.
The repository had no git tags, so the tag-triggered publish workflows had never run.

Install from source instead. Tested commands for JavaScript, TypeScript,
Python, Go, Rust and the CLI are in the
[README Installation section](README.md#installation); the other ports build
from their own directories with the commands in each port's `Makefile`.
The release process and tag convention are in [docs/RELEASING.md](docs/RELEASING.md).

## Conformance

Every planet-time port is checked against the shared fixture file
[`c/planet-time/fixtures/reference.json`](c/planet-time/fixtures/reference.json):
54 entries (9 bodies at 6 dates) generated from `javascript/planet-time/planet-time.js`.

**CI:** the [Conformance workflow](https://github.com/karwalski/interplanet/actions/workflows/conformance.yml)
([source](.github/workflows/conformance.yml)) runs each port's fixture runner
in its own job on pushes to `main`, pull requests, weekly and on demand. Each
port uses `continue-on-error`, and the run summary contains a table with one row
per port (pass, fail, skipped or setup failed) and the runner's pass/fail counts.
The workflow was added on 29 September 2026; until it has run on GitHub, there
are no CI results to cite, and the table below is the only evidence.

**Local results, 29 September 2026:** 12 of 21 ports passed, 4 failed and 4
were not run; the C port has no fixture runner (its 224 unit tests passed). Each row was produced by the same command the workflow uses, run
in a Linux container against commit `ac29d38` plus the fixes in this change.
"Checks" are the individual field comparisons each runner makes; runners check
different fields, so counts differ between ports.

| Port | Result | Runner output | Toolchain |
|------|--------|---------------|-----------|
| JavaScript | ✅ pass | 54 of 54 entries reproduced | Node 22.22 |
| TypeScript | ✅ pass | 150 passed, 0 failed | Node 22.22, TypeScript 5 |
| Python | ✅ pass | 8 fixture tests passed (all 54 entries) | Python 3.11, pytest 9.1 |
| Java | ❌ fail | 141 passed, 9 failed (Saturn hour/minute at all 6 dates) | OpenJDK 21 |
| C | no runner | 224 unit tests passed; the C port does not read `reference.json` | GCC 13.3 |
| PHP | ❌ fail | 86 passed, 64 failed (Mercury, Venus, Saturn, Uranus, Neptune) | PHP 8.4 |
| Ruby | ❌ fail | 141 passed, 9 failed (Saturn hour/minute at all 6 dates) | Ruby 3.3 |
| Go | ✅ pass | 150 passed, 0 failed | Go 1.24 |
| Swift | not run | no Swift toolchain in the container | |
| Rust | ✅ pass | 144 passed, 0 failed | Rust 1.94 |
| R | ✅ pass | 216 passed, 0 failed | R 4.3.3, jsonlite 1.8.8 |
| C# | ✅ pass | 312 passed, 0 failed | .NET SDK 10.0.112 |
| Dart | ✅ pass | 312 passed, 0 failed | Dart 3.13.4 |
| Elixir | not run | Hex (`repo.hex.pm`) was unreachable, so the `jason` dependency could not be fetched | Elixir 1.14 |
| F# | ✅ pass | 312 passed, 0 failed | .NET SDK 10.0.112 |
| Kotlin | ❌ fail | runner crashed: `JSONException` on the `null` `light_travel_s` of the Earth entries | Gradle 8.5 wrapper, JDK 17 |
| Scala | not run | no sbt in the container | |
| Lua | ✅ pass | 678 passed, 0 failed | Lua 5.4.6 |
| OCaml | ✅ pass | 328 passed, 0 failed (fixture check inside the unit test binary) | OCaml 4.14.1 |
| Zig | ✅ pass | 648 passed, 0 failed | Zig 0.15.1 |
| Julia | not run | no Julia toolchain in the container | |

Before this change the Zig fixture runner did not compile on Zig 0.15.1
(`import of file outside module path`), and nine Makefiles pointed at a
non-existent `c/fixtures/reference.json`. Both are fixed; the libraries
themselves were not changed. The Java, PHP, Ruby and Kotlin failures are open.

The JavaScript row checks that `planet-time.js` still reproduces the committed
fixture file ([`scripts/conformance/js-reference-check.js`](scripts/conformance/js-reference-check.js)).
It passes, but note that `reference.json` records `js_version` 1.9.0 while
`planet-time.js` now reports 1.10.0.

LTX ports are not covered by this workflow yet. Copies of an LTX v1.1
conformance vector file (`v11.json`) exist in the Go, Rust and Zig LTX ports,
but there is no single shared LTX fixture file and runner comparable to
`reference.json`.

---

## Directory Structure

Each language lives in its own folder under `interplanet-github/`:

```
interplanet-github/
├── javascript/
│   ├── planet-time/     ← planet-time.js reference library
│   └── ltx/             ← ltx-sdk.js LTX SDK
├── typescript/
│   ├── planet-time/     ← @interplanet/time TypeScript package
│   └── ltx/             ← @interplanet/ltx TypeScript package
├── python/
│   ├── planet-time/     ← interplanet-time PyPI package
│   └── ltx/             ← interplanet-ltx PyPI package
├── java/
│   ├── planet-time/     ← Maven Central artifact
│   └── ltx/             ← Maven Central artifact
├── c/
│   ├── planet-time/     ← libinterplanet C library
│   └── ltx/             ← libinterplanet-ltx C library
├── php/
│   ├── planet-time/     ← Packagist package
│   └── ltx/             ← Packagist package
├── ruby/
│   ├── planet-time/     ← RubyGems gem
│   └── ltx/             ← RubyGems gem
├── go/
│   ├── planet-time/     ← Go module
│   └── ltx/             ← Go module
├── swift/
│   ├── planet-time/     ← Swift Package
│   └── ltx/             ← Swift Package
├── rust/
│   ├── planet-time/     ← Rust crate
│   └── ltx/             ← Rust crate
├── r/
│   ├── planet-time/     ← R package
│   └── ltx/             ← R LTX package
├── csharp/
│   ├── planet-time/     ← .NET NuGet package
│   └── ltx/             ← .NET NuGet package
├── dart/
│   ├── planet-time/     ← Dart pub package
│   └── ltx/             ← Dart pub package
├── elixir/
│   ├── planet-time/     ← Elixir Hex package
│   └── ltx/             ← Elixir Hex package
├── fsharp/
│   ├── planet-time/     ← F# .NET NuGet package
│   └── ltx/             ← F# .NET NuGet package
├── kotlin/
│   ├── planet-time/     ← Kotlin/JVM Maven artifact
│   └── ltx/             ← Kotlin/JVM Maven artifact
├── scala/
│   ├── planet-time/     ← Scala 3 Maven artifact
│   └── ltx/             ← Scala 3 Maven artifact
├── lua/
│   ├── planet-time/     ← Lua 5.3+ module
│   └── ltx/             ← Lua 5.3+ module
├── ocaml/
│   ├── planet-time/     ← OCaml 4.13+ library (ocamlfind)
│   └── ltx/             ← OCaml 4.13+ library (ocamlfind)
├── zig/
│   ├── planet-time/     ← Zig 0.12+ library
│   └── ltx/             ← Zig 0.12+ library
└── julia/
    ├── planet-time/     ← Julia 1.9+ package
    └── ltx/             ← Julia 1.9+ package
```

---

## What is planet-time?

The **planet-time** library provides:
- Real-time planetary clock computation for all 9 planets + Moon
- Mars Coordinated Time (MTC) and sol calendar
- Light-travel delay calculation between any two bodies
- Line-of-sight (conjunction/opposition) detection
- Meeting window finder: overlapping "work hours" across worlds
- Fairness scoring for cross-timezone meetings

## What is LTX?

The **LTX** (Light-Travel Xchange) library provides:
- `createPlan` / `upgradePlan` — session plan creation
- `computeSegments` / `totalMin` — segment timing
- `makePlanId` — canonical `LTX-YYYYMMDD-NODE-DEST-v2-HASH` identifier
- `encodeHash` / `decodeHash` — base64url plan serialisation
- `buildNodeUrls` — per-node join link generation
- `generateICS` — RFC 5545 calendar file output with LTX-PLANID headers
- `storeSession` / `getSession` / `downloadICS` / `submitFeedback` — REST client

There is no `conformance/` directory and no shared cross-SDK LTX test suite
yet; see [Conformance](#conformance) for what is currently checked.

---

*Last updated: 2026-09-29*
