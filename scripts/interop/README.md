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
| (c) pfx | The same for a JS `createPlan` plan whose node names (`PREFIX_NODES` in `plan.js`) stress the planId HOSTSTR/NODESTR: JS whitespace (U+3000, U+00A0), the full Unicode upper-case mapping of `toUpperCase` (ß, ﬁ, ﬂ, ΐ, σ/ς, ı, İ, Deseret astral letters) and UTF-16 slicing (issue #37). Optional: `n/a` for a driver that does not print `JS_VP` (every driver prints it now). No cut splits a surrogate pair here; `spec/golden/plan-id-prefixes.json` covers those cases in each port's own tests. |
| wire key order | Top-level key order of the port's v2 wire JSON: `nodes first` (v, title, start, quantum, mode, nodes, segments) or `segments first (as JS)`. |

The representative plan (`plan.js`) has a non-ASCII title with an astral
character (`Réunion Mars 🚀`, a surrogate pair in UTF-16), three nodes (one
named `L-1 Gateway`, whose planId token must keep the hyphen: `L-1G`), and
segments with `speaker`/`label` (one label also has an astral character).
Every driver hard-codes the same values. `run.js` adds a note when a port's
v2 wire JSON loses the `speaker`/`label` of the representative plan; no port
does now.

Some drivers (Go, Java, Kotlin, Scala, C#, F#) also run an issue #36 extra
case, reported as a `NOTE` rather than a column: control characters, a lone
surrogate and JS `\s` whitespace (tab, NBSP, U+3000, U+2028, BOM, LF) in the
title and node names, plus a speaker-only and a label-only segment. The typed
wire JSON must be exactly what `JSON.stringify` writes and the typed planId
must equal the JSON-based one and the JS id; the driver exits non-zero if not.

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
3.13.4, Zig 0.15.1, Julia 1.10.4), after the issue #36 (escaping, whitespace,
speaker/label) and issue #37 (planId prefix) port fixes.
JS reference ids for the inputs to (c): v2 `LTX-20260315-EARTHHQ-MARS-L-1G-v2-09310844`,
v3 `LTX-20260315-EARTHHQ-MARS-L-1G-v3-f3abaee9`, prefix plan
`LTX-20260315-GRÖSSEΣΣ-FIXF-Ϊ́Λ-𐐀𐐁-I-v2-0ec4062a`.

| Port | Status | (a) v2 | (a) v3 | (c) v2 | (c) v3 | (c) pfx | Wire key order | Notes |
|---|---|---|---|---|---|---|---|---|
| javascript | PASS | ok | ok | ok | ok | ok | segments first | reference, harness baseline |
| typescript | PASS | ok | ok | ok | ok | ok | segments first | |
| python | PASS | ok | ok | ok | ok | ok | nodes first | v3 wire via `json.dumps` (`encode_hash` takes a v2 `LtxPlan`) |
| rust | PASS | ok | ok | ok | ok | ok | nodes first | v3 by setting the typed v3 fields |
| go | PASS | ok | ok | ok | ok | ok | nodes first | v3 by setting the typed v3 fields; #36 case ok |
| ruby | PASS | ok | n/a | ok | ok | ok | nodes first | no typed v3 |
| php | PASS | ok | n/a | ok | ok | ok | nodes first | no typed v3 |
| java | PASS | ok | n/a | ok | ok | ok | nodes first | no typed v3; #36 case ok |
| kotlin | PASS | ok | n/a | ok | ok | ok | nodes first | `LtxPlan`: no v3; #36 case ok |
| kotlin-v11 | PASS | ok | ok | ok | ok | ok | nodes first | `PlanV11` |
| scala | PASS | ok | n/a | ok | ok | ok | nodes first | `LtxPlan`: no v3; #36 case ok |
| scala-v11 | PASS | ok | ok | ok | ok | ok | nodes first | `PlanV11` |
| csharp | PASS | ok | n/a | ok | ok | ok | nodes first | `LtxPlan`: no v3; #36 case ok |
| csharp-v11 | PASS | ok | ok | ok | ok | ok | nodes first | `PlanV11` |
| fsharp | PASS | ok | n/a | ok | ok | ok | nodes first | `LtxPlan`: no v3; #36 case ok |
| fsharp-v11 | PASS | ok | ok | ok | ok | ok | nodes first | `PlanV11` |
| c | PASS | ok | n/a | ok | ok | ok | nodes first | `itx_plan_t`: the C port builds no v3 plans |
| dart | PASS | ok | ok | ok | ok | ok | nodes first | |
| swift | PASS | ok | ok | ok | ok | ok | nodes first | |
| zig | PASS | ok | n/a | ok | ok | ok | segments first (as JS) | typed `LtxPlan` is v2 only; v3 through `makePlanIdJson` |
| elixir | PASS | ok | ok | ok | ok | ok | nodes first | |
| lua | PASS | ok | ok | ok | ok | ok | nodes first | |
| ocaml | PASS | ok | ok | ok | ok | ok | nodes first | typed plan is v2 only; v3 through `V11` on the parsed wire JSON |
| r | PASS | ok | ok | ok | ok | ok | nodes first | |
| julia | PASS | ok | ok | ok | ok | ok | nodes first | |

