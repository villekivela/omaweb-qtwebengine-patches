#!/bin/sh
# Turn an engine tarball into a signed pacman package, on the machine you are
# sitting at.
#
# Usage: scripts/package-locally.sh <qt-version> [tarball]
#
# The build hands back an unsigned tarball, from a rented machine or from
# scripts/build-locally.sh. This is the other half: makepkg in the same
# container the engine was built in, then a detached signature made here, where
# the key is. The signature is never made in the container, so the key never
# leaves this machine (ADR 0049).
#
# What comes out is out/<name>.pkg.tar.* and its .sig, which is what
# scripts/publish_repo.sh in the Omaweb repository takes.
set -eu

version="${1:?usage: package-locally.sh <qt-version> [tarball]}"
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/out"

case "$(uname -m)" in
    x86_64|amd64)
        arch=x86_64
        platform=linux/amd64
        image="docker.io/library/archlinux:base-devel"
        ;;
    aarch64|arm64)
        arch=aarch64
        platform=linux/arm64
        image="docker.io/lopsided/archlinux:devel"
        ;;
    *)
        echo "unsupported architecture"
        exit 1
        ;;
esac

tarball="${2:-$out/omaweb-qtwebengine-$version-$arch.tar.zst}"
[ -f "$tarball" ] || { echo "no tarball at $tarball"; exit 1; }

command -v docker > /dev/null 2>&1 || { echo "install docker first"; exit 1; }
command -v gpg > /dev/null 2>&1 || { echo "install gnupg first"; exit 1; }

: "${OMAWEB_REPO_KEY:?export OMAWEB_REPO_KEY with the signing key fingerprint}"
gpg --list-secret-keys "$OMAWEB_REPO_KEY" > /dev/null \
    || { echo "no secret key for $OMAWEB_REPO_KEY in this keyring"; exit 1; }

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
pacman -Syu --noconfirm --needed --overwrite "*" base-devel > /dev/null 2>&1
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

echo "==> Signing $name on this machine"
gpg --detach-sign --no-armor --yes --local-user "$OMAWEB_REPO_KEY" \
    --output "$out/$name.sig" "$out/$name"
gpg --verify "$out/$name.sig" "$out/$name"

cat <<NEXT

Signed: $out/$name

Publish it from a checkout of the Omaweb repository, into a clone of its
gh-pages branch:

    scripts/publish_repo.sh --package $out/$name \\
        --repo-dir <gh-pages clone> --key $OMAWEB_REPO_KEY
NEXT
