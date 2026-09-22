#!/bin/sh
# Build the patched engine on a machine rented for the job, then destroy it.
#
# Usage: scripts/build-on-hetzner.sh <qt-version> <x86|arm> [--keep]
#
# Needs HCLOUD_TOKEN in the environment and an SSH key already uploaded to the
# Hetzner project (OMAWEB_SSH_KEY names it, default "omaweb-builder").
#
# What comes back is an unsigned tarball of the install tree, the unsigned
# package made from it, and their checksums.
# Packaging and signing happen where the key is, which is not here.
set -eu

version="${1:?usage: build-on-hetzner.sh <qt-version> <x86|arm> [--keep]}"
arch="${2:?usage: build-on-hetzner.sh <qt-version> <x86|arm> [--keep]}"
keep="${3:-}"

: "${HCLOUD_TOKEN:?export HCLOUD_TOKEN for the Hetzner project}"
command -v hcloud > /dev/null 2>&1 || { echo "install hcloud first"; exit 1; }

ssh_key="${OMAWEB_SSH_KEY:-omaweb-builder}"
location="${HCLOUD_LOCATION:-hel1}"
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/out"

case "$arch" in
    # Dedicated cores. A shared-vCPU instance throttles under hours of full
    # load, and Hetzner's terms ask that sustained full load not run on one.
    #
    # ccx33, eight dedicated cores and 32 GB, which builds the engine in about
    # eight hours for roughly two euros. It is here because a new project's
    # dedicated core limit was under sixteen and a ccx43 was refused.
    #
    # Hetzner is raising that limit. When sixteen cores are available a ccx43
    # costs about the same for the whole build and takes half the time, which
    # also brings it under the six hours a CI job gets, so the build no longer
    # has to outlive its driver. Set HCLOUD_TYPE_X86=ccx43 to try it, and change
    # this default once one has actually built.
    x86) type="${HCLOUD_TYPE_X86:-ccx33}" ;;
    # Ampere. 32 GB is tight for parallel links, so the remote script caps them.
    arm) type="${HCLOUD_TYPE_ARM:-cax41}" ;;
    *)   echo "arch must be x86 or arm"; exit 1 ;;
esac

server="omaweb-engine-$(echo "$version" | tr . -)-$arch-$$"
mkdir -p "$out"

# Deleted when the build is finished with, and not merely when this script is.
# The two used to be the same thing, and that made losing the driver expensive
# in both directions: a trap that fired on any exit destroyed a machine still
# building, and a `--keep` that avoided it left the machine billing until
# somebody remembered.
#
# So this deletes a machine it has collected, and leaves one it has not.
# `collect-builds.sh` runs on a schedule and deletes the rest, whether the
# build finished after the driver went away or never finished at all. Nothing
# depends on this process staying alive.
collected=""
created=""

destroy() {
    # Nothing was rented, so there is nothing to say about it. A create that
    # failed used to print advice about deleting a machine that does not exist,
    # which reads as a leak when there is none.
    if [ -z "$created" ]; then
        return
    fi
    if [ "$keep" = "--keep" ]; then
        echo "keeping $server, delete it yourself: hcloud server delete $server"
        return
    fi
    if [ -z "$collected" ]; then
        echo "leaving $server, because this build has not been collected"
        echo "the scheduled collector will take it, or: hcloud server delete $server"
        return
    fi
    echo "destroying $server"
    # Deleting is what stops the billing. A stopped server still bills for its
    # disk.
    hcloud server delete "$server" > /dev/null 2>&1 || true
}
trap destroy EXIT INT TERM

echo "creating $server ($type, $location)"
hcloud server create \
    --name "$server" \
    --type "$type" \
    --image "${HCLOUD_IMAGE:-debian-13}" \
    --location "$location" \
    --ssh-key "$ssh_key" \
    > /dev/null

created=yes
ip="$(hcloud server ip "$server")"
echo "waiting for ssh on $ip"
until ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 \
    "root@$ip" true > /dev/null 2>&1
do
    sleep 5
done

echo "sending the series"
# `packaging` as well as the series: the build packages what it built, on a
# machine of the right architecture, so nothing has to be repackaged by hand.
tar cf - -C "$here" patches scripts packaging \
    | ssh "root@$ip" "mkdir -p /root/series && tar xf - -C /root/series"

# Detached, and polled rather than watched. The build outlives any connection
# to it: a laptop that sleeps, a network that drops, a CI runner that hits
# GitHub's six-hour ceiling. Run in the foreground over ssh, any of those kills
# the build as well as the watching, and leaves a rented machine billing for
# nothing.
echo "building, which takes hours"
ssh "root@$ip" \
    "setsid nohup sh /root/series/scripts/remote-build.sh $version \
        > /root/build.log 2>&1 < /dev/null & echo started"

# The last line of the log every minute, so a run can be followed, and the
# status file is what says it is over.
while true; do
    if ssh -o ConnectTimeout=10 "root@$ip" "test -f /root/build.status" 2>/dev/null; then
        break
    fi
    ssh -o ConnectTimeout=10 "root@$ip" "tail -n 1 /root/build.log" 2>/dev/null \
        | sed 's/^/  /'
    sleep 60
done

status="$(ssh "root@$ip" "cat /root/build.status" 2>/dev/null || echo 1)"
ssh "root@$ip" "tail -n 20 /root/build.log" 2>/dev/null | sed 's/^/  /'
if [ "$status" -ne 0 ]; then
    echo "the build failed, exit $status"
    echo "the machine is kept so the log can be read: ssh root@$ip"
    keep=--keep
    exit "$status"
fi

echo "fetching the artifact"
scp "root@$ip:/root/out/*" "$out/"
# Down safely, so the machine has nothing left on it that matters.
collected=yes

destroy
trap - EXIT INT TERM

echo
ls -la "$out"
echo
echo "unsigned. Package and sign on your own machine."
