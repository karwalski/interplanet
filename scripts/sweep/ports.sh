# shellcheck shell=bash
# Port entries for scripts/sweep/run-all.sh (sourced, not run).
#
# One entry per port and library. Each runs the library's full unit tests,
# then (planet-time) the fixture runner against $FIXTURE
# (c/planet-time/fixtures/reference.json) or (ltx) the golden planId tests
# against $GOLDEN_IDS and $GOLDEN_PREFIXES, plus the package build and lint
# steps the port has. The commands follow each port's Makefile; where a
# Makefile hard-codes a path or a macOS tool, the entry spells the commands
# out. See sweep_add in run-all.sh for the fields.

# ── JavaScript (reference) ──────────────────────────────────────────────────
# planet-time.js is the fixture source: checks/js-reference-check regenerates
# reference.json from it and compares.
sweep_add ports javascript/planet-time javascript/planet-time "node npm" '
make test
npm pack --dry-run 2>&1 | tail -n 4
bash "$ROOT/scripts/sweep/npm-consumer-check.sh" . interplanet-planet-time
'
sweep_add ports javascript/ltx javascript/ltx "node npm tsc" '
make test          # smoke, templates, multi, tests/run.js (plan-ids.json + plan-id-prefixes.json)
make lint
make check-types   # ltx-sdk.d.ts current and usable from strict TypeScript
npm pack --dry-run 2>&1 | tail -n 4
bash "$ROOT/scripts/sweep/npm-consumer-check.sh" . interplanet-ltx
'

# ── TypeScript ──────────────────────────────────────────────────────────────
sweep_add ports typescript/planet-time typescript/planet-time "node npm" '
npm ci --no-audit --no-fund
npm run build
node tests/run.js
node tests/fixtures.js "$FIXTURE"
bash "$ROOT/scripts/sweep/npm-consumer-check.sh" . @interplanet/time
'
sweep_add ports typescript/ltx typescript/ltx "node npm" '
npm ci --no-audit --no-fund
npm run build
node tests/run.js  # includes plan-ids.json and plan-id-prefixes.json
bash "$ROOT/scripts/sweep/npm-consumer-check.sh" . @interplanet/ltx @types/node  # Node-only: API uses Buffer
'

# ── Python ──────────────────────────────────────────────────────────────────
# Package builds need `build` + `hatchling` in $SWEEP_PYTHON (else skipped).
py_build='
if "$SWEEP_PYTHON" -m build --version >/dev/null 2>&1; then
  "$SWEEP_PYTHON" -m build --outdir "$SWEEP_TMP/dist" . 2>&1 | tail -n 1
else
  echo "note: $SWEEP_PYTHON has no build module, package build skipped"
