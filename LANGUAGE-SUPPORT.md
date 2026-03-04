# InterPlanet — Language Support Matrix

This document lists all languages for which InterPlanet SDK libraries exist,
their support status for **planet-time** (orbital mechanics, planet clocks,
meeting windows) and **LTX** (Light-Travel Xchange session protocol), and
the current version of each.

## Support Matrix

| Language | planet-time | LTX | Notes |
|---|:---:|:---:|---|
| **JavaScript** | ✓ 1.1.0 | ✓ 1.1.0 | Separate packages: `javascript/planet-time/`, `javascript/ltx/` |
| **TypeScript** | ✓ 1.1.0 | ✓ 1.0.0 | Native TS types; separate packages |
| **Python** | ✓ 0.1.0 | ✓ 1.0.0 | PyPI: `interplanet-time` / `interplanet-ltx` |
| **Java** | ✓ 1.0.0 | ✓ 1.0.0 | Maven Central; stdlib-only |
| **C** | ✓ 1.0.0 | ✓ 1.0.0 | `libinterplanet`; no external deps |
| **PHP** | ✓ 1.0.0 | ✓ 1.0.0 | Packagist; stdlib-only |
| **Ruby** | ✓ 1.0.0 | ✓ 1.0.0 | RubyGems; stdlib-only |
| **Go** | ✓ 1.0.0 | ✓ 1.0.0 | Go modules; stdlib-only |
| **Swift** | ✓ 1.0.0 | ✓ 1.0.0 | Swift Package Index; Foundation-only |
| **Rust** | ✓ 1.0.0 | ✓ 1.0.0 | Crates.io; stdlib-only |
| **R** | ✓ 0.1.0 | — | CRAN: `interplanet.time`; base R only |
| **C#** | — | ✓ 1.0.0 | NuGet; .NET 6; planet-time: backlog (18.11) |
| **Dart** | — | ✓ 1.0.0 | pub.dev; Dart 3; planet-time: backlog (18.12) |
| **Elixir** | — | ✓ 1.0.0 | Hex; Mix 1.14+; planet-time: backlog (18.13) |
| **F#** | — | ✓ 1.0.0 | NuGet; .NET 6; planet-time: backlog (18.14) |
| **Kotlin** | — | ✓ 1.0.0 | Maven Central; JVM; planet-time: backlog (18.15) |
| **Scala** | — | ✓ 1.0.0 | Maven Central; Scala 3 JVM; planet-time: backlog (18.16) |
| **Lua** | — | ✓ 1.0.0 | stdlib-only; Lua 5.3+; planet-time: backlog (18.19) |
| **OCaml** | — | ✓ 1.0.0 | stdlib-only; OCaml 4.13+; ocamlfind; planet-time: backlog (18.18) |
| **Zig** | — | ✓ 1.0.0 | stdlib-only; Zig 0.12+; no external deps; planet-time: backlog (18.17) |
| **Julia** | — | — | planet-time: backlog (18.10); LTX: backlog (18.20) |

**Legend:** ✓ = implemented · — = not yet implemented

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
│   └── planet-time/     ← R package
├── csharp/
│   └── ltx/             ← .NET NuGet package
├── dart/
│   └── ltx/             ← Dart pub package
├── elixir/
│   └── ltx/             ← Elixir Hex package
├── fsharp/
│   └── ltx/             ← .NET NuGet package
├── kotlin/
│   └── ltx/             ← Kotlin/JVM Maven artifact
├── scala/
│   └── ltx/             ← Scala 3 Maven artifact
├── lua/
│   └── ltx/             ← Lua 5.3+ module
├── ocaml/
│   └── ltx/             ← OCaml 4.13+ library (ocamlfind)
├── zig/
│   └── ltx/             ← Zig 0.12+ LTX library
└── julia/               ← (backlog — no implementations yet)
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

All LTX implementations conform to the cross-SDK vector test suite
(see `conformance/` in the project root).

---

## Backlog — Planet-Time Ports Pending

| Story | Language | Priority |
|---|---|---|
| 18.10 | Julia | Low |
| 18.11 | C# | Medium |
| 18.12 | Dart | Medium |
| 18.13 | Elixir | Medium |
| 18.14 | F# | Medium |
| 18.15 | Kotlin | Medium |
| 18.16 | Scala | Medium |
| 18.17 | Zig | Low |
| 18.18 | OCaml | Low |
| 18.19 | Lua | Low |

## Backlog — LTX Ports Pending

| Story | Language | Priority |
|---|---|---|
| 18.20 | Julia | Low |
| 18.21 | R | Low |
| 22.3 | CLI (`interplanet ltx` subcommands) | Medium |

---

*Last updated: 2026-03-02*
