# InterPlanet — Language Support Matrix

This document lists all languages for which InterPlanet SDK libraries exist,
their support status for **planet-time** (orbital mechanics, planet clocks,
meeting windows) and **LTX** (Light-Travel Xchange session protocol), and
the current version of each.

## Parity Policy

Both **planet-time** and **LTX** must be implemented in exactly the same set of languages.
If a language has one, it must have both. Any gap is a tracked backlog item.

## Support Matrix

| Language | planet-time | LTX | Min version | Fixture tested | Notes |
|---|:---:|:---:|---|:---:|---|
| **JavaScript** | ✓ 1.1.0 | ✓ 1.1.0 | Node ≥ 16 | ✅ 54 | `javascript/planet-time/`, `javascript/ltx/` |
| **TypeScript** | ✓ 1.1.0 | ✓ 1.0.0 | Node ≥ 16 | ✅ 54 | Native TS types; `typescript/planet-time/`, `typescript/ltx/` |
| **Python** | ✓ 0.1.0 | ✓ 1.0.0 | Python ≥ 3.10 | ✅ 54 | PyPI: `interplanet-time` / `interplanet-ltx` |
| **Java** | ✓ 1.0.0 | ✓ 1.0.0 | Java 16+ | ✅ 54 | stdlib-only; `java/planet-time/`, `java/ltx/` |
| **C** | ✓ 1.0.0 | ✓ 1.0.0 | C99 | ✅ 54 | `libinterplanet`; no external deps |
| **PHP** | ✓ 1.0.0 | ✓ 1.0.0 | PHP 8.1+ | ✅ 54 | Packagist; PSR-4; stdlib-only |
| **Ruby** | ✓ 1.0.0 | ✓ 1.0.0 | Ruby 2.6+ | ✅ 54 | RubyGems; stdlib-only |
| **Go** | ✓ 1.0.0 | ✓ 1.0.0 | Go 1.21+ | ✅ 54 | Go modules; stdlib-only |
| **Swift** | ✓ 1.0.0 | ✓ 1.0.0 | Swift 5.9+ | ✅ 54 | Swift Package Index; Foundation-only |
| **Rust** | ✓ 1.0.0 | ✓ 1.0.0 | Rust 1.70+ | ✅ 54 | Crates.io; stdlib-only |
| **R** | ✓ 0.1.0 | ✓ 0.1.0 | R 4.1+ | ✅ 54 | base R only; `r/planet-time/`, `r/ltx/` |
| **C#** | ✓ 1.0.0 | ✓ 1.0.0 | .NET 8+ | ✅ 54 | NuGet; `csharp/planet-time/`, `csharp/ltx/` |
| **Dart** | ✓ 1.0.0 | ✓ 1.0.0 | Dart 3+ | ✅ 54 | pub.dev; `dart/planet-time/`, `dart/ltx/` |
| **Elixir** | ✓ 1.0.0 | ✓ 1.0.0 | Elixir 1.14+ | ✅ 54 | Hex; Mix; `elixir/planet-time/`, `elixir/ltx/` |
| **F#** | ✓ 1.0.0 | ✓ 1.0.0 | .NET 8+ | ✅ 54 | NuGet; `fsharp/planet-time/`, `fsharp/ltx/` |
| **Kotlin** | ✓ 1.0.0 | ✓ 1.0.0 | Kotlin 1.9+ JVM | ✅ 54 | Maven Central; `kotlin/planet-time/`, `kotlin/ltx/` |
| **Scala** | ✓ 1.0.0 | ✓ 1.0.0 | Scala 3 JVM | ✅ 54 | Maven Central; `scala/planet-time/`, `scala/ltx/` |
| **Lua** | ✓ 1.0.0 | ✓ 1.0.0 | Lua 5.3+ | ✅ 54 | stdlib-only; `lua/planet-time/`, `lua/ltx/` |
| **OCaml** | ✓ 1.0.0 | ✓ 1.0.0 | OCaml 4.13+ | ✅ 54 | ocamlfind; `ocaml/planet-time/`, `ocaml/ltx/` |
| **Zig** | ✓ 1.0.0 | ✓ 1.0.0 | Zig 0.12+ | ✅ 54 | stdlib-only; `zig/planet-time/`, `zig/ltx/` |
| **Julia** | ✓ 1.0.0 | ✓ 1.0.0 | Julia 1.9+ | ✅ 54 | stdlib-only; `julia/planet-time/`, `julia/ltx/` |

**Legend:** ✓ = implemented · ✅ 54 = all 54 cross-language fixture entries pass · — = not yet implemented

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

All LTX implementations conform to the cross-SDK vector test suite
(see `conformance/` in the project root).

---

*Last updated: 2026-03-08*
