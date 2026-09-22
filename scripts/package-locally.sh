#!/bin/sh
# Turn an engine tarball into a pacman package, on the machine you are sitting
# at.
#
# Usage: scripts/package-locally.sh <qt-version> [tarball]
#
# The build hands back an unsigned tarball, from a rented machine or from
# scripts/build-locally.sh. This is the other half: makepkg in the same
# container the engine was built in. The PKGBUILD and the notices are here, so
# this is the only place that knows how to package the engine.
#
# Signing is not here. Set OMAWEB_REPO_KEY and this makes the detached
# signature too, on the host rather than in the container, so the key never
# enters one. Leave it unset and what comes out is an unsigned package for the
# `Publish the engine` workflow in the Omaweb repository to sign, which is
# where the signing key already is.
set -eu

version="${1:?usage: package-locally.sh <qt-version> [tarball]}"
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/out"

# The architecture of the package, which is the architecture of the tarball
# rather than of this machine. A build comes back from a machine rented for it,
# so the two are routinely different: an x86_64 engine is packaged on whatever
# is to hand. Set OMAWEB_PACKAGE_ARCH to say which, and the container runs that
# architecture, emulated if it has to be. makepkg here copies files into a
# package rather than compiling, so emulation costs minutes and not hours.
arch="${OMAWEB_PACKAGE_ARCH:-}"
if [ -z "$arch" ]; then
    case "$(uname -m)" in
        x86_64|amd64)  arch=x86_64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *)             echo "unsupported architecture"; exit 1 ;;
    esac
fi

case "$arch" in
    x86_64)
        platform=linux/amd64
        image="docker.io/library/archlinux:base-devel"
        ;;
    aarch64)
        platform=linux/arm64
        image="docker.io/lopsided/archlinux:devel"
        ;;
    *)
        echo "OMAWEB_PACKAGE_ARCH must be x86_64 or aarch64, not $arch"
        exit 1
        ;;
esac

tarball="${2:-$out/omaweb-qtwebengine-$version-$arch.tar.zst}"
[ -f "$tarball" ] || { echo "no tarball at $tarball"; exit 1; }

# The PKGBUILD carries no hash for the tarball, because a hash of one build
# refuses every later build of the same version. This is the check that
# replaces it: SHA256SUMS is written beside the tarball by the build that made
# it, so a tarball that travelled and arrived damaged stops here.
sums="$(dirname "$tarball")/SHA256SUMS"
if [ -f "$sums" ]; then
    echo "==> Checking $(basename "$tarball") against SHA256SUMS"
    ( cd "$(dirname "$tarball")" \
        && grep -F "$(basename "$tarball")" SHA256SUMS | shasum -a 256 -c - ) \
        || { echo "the tarball does not match SHA256SUMS"; exit 1; }
else
    echo "==> No SHA256SUMS beside the tarball, so nothing checks it"
fi

command -v docker > /dev/null 2>&1 || { echo "install docker first"; exit 1; }

# Checked before the build rather than after it, so a keyring that cannot sign
# is not discovered at the end of a package.
key="${OMAWEB_REPO_KEY:-}"
if [ -n "$key" ]; then
    command -v gpg > /dev/null 2>&1 || { echo "install gnupg first"; exit 1; }
    gpg --list-secret-keys "$key" > /dev/null \
        || { echo "no secret key for $key in this keyring"; exit 1; }
fi

# A directory holding only what makepkg reads, so the container sees the
# tarball, the PKGBUILD and the notices and nothing else of this repository.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp "$here/packaging/PKGBUILD" "$here/packaging/MODIFICATIONS.md" \
    "$here/packaging/LGPL-3.0-only.txt" "$here/packaging/chromium-LICENSE.txt" "$stage/"
cp "$tarball" "$stage/"

# `-d`, because the engine's dependencies are the Qt of the machine it installs
# on, and this container has no reason to fetch them to copy files.
cat > "$stage/inside.sh" <<'INSIDE'
set -e

# The image is named for base-devel and already carries makepkg, so this is an
# update rather than an install and a failure is not fatal. It is allowed to
# fail loudly: sending it to /dev/null turned pacman refusing to run into a
# script that stopped with no output at all.
#
# `--disable-sandbox` because pacman 7 restricts its download helper with
# seccomp, which it cannot do inside an emulated container: "error restricting
# syscalls via seccomp: 22". An x86_64 package built on an Arm machine is
# exactly that case.
pacman -Syu --noconfirm --needed --disable-sandbox --overwrite "*" base-devel || \
    echo "the package database could not be updated, carrying on with the image as it is"

command -v makepkg > /dev/null 2>&1 || {
    echo "no makepkg in this image, so nothing can be packaged"
    exit 1
}

id builder > /dev/null 2>&1 || useradd -m builder
chown -R builder /pkg
su builder -c "cd /pkg && makepkg -f -d --noconfirm"
INSIDE

echo "==> Building the package in $image"
docker run --rm --platform "$platform" -v "$stage":/pkg "$image" sh /pkg/inside.sh

package="$(find "$stage" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' -print)"
[ -n "$package" ] && [ "$(printf '%s\n' "$package" | wc -l)" -eq 1 ] || {
    echo "expected one package, found:"; printf '%s\n' "$package"; exit 1
}

name="$(basename "$package")"
mkdir -p "$out"
cp -f "$package" "$out/$name"

if [ -z "$key" ]; then
    cat <<NEXT

Built, unsigned: $out/$name

Signing happens in the Omaweb repository, which holds the key. Attach this to a
release there and run the workflow:

    gh release create engine-$version --repo villekivela/omaweb \\
        --title "Engine $version" --notes "QtWebEngine $version with the series" \\
        $out/$name
    gh workflow run "Publish the engine" --repo villekivela/omaweb \\
        -f tag=engine-$version

A release that already exists takes "gh release upload" instead, which is how
the second architecture joins the first.
NEXT
    exit 0
fi

echo "==> Signing $name on this machine"
gpg --detach-sign --no-armor --yes --local-user "$key" \
    --output "$out/$name.sig" "$out/$name"
gpg --verify "$out/$name.sig" "$out/$name"

cat <<NEXT

Signed: $out/$name

Publish it from a checkout of the Omaweb repository, into a clone of its
gh-pages branch:

    scripts/publish_repo.sh --package $out/$name \\
        --repo-dir <gh-pages clone> --key $key
NEXT
