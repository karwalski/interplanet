# Cross-port LTX planId interop (issue #32)

The frozen v2 planId (docs/LTX-SPECIFICATION.md sections 4.2 and 4.3) is
imul31 over the UTF-16 code units of `JSON.stringify(plan)` in key insertion
order. The typed plan builders in most ports serialise `nodes` before
`segments`, while the JavaScript `createPlan` puts `segments` first. Both are
fine as long as every port hashes a plan in exactly the key order (and with
exactly the fields) it transmits. This directory checks that end to end,
against the JavaScript reference SDK (`javascript/ltx/ltx-sdk.js`).

## What is checked

For every port whose toolchain is found, `run.js` runs a small driver in
`drivers/<port>/` and checks:

| Column | Check |
|---|---|
| (a) v2 | The port builds the representative plan with its own typed API, serialises it with its own wire serialiser (the `#l=` share fragment, `encodeHash` or equivalent) and computes its own planId. JS parses the wire JSON and computes `makePlanId` on the parsed object. The two ids must be equal. |
| (a) v3 | The same for the port's v3 plan (its `upgradePlanToV3`, or the v3 fields of its typed plan where it has no upgrade function). `n/a` where the typed API cannot build a v3 plan. |
| (c) v2 | The port computes the planId of a JS `createPlan` plan (segments first) from its JSON text with its JSON-based function (`makePlanIdFromJson`, `make_plan_id_from_json`, `plan_id_from_json`, `makePlanIdFromMap`, ...). Must equal JS `makePlanId`. |
| (c) v3 | The same for `upgradePlanToV3(plan, { delays: { 'N1\|N2': 842 } })`. |
| wire key order | Top-level key order of the port's v2 wire JSON: `nodes first` (v, title, start, quantum, mode, nodes, segments) or `segments first (as JS)`. |

The representative plan (`plan.js`) has a non-ASCII title with an astral
character (`Réunion Mars 🚀`, a surrogate pair in UTF-16), three nodes (one
named `L-1 Gateway`, whose planId token must keep the hyphen: `L-1G`), and
segments with `speaker`/`label` (one label also has an astral character).
Every driver hard-codes the same values.

## Running

```sh
node scripts/interop/run.js                  # every port with a toolchain
node scripts/interop/run.js --only go,rust   # a subset
node scripts/interop/run.js --skip scala     # everything but
node scripts/interop/run.js --verbose        # driver output, keep the work dir
INTEROP_PATH=/opt/zig:/opt/julia/bin node scripts/interop/run.js   # extra PATH entries
```

A port whose toolchain is missing is reported as `SKIP`, not as a failure.
The exit code is 1 if any port that ran fails (`FAIL`, `BUILD-FAIL`,
`RUN-FAIL`, or `XPASS`, see below), else 0.

Toolchains each driver needs (`ports.js` has the exact commands):

| Port | Needs | Build notes |
|---|---|---|
| javascript, typescript | node (+ `tsc` for typescript) | TypeScript is compiled to `drivers/typescript/build/` |
| python | python3 | |
| rust | cargo | crates `ed25519-dalek`, `sha2`, `rand`, `base64` from crates.io or the local cache |
| go | go | `replace` directive onto `go/ltx` |
| ruby, php | ruby, php (8.1+) | |
| java | javac, java | |
| kotlin, kotlin-v11 | gradle, JDK 17 | Kotlin 1.9.22 Gradle plugin; `gradle --offline` needs it cached |
| scala, scala-v11 | sbt, java | Scala 3.6.4 via sbt |
| csharp, csharp-v11 | dotnet (net10.0) | NuGet `NSec.Cryptography` |
| fsharp, fsharp-v11 | dotnet | `dotnet fsi` with `#r "nuget: NSec.Cryptography"` |
| c | cc | C99, links `c/ltx/src/*.c` directly |
| dart | dart | `dart pub get --offline` (package `cryptography` must be cached) |
| swift | swift (5.9+) | SwiftPM fetches `apple/swift-crypto` on Linux |
| zig | zig 0.15 | |
| elixir | elixirc, elixir | |
| lua | lua 5.3+ | |
| ocaml | ocamlfind, ocamlopt | packages `unix`, `str` |
| r | Rscript + `jsonlite` | runs under `LC_ALL=C.UTF-8` |
| julia | julia 1.9+ | stdlib `SHA`, `Base64` |

