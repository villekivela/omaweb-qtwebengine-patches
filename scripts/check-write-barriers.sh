#!/bin/sh
# Say whether a built tree's V8 has its write barriers, from the flags it was compiled with.
# Usage: scripts/check-write-barriers.sh <tree>
#
# Qt's 6.11.2 turns them off, and with them V8's young generation, which cost JetStream a fifth of
# its score (omaweb#356). Patch 0018 turns them back on, and 6.140.0 does so itself, so the patch
# drops there and this is what is left to notice if a later Qt turns them off again. GN's default
# reaches the compiler as -DV8_DISABLE_WRITE_BARRIERS in the ninja file of V8's main library, so
# that file's defines are read and the file is named. A tree where it is not found fails, rather
# than passing on nothing read, because the day the build's layout moves is the day this would
# otherwise say nothing.
#
# The verdict is a Qt Test "Totals:" line, so the gate that reads the tests' totals reads this too.
set -eu

tree="${1:?usage: check-write-barriers.sh <tree>}"
layout="build/src/core/Release/*/obj/v8/v8_base_without_compiler.ninja"

fail() {
    echo "FAIL!  : $1"
    echo "Totals: 0 passed, 1 failed"
    exit 1
}

echo "=== the engine's V8, which must have its write barriers"
found=0
for ninja in "$tree"/$layout; do
    [ -f "$ninja" ] || continue
    found=$((found + 1))
    defines="$(sed -n 's/^defines = //p' "$ninja")"
    [ -n "$defines" ] || fail "$ninja has no defines line to read"
    if echo " $defines " | grep -q -- " -DV8_DISABLE_WRITE_BARRIERS[ =]"; then
        fail "$ninja compiles V8 with -DV8_DISABLE_WRITE_BARRIERS"
    fi
    echo "PASS   : $ninja compiles V8 with its write barriers"
done
[ "$found" -gt 0 ] || fail "no $layout in $tree"
echo "Totals: $found passed, 0 failed"
