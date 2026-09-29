#!/bin/sh
# Build the toke port of interplanet from source with a pinned toke compiler.
#
#   ./build.sh                  clone + build tkc at the pinned revision, then build ./interplanet
#   TKC=/path/to/tkc ./build.sh use an existing tkc (it must be the pinned revision)
#   TOKE_DIR=/some/dir ./build.sh  where to clone the toolchain (default: ./.toolchain/toke)
#
# Tested on x86_64 Linux (Ubuntu 24.04, clang 18). tkc drives clang itself, so
# clang must be on PATH.
set -eu

TOKE_REPO=https://github.com/karwalski/toke
TOKE_REV=0b0bc4e501633de471af4d7413c248036f7ccf92   # toke 3.0.0, 2026-09-23

here=$(cd "$(dirname "$0")" && pwd)

if [ -z "${TKC:-}" ]; then
  TOKE_DIR=${TOKE_DIR:-$here/.toolchain/toke}
  if [ ! -d "$TOKE_DIR/.git" ]; then
    git clone --quiet "$TOKE_REPO" "$TOKE_DIR"
  fi
  if [ "$(git -C "$TOKE_DIR" rev-parse HEAD)" != "$TOKE_REV" ]; then
    git -C "$TOKE_DIR" fetch --quiet origin
    git -C "$TOKE_DIR" checkout --quiet "$TOKE_REV"
  fi
  if [ ! -x "$TOKE_DIR/tkc" ]; then
    make -C "$TOKE_DIR" -j4 >/dev/null
  fi
  TKC=$TOKE_DIR/tkc
fi

"$TKC" --version
rm -f "$here/interplanet"
# Single source file: multi-file builds (tkc a.tk b.tk) fail to link on Linux
# at this revision, so the port is one compilation unit.
"$TKC" --diag-text "$here/src/interplanet.tk" --out "$here/interplanet" 2>&1 \
  | grep -v -e '^warning' -e '^ *|' -e '^ *-->' -e '^ *[0-9]* |' -e '^$' || true
test -x "$here/interplanet"
echo "built $here/interplanet"
