#!/usr/bin/env bash
# cross_sdk_security.sh — Cross-SDK security integration test (Story 28.10)
#
# Tests:
#   1. Python signs → TypeScript verifies
#   2. TypeScript signs → Python verifies
#
# Run from repo root:
#   bash tests/cross_sdk_security.sh
#
# Requirements:
#   - python3 with 'cryptography' package (pip install cryptography)
#   - node (for TypeScript CJS build)
#   - TypeScript SDK already built: cd typescript/ltx && npm run build

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$REPO/tests"
TS_DIST="$REPO/typescript/ltx/dist/cjs/index.js"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# ── Check prerequisites ────────────────────────────────────────────────────────

if [ ! -f "$TS_DIST" ]; then
  echo "TypeScript dist not found at $TS_DIST — building..."
  (cd "$REPO/typescript/ltx" && npm run build)
fi

# ── Test 1: Python signs → TypeScript verifies ────────────────────────────────

echo ""
echo "── Cross-SDK: Python signs → TypeScript verifies ────────────────────────"

if python3 "$TESTS/cross_sdk_sign_py.py" | node "$TESTS/cross_sdk_verify_ts.js"; then
  pass "Python → TypeScript: verifyPlan succeeded"
else
  fail "Python → TypeScript: verifyPlan failed"
fi

# ── Test 2: TypeScript signs → Python verifies ────────────────────────────────

echo ""
echo "── Cross-SDK: TypeScript signs → Python verifies ────────────────────────"

if node "$TESTS/cross_sdk_sign_ts.js" | python3 "$TESTS/cross_sdk_verify_py.py"; then
  pass "TypeScript → Python: verify_plan succeeded"
else
  fail "TypeScript → Python: verify_plan failed"
fi

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════"
echo "Cross-SDK: $PASS passed  $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
