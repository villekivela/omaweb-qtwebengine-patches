#!/bin/sh
# Fetch a QtWebEngine release, apply the series, and configure it for building.
# Usage: scripts/refresh.sh [--apply-only] 6.12.0 [work-dir]
# Leaves a tree ready for scripts/verify.sh. Reports what conflicted, if anything.
set -eu

apply_only=""
if [ "${1:-}" = "--apply-only" ]; then
    apply_only=yes
    shift
fi

version="${1:?usage: refresh.sh [--apply-only] <version> [work-dir]}"
work="${2:-$HOME/Projects/villekivela/qtwebengine}"
series="$(cd "$(dirname "$0")/.." && pwd)/patches"
system="$(uname -s)"
minor="$(echo "$version" | cut -d. -f1,2)"
tarball="qtwebengine-everywhere-src-$version.tar.xz"
tree="$work/qtwebengine-everywhere-src-$version"

mkdir -p "$work"
cd "$work"

if [ ! -f "$tarball" ]; then
    echo "fetching $tarball"
    # Up to 6.11 the engine was a module of Qt's release and carried its version. From Qt 6.12 it
    # is released on its own, versioned after its Chromium (6.140 is Chromium 140), and Qt 6.12.0
    # has no engine at all. Its prereleases sit in one flat directory; where its releases will sit
    # is not known before the first one, so both likely layouts are tried.
    for base in \
        "https://download.qt.io/official_releases/qt/$minor/$version/submodules" \
        "https://download.qt.io/development_releases/qt/$minor/$version/submodules" \
        "https://download.qt.io/official_releases/qtwebengine/$minor/$version" \
        "https://download.qt.io/official_releases/qtwebengine/$version" \
        "https://download.qt.io/development_releases/qtwebengine/$version"
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
    # A prerelease unpacks under the release's name: 6.140.0-rc into ...-src-6.140.0. It is moved
    # to the name it was asked for, so the release that follows gets a tree of its own rather than
    # being taken for an RC tree that already carries the series. It unpacks somewhere of its own
    # first, because the release's tree may already be in the work directory.
    rm -rf "$tree.unpack"
    mkdir "$tree.unpack"
    tar xJf "$tarball" -C "$tree.unpack"
    mv "$tree.unpack"/* "$tree"
    rmdir "$tree.unpack"
    cd "$tree"
    git init -q
    printf 'build/\n*.log\nbuild.sh\n__pycache__/\n' > .git/info/exclude
    git add -A
    git commit -qm "qtwebengine $version source tarball"
    git tag "v$version-tarball"
else
    cd "$tree"
fi

# A tree that already carries the series is left alone. Re-running after the
# gate failed, or after a build was interrupted, should pick the tree up rather
# than refuse it: the hours are in the tree, and `git am` on an applied series
# fails in a way that reads like a conflict when nothing has conflicted.
applied=0
if git rev-parse -q --verify "v$version-tarball" > /dev/null 2>&1; then
    applied="$(git rev-list --count "v$version-tarball"..HEAD)"
fi
total="$(ls "$series"/*.patch | wc -l | tr -d ' ')"
# A tree that carries the first N patches gets the rest, so a series that grew
# since the tree was built is applied from where it stopped. Anything left
# uncommitted in the tree is discarded first: it is a leftover of a build, not
# work, and `git am` refuses a dirty tree.
git am --abort > /dev/null 2>&1 || true
git reset -q --hard && git clean -qfd
# A patch changed in place since the tree was built counts the same as one
# that did not, so the count alone would keep the old one and build it again.
# Each patch file is applied to the tree its commit started from, in an index
# of its own, and the tree that makes is compared with the commit's. The tree
# is rewound to just before the first that differs. The build directory is
# untracked and stays, so only what the changed patches touch is rebuilt.
if [ "$applied" -gt 0 ]; then
    kept=0
    index="$(mktemp)"
    for commit in $(git rev-list --reverse "v$version-tarball"..HEAD); do
        file="$(ls "$series"/*.patch | sed -n "$((kept + 1))p")"
        [ -n "$file" ] || break
        GIT_INDEX_FILE="$index" git read-tree "$commit^" \
            && GIT_INDEX_FILE="$index" git apply --cached "$file" 2> /dev/null \
            && [ "$(GIT_INDEX_FILE="$index" git write-tree)" = "$(git rev-parse "$commit^{tree}")" ] \
            || break
        kept=$((kept + 1))
    done
    rm -f "$index"
    if [ "$kept" -lt "$applied" ]; then
        echo "SERIES CHANGED: patch $((kept + 1)) differs from the tree, applying again from there"
        if [ "$kept" -gt 0 ]; then
            git reset -q --hard "$(git rev-list --reverse "v$version-tarball"..HEAD | sed -n "${kept}p")"
        else
            git reset -q --hard "v$version-tarball"
        fi
        applied="$kept"
    fi
fi
if [ "$applied" -ge "$total" ]; then
    echo "SERIES ALREADY APPLIED: $applied commits on the tarball"
elif [ "$applied" -gt 0 ] && git am $(ls "$series"/*.patch | tail -n +"$((applied + 1))"); then
    echo "SERIES EXTENDED: $applied already applied, $((total - applied)) more, no conflicts"
elif [ "$applied" -eq 0 ] && git am "$series"/*.patch; then
    echo "SERIES APPLIED: $total patches, no conflicts"
else
    echo
    echo "CONFLICT. The patch that stopped is above. Resolve it, then:"
    echo "  cd $tree && git am --continue"
    echo "When the series is in, export it back with:"
    echo "  git format-patch -o $series v$version-tarball..HEAD"
    exit 2
fi

if [ -n "$apply_only" ]; then
    # Answering "does the series still apply" needs no Qt, no toolchain and no
    # hours. This is the check that runs the day Qt publishes.
    echo "apply-only: stopping before configure"
    exit 0
fi

cat > build.sh <<BUILD
#!/bin/sh
# Written by refresh.sh for this tree. The venv carries html5lib, which the
# Chromium build needs and which no platform ships by default.
if [ -d "$work/venv" ]; then
    PATH="$work/venv/bin:\$PATH"
    export PATH
fi
cd "\$(dirname "\$0")" || exit 1
cmake --build build --target "\${1:-all}"
echo "exit \$?"
BUILD
chmod +x build.sh

echo "configuring"
if [ -d "$work/venv" ]; then
    PATH="$work/venv/bin:$PATH"
    export PATH
fi

# The engine installs beside Omaweb rather than over the distribution's Qt, so
# every other Qt application on the machine keeps the engine it had.
prefix="${OMAWEB_ENGINE_PREFIX:-/usr/lib/omaweb}"

# OMAWEB_ENGINE_TOOLCHAIN=clang builds the engine the way Chrome is built:
# clang, linked by LLD with ThinLTO, and on x86_64 with Chrome's own PGO profile
# for this Chromium. Qt turns ThinLTO on only when Qt itself was built for LLD,
# and PGO never, so a patch outside the series opens both. The same patch lets
# V8 apply its builtins profile where it fits, since Qt's V8 is not built quite
# as Chrome's. It is opt-in while it is measured against the GCC build that
# ships (villekivela/omaweb#356).
toolchain="${OMAWEB_ENGINE_TOOLCHAIN:-}"
profile=""

# Fetches a file from Google Storage and holds it to the MD5 the bucket
# publishes, which catches a truncated or damaged download before hours are
# spent building against it. An object stored gzipped has the MD5 of those
# bytes, so it is asked for as stored and unpacked once it checks out; a client
# that does not accept gzip is sent other bytes.
fetch_checked() {
    headers="$(curl -fsSI -H 'Accept-Encoding: gzip' "$1" | tr -d '\r')"
    published="$(printf '%s\n' "$headers" | sed -n 's/^x-goog-hash: md5=//Ip')"
    encoding="$(printf '%s\n' "$headers" | sed -n 's/^x-goog-stored-content-encoding: //Ip')"
    curl -fsSL -H 'Accept-Encoding: gzip' -o "$2.download" "$1"
    fetched="$(python3 -c 'import base64, hashlib, sys
print(base64.b64encode(hashlib.md5(open(sys.argv[1], "rb").read()).digest()).decode())' \
        "$2.download")"
    if [ -z "$published" ] || [ "$fetched" != "$published" ]; then
        echo "$1 did not match its published MD5"
        exit 1
    fi
    if [ "$encoding" = "gzip" ]; then
        gzip -dc "$2.download" > "$2"
        rm "$2.download"
    else
        mv "$2.download" "$2"
    fi
}
if [ "$toolchain" = "clang" ]; then
    [ "$system" = "Linux" ] || { echo "the clang toolchain is for Linux builds"; exit 1; }
    git apply "$series/../experiments/optimised-toolchain.patch"
    echo "TOOLCHAIN: clang, LLD and ThinLTO"
    if [ "$(uname -m)" = "x86_64" ]; then
        # The profile's name is in the Chromium tree it was taken for. Qt's copy
        # of Chromium may leave the file out, and then Chromium's own tag says.
        chromium="$(awk -F= '/^MAJOR=/{a=$2} /^MINOR=/{b=$2} /^BUILD=/{c=$2} /^PATCH=/{d=$2}
            END {print a"."b"."c"."d}' src/3rdparty/chromium/chrome/VERSION)"
        named=src/3rdparty/chromium/chrome/build/linux.pgo.txt
        if [ -f "$named" ]; then
            name="$(cat "$named")"
        else
            name="$(curl -fsSL "https://chromium.googlesource.com/chromium/src/+/refs/tags/$chromium/chrome/build/linux.pgo.txt?format=TEXT" | base64 -d)"
            # Chromium's PGO configuration lists this file as an input of every
            # object it profiles, so it is put back where Chromium keeps it. It
            # is dated as the tree is, or recreating it after `git clean` would
            # rebuild everything.
            mkdir -p "$(dirname "$named")"
            printf '%s\n' "$name" > "$named"
            touch -r src/3rdparty/chromium/chrome/VERSION "$named"
        fi
        profile="$work/pgo/$name"
        if [ ! -f "$profile" ]; then
            mkdir -p "$work/pgo"
            fetch_checked \
                "https://storage.googleapis.com/chromium-optimization-profiles/pgo_profiles/$name" \
                "$profile"
        fi
        # V8 optimises its builtins from a profile of its own, kept per V8
        # version, which Qt's copy of V8 leaves out as well. They are dated as
        # the tree is, for the same reason as the name above.
        v8="$(awk '/define V8_MAJOR_VERSION/{a=$3} /define V8_MINOR_VERSION/{b=$3}
            /define V8_BUILD_NUMBER/{c=$3} /define V8_PATCH_LEVEL/{d=$3}
            END {print a"."b"."c"."d}' src/3rdparty/chromium/v8/include/v8-version.h)"
        builtins=src/3rdparty/chromium/v8/tools/builtins-pgo/profiles
        for file in meta.json x64.profile x64-rl.profile; do
            if [ ! -f "$work/pgo/v8-$v8/$file" ]; then
                mkdir -p "$work/pgo/v8-$v8"
                fetch_checked \
                    "https://storage.googleapis.com/chromium-v8-builtins-pgo/by-version/$v8/$file" \
                    "$work/pgo/v8-$v8/$file"
            fi
            cp "$work/pgo/v8-$v8/$file" "$builtins/$file"
            touch -r src/3rdparty/chromium/chrome/VERSION "$builtins/$file"
        done
        echo "PGO: Chrome's profile for Chromium $chromium, $name, and V8 $v8's for its builtins"
    else
        echo "PGO: none, Chrome publishes no Linux profile for $(uname -m)"
    fi
fi

set -- -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DFEATURE_webengine_proprietary_codecs=ON \
    -DNinja_EXECUTABLE="$(command -v ninja)" \
    -DQT_BUILD_EXAMPLES=OFF \
    -DQT_BUILD_TESTS=ON \
    -DQT_BUILD_TESTS_BATCHED=OFF

if command -v ccache > /dev/null 2>&1; then
    set -- "$@" -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_C_COMPILER_LAUNCHER=ccache
fi

if [ "$toolchain" = "clang" ]; then
    # CMake links the engine library itself, from what GN compiled, so it is
    # told to use LLD as well. ThinLTO archives hold bitcode, which only LLVM's
    # archiver indexes.
    set -- "$@" -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_AR="$(command -v llvm-ar)" -DCMAKE_NM="$(command -v llvm-nm)" \
        -DCMAKE_RANLIB="$(command -v llvm-ranlib)" \
        -DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=lld -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld \
        -DCMAKE_MODULE_LINKER_FLAGS=-fuse-ld=lld -DOMAWEB_USE_LLD=ON
    if [ -n "$profile" ]; then
        set -- "$@" -DOMAWEB_PGO_PROFILE="$profile"
    fi
fi

if [ "$system" = "Darwin" ]; then
    # A development build. It produces macOS frameworks, which cannot ship.
    set -- "$@" -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt \
        -DQT_NO_APPLE_SDK_AND_XCODE_CHECK=ON \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
else
    set -- "$@" -DCMAKE_INSTALL_PREFIX="$prefix"
fi

# From 6.140 the engine states the oldest Qt it builds against rather than requiring its own
# version, so a system Qt that is too old is refused here, by CMake, and the reason is in the log.
if ! cmake "$@" > configure.log 2>&1; then
    tail -n 30 configure.log
    echo "configure failed; the whole log is $tree/configure.log"
    exit 1
fi

sed -n '/Build QtWebEngine Modules/,/QtPdf Modules/p' build/config.summary

echo
echo "ready. Build it with:"
echo "  $tree/build.sh"
echo "then verify with:"
echo "  $(dirname "$0")/verify.sh $tree"
