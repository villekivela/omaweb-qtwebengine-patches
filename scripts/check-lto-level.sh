#!/bin/sh
# Say whether a built tree's engine library was optimized when ThinLTO linked it.
# Usage: scripts/check-lto-level.sh <tree>
#
# Chromium links every target at --lto-O0 but Chrome's own, which takes thinlto_optimize_max and
# --lto-O2. At O0 the link imports functions across files and then neither inlines nor optimizes
# them, and the engine is that library (omaweb#886). toolchain/clang.patch gives
# QtWebEngineCore Chrome's config, and this is what is left to notice if a later Qt or Chromium
# drops it. GN writes the library's link flags to QtWebEngineCore_lflags.rsp, which the CMake link
# reads, so that file is read and named. A GCC build has no ThinLTO and passes. A tree where the
# file is not found fails, rather than passing on nothing read, because the day the build's layout
# moves is the day this would otherwise say nothing.
#
# The verdict is a Qt Test "Totals:" line, so the gate that reads the tests' totals reads this too.
set -eu

tree="${1:?usage: check-lto-level.sh <tree>}"
layout="build/src/core/Release/*/QtWebEngineCore_lflags.rsp"

fail() {
    echo "FAIL!  : $1"
    echo "Totals: 0 passed, 1 failed"
    exit 1
}

echo "=== the engine's link, which must optimize what ThinLTO imports"
found=0
for rsp in "$tree"/$layout; do
    [ -f "$rsp" ] || continue
    found=$((found + 1))
    flags=" $(tr '\n' ' ' < "$rsp") "
    if ! echo "$flags" | grep -q -- " -flto=thin "; then
        echo "PASS   : $rsp links without ThinLTO"
        continue
    fi
    level="$(echo "$flags" | tr ' ' '\n' | sed -n 's/^-Wl,--lto-O\([0-9]\)$/\1/p' | tail -1)"
    [ -n "$level" ] || fail "$rsp links with ThinLTO and names no --lto-O level"
    [ "$level" -ge 2 ] || fail "$rsp links with ThinLTO at --lto-O$level"
    echo "PASS   : $rsp links with ThinLTO at --lto-O$level"
done
[ "$found" -gt 0 ] || fail "no $layout in $tree"
echo "Totals: $found passed, 0 failed"
