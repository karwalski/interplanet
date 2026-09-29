#!/usr/bin/env bash
# Sweep (issue #38): services, CLI and replication-kit tests.
# Runs every suite, prints a summary, exits non-zero if any failed.
# Needs node >= 18 and php 8.x with pdo_sqlite and sqlite3.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
failed=()
passed=()

run() {
  local name="$1"; shift
  echo "=== $name"
  if (cd "$ROOT" && "$@"); then passed+=("$name"); else failed+=("$name"); fi
}

run "cli (cli_test, cli_ltx_test)"          bash -c 'cd cli && npm test --silent'
run "node/relay-server"                     bash -c 'cd node/relay-server && npm test --silent'
run "node/mcp-server"                       bash -c 'cd node/mcp-server && npm test --silent'
run "api planId golden (php)"               php api/tests/test_planid.php
run "api + demo PHP services over HTTP"     node api/tests/test_http.js
run "research/replication-kit (incl. live)" bash -c 'cd research/replication-kit && npm test --silent'
run "javascript/ltx topics"                 node javascript/ltx/tests/topics.js

echo
echo "services sweep: ${#passed[@]} passed, ${#failed[@]} failed"
for f in "${failed[@]+"${failed[@]}"}"; do echo "  FAILED: $f"; done
[ "${#failed[@]}" -eq 0 ]