fi'
sweep_add ports python/planet-time python/planet-time python3 "
python3 -m py_compile src/interplanet_time/*.py
PYTHONPATH=src python3 -m pytest -q tests/   # test_unit.py + test_fixtures.py (reference.json)
$py_build
"
sweep_add ports python/ltx python/ltx python3 "
python3 -m py_compile src/interplanet_ltx/*.py
# planet-time on the path so the interplanet_time integration tests run too
PYTHONPATH=src:../planet-time/src python3 -m pytest -q tests/   # includes both golden files
$py_build
"

# ── Java ────────────────────────────────────────────────────────────────────
sweep_add ports java/planet-time java/planet-time "javac java make" '
make clean test   # unit tests + TestFixtures reference.json
'
sweep_add ports java/ltx java/ltx "javac java make" '
make clean test   # unit + TestParity plan-ids.json + TestPlanIdPrefixes
'

# ── Kotlin (Gradle; set GRADLE_FLAGS=--offline to use only the local cache) ──
sweep_add ports kotlin/planet-time kotlin/planet-time "gradle java" '
gradle -q ${GRADLE_FLAGS:-} build   # compile + JUnit tests
gradle -q ${GRADLE_FLAGS:-} run --args="$FIXTURE"
'
sweep_add ports kotlin/ltx kotlin/ltx "gradle java" '
gradle -q ${GRADLE_FLAGS:-} build   # check runs ltxTest: unit, v11, parity, prefix
'

# ── Scala (sbt launcher) ────────────────────────────────────────────────────
sweep_add ports scala/planet-time scala/planet-time "sbt java" '
sbt test "run $FIXTURE"
'
sweep_add ports scala/ltx scala/ltx "sbt java" '
sbt "Test/runMain InterplanetLtxTest" "Test/runMain SecurityTest" "Test/runMain V11Test" "Test/runMain ParityTest" "Test/runMain PrefixTest"
'

# ── C ───────────────────────────────────────────────────────────────────────
# Lint: -Werror except -Wformat-truncation (snprintf into fixed fields whose
# value ranges GCC cannot see). The unit tests also run under ASan + UBSan.
c_lint='-Wall -Wextra -Werror -Wno-format-truncation'
c_san='-g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all'
sweep_add ports c/planet-time c/planet-time "cc c++ make" "
cc -std=c11 $c_lint -Iinclude -c src/libinterplanet.c -o \"\$SWEEP_TMP/lint.o\"
echo '#include \"interplanet.hpp\"' | c++ -std=c++17 $c_lint -fsyntax-only -Iinclude -Ibindings/cpp -x c++ -
make clean
make test      # CMake/ctest when cmake is present: unit tests + reference.json
make fixture   # the fixture runner once more through the plain cc build
make clean
if command -v dotnet >/dev/null; then   # C# binding project builds
  dotnet build -nologo -v q --artifacts-path \"\$SWEEP_TMP/dn\" bindings/dotnet
fi
cc -std=c11 $c_san -Iinclude tests/test_libinterplanet.c src/libinterplanet.c -lm -o \"\$SWEEP_TMP/t\"
\"\$SWEEP_TMP/t\" >/dev/null
cc -std=c11 $c_san -Iinclude tests/fixture_runner.c src/libinterplanet.c -lm -o \"\$SWEEP_TMP/f\"
\"\$SWEEP_TMP/f\" \"\$FIXTURE\" | tail -n 1
"
sweep_add ports c/ltx c/ltx "cc c++ make" "
cc -std=c99 $c_lint -Iinclude -c src/libitx.c -o \"\$SWEEP_TMP/a.o\"
cc -std=c99 $c_lint -Iinclude -c src/itx_plan_json.c -o \"\$SWEEP_TMP/b.o\"
make clean
make test shared   # unit, plan-ids.json + plan-id-prefixes.json, C++ wrapper
if command -v dotnet >/dev/null; then   # C# binding (bindings/InterplanetLTX.cs) against lib/libitx.so
  LD_LIBRARY_PATH=\"\$PWD/lib\" dotnet run --artifacts-path \"\$SWEEP_TMP/dn\" --project \"\$ROOT/scripts/sweep/bindings/itx-dotnet\"
fi
make clean
cc -std=c99 $c_san -Iinclude tests/test_libitx.c src/libitx.c src/itx_plan_json.c -lm -o \"\$SWEEP_TMP/t\"
\"\$SWEEP_TMP/t\" | tail -n 1
cc -std=c99 $c_san -Iinclude tests/test_plan_json.c src/libitx.c src/itx_plan_json.c -lm -o \"\$SWEEP_TMP/p\"
\"\$SWEEP_TMP/p\" \"\$GOLDEN_IDS\" | tail -n 1
"

# ── Go ──────────────────────────────────────────────────────────────────────
sweep_add ports go/planet-time go/planet-time go '
test -z "$(gofmt -l .)" || { echo "gofmt needed:"; gofmt -l .; exit 1; }
go vet ./...
go build ./...
go test ./...
go run fixture_runner.go "$FIXTURE"
'
sweep_add ports go/ltx go/ltx go '
test -z "$(gofmt -l .)" || { echo "gofmt needed:"; gofmt -l .; exit 1; }
go vet ./...
go build ./...
go test ./...   # includes the parity (plan-ids.json) and prefix tests
'

# ── Rust ────────────────────────────────────────────────────────────────────
sweep_add ports rust/planet-time rust/planet-time cargo '
cargo build --quiet --release
cargo test --quiet
cargo run --quiet --bin fixture_check   # reference.json
if cargo clippy --version >/dev/null 2>&1; then cargo clippy --quiet --all-targets -- -D warnings; fi
'
sweep_add ports rust/ltx rust/ltx cargo '
cargo build --quiet --release
cargo test --quiet   # unit, v11, parity (plan-ids.json + plan-id-prefixes.json)
if cargo clippy --version >/dev/null 2>&1; then cargo clippy --quiet --all-targets -- -D warnings; fi
'

# ── Zig 0.15 ────────────────────────────────────────────────────────────────
sweep_add ports zig/planet-time zig/planet-time "zig make" '
make lint    # zig fmt --check
zig build test
zig run --cache-dir "$SWEEP_TMP/cache" --dep interplanet_time -Mroot=test/fixture_runner.zig \
  -Minterplanet_time=src/interplanet_time.zig -- --fixture "$FIXTURE"
'
sweep_add ports zig/ltx zig/ltx "zig make" '
make lint    # zig fmt --check
zig build test   # unit, security, v11, parity (both golden files)
'

# ── Ruby ────────────────────────────────────────────────────────────────────
sweep_add ports ruby/planet-time ruby/planet-time ruby '
for f in lib/interplanet_time.rb lib/interplanet_time/*.rb; do ruby -c "$f" >/dev/null; done
ruby -Ilib test/test_interplanet_time.rb
ruby -Ilib test/fixture_test.rb "$FIXTURE"
'
sweep_add ports ruby/ltx ruby/ltx ruby '
for f in lib/interplanet_ltx.rb lib/interplanet_ltx/*.rb; do ruby -c "$f" >/dev/null; done
ruby -Ilib test/test_interplanet_ltx.rb   # includes both golden files
'

# ── PHP (8.1+; planet-time needs Composer for PHPUnit) ──────────────────────
sweep_add ports php/planet-time php/planet-time "php composer" '
for f in src/autoload.php src/InterplanetTime/*.php tests/*.php tests/Unit/*.php; do php -l "$f" >/dev/null; done
composer install --no-interaction --no-progress --quiet
./vendor/bin/phpunit
php tests/FixtureTest.php "$FIXTURE"
'
sweep_add ports php/ltx php/ltx php '
for f in src/autoload.php src/InterplanetLTX/*.php tests/*.php; do php -l "$f" >/dev/null; done
php tests/UnitTest.php   # includes both golden files
'

# ── C# (.NET 10) ────────────────────────────────────────────────────────────
sweep_add ports csharp/planet-time csharp/planet-time dotnet '
dotnet build -nologo -v q InterplanetTime
dotnet run --project FixtureTest "$FIXTURE"
'
sweep_add ports csharp/ltx csharp/ltx dotnet '
dotnet build -nologo -v q -warnaserror InterplanetLTX.csproj
dotnet run --project tests   # unit, security, v11, parity, prefix
'

# ── F# ──────────────────────────────────────────────────────────────────────
sweep_add ports fsharp/planet-time fsharp/planet-time dotnet '
dotnet build -nologo -v q InterplanetTime
dotnet run --project FixtureTest "$FIXTURE"
'
sweep_add ports fsharp/ltx fsharp/ltx dotnet '
dotnet build -nologo -v q InterplanetLtx.fsproj
for t in UnitTest SecurityTest V11Test ParityTest PrefixTest; do dotnet fsi "tests/$t.fsx"; done
'

# ── Dart ────────────────────────────────────────────────────────────────────
sweep_add ports dart/planet-time dart/planet-time dart '
dart pub get
dart analyze lib/
dart test
dart run bin/fixture_runner.dart "$FIXTURE"
'
sweep_add ports dart/ltx dart/ltx dart '
dart pub get
dart analyze lib/ test/
dart run test/interplanet_ltx_test.dart   # includes both golden files
'

# ── Swift (5.9+; Linux fetches apple/swift-crypto for LTX) ──────────────────
sweep_add ports swift/planet-time swift/planet-time "swift swiftc" '
mkdir -p "$SWEEP_TMP/bin"
swiftc -module-name InterplanetTime Sources/InterplanetTime/*.swift Sources/RunTests/main.swift -o "$SWEEP_TMP/bin/RunTests"
"$SWEEP_TMP/bin/RunTests" "$FIXTURE"   # unit tests + reference.json
'
sweep_add ports swift/ltx swift/ltx swift '
swift build --scratch-path "$SWEEP_TMP/build" 2>&1 | tail -n 3
swift run --scratch-path "$SWEEP_TMP/build" InterplanetLTXTests   # includes both golden files
'

# ── Elixir ──────────────────────────────────────────────────────────────────
# planet-time needs Jason (a Hex package). Without Hex (e.g. hex.pm blocked),
# a Jason source checkout in $SWEEP_JASON is compiled with the library instead.
sweep_add ports elixir/planet-time elixir/planet-time "elixir mix elixirc" '
if mix hex.info >/dev/null 2>&1; then
  mix deps.get
  mix compile --warnings-as-errors
  mix test
  mix run fixture_runner/fixture_runner.exs "$FIXTURE"
else
  jason=${SWEEP_JASON:-$SWEEP_PATH/../jason}
  if [ ! -d "$jason/lib" ]; then echo "SKIP: no Hex and no Jason checkout (set SWEEP_JASON)"; exit 0; fi
  echo "note: no Hex; compiling Jason from $jason"
  mkdir -p "$SWEEP_TMP/ebin"
  find "$jason/lib" -name "*.ex" -print0 | xargs -0 elixirc --ignore-module-conflict -o "$SWEEP_TMP/ebin" >/dev/null
  elixirc --warnings-as-errors -o "$SWEEP_TMP/ebin" $(find lib -name "*.ex")
  for t in test/*_test.exs; do elixir -pa "$SWEEP_TMP/ebin" -r test/test_helper.exs "$t"; done
  elixir -pa "$SWEEP_TMP/ebin" fixture_runner/fixture_runner.exs "$FIXTURE"
fi
'
sweep_add ports elixir/ltx elixir/ltx elixir '
for t in interplanet_ltx_test security_test v11_test parity_test; do
  elixir -r test/test_helper.exs "test/$t.exs"
done
'

# ── Lua (5.3+) ──────────────────────────────────────────────────────────────
sweep_add ports lua/planet-time lua/planet-time lua '
lua test/unit_test.lua
lua test/fixture_runner.lua "$FIXTURE"
'
sweep_add ports lua/ltx lua/ltx lua '
for t in unit_test security_test v11_test parity_test; do lua "test/$t.lua"; done
'

# ── OCaml ───────────────────────────────────────────────────────────────────
sweep_add ports ocaml/planet-time ocaml/planet-time "ocamlopt make" '
make clean
make test   # unit tests + reference.json fixture check
make clean
'
sweep_add ports ocaml/ltx ocaml/ltx "ocamlfind ocamlopt make" '
make clean
make test   # unit, security, v11, parity (both golden files)
make clean
'

# ── R (needs jsonlite; runs under a UTF-8 locale) ───────────────────────────
sweep_add ports r/planet-time r/planet-time Rscript '
export LC_ALL=C.UTF-8
Rscript test/test_unit.R
Rscript test/test_fixtures.R "$FIXTURE"
'
sweep_add ports r/ltx r/ltx Rscript '
export LC_ALL=C.UTF-8
Rscript test/test_unit.R
Rscript test/test_parity.R   # both golden files
'

# ── Julia (1.9+) ────────────────────────────────────────────────────────────
sweep_add ports julia/planet-time julia/planet-time julia '
julia --startup-file=no --project=. -e "import Pkg; Pkg.instantiate(); Pkg.test()"
julia --startup-file=no --project=. fixture_runner.jl "$FIXTURE"
'
sweep_add ports julia/ltx julia/ltx julia '
julia --startup-file=no --project=. -e "import Pkg; Pkg.instantiate()"
julia --startup-file=no --project=. test/runtests.jl   # includes parity_tests.jl
'

# ── toke (demo CLI; needs tkc at the pinned revision, see toke/README.md) ───
# TKC names the compiler; else `tkc` on PATH. The binary goes to $SWEEP_TMP.
sweep_add ports toke toke "python3 clang" '
tkc=${TKC:-$(command -v tkc || true)}
[ -z "$tkc" ] && [ -x .toolchain/toke/tkc ] && tkc=$PWD/.toolchain/toke/tkc   # built by build.sh
if [ -z "$tkc" ]; then echo "SKIP: no tkc (set TKC)"; exit 0; fi
"$tkc" --diag-text src/interplanet.tk --out "$SWEEP_TMP/interplanet" >"$SWEEP_TMP/tkc.log" 2>&1 || { cat "$SWEEP_TMP/tkc.log"; exit 1; }
python3 verify.py "$SWEEP_TMP/interplanet"   # reference.json + v2 plan-ids.json
'
