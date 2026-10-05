#!/bin/sh
# Say whether a built tree's V8 has its write barriers, from the flags it was compiled with.
# Usage: scripts/check-write-barriers.sh <tree>
#
# Qt's 6.11.2 turns them off, and with them V8's young generation, which cost JetStream a fifth of
# its score (omaweb#356). Patch 0018 turns them back on, and 6.140.0 does so itself, so the patch
# drops there and this is what is left to notice if a later Qt turns them off again. GN's default
# reaches the compiler as -DV8_DISABLE_WRITE_BARRIERS in the ninja file of V8's main library, so
# that file is read and named. A tree where it is not found fails, rather than passing on nothing
# read, because the day the build's layout moves is the day this would otherwise say nothing.
#
# The verdict is a Qt Test "Totals:" line, so the gate that reads the tests' totals reads this too.
set -eu

tree="${1:?usage: check-write-barriers.sh <tree>}"

echo "=== the engine's V8, which must have its write barriers"
found=0
for ninja in "$tree"/build/src/core/Release/*/obj/v8/v8_base_without_compiler.ninja; do
    [ -f "$ninja" ] || continue
    found=$((found + 1))
    if ! grep -q "^defines = " "$ninja"; then
        echo "FAIL!  : $ninja has no defines line to read"
        echo "Totals: 0 passed, 1 failed"
        exit 1
    fi
    if grep -qw -- "-DV8_DISABLE_WRITE_BARRIERS" "$ninja"; then
        echo "FAIL!  : $ninja compiles V8 with -DV8_DISABLE_WRITE_BARRIERS"
        echo "Totals: 0 passed, 1 failed"
        exit 1
    fi
    echo "PASS   : $ninja compiles V8 with its write barriers"
done
if [ "$found" -eq 0 ]; then
    echo "FAIL!  : no build/src/core/Release/*/obj/v8/v8_base_without_compiler.ninja in $tree"
    echo "Totals: 0 passed, 1 failed"
    exit 1
fi
echo "Totals: $found passed, 0 failed"
