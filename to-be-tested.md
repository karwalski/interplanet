# To Be Tested

The following language runtimes are **not installed** on the development machine
and therefore their library tests are skipped locally. They should be tested in
CI or on a machine with the relevant toolchain installed.

## Runtimes not installed

_None — all runtimes are now installed._

## Runtimes installed but LTX tests currently failing

These runtimes are installed locally but their LTX library tests fail due to
code bugs or toolchain version mismatches. Tracked for future port-fix sprints.

_None — all installed runtimes pass._

## Runtimes that ARE installed (tests run locally)

| Language | Runtime |
|----------|---------|
| **Node.js / JavaScript** | Node ≥ 16 |
| **Python** | Python 3.10+ |
| **Java** | JDK 16+ |
| **Swift** | Swift 5.9+ (Xcode) |
| **Ruby** | Ruby 2.6+ |
| **C / C++** | clang / gcc (Xcode Command Line Tools) |
| **PHP** | PHP 8.1+ |
| **Elixir** | Elixir 1.14+ / OTP 25+ |
| **Kotlin** | kotlinc 2.3.10 — LTX 92/92 ✓ |
| **Zig** | Zig 0.15.2 — LTX 115/115 ✓ (build.zig updated for 0.15 API) |
| **Swift** | Swift 6.1.2 — LTX 95/95 ✓ (swiftc direct, macOS 15.5 SDK; SPM broken) |
| **Elixir** | Elixir 1.19 / OTP 28 — LTX 125/125 ✓ |
| **Go** | Go 1.26+ — planet-time 28/28 ✓, LTX 8/8 ✓ |
| **Rust** | Rust 1.70+ — LTX all pass ✓; planet-time fixture failures tracked as BUG-RS-1 |
| **Scala** | Scala 3.6.4 / sbt 1.10.7 — LTX 21/21 ✓, planet-time 105/105 ✓ |
| **F#** | .NET 10.0.103 — LTX 151/151 ✓ |
| **C#** | .NET 10.0.103 — LTX 137/137 ✓ |
| **Dart** | Dart 3.11.1 — LTX 24/24 ✓ |
| **Julia** | Julia 1.12.5 — LTX 2/2 E2E ✓ |
| **OCaml** | OCaml 5.4.0 |
| **Lua** | Lua 5.4.8 |
| **R** | R 4.5.2 |

## CI

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs the full test
suite. Language runtimes are installed in CI using the `setup-*` actions — see
the workflow file for the exact versions used.
