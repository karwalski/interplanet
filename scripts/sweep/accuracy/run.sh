#!/usr/bin/env bash
# Planet-time accuracy sweep: every port below computes hour, minute, second
# and day number (all 9 bodies), light time from Earth and Mars MTC at 200
# seeded random instants from 1990 to 2100, and compare.js checks each against
# javascript/planet-time/planet-time.js (exact, light time within 1 s).
#
#   scripts/sweep/accuracy/run.sh [port ...]    default: every port
#   ACCURACY_COUNT=1000 ACCURACY_SEED=7 scripts/sweep/accuracy/run.sh c go
#
# Ports: typescript python java kotlin scala c go rust zig. A port whose
# toolchain is missing is skipped. Exit code 1 if any port disagrees or fails
# to build.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
PROBES=$HERE/probes
TOOL_PATH=${SWEEP_PATH:-${INTEROP_PATH:-/tmp/claude-0/-home-user-interplanet/62b44def-77ee-5085-9fac-355ab027309f/scratchpad/bin}}
export PATH="$TOOL_PATH:/usr/local/bin:$PATH"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/planet-time-accuracy.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
node "$HERE/gen.js" "$WORK" "${ACCURACY_COUNT:-200}" "${ACCURACY_SEED:-38}" || exit 1
IN=$WORK/inputs.txt

has() { command -v "$1" >/dev/null 2>&1; }

probe_typescript() {
  has node && has npm || return 99
  (cd "$ROOT/typescript/planet-time" && { [ -d node_modules ] || npm ci --silent --no-audit --no-fund; } && npm run -s build) >&2 || return 1
  node "$PROBES/probe_ts.js" "$IN"
}
probe_python() {
  has python3 || return 99
  python3 "$PROBES/probe_py.py" "$IN"
}
probe_java() {
  has javac && has java || return 99
  local d=$WORK/java
  mkdir -p "$d"
  javac -encoding UTF-8 -d "$d" "$ROOT"/java/planet-time/src/com/interplanet/time/*.java "$PROBES/Probe.java" >&2 || return 1
  java -cp "$d" Probe "$IN" 2>/dev/null
}
probe_kotlin() {
  has gradle && has java || return 99
  local d=$WORK/kotlin
  mkdir -p "$d/probe"
  cp "$PROBES/probe.kt" "$d/probe/"
  echo 'rootProject.name = "accuracy-probe"' > "$d/settings.gradle.kts"
  cat > "$d/build.gradle.kts" <<EOF
plugins { kotlin("jvm") version "1.9.22"; application }
repositories { mavenCentral() }
kotlin { jvmToolchain(17) }
application { mainClass.set("ProbeKt") }
sourceSets { main { kotlin { srcDirs("$ROOT/kotlin/planet-time/src/main/kotlin", "probe") } } }
EOF
  (cd "$d" && gradle -q ${GRADLE_FLAGS:-} installDist) >&2 || return 1
  "$d/build/install/accuracy-probe/bin/accuracy-probe" "$IN" 2>/dev/null
}
probe_scala() {
  has sbt && has java || return 99
  local d=$WORK/scala
  mkdir -p "$d/project"
  cp "$PROBES/Probe.scala" "$d/"
  echo "sbt.version=1.10.7" > "$d/project/build.properties"
  cat > "$d/build.sbt" <<EOF
scalaVersion := "3.6.4"
Compile / unmanagedSourceDirectories += file("$ROOT/scala/planet-time/src/main/scala")
EOF
  (cd "$d" && sbt "export Runtime/fullClasspath" </dev/null | tail -n 1 > classpath.txt) >&2 || return 1
  java -cp "$(cat "$d/classpath.txt")" probe "$IN" 2>/dev/null
}
probe_c() {
  has cc || return 99
  cc -std=c11 -O2 -I"$ROOT/c/planet-time/include" "$PROBES/probe.c" "$ROOT/c/planet-time/src/libinterplanet.c" \
    -lm -o "$WORK/probe_c" >&2 || return 1
  "$WORK/probe_c" "$IN"
}
probe_go() {
  has go || return 99
  local d=$WORK/go
  mkdir -p "$d"
  cp "$PROBES/probe.go" "$d/main.go"
  printf 'module probe\n\ngo 1.21\n\nrequire github.com/interplanet/time v0.0.0\n\nreplace github.com/interplanet/time => %s\n' \
    "$ROOT/go/planet-time" > "$d/go.mod"
  (cd "$d" && go build -o probe .) >&2 || return 1
  "$d/probe" "$IN"
}
probe_rust() {
  has cargo || return 99
  local d=$WORK/rust
  mkdir -p "$d/src"
  cp "$PROBES/probe.rs" "$d/src/main.rs"
  printf '[package]\nname = "probe"\nversion = "0.0.0"\nedition = "2021"\n\n[dependencies]\ninterplanet-time = { path = "%s" }\n' \
    "$ROOT/rust/planet-time" > "$d/Cargo.toml"
  (cd "$d" && cargo build --quiet --release) >&2 || return 1
  "$d/target/release/probe" "$IN"
}
probe_zig() {
  has zig || return 99
  zig build-exe -O ReleaseSafe --cache-dir "$WORK/zig-cache" --global-cache-dir "$WORK/zig-gcache" \
    -femit-bin="$WORK/probe_zig" --dep interplanet_time -Mroot="$PROBES/probe.zig" \
    -Minterplanet_time="$ROOT/zig/planet-time/src/interplanet_time.zig" >&2 || return 1
  "$WORK/probe_zig" "$IN"
}

PORTS=(typescript python java kotlin scala c go rust zig)
[ $# -gt 0 ] && PORTS=("$@")
fails=0
for port in "${PORTS[@]}"; do
  if ! declare -F "probe_$port" >/dev/null; then echo "unknown port: $port"; fails=$((fails + 1)); continue; fi
  "probe_$port" > "$WORK/$port.tsv" 2> "$WORK/$port.err"
  code=$?
  if [ "$code" -eq 99 ]; then echo "$port: SKIP (toolchain missing)"; continue; fi
  if [ "$code" -ne 0 ]; then
    echo "$port: FAIL (probe exit $code)"; tail -n 15 "$WORK/$port.err" | sed 's/^/    /'
    fails=$((fails + 1)); continue
  fi
  node "$HERE/compare.js" "$WORK/expected.tsv" "$WORK/$port.tsv" "$port" || fails=$((fails + 1))
done
[ "$fails" -eq 0 ]
