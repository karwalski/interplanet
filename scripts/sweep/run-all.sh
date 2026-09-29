#!/usr/bin/env bash
# Full repository sweep (issue #38): every port's unit tests, the planet-time
# fixture runner against c/planet-time/fixtures/reference.json, the LTX golden
# planId tests (spec/golden/plan-ids.json, spec/golden/plan-id-prefixes.json),
# package builds and lint, the repository-level checks, the planet-time
# accuracy sweep, the cross-port interop run and the web and services
# sections. Prints a PASS/FAIL table and exits 1 if anything failed.
#
#   scripts/sweep/run-all.sh                  everything
#   scripts/sweep/run-all.sh --only go,rust   entries whose name, port or section matches
#   scripts/sweep/run-all.sh --skip interop   everything except
#   scripts/sweep/run-all.sh --list           list the entries and exit
#   scripts/sweep/run-all.sh --verbose        stream each entry's output
#
# See scripts/sweep/README.md for the environment variables.
set -u

SWEEP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$SWEEP_DIR/../.." && pwd)
export ROOT

# ── Toolchain PATH ──────────────────────────────────────────────────────────
DEFAULT_TOOL_PATH=/tmp/claude-0/-home-user-interplanet/62b44def-77ee-5085-9fac-355ab027309f/scratchpad/bin
SWEEP_PATH=${SWEEP_PATH:-${INTEROP_PATH:-$DEFAULT_TOOL_PATH}}
export SWEEP_PATH
export INTEROP_PATH=${INTEROP_PATH:-$SWEEP_PATH}
export PATH="$SWEEP_PATH:/usr/local/bin:$PATH"

# ── Shared inputs for the entries ───────────────────────────────────────────
export FIXTURE="$ROOT/c/planet-time/fixtures/reference.json"
export GOLDEN_IDS="$ROOT/spec/golden/plan-ids.json"
export GOLDEN_PREFIXES="$ROOT/spec/golden/plan-id-prefixes.json"
export SWEEP_PYTHON=${SWEEP_PYTHON:-python3}
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
SWEEP_TIMEOUT=${SWEEP_TIMEOUT:-1800}

ONLY="" SKIP_LIST="" LIST=0 VERBOSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY=$2; shift 2 ;;
    --only=*) ONLY=${1#--only=}; shift ;;
    --skip) SKIP_LIST=$2; shift 2 ;;
    --skip=*) SKIP_LIST=${1#--skip=}; shift ;;
    --list) LIST=1; shift ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help) sed -n '2,/^set -u/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# ── Entry registry ──────────────────────────────────────────────────────────
# sweep_add SECTION NAME DIR NEEDS COMMAND
#   SECTION  ports | checks | web | services (free text, used by --only)
#   NAME     row label, e.g. go/planet-time
#   DIR      working directory relative to $ROOT
#   NEEDS    space-separated executables; a missing one makes the row SKIP
#   COMMAND  bash script run with `set -eo pipefail` in DIR. It sees ROOT,
#            FIXTURE, GOLDEN_IDS, GOLDEN_PREFIXES, SWEEP_PYTHON and SWEEP_TMP
#            (a scratch directory for this entry).
E_SECTION=() E_NAME=() E_DIR=() E_NEEDS=() E_CMD=()
sweep_add() {
  E_SECTION+=("$1"); E_NAME+=("$2"); E_DIR+=("$3"); E_NEEDS+=("$4"); E_CMD+=("$5")
}

# Repository-level checks.
sweep_add checks check-versions . node 'node scripts/check-versions.js'
sweep_add checks js-reference-check . node 'node scripts/conformance/js-reference-check.js'
sweep_add checks plan-id-prefixes-current . node 'node scripts/conformance/gen-plan-id-prefixes.js --check'
sweep_add checks upper-tables-current . node 'node scripts/conformance/gen-upper-tables.js --check'
# shellcheck source=ports.sh
. "$SWEEP_DIR/ports.sh"
sweep_add checks planet-time-accuracy . node 'scripts/sweep/accuracy/run.sh'
sweep_add checks interop . node 'node scripts/interop/run.js'
# Web (Playwright) and services (CLI, API, relays, MCP, replication kit)
# are standalone scripts that exit non-zero on failure; run each as one entry.
[ -f "$SWEEP_DIR/web.sh" ] && sweep_add web web-suite . node 'bash scripts/sweep/web.sh'
[ -f "$SWEEP_DIR/services.sh" ] && sweep_add services services-suite . node 'bash scripts/sweep/services.sh'

matches() {  # matches "a,b" section name
  local list=$1 section=$2 name=$3 pat
  IFS=, read -ra pats <<<"$list"
  for pat in "${pats[@]}"; do
    [ -z "$pat" ] && continue
    # shellcheck disable=SC2254
    case "$name" in $pat|$pat/*|*/$pat) return 0 ;; esac
    [ "$section" = "$pat" ] && return 0
  done
  return 1
}

