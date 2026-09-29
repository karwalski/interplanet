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

| Language | planet-time | LTX | Min version | Fixtures (full sweep, 29 Sep 2026) | Notes |
|---|:---:|:---:|---|:---:|---|
| **JavaScript** | ✓ 1.10.0 | ✓ 1.1.0 | Node ≥ 16 | ✅ 54 | `javascript/planet-time/`, `javascript/ltx/` |
| **TypeScript** | ✓ 1.1.0 | ✓ 1.1.0 | Node ≥ 16 | ✅ 54 | Native TS types; `typescript/planet-time/`, `typescript/ltx/` |
| **Python** | ✓ 0.1.0 | ✓ 1.1.0 | Python ≥ 3.10 | ✅ 54 | PyPI names `interplanet-time` / `interplanet-ltx` (not yet published) |
| **Java** | ✓ 1.1.0 | ✓ 1.0.0 | Java 16+ | ✅ 54 | stdlib-only; `java/planet-time/`, `java/ltx/` |
| **C** | ✓ 1.0.0 | ✓ 1.0.0 | C99 | ✅ 54 | `libinterplanet`; no external deps |
| **PHP** | ✓ 0.1.0 | ✓ 1.0.0 | PHP 8.1+ | ✅ 54 | Packagist (not yet published); PSR-4; stdlib-only |
| **Ruby** | ✓ 0.1.0 | ✓ 1.0.0 | Ruby 2.6+ | ✅ 54 | RubyGems (not yet published); stdlib-only |
| **Go** | ✓ 1.0.0 | ✓ 1.1.0 | Go 1.21+ | ✅ 54 | Go modules (module path not yet fetchable); stdlib-only |
| **Swift** | ✓ 1.0.0 | ✓ 1.1.0 | Swift 5.9+ | ✅ 54 | Swift Package Index (not yet listed); Foundation-only |
| **Rust** | ✓ 0.1.0 | ✓ 1.1.0 | Rust 1.70+ | ✅ 54 | crates.io (not yet published); stdlib-only |
| **R** | ✓ 0.1.0 | ✓ 1.0.0 | R 4.1+ | ✅ 54 | base R only; `r/planet-time/`, `r/ltx/` |
| **C#** | ✓ 1.0.0 | ✓ 1.1.0 | .NET 8+ | ✅ 54 | NuGet (not yet published); `csharp/planet-time/`, `csharp/ltx/` |
| **Dart** | ✓ 0.1.0 | ✓ 1.1.0 | Dart 3+ | ✅ 54 | pub.dev (not yet published); `dart/planet-time/`, `dart/ltx/` |
| **Elixir** | ✓ 0.1.0 | ✓ 1.1.0 | Elixir 1.14+ | ✅ 54 | Hex (not yet published); Mix; `elixir/planet-time/`, `elixir/ltx/` |
| **F#** | ✓ 1.0.0 | ✓ 1.1.0 | .NET 8+ | ✅ 54 | NuGet (not yet published); `fsharp/planet-time/`, `fsharp/ltx/` |
| **Kotlin** | ✓ 1.0.0 | ✓ 1.1.0 | Kotlin 1.9+ JVM | ✅ 54 | Maven Central (not yet published); `kotlin/planet-time/`, `kotlin/ltx/` |
| **Scala** | ✓ 0.1.0 | ✓ 1.1.0 | Scala 3 JVM | ✅ 54 | Maven Central (not yet published); `scala/planet-time/`, `scala/ltx/` |
| **Lua** | ✓ 1.0.0 | ✓ 1.1.0 | Lua 5.3+ | ✅ 54 | stdlib-only; `lua/planet-time/`, `lua/ltx/` |
| **OCaml** | ✓ 1.0.0 | ✓ 1.1.0 | OCaml 4.13+ | ✅ 54 | ocamlfind; `ocaml/planet-time/`, `ocaml/ltx/` |
| **Zig** | ✓ 1.0.0 | ✓ 1.1.0 | Zig 0.12+ | ✅ 54 | stdlib-only; `zig/planet-time/`, `zig/ltx/` |
| **Julia** | ✓ 0.1.0 | ✓ 1.0.0 | Julia 1.9+ | ✅ 54 | stdlib-only; `julia/planet-time/`, `julia/ltx/` |

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

Two layers of checks exist.

- **CI:** [`.github/workflows/conformance.yml`](.github/workflows/conformance.yml) runs every port's planet-time fixture runner against [`c/planet-time/fixtures/reference.json`](c/planet-time/fixtures/reference.json) (54 entries) and writes a results table to the run summary. Runs: https://github.com/karwalski/interplanet/actions/workflows/conformance.yml. It had not yet run on GitHub when this section was written.
- **Full sweep:** [`scripts/sweep/run-all.sh`](scripts/sweep/README.md) runs every port's planet-time and LTX suites (unit tests, fixture runner, golden planId vectors in [`spec/golden/plan-ids.json`](spec/golden/plan-ids.json) and [`spec/golden/plan-id-prefixes.json`](spec/golden/plan-id-prefixes.json), lint and package builds), a planet-time accuracy comparison against `planet-time.js` at 200 seeded instants from 1990 to 2100, the cross-port planId interop runner ([`scripts/interop/`](scripts/interop/README.md)), the version check, the web app in a browser, and the API, relay, MCP, CLI and replication-kit suites.

Result of the full sweep on 29 September 2026 (x86_64 Linux): **51 of 51 entries passed.** Every port in the matrix above passes all 54 fixture entries and all golden planId vectors; the interop runner reports 25 of 25 port rows passing; every port agrees with `planet-time.js` on all accuracy cases. The toke demo CLI (`toke/`, built with the pinned tkc) passes 703 checks; it is a demo, not a library, and is not listed in the matrix.

Known open issue: [#39](https://github.com/karwalski/interplanet/issues/39). Mars Coordinated Time in `planet-time.js`, and therefore in every port and in `reference.json`, is about 52 minutes off the Allison and McEwen (2000) / Mars24 value. The ports agree with each other; the reference itself needs correcting.

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
