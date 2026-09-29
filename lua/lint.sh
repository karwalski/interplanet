#!/bin/sh
# Fallback lint for the Lua ports when luacheck is not installed: every file
# must compile (luac -p), must not assign globals, and may only read standard
# Lua 5.4 globals. Usage: sh ../lint.sh src/*.lua test/*.lua
set -u
std=' _G _VERSION arg assert collectgarbage coroutine debug dofile error getmetatable io ipairs load loadfile math next os package pairs pcall print rawequal rawget rawlen rawset require select setmetatable string table tonumber tostring type utf8 warn xpcall '
status=0
for f in "$@"; do
  if ! luac -p "$f"; then status=1; continue; fi
  listing=$(luac -l -l -p "$f")
  sets=$(printf '%s\n' "$listing" | grep -E 'SETTABUP.*_ENV' | sed -E 's/.*_ENV "([^"]*)".*/\1/' | sort -u)
  for g in $sets; do echo "$f: assigns global '$g'"; status=1; done
  gets=$(printf '%s\n' "$listing" | grep -E 'GETTABUP.*_ENV' | sed -E 's/.*_ENV "([^"]*)".*/\1/' | sort -u)
  for g in $gets; do
    case "$std" in *" $g "*) ;; *) echo "$f: reads non-standard global '$g'"; status=1 ;; esac
  done
done
[ $status -eq 0 ] && echo "lint OK ($# files)"
exit $status
