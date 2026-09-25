#!/bin/sh
# Ask the real resolver for DNS aliases, the one thing the gate cannot check.
# Usage: scripts/check-real-dns.sh <tree>
#
# The gate's DNS alias cases stand in for the resolver, because a CNAME chain
# needs a DNS server and a build machine has neither one nor the internet. That
# is how a lookup that never asked the system resolver for a name passed every
# case (omaweb#354). This loads icons from three sites whose CNAME chains are
# public and end at a CDN, once through the system resolver and once through
# DNS-over-HTTPS, and says what came back. It needs the internet, and it sends
# three lookups to Cloudflare's DoH server.
set -eu

tree="${1:?usage: check-real-dns.sh <tree>}"
test="$tree/build/tests/auto/core/qwebengineurlrequestinterceptor/tst_qwebengineurlrequestinterceptor"
[ -x "$test" ] || "$tree/build.sh" tst_qwebengineurlrequestinterceptor

if [ "$(uname -s)" = "Darwin" ]; then
    path_var=DYLD_FRAMEWORK_PATH
else
    path_var=LD_LIBRARY_PATH
fi
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
    export QT_QPA_PLATFORM
fi

env "$path_var=$tree/build/lib" OMAWEB_CHECK_REAL_DNS=1 \
    "$test" dnsAliasesFromTheResolver -nocrashhandler -o -,txt 2>&1
