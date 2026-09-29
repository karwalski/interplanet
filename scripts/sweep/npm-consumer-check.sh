#!/usr/bin/env bash
# Pack an npm package and use it the way a consumer would:
#   npm-consumer-check.sh <package dir> <package name> [type packages...]
# Installs the tarball into a scratch project, then checks that `require` and
# `import` both load it without warnings and (when tsc is on PATH) that its
# type declarations resolve under moduleResolution node16 (CJS and ESM
# consumers) and bundler. Extra arguments are npm packages the consumer needs
# for type checking, e.g. @types/node for a package whose API uses Buffer.
set -eo pipefail

pkg=$(cd "$1" && pwd)
name=$2
shift 2
type_pkgs=("$@")
work=$(mktemp -d "${TMPDIR:-/tmp}/npm-consumer.XXXXXX")
trap 'rm -rf "$work"' EXIT

tarball=$(cd "$pkg" && npm pack --silent --pack-destination "$work" | tail -n 1)
mkdir "$work/app"
cd "$work/app"
echo '{ "name": "consumer", "version": "0.0.0", "private": true }' > package.json
npm install --silent --no-audit --no-fund --ignore-scripts "$work/$tarball"

check_quiet() {  # label, then a command whose stderr must be empty
  local label=$1; shift
  local err
  err=$("$@" 2>&1 >/dev/null) || { echo "FAIL $label: $err"; return 1; }
  if [ -n "$err" ]; then echo "FAIL $label (stderr): $err"; return 1; fi
  echo "ok   $label"
}

check_quiet "require('$name')" node -e "
  const m = require('$name');
  if (!m || Object.keys(m).length === 0) { console.error('no exports'); process.exit(1); }"
# --no-experimental-detect-module: behave like Node before 20.19 / 22.7, where
# ESM syntax in a .js file of a package without "type": "module" is an error.
nodeflags=""
node --no-experimental-detect-module -e 0 2>/dev/null && nodeflags=--no-experimental-detect-module
check_quiet "import '$name'" node $nodeflags --input-type=module -e "
  const m = await import('$name');
  if (Object.keys(m).length < 2) { console.error('no named exports'); process.exit(1); }"

if command -v tsc >/dev/null 2>&1; then
  types=()   # TypeScript 6 includes no @types package unless named
  if [ ${#type_pkgs[@]} -gt 0 ]; then
    npm install --silent --no-audit --no-fund --ignore-scripts "${type_pkgs[@]}"
    for p in "${type_pkgs[@]}"; do
      case "$p" in @types/*) types+=(--types "${p#@types/}") ;; esac
    done
  fi
  echo "import * as m from '$name'; export const k: string[] = Object.keys(m);" > esm.mts
  echo "import * as m from '$name'; export const k: string[] = Object.keys(m);" > cjs.cts
  tsc --noEmit --strict "${types[@]}" --module node16 --moduleResolution node16 esm.mts cjs.cts
  echo "ok   types (node16, ESM and CJS consumers)"
  tsc --noEmit --strict "${types[@]}" --module esnext --moduleResolution bundler esm.mts
  echo "ok   types (bundler)"
fi
