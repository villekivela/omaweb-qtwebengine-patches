#!/bin/sh
# The build itself, run inside a container of the distribution the engine ships
# to. Called on a rented machine by `remote-build.sh` and on a machine you
# already have by `build-locally.sh`: one recipe, so an engine built here and an
# engine built there are the same engine.
#
# Usage: build-inside.sh <qt-version>, with the series at /root/series, work
# space at /root/work and the artifact left in /root/out.
set -eu
version="${1:?usage: build-inside.sh <qt-version>}"

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

# The series is applied with `git am`, which refuses to record a commit without
# somebody to record it as. The container is fresh every time, so it has nobody
# until it is told.
git config --global user.email "builder@omaweb.invalid"
git config --global user.name "Engine build"
git config --global --add safe.directory '*'

cd /root/work
# Kept, because what the series did is half of what maintaining it costs and
# `release-row.sh` reads it out of here rather than anyone remembering. Through
# `tee` so a run can still be watched, and the status comes back out of a file
# because a pipeline's status is the last command's and `/bin/sh` has no
# pipefail.
( OMAWEB_ENGINE_PREFIX=/usr/lib/omaweb sh /root/series/scripts/refresh.sh \
    "$version" /root/work; echo "$?" > /root/out/apply.status ) \
    | tee /root/out/apply.txt
applied="$(cat /root/out/apply.status)"
rm -f /root/out/apply.status
[ "$applied" -eq 0 ] || exit "$applied"
tree="/root/work/qtwebengine-everywhere-src-$version"

# Comfortable for compiling and not for linking at this much memory per core,
# so the link steps run fewer at a time.
cd "$tree"
cmake --build build --parallel "$(nproc)" -- -j "$(nproc)" -l "$(nproc)"

sh /root/series/scripts/verify.sh "$tree" | tee /root/out/verify.txt
# Every case passed and at least the ones this series adds ran. The count is not written down:
# a gate that names a number refuses the day the suite grows, which is how a green run was
# refused once already. The gate runs more than one test program, and each reports its own
# totals, so every one of them has to read none failed and the extension tests' must be there.
if [ "$(grep -cE "^Totals: " /root/out/verify.txt)" -lt 2 ] \
    || grep -qE "^Totals: [0-9]+ passed, [1-9]" /root/out/verify.txt; then
    echo "the gate did not pass, so nothing is packaged"
    exit 2
fi

DESTDIR=/root/work/staging cmake --install "$tree/build" > /dev/null
cd /root/work/staging
tarball="/root/out/omaweb-qtwebengine-$version-$(uname -m).tar.zst"
tar caf "$tarball" .

# And the package, here rather than on somebody's laptop, because this container
# is already Arch and already the right architecture. It is left unsigned: the
# signing key is not on a build machine (ADR 0049), and the workflow that
# publishes holds it.
pacman -S --noconfirm --needed pacman-contrib > /dev/null 2>&1 || true
# Not under /root: that directory is 0700, so the packaging user cannot
# traverse into it however the stage directory itself is owned, and makepkg
# dies with "Permission denied" after the engine has already been built.
stage=/tmp/omaweb-package
rm -rf "$stage"
mkdir -p "$stage"
cp /root/series/packaging/PKGBUILD /root/series/packaging/MODIFICATIONS.md \
    /root/series/packaging/LGPL-3.0-only.txt \
    /root/series/packaging/chromium-LICENSE.txt "$stage/"
cp "$tarball" "$stage/"

# makepkg refuses to run as root, and a container has nobody else until it is
# told. `-d` because this copies files into a package rather than compiling
# against anything, and the engine's dependencies are the running system's Qt.
id packager > /dev/null 2>&1 || useradd -m packager
chown -R packager "$stage"
su packager -c "cd $stage && makepkg -f -d --noconfirm"

package="$(find "$stage" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' -print)"
if [ -z "$package" ] || [ "$(printf '%s\n' "$package" | wc -l)" -ne 1 ]; then
    echo "packaging produced no single package:"
    printf '%s\n' "$package"
    exit 3
fi
cp "$package" /root/out/
echo "packaged $(basename "$package")"

# What was built, in the two numbers Omaweb's security baseline records. Read
# out of the tree rather than restated, because a baseline that disagrees with
# the engine it names marks every reader's build an unsupported preview.
#
# The third field the baseline carries, the Chromium release whose security
# fixes this engine includes, is not in the tree: Qt says it in prose in the
# release notes. So it is not guessed here, and whoever reads those notes fills
# it in.
chromium="$(awk -F= '/^MAJOR=/{a=$2} /^MINOR=/{b=$2} /^BUILD=/{c=$2} /^PATCH=/{d=$2}
    END {print a"."b"."c"."d}' "$tree/src/3rdparty/chromium/chrome/VERSION")"
printf '{\n  "qtwebengine": "%s",\n  "chromium": "%s"\n}\n' "$version" "$chromium" \
    > /root/out/engine.json
cat /root/out/engine.json
