#!/bin/sh
# Runs fetch-profiles.sh against stand-ins for Google Storage and Chromium's source, served
# locally, and checks the profile it picks for each tree and what it does with a bad download.
#
# Usage: scripts/test-fetch-profiles.sh
#
# Nothing here reaches Google. The stand-in publishes an MD5 the way the real bucket does, in
# x-goog-hash, and stores an object gzipped the way the real bucket stores Chrome's profiles.
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

# A file is served with the MD5 of its bytes. A file beside it named .gzstored is served instead,
# as an object stored gzipped. A file beside it named .badmd5 makes the published MD5 wrong.
# ?format=TEXT answers in base64, as Gitiles does.
cat > "$work/serve.py" << 'SERVE'
import base64, hashlib, http.server, os, sys

root = sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):
    def answer(self, body):
        path, _, query = self.path.partition("?")
        file = os.path.join(root, path.lstrip("/"))
        headers = {}
        if os.path.exists(file + ".gzstored"):
            data = open(file + ".gzstored", "rb").read()
            headers["x-goog-stored-content-encoding"] = "gzip"
            headers["Content-Encoding"] = "gzip"
        elif os.path.isfile(file):
            data = open(file, "rb").read()
        else:
            self.send_response(404)
            self.end_headers()
            return
        if query == "format=TEXT":
            data = base64.b64encode(data)
        md5 = hashlib.md5(data).digest()
        if os.path.exists(file + ".badmd5"):
            md5 = hashlib.md5(b"something else").digest()
        headers["x-goog-hash"] = "crc32c=AAAAAA==, md5=" + base64.b64encode(md5).decode()
        self.send_response(200)
        for name, value in headers.items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if body:
            self.wfile.write(data)

    def do_GET(self):
        self.answer(True)

    def do_HEAD(self):
        self.answer(False)

    def log_message(self, *args):
        pass

http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
SERVE
mkdir -p "$work/served"
python3 "$work/serve.py" "$port" "$work/served" &
server=$!
# Any answer will do, and the root is a 404. Ten seconds, so a server that never came up fails
# the test rather than hanging it.
tries=0
until curl -s -o /dev/null "http://127.0.0.1:$port/"; do
    tries=$((tries + 1))
    [ "$tries" -lt 100 ] || { echo "FAIL the stand-in server did not start"; exit 1; }
    sleep 0.1
done
base="http://127.0.0.1:$port"

export OMAWEB_PGO_BUCKET="$base/pgo_profiles"
export OMAWEB_V8_PGO_BUCKET="$base/by-version"
export OMAWEB_CHROMIUM_TAGS="$base/tags"

# What the stand-in serves: one Chrome profile, the name Chromium's tag gives for it, and V8's
# builtins profiles for one V8.
tag="$work/served/tags/140.0.7339.225/chrome/build"
mkdir -p "$work/served/pgo_profiles" "$work/served/by-version/14.0.365.10" "$tag"
echo "chrome profile" > "$work/served/pgo_profiles/chrome-linux-7339-1.profdata"
echo "chrome-linux-7339-1.profdata" > "$tag/linux.pgo.txt"
for file in meta.json x64.profile x64-rl.profile; do
    echo "v8 $file" > "$work/served/by-version/14.0.365.10/$file"
done

# Where a stand-in tree keeps its Chromium.
chromium() {
    echo "$work/$1/src/3rdparty/chromium"
}

# A stand-in for the engine's tree: Chromium 140.0.7339.225 with V8 14.0.365.10, as 6.11.2 is.
stand_in() {
    mkdir -p "$(chromium "$1")/chrome/build" "$(chromium "$1")/v8/include" \
        "$(chromium "$1")/v8/tools/builtins-pgo/profiles"
    printf 'MAJOR=140\nMINOR=0\nBUILD=7339\nPATCH=225\n' > "$(chromium "$1")/chrome/VERSION"
    printf '#define V8_%s\n' "MAJOR_VERSION 14" "MINOR_VERSION 0" "BUILD_NUMBER 365" \
        "PATCH_LEVEL 10" > "$(chromium "$1")/v8/include/v8-version.h"
}

# A stand-in tree that names its own Chrome profile, as Chromium's own tree does.
names() {
    echo "$2" > "$(chromium "$1")/chrome/build/linux.pgo.txt"
}

# One of V8's builtins profiles as a stand-in tree holds it, or nothing.
builtins() {
    cat "$(chromium "$1")/v8/tools/builtins-pgo/profiles/$2" 2> /dev/null
}

failed=0
fail() {
    echo "FAIL $1"
    failed=1
}

# Runs the fetch for a tree on a machine, with the cache given or one of the tree's own.
fetch() {
    sh "$here/fetch-profiles.sh" "$work/$1" "${3:-$work/$1-cache}" "$2" 2> "$work/$1.log"
}

