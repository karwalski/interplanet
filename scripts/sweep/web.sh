#!/usr/bin/env bash
# Sweep (issue #38): the web app end to end in Chromium via Playwright.
# Serves a copy of demo/ under php -S (api/*.php with a SQLite getDB stub,
# relay-server.php, a share.php stand-in) and runs scripts/sweep/web/tests/*.js.
# External CDNs and APIs are stubbed by route interception.
# Needs node >= 18, php 8.x with pdo_sqlite and sqlite3, and Playwright with
# Chromium (found via NODE_PATH, default /opt/node22/lib/node_modules).
# Extra arguments pass through, e.g. --file ltx or --only "share URL".
# Exits non-zero if any test fails.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export NODE_PATH="${NODE_PATH:-/opt/node22/lib/node_modules}"
exec node "$ROOT/scripts/sweep/web/run.js" "$@"