Rows with a `-v11` suffix drive the second typed model some ports carry
(`PlanV11` in Kotlin, Scala, C# and F#), which supports speaker/label and v3;
the plain row drives the older `LtxPlan` model.

`xfail` in `ports.js` marks a documented, known incompatibility: its failure
is reported as `XFAIL` and does not fail the run, and an unexpected pass is
reported as `XPASS` and does, so the entry is removed once the port is fixed.

## Results

Run on 29 September 2026 in the development container (node 22.22, Python
3.11, Go 1.24.7, cargo 1.94.1, Ruby 3.3.6, PHP 8.4.19, JDK 21 and Gradle
8.14.3, sbt 1.10.7 with Scala 3.6.4, .NET 10.0.112, Swift 5.10.1, Elixir 1.14
on OTP 24, Lua 5.4.6, OCaml 4.14.1, R 4.3.3, gcc 13.3, TypeScript 6.0.2, Dart
3.13.4, Zig 0.15.1, Julia 1.10.4), after the port fixes listed below.
JS reference ids for the inputs to (c): v2 `LTX-20260315-EARTHHQ-MARS-L-1G-v2-09310844`,
v3 `LTX-20260315-EARTHHQ-MARS-L-1G-v3-f3abaee9`.

| Port | Status | (a) v2 | (a) v3 | (c) v2 | (c) v3 | Wire key order | Notes |
|---|---|---|---|---|---|---|---|
| javascript | PASS | ok | ok | ok | ok | segments first | reference, harness baseline |
| typescript | PASS | ok | ok | ok | ok | segments first | |
| python | PASS | ok | ok | ok | ok | nodes first | v3 wire via `json.dumps` (`encode_hash` takes a v2 `LtxPlan`) |
| rust | PASS | ok | ok | ok | ok | nodes first | v3 by setting the typed v3 fields |
| go | PASS | ok | ok | ok | ok | nodes first | v3 by setting the typed v3 fields |
| ruby | PASS | ok | n/a | ok | ok | nodes first | typed segments have no speaker/label; no typed v3 |
| php | PASS | ok | n/a | ok | ok | nodes first | typed segments have no speaker/label; no typed v3 |
| java | PASS | ok | n/a | ok | ok | nodes first | typed segments have no speaker/label; no typed v3 |
| kotlin | PASS | ok | n/a | ok | ok | nodes first | `LtxPlan`: no speaker/label, no v3 |
| kotlin-v11 | PASS | ok | ok | ok | ok | nodes first | `PlanV11` |
| scala | PASS | ok | n/a | ok | ok | nodes first | `LtxPlan`: no speaker/label, no v3 |
| scala-v11 | PASS | ok | ok | ok | ok | nodes first | `PlanV11` |
| csharp | PASS | ok | n/a | ok | ok | nodes first | `LtxPlan`: no speaker/label, no v3 |
| csharp-v11 | PASS | ok | ok | ok | ok | nodes first | `PlanV11` |
| fsharp | PASS | ok | n/a | ok | ok | nodes first | `LtxPlan`: no speaker/label, no v3 |
| fsharp-v11 | PASS | ok | ok | ok | ok | nodes first | `PlanV11` |
| c | PASS | ok | n/a | ok | ok | nodes first | `itx_plan_t`: no speaker/label; the C port builds no v3 plans |
| dart | PASS | ok | ok | ok | ok | nodes first | |
| swift | PASS | ok | ok | ok | ok | nodes first | |
| zig | XFAIL | MISMATCH | n/a | ok | ok | nodes first | typed `Plan` API is not the v2 schema, see below |
| elixir | PASS | ok | ok | ok | ok | nodes first | |
| lua | PASS | ok | ok | ok | ok | nodes first | |
| ocaml | PASS | ok | ok | ok | ok | nodes first | typed plan: no speaker/label; v3 through `V11` on the parsed wire JSON |
| r | PASS | ok | ok | ok | ok | nodes first | `ltx_segment_spec`: no speaker/label |
| julia | PASS | ok | ok | ok | ok | nodes first | `LtxSegmentSpec`: no speaker/label |

24 pass, 0 fail, 1 known-incompatible (xfail), 0 skipped. Every toolchain was
available; sbt, Dart, Zig and Julia were not on the default PATH and were
supplied through `INTEROP_PATH`.

Every port's JSON-based planId function reproduces JS for both the v2
(segments first) and v3 inputs, and every port except Zig now transmits
exactly what it hashes.

### Port fixes found by this runner

Before the fixes the runner reported these disagreements. Each fix is
minimal, leaves the frozen algorithm and the v2 bytes of existing plans
unchanged, and has a regression test in the port.

| Port | Problem | Fix | Test |
|---|---|---|---|
| Python | `create_plan` dropped `speaker`/`label` from the segments passed to it, so they were missing from the plan, the wire JSON and the planId | pass them through | `tests/test_ltx.py` `TestCreatePlanInterop` |
| Go | `EncodeHash` wire JSON omitted the v3 fields (`delays`, `planVersion`, `prevPlanHash`) that `MakePlanID` hashes: v3 ids disagreed | emit them when set | `ltx_parity_test.go` `TestEncodeHashV3WireMatchesPlanID` |
| Rust | same as Go in `encode_hash` | same | `tests/parity_test.rs` `test_encode_hash_v3_wire_matches_plan_id` |
| Swift | same as Go in `encodeHash` | same (delays in sorted key order) | `Tests/InterplanetLTXTests/main.swift` |
| Kotlin | `InterplanetLTX.makePlanId` (typed `LtxPlan`) hashed UTF-8 bytes, not UTF-16 code units: any non-ASCII title gave a wrong id | hash `Char` code units | `ParityTest.kt` |
| F# | `InterplanetLtx.makePlanId` (typed `LtxPlan`) kept only letters and digits in HOSTSTR/NODESTR, dropping `-`: `L1GA` instead of `L-1G` | strip whitespace only, as the spec says | `tests/UnitTest.fsx` |
| Lua | `encode_hash` serialised with alphabetically sorted keys (`mode, nodes, quantum, ...`) while `make_plan_id` hashes a plain v2 table in schema order: v2 ids of shared plans disagreed | new `wire_json` serialises in the hashed order; used by `encode_hash` and `build_node_urls` | `test/parity_test.lua` |
| R | `encode_hash` serialised a fixed v2 field list while `make_plan_id` hashes `json_stringify(plan)`: v3 fields were not transmitted, and a plan list in another key order was re-shared in a different order than hashed | `encode_hash` and `build_node_urls` use `json_stringify(plan)` | `test/test_parity.R` |

### Known incompatibility (not fixed)

**Zig typed API.** `zig/ltx/src/interplanet_ltx.zig` (`createPlan`,
`encodeHash`, `makePlanId`) predates the v2 schema. Its `#l=` JSON has
`"v":"2"` as a string, nodes with `is_host` instead of `role`/`delay`, and
timed segments (`id`, `duration`, `start_offset`, `speaker`) instead of
`{type, q}`; `makePlanId` builds HOSTSTR/NODESTR from node ids rather than
names (`LTX-20260315-N0-N1-v2-...`) and hashes UTF-8 bytes. No other port can
read that JSON as a plan, so no minimal fix exists; it needs the typed model
rewritten to the v2 schema (a separate change). The Zig JSON API
(`ltx_v11.zig`: `makePlanIdJson`, `planHashJson`, ...) is conformant, as (c)
shows.

### Gaps and observations

- **Typed APIs without speaker/label.** Ruby, PHP, Java, the `LtxPlan` model of
  Kotlin, Scala, C# and F#, C, OCaml, R and Julia cannot build attributed
  segments with their typed API, and their typed decoders drop them. Their
  JSON-based functions handle them. Not an id disagreement, so not changed.
- **Decoding a JS share into a typed plan.** Nodes-first typed models
  re-serialise a received JS (segments first) plan in their own order, so the
  typed `makePlanId` of a decoded JS plan is not the sender's id. That is by
  design (a typed plan hashes what it transmits); receivers must use the
  JSON-based planId function on the received text, as the golden vectors do.
- Not exercised by the representative plan, seen while reading the code:
  the Java and Kotlin `LtxPlan` serialisers escape only `\` and `"`, so a
  control character in a title produces invalid JSON; Go and C# typed
  `MakePlanId` strip only spaces (not tabs or other whitespace) from node names.
- Outside the ports (read, not run): `api/ltx.php` `makePlanId` rewrites
  `mode` (the `createPlan` default `LTX` becomes `LTX-LIVE`) before hashing
  and hashes the UTF-8 bytes of `json_encode($cfg)`, not UTF-16 code units;
  `node/relay-server/server.js` hashes a fixed nodes-first subset of the
  plan. Neither equals the SDK planId of a JS `createPlan` plan, and the PHP
  one also differs for any non-ASCII title.

### Not driven

- **Toke**: out of scope here (issue #33).
- **C++ wrapper** `c/ltx/include/itx.hpp`: a header-only wrapper over the C
  functions driven in the `c` row, so not driven separately.

## Adding a port

1. Add `drivers/<port>/` with a driver that builds the plan in `plan.js` with
   the port's typed API and follows the contract at the top of `run.js`:
   `<driver> <inDir> <outDir>`, write `outDir/wire-v2.json` (and
   `wire-v3.json`), print `ID_V2`, `ID_V3`, `JS_V2`, `JS_V3` lines (omit a
   line for anything the port cannot do; `NOTE` lines are passed through).
2. Add its entry to `ports.js`.
