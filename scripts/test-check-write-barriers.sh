#!/bin/sh
# Runs check-write-barriers.sh against stand-in build trees and checks its verdict for each.
#
# Usage: scripts/test-check-write-barriers.sh
#
# A real tree takes hours to build and holds the setting only one way, so the stand-ins hold V8's
# ninja file with the define, without it, without a defines line, and not at all.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failed=0

# A tree whose V8 compiles with the given defines, or with no defines line when given none.
tree() {
    dir="$work/$1/build/src/core/Release/aarch64/obj/v8"
    mkdir -p "$dir"
    if [ -n "$2" ]; then
        printf 'defines = %s\ninclude_dirs = -I../..\n' "$2" > "$dir/v8_base_without_compiler.ninja"
    else
        printf 'include_dirs = -I../..\n' > "$dir/v8_base_without_compiler.ninja"
    fi
}

# The exit status and the verdict line a tree gets, and the file that line has to name.
check() {
    name="$1" status="$2" verdict="$3" names="$4"
    output="$(sh "$here/check-write-barriers.sh" "$work/$name" 2>&1)" && actual=0 || actual=$?
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

ninja="build/src/core/Release/aarch64/obj/v8/v8_base_without_compiler.ninja"

# Qt's 6.11.2 as it ships: no write barriers, so a single generation.
tree off "-DV8_ENABLE_WEBASSEMBLY -DV8_DISABLE_WRITE_BARRIERS -DV8_ENABLE_SINGLE_GENERATION"
check off 1 "0 passed, 1 failed" "off/$ninja"

# With patch 0018, or from 6.140.0 on.
tree on "-DV8_ENABLE_WEBASSEMBLY -DV8_ENABLE_LAZY_SOURCE_POSITIONS"
check on 0 "1 passed, 0 failed" "on/$ninja"

# A define that only starts the same way is not the one.
tree prefix "-DV8_DISABLE_WRITE_BARRIERS_FOR_TESTING"
check prefix 0 "1 passed, 0 failed" "prefix/$ninja"

# A file that no longer says what it compiles with proves nothing either way.
tree undefined ""
check undefined 1 "0 passed, 1 failed" "undefined/$ninja"

# A tree whose layout moved, or that was never built.
mkdir -p "$work/unbuilt/build"
check unbuilt 1 "0 passed, 1 failed" "$work/unbuilt"

exit "$failed"
