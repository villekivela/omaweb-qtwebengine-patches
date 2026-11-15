#!/bin/sh
# Runs refresh.sh --apply-only against stand-ins for download.qt.io, served locally, and checks
# that it finds the tarball in each layout an engine has been released in.
#
# Usage: scripts/test-refresh-fetch.sh
#
# Nothing here reaches Qt. refresh.sh runs from a copy beside a series of one patch, so applying
# it takes seconds and the case shows whether the tarball was found.
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
mkdir "$work/site"
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$work/site" > /dev/null 2>&1 &
server=$!
until curl -fs -o /dev/null "http://127.0.0.1:$port/"; do sleep 0.1; done

mkdir -p "$work/repo/scripts" "$work/repo/patches"
cp "$here/refresh.sh" "$work/repo/scripts/"
cat > "$work/repo/patches/0001-add-a-file.patch" << 'PATCH'
From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001
From: Test <test@omaweb.invalid>
Date: Sat, 14 Nov 2026 00:00:00 +0000
Subject: [PATCH] add a file

---
 added.txt | 1 +
 1 file changed, 1 insertion(+)
 create mode 100644 added.txt

diff --git a/added.txt b/added.txt
new file mode 100644
index 0000000..ce01362
--- /dev/null
+++ b/added.txt
@@ -0,0 +1 @@
+hello
PATCH

GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@omaweb.invalid
GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@omaweb.invalid
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

# A tarball of version $2 at path $1 of the stand-in server. A prerelease unpacks under the
# release's name, as Qt's do.
tarball() {
    tree="qtwebengine-everywhere-src-${2%-*}"
    mkdir -p "$work/src/$tree" "$work/site/$1"
    echo "$2" > "$work/src/$tree/README"
    tar cJf "$work/site/$1/qtwebengine-everywhere-src-$2.tar.xz" -C "$work/src" "$tree"
    rm -rf "$work/src"
}

failed=0

check() {
    name="$1" version="$2" expected="$3"
    output="$(QT_DOWNLOADS="http://127.0.0.1:$port" \
        sh "$work/repo/scripts/refresh.sh" --apply-only "$version" "$work/engines/$name" 2>&1 \
        || true)"
    if echo "$output" | grep -q "$expected"; then
        echo "ok   $name: $expected"
    else
        echo "FAIL $name: expected \"$expected\", got:"
        echo "$output" | sed 's/^/     /'
        failed=1
    fi
}

# Up to 6.11 the engine is a module of Qt's release.
tarball official_releases/qt/6.11/6.11.3/submodules 6.11.3
check module 6.11.3 "SERIES APPLIED: 1 patches"

# From 6.140 it is released on its own, in a directory per series with its source under src/.
# 6.140.0 was the first, and refresh.sh guessed the layout without src/ and found nothing.
tarball official_releases/qtwebengine/6.140/6.140.0/src 6.140.0
check release 6.140.0 "SERIES APPLIED: 1 patches"

# Its prereleases sit in one flat directory.
tarball development_releases/qtwebengine/6.146.0-rc 6.146.0-rc
check prerelease 6.146.0-rc "SERIES APPLIED: 1 patches"

# A version nobody published stops before anything is unpacked.
check missing 6.152.0 "no tarball for 6.152.0"

exit "$failed"
