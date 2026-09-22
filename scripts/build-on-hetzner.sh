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
    # load, which is exactly what this is.
    x86) type="${HCLOUD_TYPE_X86:-ccx43}" ;;
    # Ampere. 32 GB is tight for parallel links, so the remote script caps them.
    arm) type="${HCLOUD_TYPE_ARM:-cax41}" ;;
    *)   echo "arch must be x86 or arm"; exit 1 ;;
esac

server="omaweb-engine-$(echo "$version" | tr . -)-$arch-$$"
mkdir -p "$out"

destroy() {
    if [ "$keep" = "--keep" ]; then
        echo "keeping $server, delete it yourself: hcloud server delete $server"
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

echo "building, which takes hours"
ssh "root@$ip" "sh /root/series/scripts/remote-build.sh $version" 2>&1 | sed 's/^/  /'

echo "fetching the artifact"
scp "root@$ip:/root/out/*" "$out/"

destroy
trap - EXIT INT TERM

echo
ls -la "$out"
echo
echo "unsigned. Package and sign on your own machine."
