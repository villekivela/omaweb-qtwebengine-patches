# A modified QtWebEngine

This package is not Qt's build of QtWebEngine 6.140.0. It is that release with a patch series
applied, and it installs into `/usr/lib/omaweb` so that the distribution's `qt6-webengine` stays
where it is and every other Qt application on the machine keeps the engine it had.

LGPL-3.0 asks a modified build to say that it is modified and to carry the notices. That is what
this file is for.

## What changed

Thirty-three patches, applied in order to the released source. Thirteen add the part of Chromium's
extension runtime that QtWebEngine compiles out: renderer bindings, the `tabs`, `windows`,
`permissions`, `scripting`, `notifications` and `webNavigation` namespaces behind an embedder
delegate, native messaging, and web accessible resources. Five of those are bug fixes in Qt's own
code rather than additions. The fourteenth restores Perfetto's `track_event_macros.h` to the version
Chromium ships, which Qt's copy changes. The fifteenth lets a request interceptor ask for the DNS
aliases of a request's host, and the sixteenth reports the certificate chain a page arrived over on
`QWebEngineLoadingInfo`. The seventeenth adds one more piece of the extension runtime: the
application says where the window holding a page is, and the `windows` namespace reports it to an
extension. The twentieth keeps the content scripts an extension registers to persist across a
restart, in the profile's storage path, forgets them when another version of the extension is
loaded, holds a page they are for until they are read, writes a profile's preferences before it is
deleted or set up on another path, and fixes Chromium's `scripting` namespace keeping one only for
the session after an update that leaves its persistence out. The nineteenth adds one more piece of
the extension runtime: a page an extension opens is a window of its own, and the extension is told
when it closes. The twentieth is a bug fix in Qt's own code: deleting a profile while an extension's
message waits for its worker no longer crashes the application. The twenty-first is a bug fix in
Qt's own code as well: when the application's colour scheme changes, pages are told it, and a
favicon drawn for the earlier scheme is drawn again, at once for a page on show and on the next
visit for any other. The twenty-second adds `QWebEngineExtensionManager::setPageIsTab`, through
which the application says it shows a page an extension opened as one of its tabs, so the page
leaves the window of its own for the browser's. The twenty-third changes Chromium's favicon ranking:
a page's SVG icon is tried before its raster ones and taken once it is drawn, so an icon that
follows the colour scheme is shown rather than a raster one declared beside it. The twenty-fourth is
a bug fix for a build without BlueZ, as this one is: Chromium is told there is no Bluetooth LE, so a
page that asks what its passkeys can reach hears back rather than waiting on a Bluetooth adapter
that never comes. The twenty-fifth removes Chromium's disguise for a missing push service in a
window that keeps nothing: a page that subscribes there is refused at once, as in any other window,
rather than after a question to the application. The twenty-sixth grants a page's clipboard write of
text or a known image format during a click or a key press without asking the application, as Chrome
does. The twenty-seventh adds one more piece of the extension runtime: an extension that declares
`clipboardRead` or `clipboardWrite` reads or writes the clipboard without a gesture or a question.
The twenty-eighth is a bug fix in Qt's own code: an offscreen document that selects text no longer
crashes the engine. The twenty-ninth gives every page Chrome's `chrome.app`, `chrome.csi` and
`chrome.loadTimes`, defined as Chrome's renderer defines them, which Google's sign-in reads. The
thirtieth is Qt's own fix to the engine's build, so that it links where Qt has GLX and the engine is
built without X11, as this one is. The thirty-first adds `QWebEngineDevToolsSession`, a DevTools
protocol session of one page whose client is not trusted, so it cannot list, open or reach any other
page or the browser. It reaches only the children its page's auto-attach brings: frames, dedicated
workers and the service worker whose scope holds the page. The thirty-second adds
`QWebEngineExtensionManager::setSelectedPage`, through which the application says which of its tabs
the reader is using, so an extension asking for the active tab is answered with that page rather
than with the last page on show. The last adds a fifth algorithm to Chromium's forced dark mode,
chosen with `--dark-mode-settings=InversionAlgorithm=4`, which maps each colour by the role it is
drawn in, toward a ground colour and a text colour, after Dark Reader's colour functions (MIT
licensed), and `QWebEngineSettings::setForceDarkModeGroundColor` and `setForceDarkModeTextColor`
with their Qt Quick properties, through which the application gives each page those two colours.

On x86_64 the engine is built with clang and LLD, with ThinLTO and Chrome's own PGO profile for its
Chromium, where Qt's build would use GCC. On aarch64 it is built with GCC, as Qt's is.
`toolchain/clang.patch` opens the clang build in Qt's build files, `cmake/QtToolchainHelpers.cmake`
and `src/core/CMakeLists.txt`, and edits Chromium's `v8/BUILD.gn`: where V8's builtins profile no
longer fits a builtin, V8's snapshot step builds that builtin without it instead of stopping. It
also links `QtWebEngineCore` with ThinLTO's optimizations, `--lto-O2`, as Chrome's own targets are
linked, in `src/core/configure/BUILD.root.gn.in`. It changes how the engine is compiled, not what
its code does. `toolchain/gcc.patch` edits Chromium's `build/config/compiler/BUILD.gn` so that a
GCC build compiles without fused multiply-adds, `-ffp-contract=off`, as Chromium's clang build
does. `scripts/engine-toolchain.sh` names the toolchain each architecture is built with.

QtWebEngine 6.140.0 versions its modules after the engine rather than after the Qt it is built
against, so its libraries, headers and CMake package say 6.140.0 on any Qt.
`toolchain/module-version.patch` did the same for the engines before it, and is not applied to this
one.

Each patch is a single commit with its own message explaining what it changes and why. They are in
`patches/` in the repository named as this package's URL, and `README.md` there lists them one by
one.

## Corresponding source

The base is the released source tarball, which carries the Chromium tree it builds under
`src/3rdparty`:

```text
https://download.qt.io/official_releases/qtwebengine/6.140/6.140.0/src/qtwebengine-everywhere-src-6.140.0.tar.xz
```

`scripts/refresh.sh 6.140.0` fetches that tarball, unpacks it, commits it under the tag
`v6.140.0-tarball` and applies the series on top, so the modification is a range of commits rather
than a description of one. `scripts/build-inside.sh` is the build.

## Replacing this engine

The engine stays a shared library, separate from the application that loads it, at
`/usr/lib/omaweb/lib`. A different build of the same version can be put there instead, which is
what LGPL-3.0 section 4 asks for.

## Notices

`chromium-LICENSE.txt` is Chromium's own notice, taken verbatim from the tree this engine is built
from. `LGPL-3.0-only.txt` is the licence QtWebEngine's own code is under. Both are fetched from
Qt's repositories by `scripts/fetch-licenses.sh` rather than written by hand.

Patch 0033's colour mappings are adapted from Dark Reader, which is under the MIT licence. Its
notice is carried beside them, in `dark_mode_color_filter.cc`.

Chromium's own third party components carry their notices in the source tarball, under
`src/3rdparty/chromium/third_party/*/LICENSE`. This package does not restate them, and generating a
consolidated credits document from the tree is not done yet.
