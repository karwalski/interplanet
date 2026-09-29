# Repository sweep (issue #38)

`run-all.sh` runs everything that can be checked locally, one row per entry,
and prints a PASS/FAIL table. It exits 1 if any entry fails. An entry whose
toolchain is not on `PATH` is `SKIP`, not a failure.

```sh
scripts/sweep/run-all.sh                     # everything
scripts/sweep/run-all.sh --list              # the entries and what they need
scripts/sweep/run-all.sh --only go,rust      # by port, by name (go/ltx) or by section (ports, checks, web, services)
scripts/sweep/run-all.sh --skip interop,scala
scripts/sweep/run-all.sh --only c --verbose  # stream the output instead of logging it
```

Each entry's output goes to `<log dir>/<entry>.log`; a failing entry also
prints its last 25 lines. The note column is the entry's last "N passed" line.

## Files

| File | What |
|---|---|
| `run-all.sh` | The runner: PATH setup, the entry registry (`sweep_add`), the repository checks, the table. |
| `ports.sh` | One entry per port and library (sourced by `run-all.sh`). |
| `web.sh`, `services.sh` | Web and services sections (web, api, node, cli, research). Sourced when present; they call `sweep_add` the same way. |
| `npm-consumer-check.sh` | Packs an npm package, installs the tarball in a scratch project and checks `require`, `import` (with Node's pre-22.7 ESM rules) and the TypeScript declarations (node16 and bundler resolution). |
| `bindings/itx-dotnet/` | Runtime smoke test of the C# binding of `c/ltx` against `libitx.so`. |
| `accuracy/` | Planet-time accuracy sweep, see below. |

## What runs

**checks** (repository level):

| Entry | Command |
|---|---|
| check-versions | `node scripts/check-versions.js` |
| js-reference-check | `node scripts/conformance/js-reference-check.js` (planet-time.js still reproduces reference.json) |
| plan-id-prefixes-current | `node scripts/conformance/gen-plan-id-prefixes.js --check` |
| upper-tables-current | `node scripts/conformance/gen-upper-tables.js --check` |
| planet-time-accuracy | `scripts/sweep/accuracy/run.sh` |
| interop | `node scripts/interop/run.js` (cross-port planId interop, `scripts/interop/README.md`) |

**ports**: for every port, `<port>/planet-time` runs the unit tests and the
fixture runner against `c/planet-time/fixtures/reference.json`, and
`<port>/ltx` runs the unit tests, which include the golden planId tests
(`spec/golden/plan-ids.json` and `spec/golden/plan-id-prefixes.json`). The
commands follow each port's Makefile; `ports.sh` has them. Extra steps where
the port has them:

| Port | Extra steps |
|---|---|
| javascript, typescript | `npm pack` and `npm-consumer-check.sh`; `make lint` and `make check-types` (JS LTX) |
| python | `py_compile`; `python -m build` when `$SWEEP_PYTHON` has `build` |
| java | `javac -encoding UTF-8 -Xlint:all` (Makefile) |
| kotlin | `gradle build` (compile, tests) |
| c | `-Wall -Wextra -Werror` compile (minus `-Wformat-truncation`), the C++ headers, ASan + UBSan runs of the unit tests, the .NET binding projects |
| go | `gofmt -l`, `go vet`, `go build` |
| rust | `cargo build --release`, `cargo clippy --all-targets -D warnings` |
| zig | `make lint` (`zig fmt --check`) |
| ruby, php | `ruby -c`, `php -l` |
| dart, elixir | `dart analyze`, `mix compile --warnings-as-errors` |
| toke | builds the demo CLI with `$TKC` (or `tkc` on PATH) and runs `toke/verify.py`; `SKIP` without a compiler |

## Environment

| Variable | Default | Use |
|---|---|---|
| `SWEEP_PATH` | `$INTEROP_PATH`, else `/tmp/claude-0/-home-user-interplanet/62b44def-77ee-5085-9fac-355ab027309f/scratchpad/bin` | Extra PATH entries, colon separated (julia, zig, sbt and dart live there in the reference container). `/usr/local/bin` (swift) is always added. Also exported as `INTEROP_PATH` for the interop run. |
| `SWEEP_LOG_DIR` | a new `mktemp -d` | Where the logs go. |
| `SWEEP_TIMEOUT` | `1800` | Seconds per entry. |
| `SWEEP_PYTHON` | `python3` | Interpreter for `python -m build` (needs the `build` package; a venv with `build` and `hatchling` works offline). |
| `GRADLE_FLAGS` | empty | e.g. `--offline` to use only the Gradle cache. |
| `TKC` | `tkc` on PATH | toke compiler at the revision pinned in `toke/README.md`. |
| `SWEEP_JASON` | `$SWEEP_PATH/../jason` | Jason source checkout for elixir/planet-time when Hex is not installed (hex.pm unreachable): Jason and the library are compiled with `elixirc` and the ExUnit files run with `elixir`. Without either the row is `SKIP`. |

Toolchains (all optional): node + npm (+ `tsc` for the JS type checks),
python3 + pytest, JDK 17+, gradle, sbt, cc/c++ (+ cmake), go, cargo (+ clippy),
zig 0.15, ruby, php 8.1+ and composer, dotnet 10, dart, swift 5.9+, elixir +
mix, lua 5.3+, ocamlfind + ocamlopt, R with jsonlite, julia 1.9+, clang (toke).

## Adding an entry

```sh
sweep_add <section> <name> <dir relative to the repo root> "<needed executables>" '
command one
command two   # runs under bash -eo pipefail in <dir>
'
```

The commands see `$ROOT`, `$FIXTURE`, `$GOLDEN_IDS`, `$GOLDEN_PREFIXES`,
`$SWEEP_PYTHON` and `$SWEEP_TMP` (a scratch directory removed afterwards). An
entry that decides at run time it cannot run prints a line starting with
`SKIP:` and exits 0.

## Planet-time accuracy (`accuracy/`)

The fixtures cover 6 instants, and several fixture runners check only a few
fields. `accuracy/run.sh` draws 200 instants from 1990 to 2100 (seeded, so
repeatable), and for each of the 9 bodies has every port compute hour,
minute, second and day number (`getPlanetTime` at offset 0), light time from
Earth and, for Mars, MTC sol/hour/minute/second. `compare.js` requires exact
agreement with `javascript/planet-time/planet-time.js` except light time,
which may differ by up to 1 s.

```sh
scripts/sweep/accuracy/run.sh                  # typescript python java kotlin scala c go rust zig
scripts/sweep/accuracy/run.sh go rust          # a subset
ACCURACY_COUNT=3000 ACCURACY_SEED=7 scripts/sweep/accuracy/run.sh c
```

`gen.js` writes the inputs (`<body> <utc_ms>` per line) and the expected
output; each port has a small probe in `accuracy/probes/` that reads the
inputs and prints one tab-separated row per case:
`body utc_ms hour minute second day_number light_s mtc_sol mtc_hour
mtc_minute mtc_second`, with `-` for no light time (Earth, Moon) or no MTC
(not Mars) and light time to 3 decimals. Another port joins by adding a
probe and a `probe_<port>` function in `run.sh`.
