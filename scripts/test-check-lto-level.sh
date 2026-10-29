#!/bin/sh
# Runs check-lto-level.sh against stand-in build trees and checks its verdict for each.
#
# Usage: scripts/test-check-lto-level.sh
#
# A real tree takes hours to build and links only one way, so the stand-ins hold the engine's link
# flags at each level, from a GCC build, with no level, and not at all.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failed=0

# A stand-in tree whose engine library links with the given flags.
stand_in() {
    dir="$work/$1/build/src/core/Release/x86_64"
    mkdir -p "$dir"
    printf '%s\n' "$2" > "$dir/QtWebEngineCore_lflags.rsp"
}

# The exit status and the verdict line a tree gets, and the file that line has to name.
check() {
    name="$1" status="$2" verdict="$3" names="$4"
    output="$(sh "$here/check-lto-level.sh" "$work/$name" 2>&1)" && actual=0 || actual=$?
    if [ "$actual" != "$status" ]; then
        echo "FAIL $name: expected exit $status, got $actual"
        failed=1
    elif ! echo "$output" | grep -qx "Totals: $verdict"; then
        echo "FAIL $name: expected Totals: $verdict, got: $output"
        failed=1
    elif ! echo "$output" | grep -qF "$names"; then
        echo "FAIL $name: expected the output to name $names, got: $output"
        failed=1
    else
        echo "ok   $name: Totals: $verdict"
    fi
}

rsp="build/src/core/Release/x86_64/QtWebEngineCore_lflags.rsp"

# Chromium's default for every target but Chrome's own: the link imports across files and then
# does not optimize what it imported.
stand_in o0 "-fPIC -flto=thin -Wl,--thinlto-jobs=all -Wl,--lto-O0 -fuse-ld=lld"
check o0 1 "0 passed, 1 failed" "o0/$rsp"

# Chrome's own target, thinlto_optimize_max.
stand_in o2 "-fPIC -flto=thin -Wl,--thinlto-jobs=all -Wl,--lto-O2 -fuse-ld=lld"
check o2 0 "1 passed, 0 failed" "o2/$rsp"

# A level that only starts the same way is not the one.
stand_in o1 "-fPIC -flto=thin -Wl,--lto-O1"
check o1 1 "0 passed, 1 failed" "o1/$rsp"

# aarch64 builds with GCC and links no ThinLTO, so it has no level to hold.
stand_in gcc "-fPIC -Wl,--gc-sections -Wl,-z,relro"
check gcc 0 "1 passed, 0 failed" "gcc/$rsp"

# A ThinLTO link that names no level proves nothing either way.
stand_in nolevel "-fPIC -flto=thin -fuse-ld=lld"
check nolevel 1 "0 passed, 1 failed" "nolevel/$rsp"

# A tree whose layout moved, or that was never built.
mkdir -p "$work/unbuilt/build"
check unbuilt 1 "0 passed, 1 failed" "$work/unbuilt"

exit "$failed"
