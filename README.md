# QtWebEngine extension patches

Patches that let QtWebEngine host a password manager's Chromium extension. They are proposed
upstream rather than maintained as a fork: nothing patched is distributed, and this series exists to
be submitted, rebased, and eventually deleted when Qt carries the same work.

Written for [omaweb#344](https://github.com/villekivela/omaweb/issues/344), which asks whether
Omaweb can host Bitwarden and 1Password as Known extensions. The findings are recorded in
`docs/research/password-manager-extensions.md` in that repository.

Base: `qtwebengine-everywhere-src-6.11.1`, the released tarball.

## The series

| Patch | What it does | Upstream shape |
| --- | --- | --- |
| 0001 | Binds `EventRouter` and `RendererHost` for a render process, a render frame and a service worker. Without the worker binding an extension that calls `chrome.i18n.getMessage` at the top of its service worker never finishes evaluating; without the frame binding an extension page never receives an event its worker did. | A bug fix with a test. Submit as-is. |
| 0002 | Defines the pure-computation seatbelt profile name, which the macOS 26 SDK dropped. | A local build fix, not part of the series. Do not submit. |
| 0003 | Re-points `ExtensionPrefs` when a profile's `PrefService` is rebuilt, instead of replacing the instance other keyed services already cached. Fixes a crash in `setExtensionEnabled` after the storage path changes. | A bug fix with a test. Submit as-is. |
| 0004 | Compiles Chrome's schemas for `tabs`, `windows`, `permissions`, `webNavigation`, `commands`, `contextMenus`, `privacy`, `action` and `extension`, and implements the read side of `tabs` and `windows` on a tab registry behind an embedder delegate. | A feature. Needs a public API before submission, see below. |
| 0005 | Compiles Chrome's `scripting` API, which reaches a tab through the delegate above. | Follows 0004. |
| 0006 | Compiles Chrome's native messaging host manifest parser, process launcher and port dispatcher, and looks a manifest up through QtWebEngine path keys of its own. | Follows 0004. |

## The open design question

`TabsDelegateQt` is internal, and `ExtensionsBrowserClientQt` fills it by walking the profile's
adapter clients and treating every page as a tab. That is a guess about what a tab is, which is
fine for a prototype and not fine for Qt. Before 0004 can be proposed, the application has to be
able to say which of its pages are tabs and which one is active, through public API. Raise that on
QTBUG before writing code.

## Applying them

```sh
curl -O https://download.qt.io/official_releases/qt/6.11/6.11.1/submodules/qtwebengine-everywhere-src-6.11.1.tar.xz
tar xJf qtwebengine-everywhere-src-6.11.1.tar.xz
cd qtwebengine-everywhere-src-6.11.1
git init && git add -A && git commit -qm "qtwebengine 6.11.1" && git tag v6.11.1-tarball
git am /path/to/patches/*.patch
```

Building needs a Python environment with `html5lib`, and on macOS the Metal toolchain
(`xcodebuild -downloadComponent MetalToolchain`):

```sh
cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt \
  -DQT_NO_APPLE_SDK_AND_XCODE_CHECK=ON -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DQT_BUILD_TESTS=ON -DQT_BUILD_TESTS_BATCHED=OFF
cmake --build build
```

A first build is hours. Afterwards:

```sh
DYLD_FRAMEWORK_PATH=$PWD/build/lib ./build/tests/auto/widgets/extensions/tst_qwebengineextension
```

22 tests pass with the series applied. Four of them fail against a stock build, which is the point
of them: `serviceWorkerLocalization`, `enableAfterStoragePathChange`, `tabsWindowsAndScripting` and
`nativeMessaging`.

## Rebasing onto a new Qt release

The measurement that decides whether this series is maintainable. For each new tag: unpack it, apply
the series, build, run the tests, then run the
[extension probe](https://github.com/villekivela/omaweb-extension-probe) against a real extension.
Record what a conflict cost in people's time rather than machine time.

| Release | Patches applying | Build | Tests | People's time |
| --- | --- | --- | --- | --- |
| 6.11.2 | 6 of 6, no conflicts, no fuzz | clean | 22 of 22 | none |

One caveat about that row. 6.11.1 and 6.11.2 share a Chromium base, so nothing the copied Chrome
files depend on moved. Patches 0005 and 0006 carry copies of `scripting_api.cc` and the native
messaging stack, and a Chromium major bump means re-copying them from the new Chromium and adapting
them again. Qt's `dev` is still on the 140-based fork and a 146-based branch exists, so that bump
lands in 6.12 or 6.13. Until the series has been through one, the cost of a rebase is unmeasured.

## Licence

The patches contain Qt WebEngine and Chromium source and are derivative works of them: Qt files are
LGPL-3.0 / GPL-2.0 / GPL-3.0 or the Qt commercial licence, Chromium files are BSD-3-Clause. Each
file keeps the headers it arrived with. Nothing here is under Omaweb's own licence.