# The profile Chromium's tag names, held to its MD5, and V8's profiles put where V8 looks.
stand_in tagged
if profile="$(fetch tagged x86_64)"; then
    [ "$profile" = "$work/tagged-cache/chrome-linux-7339-1.profdata" ] \
        || fail "tagged: expected the tag's profile, got $profile"
    [ "$(cat "$profile" 2> /dev/null)" = "chrome profile" ] \
        || fail "tagged: the profile is not the one served"
    [ "$(cat "$(chromium tagged)/chrome/build/linux.pgo.txt" 2> /dev/null)" \
        = "chrome-linux-7339-1.profdata" ] || fail "tagged: the name is not put back in the tree"
    for file in meta.json x64.profile x64-rl.profile; do
        [ "$(builtins tagged "$file")" = "v8 $file" ] \
            || fail "tagged: V8's $file is not in the tree"
    done
    [ "$failed" -eq 0 ] && echo "ok   tagged: $(basename "$profile") and V8 14.0.365.10's builtins"
else
    fail "tagged: the fetch failed: $(cat "$work/tagged.log")"
fi

# A tree that names its own profile is taken at its word, and the tag is not asked.
stand_in named
names named chrome-linux-7339-2.profdata
echo "the tree's own" > "$work/served/pgo_profiles/chrome-linux-7339-2.profdata"
if profile="$(fetch named x86_64)" && [ "$(cat "$profile")" = "the tree's own" ]; then
    echo "ok   named: $(basename "$profile")"
else
    fail "named: expected chrome-linux-7339-2.profdata, got ${profile:-nothing}"
fi

# Chrome's profiles are stored gzipped. The MD5 is of the gzip, and what is kept is unpacked.
stand_in gzipped
names gzipped chrome-linux-7339-3.profdata
echo "stored gzipped" | gzip -c > "$work/served/pgo_profiles/chrome-linux-7339-3.profdata.gzstored"
if profile="$(fetch gzipped x86_64)" && [ "$(cat "$profile")" = "stored gzipped" ]; then
    echo "ok   gzipped: unpacked"
else
    fail "gzipped: expected the unpacked profile, got $(cat "${profile:-/dev/null}" 2> /dev/null)"
fi

# A download that does not match its published MD5 stops the build, and is not kept to be
# taken for good on the next.
stand_in damaged
names damaged chrome-linux-7339-4.profdata
echo "damaged" > "$work/served/pgo_profiles/chrome-linux-7339-4.profdata"
touch "$work/served/pgo_profiles/chrome-linux-7339-4.profdata.badmd5"
if fetch damaged x86_64 > /dev/null; then
    fail "damaged: a profile that did not match its MD5 was taken"
elif [ -e "$work/damaged-cache/chrome-linux-7339-4.profdata" ] \
    || [ -e "$work/damaged-cache/chrome-linux-7339-4.profdata.download" ]; then
    fail "damaged: the profile was left in the cache"
else
    echo "ok   damaged: refused"
fi

# A gzip that matches its MD5 but does not unpack, as an object stored cut short would, stops the
# build too. Nothing is left under the profile's name, or the next build would take it unchecked.
stand_in truncated
names truncated chrome-linux-7339-6.profdata
head -c 20 "$work/served/pgo_profiles/chrome-linux-7339-3.profdata.gzstored" \
    > "$work/served/pgo_profiles/chrome-linux-7339-6.profdata.gzstored"
if fetch truncated x86_64 > /dev/null; then
    fail "truncated: a profile that did not unpack was taken"
elif [ -e "$work/truncated-cache/chrome-linux-7339-6.profdata" ]; then
    fail "truncated: what unpacked was left in the cache under the profile's name"
else
    echo "ok   truncated: refused, nothing kept"
fi

# Chrome publishes no profile for aarch64, so there is none to name. V8's builtins profile is
# taken from x64's, as V8's own build does for arm64.
stand_in arm
if profile="$(fetch arm aarch64)" && [ -z "$profile" ] \
    && [ "$(builtins arm x64.profile)" = "v8 x64.profile" ]; then
    echo "ok   arm: no Chrome profile, V8's builtins"
else
    fail "arm: expected no profile and V8's builtins, got '${profile:-}': $(cat "$work/arm.log")"
fi

# A profile already fetched is used again without asking, so a rebuild needs no network.
stand_in cached
names cached chrome-linux-7339-5.profdata
mkdir -p "$work/cached-cache/v8-14.0.365.10"
echo "kept" > "$work/cached-cache/chrome-linux-7339-5.profdata"
for file in meta.json x64.profile x64-rl.profile; do
    echo "kept $file" > "$work/cached-cache/v8-14.0.365.10/$file"
done
if profile="$(fetch cached x86_64)" && [ "$(cat "$profile")" = "kept" ] \
    && [ "$(builtins cached x64.profile)" = "kept x64.profile" ]; then
    echo "ok   cached: not fetched again"
else
    fail "cached: expected the kept profiles, got $(cat "${profile:-/dev/null}" 2> /dev/null)"
fi

exit "$failed"
