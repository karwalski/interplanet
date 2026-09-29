'use strict';
/**
 * Port table for scripts/interop/run.js. Each entry:
 *   name   row label, and driver directory under scripts/interop/drivers/
 *   dir    driver directory when it differs from name (built once per run)
 *   need   executables that must exist (PATH lookup, or absolute paths)
 *   build  optional shell command run in the driver dir before `run`
 *   run    shell command run in the driver dir; gets <inDir> <outDir>
 *   xfail  known, documented incompatibility: a FAIL is reported as XFAIL and
 *          does not fail the run; an unexpected PASS is reported as XPASS and
 *          does (so the entry gets removed once the port is fixed)
 * Commands see $ROOT (the repository root).
 */
module.exports = [
  { name: 'javascript', need: ['node'], run: 'node driver.js' },
  { name: 'python', need: ['python3'], run: 'python3 driver.py' },
  { name: 'typescript', need: ['node', 'tsc'],
    build: 'tsc -p "$ROOT/typescript/ltx/tsconfig.cjs.json" --outDir build/ts --declarationDir build/types',
    run: 'node driver.js' },
  { name: 'rust', need: ['cargo'], build: 'cargo build --quiet --release --target-dir build', run: './build/release/ltx-interop-driver' },
  { name: 'go', need: ['go'], build: 'go build -o build/driver .', run: './build/driver' },
  { name: 'ruby', need: ['ruby'], run: 'ruby driver.rb' },
  { name: 'php', need: ['php'], run: 'php driver.php' },
  { name: 'java', need: ['javac', 'java'],
    build: 'mkdir -p build && javac -encoding UTF-8 -d build "$ROOT"/java/ltx/src/com/interplanet/ltx/*.java Driver.java',
    run: 'java -Dfile.encoding=UTF-8 -cp build Driver' },
  { name: 'kotlin', need: ['gradle', 'java'], build: 'gradle -q --offline installDist',
    run: './build/install/driver/bin/driver main' },
  { name: 'kotlin-v11', dir: 'kotlin', need: ['gradle', 'java'], build: 'gradle -q --offline installDist',
    run: './build/install/driver/bin/driver v11' },
  { name: 'scala', need: ['sbt', 'java'],
    build: 'mkdir -p build && sbt "export Runtime/fullClasspath" </dev/null | tail -n 1 > build/classpath.txt',
    run: 'java -cp "$(cat build/classpath.txt)" Driver main' },
  { name: 'scala-v11', dir: 'scala', need: ['sbt', 'java'],
    build: 'mkdir -p build && sbt "export Runtime/fullClasspath" </dev/null | tail -n 1 > build/classpath.txt',
    run: 'java -cp "$(cat build/classpath.txt)" Driver v11' },
  { name: 'csharp', need: ['dotnet'], build: 'dotnet build -nologo -v q -c Release -o build/out',
    run: 'dotnet build/out/Driver.dll main' },
  { name: 'csharp-v11', dir: 'csharp', need: ['dotnet'], build: 'dotnet build -nologo -v q -c Release -o build/out',
    run: 'dotnet build/out/Driver.dll v11' },
  { name: 'fsharp', need: ['dotnet'], run: 'dotnet fsi driver.fsx main' },
  { name: 'fsharp-v11', dir: 'fsharp', need: ['dotnet'], run: 'dotnet fsi driver.fsx v11' },
  { name: 'c', need: ['cc'],
    build: 'mkdir -p build && cc -std=c99 -O2 -I"$ROOT/c/ltx/include" driver.c "$ROOT/c/ltx/src/libitx.c" "$ROOT/c/ltx/src/itx_plan_json.c" -lm -o build/driver',
    run: './build/driver' },
  { name: 'dart', need: ['dart'], build: 'dart pub get --offline >/dev/null && mkdir -p build && dart compile exe bin/driver.dart -o build/driver >/dev/null',
    run: './build/driver' },
  { name: 'swift', need: ['swift'], build: 'swift build -c release --scratch-path build 2>&1 | tail -n 3 && test -x build/release/Driver',
    run: './build/release/Driver' },
  { name: 'zig', need: ['zig'],
    build: 'mkdir -p build && zig build-exe -O ReleaseSafe --cache-dir build/cache --global-cache-dir build/gcache -femit-bin=build/driver --dep ltx --dep v11 -Mroot=driver.zig -Mltx="$ROOT/zig/ltx/src/interplanet_ltx.zig" -Mv11="$ROOT/zig/ltx/src/ltx_v11.zig"',
    run: './build/driver' },
  { name: 'elixir', need: ['elixirc', 'elixir'],
    build: 'mkdir -p build && elixirc --ignore-module-conflict -o build "$ROOT"/elixir/ltx/lib/interplanet_ltx/*.ex >/dev/null',
    run: 'elixir -pa build driver.exs' },
  { name: 'lua', need: ['lua'], run: 'cd "$ROOT/lua/ltx" && lua "$OLDPWD/driver.lua"' },
  { name: 'ocaml', need: ['ocamlfind', 'ocamlopt'],
    build: 'rm -rf build && mkdir -p build && cp "$ROOT"/ocaml/ltx/lib/*.ml driver.ml build/ && cd build && ocamlfind ocamlopt -package unix,str -linkpkg constants.ml models.ml interplanet_ltx.ml ed25519.ml security.ml validate.ml v11.ml driver.ml -o driver',
    run: './build/driver' },
  { name: 'r', need: ['Rscript'], run: 'cd "$ROOT/r/ltx" && LC_ALL=C.UTF-8 Rscript "$OLDPWD/driver.R"' },
  { name: 'julia', need: ['julia'], run: 'julia --startup-file=no --project="$ROOT/julia/ltx" driver.jl' },
];