selected=()
for i in "${!E_NAME[@]}"; do
  if [ -n "$ONLY" ] && ! matches "$ONLY" "${E_SECTION[$i]}" "${E_NAME[$i]}"; then continue; fi
  if [ -n "$SKIP_LIST" ] && matches "$SKIP_LIST" "${E_SECTION[$i]}" "${E_NAME[$i]}"; then continue; fi
  selected+=("$i")
done

if [ "$LIST" = 1 ]; then
  for i in "${selected[@]}"; do
    printf '%-9s %-28s %-24s needs: %s\n' "${E_SECTION[$i]}" "${E_NAME[$i]}" "${E_DIR[$i]}" "${E_NEEDS[$i]}"
  done
  exit 0
fi

LOG_DIR=${SWEEP_LOG_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/interplanet-sweep.XXXXXX")}
mkdir -p "$LOG_DIR"
echo "Sweep of $ROOT"
echo "Logs: $LOG_DIR"
echo "PATH additions: $SWEEP_PATH:/usr/local/bin"
echo

R_STATUS=() R_TIME=() R_NOTE=()
fails=0
for i in "${selected[@]}"; do
  name=${E_NAME[$i]}
  log="$LOG_DIR/$(printf '%s' "$name" | tr '/ ' '__').log"
  missing=""
  for tool in ${E_NEEDS[$i]}; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
  done
  if [ -n "$missing" ]; then
    R_STATUS[$i]=SKIP; R_TIME[$i]=0; R_NOTE[$i]="missing:$missing"
    printf '%-28s SKIP (missing:%s)\n' "$name" "$missing"
    continue
  fi
  printf '%-28s ' "$name"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/sweep-entry.XXXXXX")
  start=$(date +%s)
  script="set -eo pipefail
${E_CMD[$i]}"
  if [ "$VERBOSE" = 1 ]; then
    echo
    ( cd "$ROOT/${E_DIR[$i]}" && SWEEP_TMP=$tmp timeout "$SWEEP_TIMEOUT" bash -c "$script" ) </dev/null 2>&1 | tee "$log"
    code=${PIPESTATUS[0]}
  else
    ( cd "$ROOT/${E_DIR[$i]}" && SWEEP_TMP=$tmp timeout "$SWEEP_TIMEOUT" bash -c "$script" ) </dev/null >"$log" 2>&1
    code=$?
  fi
  rm -rf "$tmp"
  secs=$(( $(date +%s) - start ))
  # Last line that reports a pass count, whatever the runner's wording.
  note=$(grep -aiE '[0-9]+ (passed|tests? passed|pass(es)?\b)|passed: *[0-9]+|[0-9]+ checks' "$log" | tail -n 1 \
         | sed -E 's/\x1b\[[0-9;]*m//g; s/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c1-60)
  if [ "$code" -eq 0 ] && grep -q '^SKIP:' "$log"; then
    # An entry may decide at run time that it cannot run (prints "SKIP: why").
    R_STATUS[$i]=SKIP; note=$(grep -m1 '^SKIP:' "$log" | cut -c7-66)
  elif [ "$code" -eq 0 ]; then
    R_STATUS[$i]=PASS
  else
    R_STATUS[$i]=FAIL; fails=$((fails + 1))
    [ "$code" -eq 124 ] && note="timeout after ${SWEEP_TIMEOUT}s"
    [ -n "$note" ] || note="exit $code"
  fi
  R_TIME[$i]=$secs; R_NOTE[$i]=$note
  printf '%s (%ss)\n' "${R_STATUS[$i]}" "$secs"
  if [ "$code" -ne 0 ] && [ "$VERBOSE" = 0 ]; then
    tail -n 25 "$log" | sed 's/^/    | /'
  fi
done

echo
printf '| %-9s | %-28s | %-6s | %6s | %s\n' Section Entry Result Time Note
printf '|%s|%s|%s|%s|%s\n' ----------- ------------------------------ -------- -------- ------------------------------
pass=0 skip=0
for i in "${selected[@]}"; do
  case "${R_STATUS[$i]}" in PASS) pass=$((pass + 1)) ;; SKIP) skip=$((skip + 1)) ;; esac
  printf '| %-9s | %-28s | %-6s | %5ss | %s\n' "${E_SECTION[$i]}" "${E_NAME[$i]}" "${R_STATUS[$i]}" "${R_TIME[$i]}" "${R_NOTE[$i]}"
done
echo
echo "$pass passed, $fails failed, $skip skipped (of ${#selected[@]}). Logs: $LOG_DIR"
[ "$fails" -eq 0 ]
