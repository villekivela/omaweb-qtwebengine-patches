#!/bin/sh
# Build the patched engine on the machine you are sitting at, in a container of
# the distribution it ships to.
#
# Usage: scripts/build-locally.sh <qt-version>
#
# For when no rented machine will do: Hetzner has no Arm capacity at all some
# days, and an Apple Silicon Mac is an arm64 machine that is already paid for.
# The container is the same one the rented machine runs, and so is the build, so
# what comes out is the same artifact from the same recipe. It takes hours
# either way.
#
# The work space is a container volume rather than a folder on the host: a build
# this size on a shared filesystem spends its day waiting for the filesystem.
set -eu

version="${1:?usage: build-locally.sh <qt-version>}"
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/out"

command -v docker > /dev/null 2>&1 || { echo "install docker first"; exit 1; }

case "$(uname -m)" in
    x86_64|amd64)  image="docker.io/library/archlinux:base-devel" ;;
    aarch64|arm64) image="docker.io/lopsided/archlinux:devel" ;;
    *)             echo "unsupported architecture"; exit 1 ;;
esac

mkdir -p "$out"
docker volume create omaweb-engine-work > /dev/null

echo "building $version in $image, which takes hours"
docker run --rm \
    --platform "linux/$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')" \
    -v omaweb-engine-work:/root/work \
    -v "$here:/root/series:ro" \
    -v "$out:/root/out" \
    "$image" sh /root/series/scripts/build-inside.sh "$version"

cd "$out"
sha256sum ./*.tar.zst > SHA256SUMS
cat SHA256SUMS
echo
echo "unsigned. Package and sign where the key is."
echo "the work space is kept: docker volume rm omaweb-engine-work"
