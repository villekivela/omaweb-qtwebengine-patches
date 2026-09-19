#!/bin/sh
# Fetch a QtWebEngine release, apply the series, and configure it for building.
# Usage: scripts/refresh.sh 6.12.0 [work-dir]
# Leaves a tree ready for scripts/verify.sh. Reports what conflicted, if anything.
set -eu

version="${1:?usage: refresh.sh <version> [work-dir]}"
work="${2:-$HOME/Projects/villekivela/qtwebengine}"
series="$(cd "$(dirname "$0")/.." && pwd)/patches"
minor="$(echo "$version" | cut -d. -f1,2)"
tarball="qtwebengine-everywhere-src-$version.tar.xz"
tree="$work/qtwebengine-everywhere-src-$version"

mkdir -p "$work"
cd "$work"

if [ ! -f "$tarball" ]; then
    echo "fetching $tarball"
    for base in \
        "https://download.qt.io/official_releases/qt/$minor/$version/submodules" \
        "https://download.qt.io/development_releases/qt/$minor/$version/submodules"
    do
        if curl -fsSL -o "$tarball.part" "$base/$tarball"; then
            mv "$tarball.part" "$tarball"
            break
        fi
    done
    rm -f "$tarball.part"
    [ -f "$tarball" ] || { echo "no tarball for $version"; exit 1; }
fi

if [ ! -d "$tree" ]; then
    echo "unpacking"
    tar xJf "$tarball"
    cd "$tree"
    printf 'build/\n*.log\nbuild.sh\n__pycache__/\n' > .git/info/exclude 2>/dev/null || true
    git init -q
    printf 'build/\n*.log\nbuild.sh\n__pycache__/\n' > .git/info/exclude
    git add -A
    git commit -qm "qtwebengine $version source tarball"
    git tag "v$version-tarball"
else
    cd "$tree"
fi

echo "applying the series"
if git am "$series"/*.patch; then
    echo "SERIES APPLIED: $(ls "$series"/*.patch | wc -l | tr -d ' ') patches, no conflicts"
else
    echo
    echo "CONFLICT. The patch that stopped is above. Resolve it, then:"
    echo "  cd $tree && git am --continue"
    echo "When the series is in, export it back with:"
    echo "  git format-patch -o $series v$version-tarball..HEAD"
    exit 2
fi

cat > build.sh <<'BUILD'
#!/bin/sh
export PATH="$HOME/Projects/villekivela/qtwebengine/venv/bin:$PATH"
export PYTHONPATH="$HOME/Projects/villekivela/qtwebengine/venv/lib/python3.14/site-packages"
cd "$(dirname "$0")" || exit 1
cmake --build build --target "${1:-all}"
echo "exit $?"
BUILD
chmod +x build.sh

echo "configuring"
PATH="$work/venv/bin:$PATH"
export PATH
PYTHONPATH="$work/venv/lib/python3.14/site-packages"
export PYTHONPATH
cmake -S . -B build -G Ninja \
    -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt \
    -DCMAKE_BUILD_TYPE=Release \
    -DFEATURE_webengine_proprietary_codecs=ON \
    -DQT_NO_APPLE_SDK_AND_XCODE_CHECK=ON \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DNinja_EXECUTABLE="$(command -v ninja)" \
    -DQT_BUILD_EXAMPLES=OFF \
    -DQT_BUILD_TESTS=ON \
    -DQT_BUILD_TESTS_BATCHED=OFF \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    > configure.log 2>&1

sed -n '/Build QtWebEngine Modules/,/QtPdf Modules/p' build/config.summary

echo
echo "ready. Build it with:"
echo "  $tree/build.sh"
echo "then verify with:"
echo "  $(dirname "$0")/verify.sh $tree"
