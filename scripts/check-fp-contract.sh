#!/bin/sh
# Say whether a GCC-built tree's engine was compiled without fused multiply-adds.
# Usage: scripts/check-fp-contract.sh <tree>
#
# GCC fuses a multiply and an add into one FMA by default, and every aarch64 has FMA. Chromium
# turns that off with -ffp-contract=off only in a clang block Qt skips, so the GCC engine rounded
# otherwise than the clang one and drew a darkened white page #1b1b1b where x86_64 draws #121212
# (#34, omaweb#936). toolchain/gcc.patch adds the flag, and this is what is left to notice if a
# later Qt or Chromium moves it. Dark mode's colour filter is compiled into Blink's platform
# library, so that library's ninja file is read for its flags and named, and the compiler is read
# from the cxx rule in toolchain.ninja beside it. A clang build passes. A tree where the files are
# not found fails, rather than passing on nothing read, because the day the build's layout moves
# is the day this would otherwise say nothing.
#
# The verdict is a Qt Test "Totals:" line, so the gate that reads the tests' totals reads this too.
set -eu

tree="${1:?usage: check-fp-contract.sh <tree>}"
layout="build/src/core/Release/*/obj/third_party/blink/renderer/platform/platform.ninja"

fail() {
    echo "FAIL!  : $1"
    echo "Totals: 0 passed, 1 failed"
    exit 1
}

echo "=== the engine's floating point, which GCC must not fuse"
found=0
for ninja in "$tree"/$layout; do
    [ -f "$ninja" ] || continue
    found=$((found + 1))
    toolchain="${ninja%/obj/*}/toolchain.ninja"
    [ -f "$toolchain" ] || fail "no toolchain.ninja beside $ninja"
    # The compiler is the word of the cxx rule's command that names one, after any launcher.
    compiler="$(sed -n '/^rule cxx$/,/^rule /s/^  command = //p' "$toolchain" | tr ' ' '\n' \
        | sed 's|.*/||' | grep -E -m 1 '^(.*g|clang)\+\+(-[0-9.]+)?$' || true)"
    [ -n "$compiler" ] || fail "$toolchain names no C++ compiler in its cxx rule"
    case "$compiler" in
        clang++*)
            echo "PASS   : $ninja is compiled by clang"
            continue
            ;;
    esac
    flags="$(sed -n 's/^cflags = //p' "$ninja")"
    contract="$(echo " $flags " | tr ' ' '\n' | sed -n 's/^-ffp-contract=//p' | tail -1)"
    [ "$contract" = "off" ] \
        || fail "$ninja is compiled by GCC with -ffp-contract=${contract:-fast, its default}"
    echo "PASS   : $ninja is compiled by GCC with -ffp-contract=off"
done
[ "$found" -gt 0 ] || fail "no $layout in $tree"
echo "Totals: $found passed, 0 failed"