25 pass, 0 fail, 0 known-incompatible (xfail), 0 skipped. Every toolchain was
available; sbt, Dart, Zig and Julia were not on the default PATH and were
supplied through `INTEROP_PATH`. Every typed model now carries
`speaker`/`label`, and every driver prints `JS_VP`.

Every port's JSON-based planId function reproduces JS for the v2 (segments
first), v3 and prefix inputs, and every port transmits exactly what it
hashes.

### Port fixes found by this runner

Before the fixes the runner reported these disagreements. Each fix leaves
the frozen algorithm unchanged and has a regression test in the port. All
but Zig are minimal and keep the v2 bytes of existing plans; the Zig typed
model was not the v2 schema, so its plans (and their ids) change to what JS
produces for the same values.

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
| Zig | the typed model in `interplanet_ltx.zig` predated the v2 schema: `"v":"2"` as a string, nodes with `is_host` instead of `role`/`delay`, timed segments instead of `{type, q}`, and `makePlanId` built HOSTSTR/NODESTR from node ids and hashed UTF-8 bytes; no other port could read its `#l=` JSON as a plan (issue #35) | typed model rewritten to the v2 schema as JS `createPlan`: `LtxPlan` with `v: 2`, nodes `{id, name, role, delay, location}`, segments `{type, q, speaker?, label?}`, JS default segments, wire JSON in the JS key order, and `makePlanId` hashing exactly that JSON (UTF-16 imul31, name-based HOSTSTR/NODESTR) | `src/unit_test.zig` |

### Gaps and observations

- **Decoding a JS share into a typed plan.** Nodes-first typed models
  re-serialise a received JS (segments first) plan in their own order, so the
  typed `makePlanId` of a decoded JS plan is not the sender's id. That is by
  design (a typed plan hashes what it transmits); receivers must use the
  JSON-based planId function on the received text, as the golden vectors do.
  The planId prefix (`LTX-date-HOSTSTR-NODESTR`) does not depend on key
  order, and the ports' `plan-id-prefixes.json` tests check it on the typed
  paths too.
- **Lone surrogates in the id.** When the UTF-16 slicing splits a surrogate
  pair, the id holds a lone high surrogate. Ports keep it where their string
  type can (JS, TypeScript, Python, Dart, Java, Kotlin, Scala, C#, F#: the
  exact `planId`; C, Ruby, PHP, Julia, OCaml, Lua, Zig and `api/ltx-planid.php`:
  WTF-8 bytes) and use U+FFFD where strings must be valid UTF-8 (Rust, Swift,
  Go, Elixir, R), which is also what JS sends over HTTP. The representative
  and prefix plans here never split a pair; `spec/golden/plan-id-prefixes.json`
  covers it per port. The web API returns and stores the U+FFFD form.
- **Unicode version of upper-casing.** Ports without full JS case mapping use
  tables generated from node's `toUpperCase` by
  `scripts/conformance/gen-upper-tables.js` (C, OCaml, R, Lua, Zig, Dart,
  Julia, C#, F#, Go). Java, Kotlin and Scala use `toUpperCase(Locale.ROOT)`
  and PHP `mb_strtoupper`: full mappings with the special casings, but from
  the runtime's Unicode version (JDK 21: Unicode 15; PHP 8.4: Unicode 16), so
  letters added in later Unicode versions (for example U+A7CD, U+10D70..) are
  not upper-cased as node 22 (Unicode 17) does. Different JS engines differ the
  same way.
- The ICS node ids (`LTX-NODE:ID=`) in several ports still use the platform
  upper-casing and whitespace (`\s` of the regex engine, or spaces only); they
  are not part of the planId and are not checked here.

### Not driven

- **Toke**: out of scope here (issue #33).
- **C++ wrapper** `c/ltx/include/itx.hpp`: a header-only wrapper over the C
  functions driven in the `c` row, so not driven separately.

## Adding a port

1. Add `drivers/<port>/` with a driver that builds the plan in `plan.js` with
   the port's typed API and follows the contract at the top of `run.js`:
   `<driver> <inDir> <outDir>`, write `outDir/wire-v2.json` (and
   `wire-v3.json`), print `ID_V2`, `ID_V3`, `JS_V2`, `JS_V3` and `JS_VP`
   (the JSON planId of `inDir/js-vP.json`) lines (omit a line for anything
   the port cannot do; `NOTE` lines are passed through).
2. Add its entry to `ports.js`.
