#!/bin/sh
# Run the extension tests against a built tree, and say which of them prove the patches.
# Usage: scripts/verify.sh <tree>
set -eu

tree="${1:?usage: verify.sh <tree>}"
test="$tree/build/tests/auto/widgets/extensions/tst_qwebengineextension"
interceptor="$tree/build/tests/auto/core/qwebengineurlrequestinterceptor/tst_qwebengineurlrequestinterceptor"

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

# The engine's own data — the resource packs, the ICU table and the locale
# packs — is written under the Chromium output directory rather than beside the
# library, and is only gathered into one place by `cmake --install`. An
# uninstalled tree has to be told where each of them is, for the same reason as
# the helper above.
resources="$(dirname "$(find "$tree/build/src/core" -name qtwebengine_resources.pak \
    -not -path '*/host/*' 2> /dev/null | head -1)")"
locales="$(find "$tree/build/src/core" -type d -name qtwebengine_locales 2> /dev/null | head -1)"
[ -d "$resources" ] 2> /dev/null || resources=""
[ -d "$locales" ] 2> /dev/null || locales=""
# A macOS build carries all of this inside QtWebEngineCore.framework, which is
# where the engine looks first. Pointed at the Chromium output directory
# instead, the renderer was never handed its ICU data and the test crashed on
# its first page, so on macOS the framework is left to answer for itself.
if [ "$(uname)" = Darwin ]; then
    resources=""
    locales=""
fi

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
if [ "$(id -u)" = "0" ]; then
    # A build container is root, and Chromium refuses to start its own sandbox
    # as root. This is off for a test run on a machine that exists to run this
    # test and is then destroyed. It says nothing about the browser, which ships
    # with the sandbox it was built with.
    QTWEBENGINE_CHROMIUM_FLAGS="$QTWEBENGINE_CHROMIUM_FLAGS --no-sandbox"
fi
export QTWEBENGINE_CHROMIUM_FLAGS

# Read from the build rather than run, and before the tests, so its verdict is there even when a
# test never reaches one. Its Totals line goes to the gate with theirs.
sh "$(dirname "$0")/check-write-barriers.sh" "$tree" || true
# The fonts too, so a machine with none says so before the cases it takes down.
sh "$(dirname "$0")/check-fonts.sh" || true

[ -x "$test" ] || "$tree/build.sh" tst_qwebengineextension

echo "=== patched engine, where everything must pass"
# Every line is kept. A gate that reports only the lines it was looking for
# says nothing at all on the day the test never reaches a verdict, which is the
# day the report is most needed.
# `-nocrashhandler` stops Qt Test answering a crash with its own gdb backtrace,
# which is the other twenty-minute wait.
if env "$path_var=$tree/build/lib" \
    ${helper:+QTWEBENGINEPROCESS_PATH="$helper"} \
    ${resources:+QTWEBENGINE_RESOURCES_PATH="$resources"} \
    ${locales:+QTWEBENGINE_LOCALES_PATH="$locales"} \
    "$test" -nocrashhandler -o -,txt 2>&1
then
    :
else
    echo "  the test did not finish cleanly, exit $?"
fi

# The request interceptor's DNS aliases are the one patch that is not about
# extensions, so its cases live in Qt's own interceptor test. Only the cases the
# patch adds run: the rest of that suite is Qt's, and it is Qt's to keep green.
[ -x "$interceptor" ] || "$tree/build.sh" tst_qwebengineurlrequestinterceptor

echo "=== patched engine, the request interceptor's DNS aliases"
if env "$path_var=$tree/build/lib" \
    ${helper:+QTWEBENGINEPROCESS_PATH="$helper"} \
    ${resources:+QTWEBENGINE_RESOURCES_PATH="$resources"} \
    ${locales:+QTWEBENGINE_LOCALES_PATH="$locales"} \
    "$interceptor" dnsAliasesReachASecondCall dnsAliasesAreNotLookedUpUnlessAsked \
    dnsAliasesAreNotLookedUpForABlockedRequest dnsAliasesAreNotLookedUpBehindAProxy \
    dnsAliasesThatFailLeaveTheFirstDecision dnsAliasesNamingOnlyTheHostMakeNoSecondCall \
    dnsAliasesAreRememberedForAHost dnsAliasesAreRememberedPerProfile \
    -nocrashhandler -o -,txt 2>&1
then
    :
else
    echo "  the test did not finish cleanly, exit $?"
fi

# The certificate chain a page arrived over is the one patch whose case lives
# in Qt's certificate error test, because that test has the server certificate
# to accept. Only the case the patch adds runs.
certificates="$tree/build/tests/auto/core/certificateerror/tst_certificateerror"
[ -x "$certificates" ] || "$tree/build.sh" tst_certificateerror

echo "=== patched engine, the certificate chain a page arrived over"
if env "$path_var=$tree/build/lib" \
    ${helper:+QTWEBENGINEPROCESS_PATH="$helper"} \
    ${resources:+QTWEBENGINE_RESOURCES_PATH="$resources"} \
    ${locales:+QTWEBENGINE_LOCALES_PATH="$locales"} \
    "$certificates" loadingInfoCarriesAcceptedChain -nocrashhandler -o -,txt 2>&1
then
    :
else
    echo "  the test did not finish cleanly, exit $?"
fi

# A favicon drawn again when the colour scheme changes and an SVG icon ranked
# above a raster one are the patches about favicons, so their cases live in
# Qt's favicon tests, one for a page and one for the Quick view. Only the cases
# the patches add run.
favicon="$tree/build/tests/auto/widgets/favicon/tst_favicon"
favicon_cases="redrawOnColorSchemeChange redrawOnNextVisitAfterColorSchemeChange \
redrawAfterAPageStartsUnderAnotherScheme sameDrawingIsNotReportedAgain \
svgRanksAboveARasterBesideIt svgRanksAboveARasterDeclaredAfterIt rasterShownWhenTheSvgFails"
[ -x "$favicon" ] || "$tree/build.sh" tst_favicon

