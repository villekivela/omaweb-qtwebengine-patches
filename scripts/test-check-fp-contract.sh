#!/bin/sh
# Runs check-fp-contract.sh against stand-in build trees and checks its verdict for each.
#
# Usage: scripts/test-check-fp-contract.sh
#
# A real tree takes hours to build and with one compiler only, so the stand-ins hold the compiler
# toolchain.ninja names and the flags Blink's platform library is compiled with: GCC with and
# without the flag, GCC named c++ and behind ccache, clang, and no build at all.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failed=0

# A stand-in tree compiled by C++ compiler $2, with Blink's platform library given cflags $3.
stand_in() {
    dir="$work/$1/build/src/core/Release/aarch64"
    mkdir -p "$dir/obj/third_party/blink/renderer/platform"
    printf 'rule cxx\n  command = %s -MD -MF ${out}.d ${defines} ${cflags} -c ${in} -o ${out}\n' \
        "$2" > "$dir/toolchain.ninja"
    printf 'defines = -DNDEBUG\ncflags = %s\ncflags_cc = -std=c++20\n' "$3" \
        > "$dir/obj/third_party/blink/renderer/platform/platform.ninja"
}

# The exit status and the verdict line a tree gets, and the file that line has to name.
check() {
    name="$1" status="$2" verdict="$3" names="$4"
    output="$(sh "$here/check-fp-contract.sh" "$work/$name" 2>&1)" && actual=0 || actual=$?
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

ninja="build/src/core/Release/aarch64/obj/third_party/blink/renderer/platform/platform.ninja"

# GCC fuses multiply-adds unless told not to, and then dark mode's white is #1b1b1b (#34).
stand_in gcc /usr/bin/g++ "-fPIC -O2 -fno-strict-aliasing"
check gcc 1 "0 passed, 1 failed" "gcc/$ninja"

stand_in gccoff /usr/bin/g++ "-fPIC -O2 -ffp-contract=off -fno-strict-aliasing"
check gccoff 0 "1 passed, 0 failed" "gccoff/$ninja"

# GCC takes the last -ffp-contract it is given.
stand_in gcclast /usr/bin/g++ "-ffp-contract=off -O2 -ffp-contract=fast"
check gcclast 1 "0 passed, 1 failed" "gcclast/$ninja"

# Qt names GCC by CMake's compiler, which is c++ on Arch Linux ARM, and it is GCC all the same.
stand_in cxx /usr/sbin/c++ "-fPIC -O2"
check cxx 1 "0 passed, 1 failed" "cxx/$ninja"

stand_in cxxoff /usr/sbin/c++ "-fPIC -O2 -ffp-contract=off"
check cxxoff 0 "1 passed, 0 failed" "cxxoff/$ninja"

# Behind a compiler launcher it is still GCC.
stand_in ccache "ccache /usr/bin/g++" "-fPIC -O2"
check ccache 1 "0 passed, 1 failed" "ccache/$ninja"

# x86_64 builds with clang, which the flag is not for.
stand_in clang /usr/bin/clang++ "-fPIC -O2"
check clang 0 "1 passed, 0 failed" "clang/$ninja"

# A tree whose layout moved, or that was never built.
mkdir -p "$work/unbuilt/build"
check unbuilt 1 "0 passed, 1 failed" "$work/unbuilt"

exit "$failed"
