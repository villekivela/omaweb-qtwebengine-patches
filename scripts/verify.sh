#!/bin/sh
# Run the extension tests against a built tree, and say which of them prove the patches.
# Usage: scripts/verify.sh <tree>
set -eu

tree="${1:?usage: verify.sh <tree>}"
test="$tree/build/tests/auto/widgets/extensions/tst_qwebengineextension"

# macOS resolves frameworks through DYLD_FRAMEWORK_PATH, Linux libraries through
# LD_LIBRARY_PATH, and the stock engine sits in a different place on each.
if [ "$(uname -s)" = "Darwin" ]; then
    path_var=DYLD_FRAMEWORK_PATH
    stock="${STOCK_QT_LIB:-/opt/homebrew/opt/qtwebengine/lib}"
else
    path_var=LD_LIBRARY_PATH
    stock="${STOCK_QT_LIB:-/usr/lib}"
fi

# An engine runs its renderers as a separate program, and a tree that has not
# been installed keeps that program where it was built. The test looks in the
# installed places and in its own folder, neither of which is that, so a build
# tree has to be pointed at it. On macOS the framework bundle carries it and
# this is already true, which is why it went unnoticed until the first Linux
# build.
helper="$tree/build/lib/qt6/QtWebEngineProcess"
[ -x "$helper" ] || helper=""

# A build machine has no display. Widgets draw into nothing rather than
# refusing to start.
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
    export QT_QPA_PLATFORM
fi

# Chromium answers a crash by shelling out to gdb for a backtrace, which on a
# build machine turns a test that died in a second into twenty minutes of
# waiting. The verdict is what is wanted here, not the backtrace.
QTWEBENGINE_CHROMIUM_FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:-} --disable-in-process-stack-traces"
export QTWEBENGINE_CHROMIUM_FLAGS

[ -x "$test" ] || "$tree/build.sh" tst_qwebengineextension

echo "=== patched engine, where everything must pass"
# Every line is kept. A gate that reports only the lines it was looking for
# says nothing at all on the day the test never reaches a verdict, which is the
# day the report is most needed.
if env "$path_var=$tree/build/lib" \
    ${helper:+QTWEBENGINEPROCESS_PATH="$helper"} \
    "$test" -o -,txt 2>&1
then
    :
else
    echo "  the test did not finish cleanly, exit $?"
fi

echo "=== stock engine, where each of these must fail or crash"
if [ ! -e "$stock/qt6/QtWebEngineProcess" ] && [ ! -e "$stock/QtWebEngineProcess" ] \
    && [ ! -d "$stock/QtWebEngineCore.framework" ]
then
    echo "  no stock engine installed here, so there is nothing to compare against"
    exit 0
fi
for case in serviceWorkerLocalization enableAfterStoragePathChange tabsWindowsAndScripting nativeMessaging
do
    output=$(env "$path_var=$stock" "$test" "$case" -o -,txt 2>&1) && status=0 || status=$?
    verdict=$(echo "$output" | grep -E "^(PASS|FAIL).*$case" | head -1 | cut -d: -f1 | tr -d ' ')
    case "$verdict" in
        FAIL*) result="fails" ;;
        PASS*) result="PASSES, which means it proves nothing" ;;
        *)     if [ "$status" -gt 128 ] || echo "$output" | grep -q "Received signal"; then
                   result="crashes, signal $((status - 128))"
               else
                   result="no verdict, exit $status"
               fi ;;
    esac
    printf "  %-32s %s\n" "$case" "$result"
done
