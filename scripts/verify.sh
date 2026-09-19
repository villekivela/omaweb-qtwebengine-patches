#!/bin/sh
# Run the extension tests against a built tree, and say which of them prove the patches.
# Usage: scripts/verify.sh <tree>
set -eu

tree="${1:?usage: verify.sh <tree>}"
test="$tree/build/tests/auto/widgets/extensions/tst_qwebengineextension"

[ -x "$test" ] || "$tree/build.sh" tst_qwebengineextension

echo "=== patched engine"
DYLD_FRAMEWORK_PATH="$tree/build/lib" "$test" -o -,txt 2>&1 | grep -E "^(FAIL|Totals)"

echo "=== stock engine, where four of these must fail"
for case in serviceWorkerLocalization enableAfterStoragePathChange tabsWindowsAndScripting nativeMessaging
do
    result=$(DYLD_FRAMEWORK_PATH=/opt/homebrew/opt/qtwebengine/lib "$test" "$case" -o -,txt 2>&1 \
        | grep -E "^(PASS|FAIL).*$case" | head -1 | cut -d: -f1)
    printf "  %-32s %s\n" "$case" "${result:-no result}"
done
