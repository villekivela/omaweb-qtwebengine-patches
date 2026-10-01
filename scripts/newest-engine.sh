#!/bin/sh
# Print the newest released QtWebEngine version, the one `refresh.sh` should try.
# Usage: scripts/newest-engine.sh
#
# Up to 6.11 the engine was a module of Qt's release and carried its version. From Qt 6.12 it is
# released on its own and versioned after its Chromium, so Qt 6.12.0 has no engine and the newest
# Qt release is no longer the newest engine. Both are read here: the newest Qt release that ships
# an engine, and the newest separate engine release, and the higher of the two wins. 6.140 sorts
# above 6.11, so once separate releases exist they win. Omaweb's baseline check applies the same
# rule, in scripts/check_security_baseline.py.
set -eu

releases="${QT_RELEASES:-https://download.qt.io/official_releases}"

# A listing is read inside a command substitution, where a failure cannot stop the script, so it
# is recorded here and checked at the end. Only a 404 means "nothing there": the engine's own
# directory does not exist before its first release. A timeout or a server error is not evidence
# that no newer engine exists, and quietly answering an older one would test the wrong engine.
failed="$(mktemp)"
trap 'rm -f "$failed"' EXIT

newest_first() {
    sort -t. -k1,1nr -k2,2nr -k3,3nr
}

# The version directories a download.qt.io listing names, one per line, highest first.
listing() {
    page="$(mktemp)"
    code="$(curl -sSL -o "$page" -w '%{http_code}' "$1" 2> /dev/null)" || code=unreachable
    case "$code" in
        200) grep -o 'href="[0-9][0-9.]*/"' "$page" | grep -o '[0-9][0-9.]*[0-9]' | newest_first ;;
        404) ;;
        *) echo "cannot read $1 ($code)" >> "$failed" ;;
    esac
    rm -f "$page"
}

url_exists() {
    curl -fsIL -o /dev/null "$1" 2> /dev/null
}

# The newest Qt release whose submodules include the engine. Every Qt release from 6.12 has none.
from_qt() {
    for series in $(listing "$releases/qt/"); do
        for version in $(listing "$releases/qt/$series/"); do
            tarball="qtwebengine-everywhere-src-$version.tar.xz"
            if url_exists "$releases/qt/$series/$version/submodules/$tarball"; then
                echo "$version"
                return
            fi
        done
    done
}

# The newest separate release. Where its releases will sit is not known before the first one, so
# a directory per series and a flat directory per version are both read.
separate() {
    for entry in $(listing "$releases/qtwebengine/"); do
        case "$entry" in
            *.*.*) echo "$entry" ;;
            *) listing "$releases/qtwebengine/$entry/" ;;
        esac
    done
}

newest="$( { from_qt; separate; } | newest_first | head -n 1)"
if [ -s "$failed" ]; then
    cat "$failed" >&2
    exit 1
fi
[ -n "$newest" ] || { echo "no QtWebEngine release found under $releases" >&2; exit 1; }
echo "$newest"
