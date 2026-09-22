#!/bin/sh
# Prints the row a qualified release adds to the table in README.md, read from
# what the run produced rather than remembered.
#
# Usage: scripts/release-row.sh <qt-version> [apply-log] [out-dir]
#
# The table measures what maintaining the series costs: whether it applied,
# whether the build was clean, what the gate said, and how much of a person's
# time it took. Three of those four are in the artifacts. The fourth is a
# judgement, so this prints `none` when nothing needed resolving and asks you to
# say otherwise when something did.
set -eu

version="${1:?usage: release-row.sh <qt-version> [apply-log] [out-dir]}"
here="$(cd "$(dirname "$0")/.." && pwd)"
apply_log="${2:-}"
out="${3:-$here/out}"

# What `refresh.sh` said when it applied the series. Its three outcomes are the
# three things this column can say.
applying="unrecorded"
if [ -n "$apply_log" ] && [ -f "$apply_log" ]; then
    if grep -q "^SERIES APPLIED:" "$apply_log"; then
        applying="$(sed -n 's/^SERIES APPLIED: \(.*\)/\1/p' "$apply_log" | head -1)"
    elif grep -q "^SERIES EXTENDED:" "$apply_log"; then
        applying="$(sed -n 's/^SERIES EXTENDED: \(.*\)/\1/p' "$apply_log" | head -1)"
    elif grep -q "^SERIES ALREADY APPLIED:" "$apply_log"; then
        applying="already applied"
    elif grep -q "^CONFLICT" "$apply_log"; then
        applying="conflicted"
    fi
fi

# The gate, from the run that produced the artifact rather than from a number
# anybody typed.
tests="unrecorded"
if [ -f "$out/verify.txt" ]; then
    passed="$(sed -n 's/^Totals: \([0-9]*\) passed.*/\1/p' "$out/verify.txt" | head -1)"
    failed="$(sed -n 's/^Totals: [0-9]* passed, \([0-9]*\) failed.*/\1/p' "$out/verify.txt" | head -1)"
    if [ -n "$passed" ]; then
        if [ "${failed:-0}" = "0" ]; then
            tests="$passed of $passed"
        else
            tests="$passed passed, $failed FAILED"
        fi
    fi
fi

# Clean or incremental, which is what the column has always meant: a fresh
# tarball compiled from nothing, or a tree that was already built being added
# to. `refresh.sh` says which by which of its three outcomes it reported.
case "$applying" in
    "already applied"|*"already applied"*) build="incremental" ;;
    unrecorded)                            build="unrecorded" ;;
    conflicted)                            build="did not build" ;;
    *)                                     build="clean" ;;
esac

case "$applying" in
    conflicted) time="a person resolved a conflict, say how long" ;;
    *)          time="none" ;;
esac

# A release is both architectures. This is not a column, so it goes to stderr
# rather than into a row that would read as finished.
for arch in x86_64 aarch64; do
    if [ -z "$(find "$out" -maxdepth 1 -name "*-$arch.pkg.tar.*" ! -name '*.sig' \
        -print 2>/dev/null)" ]; then
        echo "release-row: no $arch package in $out, so this release is not finished" >&2
    fi
done

printf '| %s | %s | %s | %s | %s |\n' \
    "$version" "$applying" "$build" "$tests" "$time"
