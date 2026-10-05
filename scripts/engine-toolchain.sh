#!/bin/sh
# Names the toolchain an engine build on this machine uses: clang or gcc.
#
# Usage: scripts/engine-toolchain.sh [machine], where machine is what `uname -m` prints and
# defaults to this one's. OMAWEB_ENGINE_TOOLCHAIN asks for one by name instead.
#
# clang means clang and LLD with ThinLTO, and on x86_64 Chrome's PGO profile as well
# (`toolchain/README.md`). Each architecture takes the toolchain that was measured to be faster on
# it. One answer, read by `build-locally.sh` on the host and by `build-inside.sh` in the
# container, because the host names the work space after it and the container builds with it.
set -eu

machine="${1:-$(uname -m)}"

case "${OMAWEB_ENGINE_TOOLCHAIN:-}" in
    gcc | clang)
        echo "$OMAWEB_ENGINE_TOOLCHAIN"
        exit 0
        ;;
    "") ;;
    *)
        echo "OMAWEB_ENGINE_TOOLCHAIN is gcc or clang, not $OMAWEB_ENGINE_TOOLCHAIN" >&2
        exit 1
        ;;
esac

case "$machine" in
    x86_64 | amd64) echo clang ;;
    aarch64 | arm64) echo gcc ;;
    *)
        echo "no engine is built for $machine" >&2
        exit 1
        ;;
esac
