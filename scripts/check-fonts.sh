#!/bin/sh
# Say whether the machine running the gate has a font for the test pages to draw their text in.
# Usage: scripts/check-fonts.sh
#
# Neither container image the engine builds in ships a font. Blink stops the renderer on purpose
# (FontCache::CrashWithFontInfo) the first time a page shapes text with no font to fall back to, and
# says nothing on the way out. The 6.11.2-16 gate on aarch64 reported that as three clipboard cases
# failing, with the renderer gone as "ProcessGone: 3 (5)", and the patches were not the cause. So
# the fonts are counted before the tests run, and the gate names this first.
#
# A tree built on macOS has no fontconfig, and the system draws its text, so nothing is counted and
# the line says so. The verdict is a Qt Test "Totals:" line, so the gate that reads the tests'
# totals reads this too. Shell builtins only besides fc-list, so a test can stand one in.
set -eu

echo "=== fonts, which the test pages draw their text in"
if ! command -v fc-list > /dev/null 2>&1; then
    echo "  no fontconfig here, so the fonts were not counted"
    exit 0
fi

fonts="$(fc-list)"
count=0
IFS='
'
for font in $fonts; do
    [ -n "$font" ] && count=$((count + 1))
done

if [ "$count" -eq 0 ]; then
    echo "FAIL!  : no font installed, so a page that shapes text stops its renderer"
    echo "Totals: 0 passed, 1 failed"
    exit 1
fi
echo "PASS   : font faces installed: $count"
echo "Totals: 1 passed, 0 failed"
