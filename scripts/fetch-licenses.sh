#!/bin/sh
# Fetch the licence texts the engine package installs, from the trees it is
# built from.
#
# Usage: scripts/fetch-licenses.sh <qt-version> <chromium-branch>
#
# Retyping a licence is how a notice stops matching the code it covers, so both
# files come from the repositories the build uses: the LGPL text from the
# qtwebengine tag, Chromium's notice from the Qt fork of Chromium that tag
# builds. Run this when the base version changes and commit what it writes.
set -eu

version="${1:?usage: fetch-licenses.sh <qt-version> <chromium-branch>}"
branch="${2:?usage: fetch-licenses.sh <qt-version> <chromium-branch>}"
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/packaging"

fetch() {
    echo "fetching $2"
    curl -fsSL -o "$out/$2.part" "$1"
    mv "$out/$2.part" "$out/$2"
}

fetch "https://code.qt.io/cgit/qt/qtwebengine.git/plain/LICENSES/LGPL-3.0-only.txt?h=v$version" \
    LGPL-3.0-only.txt
# Comment prefixes and all. This is the file in the tree, and a notice that has
# been tidied is no longer the notice.
fetch "https://code.qt.io/cgit/qt/qtwebengine-chromium.git/plain/chromium/LICENSE?h=$branch" \
    chromium-LICENSE.txt

echo "wrote $out/LGPL-3.0-only.txt and $out/chromium-LICENSE.txt"
echo "update sha256sums in $out/PKGBUILD"
