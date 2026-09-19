#!/bin/sh
# Run the extension tests against a built tree, and say which of them prove the patches.
# Usage: scripts/verify.sh <tree>
set -eu

tree="${1:?usage: verify.sh <tree>}"
test="$tree/build/tests/auto/widgets/extensions/tst_qwebengineextension"
stock="${STOCK_QT_LIB:-/opt/homebrew/opt/qtwebengine/lib}"

[ -x "$test" ] || "$tree/build.sh" tst_qwebengineextension

echo "=== patched engine, where everything must pass"
DYLD_FRAMEWORK_PATH="$tree/build/lib" "$test" -o -,txt 2>&1 | grep -E "^(FAIL|Totals)"

echo "=== stock engine, where each of these must fail or crash"
for case in serviceWorkerLocalization enableAfterStoragePathChange tabsWindowsAndScripting nativeMessaging
do
    output=$(DYLD_FRAMEWORK_PATH="$stock" "$test" "$case" -o -,txt 2>&1) && status=0 || status=$?
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
