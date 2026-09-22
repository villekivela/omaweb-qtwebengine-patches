#!/bin/sh
# Collects finished engine builds from rented machines, and destroys the
# machines.
#
# Usage: scripts/collect-builds.sh [--max-hours N]
#
# Needs HCLOUD_TOKEN, and the builder's ssh key already loaded or at
# ~/.ssh/id_ed25519.
#
# A build takes about eight hours, which outlives an ssh session, a laptop and
# a CI job's six-hour ceiling. So the build detaches on the machine and whoever
# started it may never come back. This is what comes back: it runs on a
# schedule, takes the artifacts off any machine whose build has finished, and
# deletes it either way.
#
# Nothing here decides whether a build was any good. `verify.sh` already
# refused to package a tree that failed the gate, and `remote-build.sh` records
# its exit status. This moves files and stops billing.
set -eu

max_hours=14
while [ $# -gt 0 ]; do
    case "$1" in
        --max-hours) max_hours="${2:?--max-hours needs a number}"; shift 2 ;;
        *) echo "usage: $0 [--max-hours N]"; exit 2 ;;
    esac
done

: "${HCLOUD_TOKEN:?export HCLOUD_TOKEN for the Hetzner project}"
command -v hcloud > /dev/null 2>&1 || { echo "install hcloud first"; exit 1; }

here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/out"
mkdir -p "$out"

# Only the machines this project's builds create. A name is how they are told
# apart from anything else in the project, so nothing else is ever touched.
servers="$(hcloud server list --output noheader --output columns=name \
    | grep '^omaweb-engine-' || true)"
if [ -z "$servers" ]; then
    echo "collect: no build machines"
    exit 0
fi

ssh_opts="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o BatchMode=yes"

echo "$servers" | while read -r server; do
    [ -n "$server" ] || continue
    ip="$(hcloud server ip "$server" 2>/dev/null || true)"
    created="$(hcloud server describe "$server" --output json 2>/dev/null \
        | sed -n 's/.*"created": *"\([^"]*\)".*/\1/p' | head -1)"

    # Whole hours since it was created, which is all the age needs to be.
    age_hours=0
    if [ -n "$created" ]; then
        now="$(date -u +%s)"
        then_="$(date -u -d "$created" +%s 2>/dev/null \
            || date -u -j -f "%Y-%m-%dT%H:%M:%S" "${created%%+*}" +%s 2>/dev/null \
            || echo "$now")"
        age_hours=$(( (now - then_) / 3600 ))
    fi

    echo "== $server, ${age_hours}h old, $ip"

    finished=no
    if [ -n "$ip" ] && ssh $ssh_opts "root@$ip" "test -f /root/build.status" 2>/dev/null; then
        finished=yes
    fi

    if [ "$finished" = no ] && [ "$age_hours" -lt "$max_hours" ]; then
        echo "   still building, leaving it"
        continue
    fi

    if [ "$finished" = yes ]; then
        status="$(ssh $ssh_opts "root@$ip" "cat /root/build.status" 2>/dev/null || echo 1)"
        echo "   finished, exit $status"
        if [ "$status" -eq 0 ]; then
            # The artifacts first, and only then the deletion, so a transfer
            # that fails leaves the machine for the next run rather than
            # throwing away eight hours.
            if scp $ssh_opts "root@$ip:/root/out/*" "$out/" 2>/dev/null; then
                echo "   collected into $out"
            else
                echo "   could not collect, so leaving the machine"
                continue
            fi
        else
            # A failed build's log is the only thing worth keeping off it.
            scp $ssh_opts "root@$ip:/root/build.log" \
                "$out/$server-build.log" 2>/dev/null \
                && echo "   kept the log as $out/$server-build.log"
        fi
    else
        echo "   past ${max_hours}h and not finished, so it is not going to"
        scp $ssh_opts "root@$ip:/root/build.log" \
            "$out/$server-build.log" 2>/dev/null \
            && echo "   kept the log as $out/$server-build.log"
    fi

    echo "   deleting $server"
    hcloud server delete "$server" > /dev/null 2>&1 \
        && echo "   deleted" \
        || echo "   COULD NOT DELETE, it is still billing"
done