echo "=== patched engine, a favicon drawn again when the colour scheme changes, and an SVG one first"
# shellcheck disable=SC2086 # one argument per case
if env "$path_var=$tree/build/lib" \
    ${helper:+QTWEBENGINEPROCESS_PATH="$helper"} \
    ${resources:+QTWEBENGINE_RESOURCES_PATH="$resources"} \
    ${locales:+QTWEBENGINE_LOCALES_PATH="$locales"} \
    "$favicon" $favicon_cases -nocrashhandler -o -,txt 2>&1
then
    :
else
    echo "  the test did not finish cleanly, exit $?"
fi

# The Quick tests load the engine's QML module, which an uninstalled tree keeps
# under its build, and run from their own directory, where they find their list.
qmltests="$tree/build/tests/auto/quick/qmltests/tst_qmltests"
[ -x "$qmltests" ] || "$tree/build.sh" tst_qmltests

echo "=== patched engine, a favicon the Quick view draws again"
if (cd "$(dirname "$qmltests")" && env "$path_var=$tree/build/lib" \
    QML_IMPORT_PATH="$tree/build/lib/qt6/qml" \
    ${helper:+QTWEBENGINEPROCESS_PATH="$helper"} \
    ${resources:+QTWEBENGINE_RESOURCES_PATH="$resources"} \
    ${locales:+QTWEBENGINE_LOCALES_PATH="$locales"} \
    "$qmltests" WebEngineFavicon::test_faviconRedrawnWhenColorSchemeChanges \
    -nocrashhandler -o -,txt 2>&1)
then
    :
else
    echo "  the test did not finish cleanly, exit $?"
fi

# Three patches change what a page hears: what its passkeys can reach (0026), how a push
# subscription is answered (0027) and what window.chrome holds (0031). Their cases live in Qt's
# page test, and only they run.
page="$tree/build/tests/auto/widgets/qwebenginepage/tst_qwebenginepage"
page_cases="clientCapabilitiesAnswerWithoutBluetooth pushSubscribeAnswersAlikeOffTheRecord \
windowChromeAnswersAsChromeDoes"
# The stock run below reads the first result line of each case, so 0027's case lists its
# off-the-record row first, the one a stock engine fails.
# Patch 0027 has a control beside its case: a notifications request still reaches the
# application off the record, which a stock engine does too, so it runs on the patched
# engine only.
patched_page_cases="$page_cases notificationRequestStillReachesTheApplicationOffTheRecord"
[ -x "$page" ] || "$tree/build.sh" tst_qwebenginepage

echo "=== patched engine, a page told what its passkeys can reach"
# shellcheck disable=SC2086 # one argument per case
if env "$path_var=$tree/build/lib" \
    ${helper:+QTWEBENGINEPROCESS_PATH="$helper"} \
    ${resources:+QTWEBENGINE_RESOURCES_PATH="$resources"} \
    ${locales:+QTWEBENGINE_LOCALES_PATH="$locales"} \
    "$page" $patched_page_cases -nocrashhandler -o -,txt 2>&1
then
    :
else
    echo "  the test did not finish cleanly, exit $?"
fi

# Patch 0028 grants a sanitized clipboard write during a gesture, so its cases live in Qt's
# permission test. The stock run reads the first result line of each case, so
# clipboardReadWritePermissionInitialState lists first the row without either setting, the one a
# stock engine fails. clipboardReadWritePermission's clipboard-write query changes with it too.
# Patches 0029 and 0030 are about an extension's documents, so their cases are in the extension
# test above.
permission="$tree/build/tests/auto/widgets/qwebenginepermission/tst_qwebenginepermission"
permission_cases="clipboardReadWritePermissionInitialState clickedWriteIsNotAsked"
[ -x "$permission" ] || "$tree/build.sh" tst_qwebenginepermission

echo "=== patched engine, the clipboard a page writes during a gesture"
# shellcheck disable=SC2086 # one argument per case
if env "$path_var=$tree/build/lib" \
    ${helper:+QTWEBENGINEPROCESS_PATH="$helper"} \
    ${resources:+QTWEBENGINE_RESOURCES_PATH="$resources"} \
    ${locales:+QTWEBENGINE_LOCALES_PATH="$locales"} \
    "$permission" $permission_cases clipboardReadWritePermission -nocrashhandler -o -,txt 2>&1
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
# A stock engine drops every drawing at an address it already shows, so
# sameDrawingIsNotReportedAgain passes there by construction, and it shows the
# raster beside an SVG it cannot fetch, as rasterShownWhenTheSvgFails expects.
# Both guard what a patch keeps and are left out here.
stock_favicon_cases="redrawOnColorSchemeChange redrawOnNextVisitAfterColorSchemeChange \
redrawAfterAPageStartsUnderAnotherScheme svgRanksAboveARasterBesideIt \
svgRanksAboveARasterDeclaredAfterIt"
for case in serviceWorkerLocalization enableAfterStoragePathChange tabsWindowsAndScripting \
    nativeMessaging anExtensionUsesTheClipboardItsPermissionsAllow \
    anOffscreenDocumentCanSelectText $stock_favicon_cases $page_cases $permission_cases
do
    program="$test"
    case " $favicon_cases " in *" $case "*) program="$favicon" ;; esac
    case " $page_cases " in *" $case "*) program="$page" ;; esac
    case " $permission_cases " in *" $case "*) program="$permission" ;; esac
    output=$(env "$path_var=$stock" "$program" "$case" -nocrashhandler -o -,txt 2>&1) \
        && status=0 || status=$?
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
