# A modified QtWebEngine

This package is not Qt's build of QtWebEngine 6.11.2. It is that release with a patch series
applied, and it installs into `/usr/lib/omaweb` so that the distribution's `qt6-webengine` stays
where it is and every other Qt application on the machine keeps the engine it had.

LGPL-3.0 asks a modified build to say that it is modified and to carry the notices. That is what
this file is for.

## What changed

Eighteen patches, applied in order to the released source. Fourteen add the part of Chromium's
extension runtime that QtWebEngine compiles out: renderer bindings, the `tabs`, `windows`,
`permissions`, `scripting`, `notifications` and `webNavigation` namespaces behind an embedder
delegate, native messaging, and web accessible resources. Five of those are bug fixes in Qt's own
code rather than additions. The fifteenth restores Perfetto's `track_event_macros.h` to the version
Chromium ships, which Qt's copy changes. The sixteenth lets a request interceptor ask for the DNS
aliases of a request's host, and the seventeenth reports the certificate chain a page arrived over
on `QWebEngineLoadingInfo`. The eighteenth turns V8's write barriers back on, which Qt's 6.11.2
build turns off and its 6.140.0 turns on again.

On x86_64 the engine is built with clang and LLD, with ThinLTO and Chrome's own PGO profile for its
Chromium, where Qt's build would use GCC. On aarch64 it is built with GCC, as Qt's is.
`toolchain/clang.patch` opens the clang build in Qt's build files, `cmake/QtToolchainHelpers.cmake`
and `src/core/CMakeLists.txt`. Where V8's builtins profile no longer fits a builtin, the patch has
V8's snapshot step build that builtin without it instead of stopping. It changes how the engine is
compiled, not what its code does. `scripts/engine-toolchain.sh` names the toolchain each architecture is built with.

Each patch is a single commit with its own message explaining what it changes and why. They are in
`patches/` in the repository named as this package's URL, and `README.md` there lists them one by
one.

## Corresponding source

The base is the released source tarball, which carries the Chromium tree it builds under
`src/3rdparty`:

```text
https://download.qt.io/official_releases/qt/6.11/6.11.2/submodules/qtwebengine-everywhere-src-6.11.2.tar.xz
```

`scripts/refresh.sh 6.11.2` fetches that tarball, unpacks it, commits it under the tag
`v6.11.2-tarball` and applies the series on top, so the modification is a range of commits rather
than a description of one. `scripts/build-inside.sh` is the build.

## Replacing this engine

The engine stays a shared library, separate from the application that loads it, at
`/usr/lib/omaweb/lib`. A different build of the same version can be put there instead, which is
what LGPL-3.0 section 4 asks for.

## Notices

`chromium-LICENSE.txt` is Chromium's own notice, taken verbatim from the tree this engine is built
from. `LGPL-3.0-only.txt` is the licence QtWebEngine's own code is under. Both are fetched from
Qt's repositories by `scripts/fetch-licenses.sh` rather than written by hand.

Chromium's own third party components carry their notices in the source tarball, under
`src/3rdparty/chromium/third_party/*/LICENSE`. This package does not restate them, and generating a
consolidated credits document from the tree is not done yet.
