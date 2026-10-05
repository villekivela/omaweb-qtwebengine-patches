#!/bin/sh
# Fetches the profiles a clang build of the engine optimises from, and prints the path of Chrome's
# PGO profile for it, or nothing where Chrome publishes none.
#
# Usage: scripts/fetch-profiles.sh <tree> <cache-dir> [machine]
#
# Called by `refresh.sh` for OMAWEB_ENGINE_TOOLCHAIN=clang. machine is what `uname -m` prints and
# defaults to this one's. Downloads are kept in the cache directory, so a rebuild needs no network.
#
# Chrome's profile is taken for the Chromium the tree carries: its tag names the profile in
# chrome/build/linux.pgo.txt, and that names the object in Chrome's bucket. Chrome publishes one
# for x86_64 Linux and none for aarch64. V8's builtins are profiled per V8 version, and V8 applies
# its x64 profile on arm64 too, so both machines get those.
set -eu

tree="${1:?usage: fetch-profiles.sh <tree> <cache-dir> [machine]}"
cache="${2:?usage: fetch-profiles.sh <tree> <cache-dir> [machine]}"
machine="${3:-$(uname -m)}"
pgo_bucket="${OMAWEB_PGO_BUCKET:-https://storage.googleapis.com/chromium-optimization-profiles/pgo_profiles}"
v8_bucket="${OMAWEB_V8_PGO_BUCKET:-https://storage.googleapis.com/chromium-v8-builtins-pgo/by-version}"
tags="${OMAWEB_CHROMIUM_TAGS:-https://chromium.googlesource.com/chromium/src/+/refs/tags}"
chromium_tree="$tree/src/3rdparty/chromium"

# Fetches a file from Google Storage and holds it to the MD5 the bucket publishes, which catches a
# truncated or damaged download before hours are spent building against it. An object stored
# gzipped has the MD5 of those bytes, so it is asked for as stored and unpacked once it checks
# out; a client that does not accept gzip is sent other bytes.
fetch_checked() {
    headers="$(curl -fsSI -H 'Accept-Encoding: gzip' "$1" | tr -d '\r')"
    # A pipeline's status is tr's, so a request that failed shows as no headers.
    [ -n "$headers" ] || { echo "$1 did not answer" >&2; exit 1; }
    published="$(printf '%s\n' "$headers" | sed -n 's/^x-goog-hash: .*md5=//Ip')"
    encoding="$(printf '%s\n' "$headers" | sed -n 's/^x-goog-stored-content-encoding: //Ip')"
    curl -fsSL -H 'Accept-Encoding: gzip' -o "$2.download" "$1"
    fetched="$(python3 -c 'import base64, hashlib, sys
print(base64.b64encode(hashlib.md5(open(sys.argv[1], "rb").read()).digest()).decode())' \
        "$2.download")"
    if [ -z "$published" ] || [ "$fetched" != "$published" ]; then
        rm -f "$2.download"
        echo "$1 did not match its published MD5" >&2
        exit 1
    fi
    if [ "$encoding" = "gzip" ]; then
        gzip -dc "$2.download" > "$2"
        rm "$2.download"
    else
        mv "$2.download" "$2"
    fi
}

mkdir -p "$cache"

# V8's builtins profile, kept per V8 version, which Qt's copy of V8 leaves out. Dated as the tree
# is, or putting them back after `git clean` would rebuild everything that depends on them.
v8="$(awk '/define V8_MAJOR_VERSION/{a=$3} /define V8_MINOR_VERSION/{b=$3}
    /define V8_BUILD_NUMBER/{c=$3} /define V8_PATCH_LEVEL/{d=$3}
    END {print a"."b"."c"."d}' "$chromium_tree/v8/include/v8-version.h")"
builtins="$chromium_tree/v8/tools/builtins-pgo/profiles"
mkdir -p "$builtins" "$cache/v8-$v8"
for file in meta.json x64.profile x64-rl.profile; do
    if [ ! -f "$cache/v8-$v8/$file" ]; then
        fetch_checked "$v8_bucket/$v8/$file" "$cache/v8-$v8/$file"
    fi
    cp "$cache/v8-$v8/$file" "$builtins/$file"
    touch -r "$chromium_tree/chrome/VERSION" "$builtins/$file"
done

case "$machine" in
    x86_64 | amd64) ;;
    *)
        echo "PGO: V8 $v8's for its builtins. Chrome publishes no profile for $machine" >&2
        exit 0
        ;;
esac

# The profile's name is in the Chromium tree it was taken for. Qt's copy of Chromium leaves the
# file out, and then Chromium's own tag says.
chromium="$(awk -F= '/^MAJOR=/{a=$2} /^MINOR=/{b=$2} /^BUILD=/{c=$2} /^PATCH=/{d=$2}
    END {print a"."b"."c"."d}' "$chromium_tree/chrome/VERSION")"
named="$chromium_tree/chrome/build/linux.pgo.txt"
if [ -f "$named" ]; then
    name="$(cat "$named")"
else
    name="$(curl -fsSL "$tags/$chromium/chrome/build/linux.pgo.txt?format=TEXT" | base64 -d)"
    [ -n "$name" ] || { echo "Chromium $chromium's tag names no PGO profile" >&2; exit 1; }
    # Chromium's PGO configuration lists this file as an input of every object it profiles, so it
    # is put back where Chromium keeps it, dated as the tree is for the same reason as above.
    mkdir -p "$(dirname "$named")"
    printf '%s\n' "$name" > "$named"
    touch -r "$chromium_tree/chrome/VERSION" "$named"
fi

if [ ! -f "$cache/$name" ]; then
    fetch_checked "$pgo_bucket/$name" "$cache/$name"
fi
echo "PGO: Chrome's profile for Chromium $chromium, $name, and V8 $v8's for its builtins" >&2
echo "$cache/$name"
