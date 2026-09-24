#!/bin/sh
# Collects finished engine builds from rented machines, and destroys the
# machines.
#
# Usage: scripts/collect-builds.sh [--max-hours N] [--defer-delete FILE]
#        scripts/collect-builds.sh --delete-listed FILE
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
# Each machine's files land in out/<machine>/. Both architectures write
# SHA256SUMS, verify.txt, apply.txt and engine.json, and one directory for two
# machines kept whichever arrived last.
#
# --defer-delete writes the names of the machines to delete into FILE instead
# of deleting them, and --delete-listed deletes them. On a runner the copy in
# out/ is not safe until the artifact is uploaded, and a machine deleted before
# then took the only other copy with it.
#
# Exits non-zero when a machine could not be collected or could not be
# deleted, because both leave a machine billing and a green run says nobody
# needs to look.
#
# Nothing here decides whether a build was any good. `verify.sh` already
# refused to package a tree that failed the gate, and `remote-build.sh` records
# its exit status. This moves files and stops billing.
set -eu

max_hours=14
defer=""
delete_listed=""
while [ $# -gt 0 ]; do
    case "$1" in
        --max-hours) max_hours="${2:?--max-hours needs a number}"; shift 2 ;;
        --defer-delete) defer="${2:?--defer-delete needs a file}"; shift 2 ;;
        --delete-listed) delete_listed="${2:?--delete-listed needs a file}"; shift 2 ;;
        *) echo "usage: $0 [--max-hours N] [--defer-delete FILE] | --delete-listed FILE"; exit 2 ;;
    esac
done

: "${HCLOUD_TOKEN:?export HCLOUD_TOKEN for the Hetzner project}"
command -v hcloud > /dev/null 2>&1 || { echo "install hcloud first"; exit 1; }

trouble=0

delete() {
    echo "   deleting $1"
    if hcloud server delete "$1" > /dev/null 2>&1; then
        echo "   deleted"
    else
        echo "   COULD NOT DELETE $1, it is still billing"
        trouble=1
    fi
}

if [ -n "$delete_listed" ]; then
    if [ ! -s "$delete_listed" ]; then
        echo "delete: nothing to delete"
        exit 0
    fi
    while read -r server; do
        [ -n "$server" ] || continue
        echo "== $server"
        delete "$server"
    done < "$delete_listed"
    exit "$trouble"
fi

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

# The builder key by name where there is one. A runner writes it to the default
# identity, but a machine with more than one key does not, and ssh then fails
# with "Permission denied" — which this used to read as a machine that is still
# building. That mistake is expensive in one direction: a finished build is
# never collected and its machine bills until the age limit.
key="${OMAWEB_BUILDER_KEY:-$HOME/.ssh/omaweb-builder}"
ssh_opts="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o BatchMode=yes"
if [ -f "$key" ]; then
    ssh_opts="$ssh_opts -i $key"
fi

# Deleted now, or listed for a later step to delete once the artifact is safe.
done_with() {
    if [ -n "$defer" ]; then
        echo "$1" >> "$defer"
        echo "   listed for deletion once the artifact is uploaded"
    else
        delete "$1"
    fi
}

# Read from a here-document rather than a pipe, so the loop runs in this shell
# and what it records in $trouble is still there when it ends.
while read -r server; do
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
    dest="$out/$server"

    # Reachable and finished are different questions, and answering them
    # together is how an unreachable machine gets reported as a busy one.
    reachable=no
    finished=no
    if [ -n "$ip" ] && ssh $ssh_opts "root@$ip" true 2>/dev/null < /dev/null; then
        reachable=yes
        if ssh $ssh_opts "root@$ip" "test -f /root/build.status" 2>/dev/null < /dev/null; then
            finished=yes
        fi
    fi

    if [ "$reachable" = no ]; then
        echo "   cannot be reached, so nothing can be collected from it"
        if [ "$age_hours" -lt "$max_hours" ]; then
            echo "   under ${max_hours}h, so leaving it in case that is temporary"
            continue
        fi
    elif [ "$finished" = no ] && [ "$age_hours" -lt "$max_hours" ]; then
        echo "   still building, leaving it"
        continue
    fi

    if [ "$finished" = yes ]; then
        status="$(ssh $ssh_opts "root@$ip" "cat /root/build.status" 2>/dev/null < /dev/null \
            || echo 1)"
        echo "   finished, exit $status"

        # Whatever it left behind, whether it succeeded or not. A run can fail
        # after the engine is built and the gate has passed: packaging is the
        # last step and it has its own ways to die. Taking the artifacts only
        # from a clean run threw away a good engine and hours of machine time,
        # which is what this used to do.
        if ssh $ssh_opts "root@$ip" "ls /root/out/* > /dev/null 2>&1" < /dev/null; then
            mkdir -p "$dest"
            # The artifacts first, and only then the deletion, so a transfer
            # that fails leaves the machine for the next run rather than
            # discarding what it holds.
            if scp $ssh_opts "root@$ip:/root/out/*" "$dest/" 2>/dev/null < /dev/null; then
                echo "   collected into $dest"
            else
                trouble=1
                # Not forever. A machine whose files could not be copied for
                # twice the age limit is not going to give them up, and leaving
                # it had no end: it billed until somebody noticed.
                if [ "$age_hours" -lt $(( max_hours * 2 )) ]; then
                    echo "   COULD NOT COLLECT, so leaving the machine for the next run"
                    continue
                fi
                echo "   COULD NOT COLLECT for $(( max_hours * 2 ))h, so giving up on it"
            fi
        else
            echo "   nothing in /root/out to collect"
        fi

        if [ "$status" -ne 0 ]; then
            # What went wrong is worth keeping off a machine about to go.
            mkdir -p "$dest"
            scp $ssh_opts "root@$ip:/root/build.log" "$dest/build.log" 2>/dev/null < /dev/null \
                && echo "   kept the log as $dest/build.log"
        fi
    else
        echo "   past ${max_hours}h and not finished, so it is not going to"
        mkdir -p "$dest"
        scp $ssh_opts "root@$ip:/root/build.log" "$dest/build.log" 2>/dev/null < /dev/null \
            && echo "   kept the log as $dest/build.log"
    fi

    done_with "$server"
done <<EOF
$servers
EOF

exit "$trouble"
