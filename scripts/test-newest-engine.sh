#!/bin/sh
# Runs newest-engine.sh against stand-ins for download.qt.io, served locally, and checks the
# version it picks for each layout the engine has been or may be released in.
#
# Usage: scripts/test-newest-engine.sh
#
# Nothing here reaches Qt. The real server holds only the layout of today, and the case that
# matters most, the first separate engine release, does not exist on it yet.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
server=""
trap '[ -z "$server" ] || kill "$server"; rm -rf "$work"' EXIT

port="$(python3 -c '
import socket
s = socket.socket()
s.bind(("", 0))
print(s.getsockname()[1])')"
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$work" > /dev/null 2>&1 &
server=$!
until curl -fs -o /dev/null "http://127.0.0.1:$port/"; do sleep 0.1; done

failed=0

# A Qt release that ships the engine as a module.
qt() {
    mkdir -p "$1/qt/${2%.*}/$2/submodules"
    touch "$1/qt/${2%.*}/$2/submodules/qtwebengine-everywhere-src-$2.tar.xz"
}

# A Qt release without one, as every release from 6.12 is.
qt_without() {
    mkdir -p "$1/qt/${2%.*}/$2/submodules"
    touch "$1/qt/${2%.*}/$2/submodules/qtbase-everywhere-src-$2.tar.xz"
}

check() {
    name="$1" expected="$2" releases="${3:-http://127.0.0.1:$port/$1}"
    actual="$(QT_RELEASES="$releases" sh "$here/newest-engine.sh" 2> /dev/null || echo "failed")"
    if [ "$actual" = "$expected" ]; then
        echo "ok   $name: $actual"
    else
        echo "FAIL $name: expected $expected, got $actual"
        failed=1
    fi
}

# Before the split: the newest Qt release, compared as numbers and not as text.
qt "$work/before" 6.9.3
qt "$work/before" 6.11.2
qt "$work/before" 6.11.10
check before 6.11.10

# Qt 6.12.0 is out and the engine is not. This is the day #484 was opened on, when the newest Qt
# was taken for the newest engine and its tarball did not exist.
qt "$work/gap" 6.11.2
qt_without "$work/gap" 6.12.0
check gap 6.11.2

# The engine released on its own, in a directory per series.
qt "$work/series" 6.11.2
qt_without "$work/series" 6.12.0
mkdir -p "$work/series/qtwebengine/6.140/6.140.0" "$work/series/qtwebengine/6.140/6.140.1"
check series 6.140.1

# The same, in a flat directory per version, as its prereleases are published. A prerelease is
# not a release and is never picked.
qt "$work/flat" 6.11.2
mkdir -p "$work/flat/qtwebengine/6.140.0" "$work/flat/qtwebengine/6.146.0-rc"
check flat 6.140.0

# Nothing at all is a failure, not an empty version handed to refresh.sh.
mkdir -p "$work/empty"
check empty failed

# A server that does not answer is a failure too. Taking it for "no separate release" would
# answer 6.11 on the day 6.140 is out, and the daily check would test the wrong engine.
check unreachable failed "http://127.0.0.1:1"

exit "$failed"
