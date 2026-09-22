#!/bin/sh
# Runs on the rented machine. Builds the patched engine inside an Arch
# container, so the binaries match the distribution they ship to rather than
# whatever the rented image happens to be. The build itself is
# `build-inside.sh`, which `build-locally.sh` runs in the same container on a
# machine you already have.
#
# Usage: remote-build.sh <qt-version>
set -eu

version="${1:?usage: remote-build.sh <qt-version>}"

# Written on the way out whatever happened, because the machine that started
# this build may not be the one that comes back for it: an hours-long build
# outlives ssh connections, laptops and a CI runner's six-hour ceiling. A driver
# polls for this file to tell a finished build from a running one.
finish() {
    echo "$?" > /root/build.status
}
trap finish EXIT

# Arch publishes no official ARM image, so aarch64 uses Arch Linux ARM through a
# community image. That is the same source ADR 0044 already builds on.
case "$(uname -m)" in
    x86_64)  image="docker.io/library/archlinux:base-devel" ;;
    aarch64) image="docker.io/lopsided/archlinux:devel" ;;
    *)       echo "unsupported architecture"; exit 1 ;;
esac

if ! command -v podman > /dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq podman > /dev/null
fi

mkdir -p /root/out /root/work


podman run --rm \
    -v /root/work:/root/work \
    -v /root/series:/root/series \
    -v /root/out:/root/out \
    "$image" sh /root/series/scripts/build-inside.sh "$version"

cd /root/out
# The package as well as the tarball. The tarball is what a later manual
# packaging run verifies against; the package is what travels to be signed.
sha256sum ./*.tar.zst ./*.pkg.tar.* > SHA256SUMS
cat SHA256SUMS
