#!/bin/sh
# Runs engine-toolchain.sh for each machine the engine is built on, with and without a toolchain
# asked for, and checks the one it names.
#
# Usage: scripts/test-engine-toolchain.sh
#
# The toolchain decides which work space a local build takes and what the rented machine
# installs, so a wrong answer costs a build of hours before anything says so.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
failed=0

check() {
    name="$1" asked="$2" machine="$3" expected="$4"
    actual="$(OMAWEB_ENGINE_TOOLCHAIN="$asked" sh "$here/engine-toolchain.sh" "$machine" 2> /dev/null \
        || echo "failed")"
    if [ "$actual" = "$expected" ]; then
        echo "ok   $name: $actual"
    else
        echo "FAIL $name: expected $expected, got $actual"
        failed=1
    fi
}

# Measured on x86_64 with Chrome's profile (villekivela/omaweb#356), so the builders take it there.
check "x86_64 by default" "" x86_64 clang
# A Mac or a Docker host names the same machine its own way.
check "amd64 by default" "" amd64 clang

# Without Chrome's profile, which Chrome does not publish for aarch64, clang measured within the
# spread of GCC there (villekivela/omaweb#575), so aarch64 keeps GCC.
check "aarch64 by default" "" aarch64 gcc
check "arm64 by default" "" arm64 gcc

# Asked for by name, either way round, on either machine.
check "gcc asked for on x86_64" gcc x86_64 gcc
check "clang asked for on aarch64" clang aarch64 clang
check "gcc asked for on aarch64" gcc aarch64 gcc

# A name it does not know is refused rather than taken for the default.
check "a misspelt toolchain" clnag x86_64 failed
check "an unknown machine" "" riscv64 failed

exit "$failed"
