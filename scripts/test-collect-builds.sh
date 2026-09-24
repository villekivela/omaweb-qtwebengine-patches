#!/bin/sh
# Runs collect-builds.sh against stand-ins for hcloud, ssh and scp, one machine
# for each way a machine can be found, and checks what it collected, what it
# deleted and how it exited.
#
# Usage: scripts/test-collect-builds.sh
#
# Nothing here reaches Hetzner or any machine. The collector deletes rented
# machines, and the ways it can go wrong are ones a real build takes hours to
# reach, so they are rehearsed here instead.
set -eu

here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/repo"
cp -R "$here/scripts" "$work/repo/"

# a finished and is collected, b finished but its files will not copy, c the
# same but old enough to give up on, d still building, e failed and will not
# delete. The last is not ours and must never be touched.
cat > "$work/bin/hcloud" << 'EOF'
#!/bin/sh
case "$1 $2" in
"server list")
    printf '%s\n' omaweb-engine-a omaweb-engine-b omaweb-engine-c \
        omaweb-engine-d omaweb-engine-e somebody-elses-machine ;;
"server ip") echo "ip-${3#omaweb-engine-}" ;;
"server describe")
    case "$3" in *-c) hours=30 ;; *-d) hours=2 ;; *) hours=3 ;; esac
    then_=$(( $(date -u +%s) - hours * 3600 ))
    created="$(date -u -d "@$then_" +%Y-%m-%dT%H:%M:%S 2>/dev/null \
        || date -u -r "$then_" +%Y-%m-%dT%H:%M:%S)"
    echo "{\"created\": \"$created+00:00\"}" ;;
"server delete")
    echo "$3" >> "$STUB/deleted"
    [ "$3" != omaweb-engine-e ] ;;
esac
EOF

# The host and the command are the last two arguments, whatever options come
# before them. Reads its input the way a real ssh does, so a loop that shares
# its input with ssh loses the names after the first here as it would there.
cat > "$work/bin/ssh" << 'EOF'
#!/bin/sh
cat > /dev/null
for arg; do host=$prev; prev=$arg; done
case "$prev" in
true) exit 0 ;;
"test -f /root/build.status") [ "$host" != root@ip-d ] ;;
"cat /root/build.status") if [ "$host" = root@ip-e ]; then echo 1; else echo 0; fi ;;
ls*) exit 0 ;;
esac
EOF

cat > "$work/bin/scp" << 'EOF'
#!/bin/sh
for arg; do src=$dst; dst=$arg; done
case "$src" in root@ip-b:* | root@ip-c:/root/out/*) exit 1 ;; esac
if [ -d "$dst" ]; then touch "$dst/engine.pkg.tar.zst"; else touch "$dst"; fi
EOF
chmod +x "$work/bin/"*

failures=0
check() {
    if [ "$2" = "$3" ]; then
        echo "ok    $1"
    else
        echo "FAIL  $1"
        echo "      expected: $(printf '%s' "$3" | tr '\n' ' ')"
        echo "      got:      $(printf '%s' "$2" | tr '\n' ' ')"
        failures=$(( failures + 1 ))
    fi
}

collect() {
    PATH="$work/bin:$PATH" STUB="$work" HCLOUD_TOKEN=stub \
        OMAWEB_BUILDER_KEY=/nonexistent \
        sh "$work/repo/scripts/collect-builds.sh" "$@" > "$work/log" 2>&1
}

listed() { cat "$work/list" 2>/dev/null || true; }
deleted() { cat "$work/deleted" 2>/dev/null || true; }
collected() { (cd "$work/repo/out" && find . -type f | sed 's|^\./||' | sort); }

finished_machines="omaweb-engine-a
omaweb-engine-c
omaweb-engine-e"

# Deferred: machines are listed and none is deleted, so a failed upload loses
# nothing.
status=0
collect --defer-delete "$work/list" || status=$?
check "deferred: a machine that would not copy fails the run" "$status" 1
check "deferred: finished machines are listed" "$(listed)" "$finished_machines"
check "deferred: nothing is deleted yet" "$(deleted)" ""
check "deferred: each machine's files in a directory of its own" "$(collected)" \
    "omaweb-engine-a/engine.pkg.tar.zst
omaweb-engine-e/build.log
omaweb-engine-e/engine.pkg.tar.zst"

status=0
collect --delete-listed "$work/list" || status=$?
check "delete-listed: a delete that failed fails the run" "$status" 1
check "delete-listed: every listed machine is deleted" "$(deleted)" "$finished_machines"

rm -f "$work/deleted"
status=0
collect --delete-listed "$work/nothing" || status=$?
check "delete-listed: an empty list succeeds" "$status" 0
check "delete-listed: an empty list deletes nothing" "$(deleted)" ""

# Immediate, as when run by hand.
rm -rf "$work/deleted" "$work/repo/out"
status=0
collect || status=$?
check "immediate: fails when a machine is left billing" "$status" 1
check "immediate: finished machines are deleted" "$(deleted)" "$finished_machines"

if [ "$failures" -ne 0 ]; then
    echo
    echo "$failures failed. The last run said:"
    sed 's/^/  /' "$work/log"
    exit 1
fi
echo "all passed"
