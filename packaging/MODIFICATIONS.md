# A modified QtWebEngine

This package is not Qt's build of QtWebEngine 6.11.2. It is that release with a patch series
applied, and it installs into `/usr/lib/omaweb` so that the distribution's `qt6-webengine` stays
where it is and every other Qt application on the machine keeps the engine it had.

LGPL-3.0 asks a modified build to say that it is modified and to carry the notices. That is what
this file is for.

## What changed

Fourteen patches, applied in order to the released source. What they add is the part of Chromium's
extension runtime that QtWebEngine compiles out: renderer bindings, the `tabs`, `windows`,
`permissions`, `scripting`, `notifications` and `webNavigation` namespaces behind an embedder
delegate, native messaging, and web accessible resources. Five of them are bug fixes in Qt's own
code rather than additions.

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
