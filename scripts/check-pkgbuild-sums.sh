#!/bin/bash
# Check that the checksums packaging/PKGBUILD records match the files beside it.
# Usage: scripts/check-pkgbuild-sums.sh
#
# makepkg checks them only when an engine is packaged, hours into a release,
# and a notice edited without its checksum stops the package there. This reads
# the same two arrays makepkg does and checks them in a second. A SKIP is left
# alone: it marks the tarball, which each build makes anew.
set -eu

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here/packaging"

# Sourcing defines the arrays makepkg reads, and package(), which is never
# called. A PKGBUILD's top level is assignments, so nothing else runs.
# shellcheck disable=SC1091
. ./PKGBUILD
# shellcheck disable=SC2154 # both arrays come from the PKGBUILD

if [ "${#source[@]}" -ne "${#sha256sums[@]}" ]; then
    echo "PKGBUILD lists ${#source[@]} sources and ${#sha256sums[@]} checksums"
    exit 1
fi

failed=0
for index in "${!source[@]}"; do
    file="${source[$index]}"
    recorded="${sha256sums[$index]}"
    [ "$recorded" = "SKIP" ] && continue
    actual="$(sha256sum "$file" | cut -d' ' -f1)"
    if [ "$actual" != "$recorded" ]; then
        echo "$file: PKGBUILD records $recorded, the file is $actual"
        failed=1
    fi
done

if [ "$failed" -ne 0 ]; then
    echo "update sha256sums in packaging/PKGBUILD"
    exit 1
fi
echo "every checksum in packaging/PKGBUILD matches"
