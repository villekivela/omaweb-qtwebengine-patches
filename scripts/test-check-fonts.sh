#!/bin/sh
# Runs check-fonts.sh against stand-in fc-list programs and checks its verdict for each.
#
# Usage: scripts/test-check-fonts.sh
#
# The machine this runs on has whatever fonts it has, so the stand-ins answer for it: no font, one
# font, and no fontconfig at all.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failed=0

# A directory holding an fc-list that prints the given lines, or no fc-list when given "missing".
stand_in() {
    mkdir -p "$work/$1"
    [ "$2" = missing ] && return
    printf '#!/bin/sh\nprintf "%%s" "%s"\n' "$2" > "$work/$1/fc-list"
    chmod +x "$work/$1/fc-list"
}

# The exit status a machine gets, its Totals line ("none" for no line at all), and a phrase the
# output has to carry.
check() {
    name="$1" status="$2" verdict="$3" says="$4"
    output="$(PATH="$work/$name" /bin/sh "$here/check-fonts.sh" 2>&1)" \
        && actual=0 || actual=$?
    totals="$(echo "$output" | sed -n 's/^Totals: //p')"
    [ -n "$totals" ] || totals=none
    if [ "$actual" != "$status" ]; then
        echo "FAIL $name: expected exit $status, got $actual: $output"
        failed=1
    elif [ "$totals" != "$verdict" ]; then
        echo "FAIL $name: expected Totals: $verdict, got: $output"
        failed=1
    elif ! echo "$output" | grep -qF "$says"; then
        echo "FAIL $name: expected the output to say $says, got: $output"
        failed=1
    else
        echo "ok   $name: Totals: $verdict"
    fi
}

# Neither container image the engine builds in ships a font. Blink then stops the renderer the
# first time a page shapes text, and the gate reported it as three clipboard failures.
stand_in none ""
check none 1 "0 passed, 1 failed" "no font"

stand_in one "/usr/share/fonts/gnu-free/FreeSans.otf: FreeSans:style=Regular
"
check one 0 "1 passed, 0 failed" "font faces installed: 1"

# A tree built on macOS has no fontconfig, and the system draws its text. Nothing is counted there,
# and the line says so rather than passing.
stand_in missing missing
check missing 0 none "not counted"

exit "$failed"
