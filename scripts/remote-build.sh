#!/bin/sh
# Runs on the rented machine. Builds the patched engine inside an Arch
# container, so the binaries match the distribution they ship to rather than
# whatever the rented image happens to be.
#
# Usage: remote-build.sh <qt-version>
set -eu

version="${1:?usage: remote-build.sh <qt-version>}"

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

cat > /root/work/inside.sh <<'INSIDE'
#!/bin/sh
set -eu
version="$1"

pacman -Syu --noconfirm --needed \
    base-devel git cmake ninja python python-html5lib nodejs npm gperf \
    qt6-base qt6-declarative qt6-tools qt6-websockets qt6-webchannel \
    qt6-positioning qt6-svg libxkbcommon libxkbcommon-x11 libxcomposite \
    libxcursor libxrandr libxtst libxdamage nss libdrm mesa pipewire \
    libxslt libvpx re2 snappy minizip jsoncpp ffmpeg opus > /dev/null

# QtWebEngine builds against the Qt it belongs to. A mismatch fails late and
# confusingly, so fail early and clearly instead.
system_qt="$(qmake6 -query QT_VERSION)"
if [ "$system_qt" != "$version" ]; then
    echo "system Qt is $system_qt but the engine is $version."
    echo "Wait for the distribution to catch up, or build the rest of Qt too."
    exit 1
fi

cd /root/work
OMAWEB_ENGINE_PREFIX=/usr/lib/omaweb sh /root/series/scripts/refresh.sh "$version" /root/work
tree="/root/work/qtwebengine-everywhere-src-$version"

# 32 GB across 16 cores is comfortable for compiling and not for linking, so the
# link steps run fewer at a time.
cd "$tree"
cmake --build build --parallel "$(nproc)" -- -j "$(nproc)" -l "$(nproc)"

sh /root/series/scripts/verify.sh "$tree" | tee /root/out/verify.txt
if ! grep -qE "2[0-9] passed, 0 failed" /root/out/verify.txt; then
    echo "the gate did not pass, so nothing is packaged"
    exit 2
fi

DESTDIR=/root/work/staging cmake --install "$tree/build" > /dev/null
cd /root/work/staging
tar caf "/root/out/omaweb-qtwebengine-$version-$(uname -m).tar.zst" .
INSIDE
chmod +x /root/work/inside.sh

podman run --rm \
    -v /root/work:/root/work \
    -v /root/series:/root/series \
    -v /root/out:/root/out \
    "$image" sh /root/work/inside.sh "$version"

cd /root/out
sha256sum ./*.tar.zst > SHA256SUMS
cat SHA256SUMS
