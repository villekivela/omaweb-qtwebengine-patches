# QtWebEngine extension patches

Eleven patches that let QtWebEngine host a password manager's Chromium extension. Base is the
released `qtwebengine-everywhere-src-6.11.2` tarball.

Built for [omaweb#344](https://github.com/villekivela/omaweb/issues/344), which asks whether Omaweb
can host Bitwarden and 1Password. The findings live in `docs/research/password-manager-extensions.md`
in that repository.

Two of the eleven are ordinary bug fixes headed for Gerrit. The rest wait on one question to Qt, in
`upstream/QTBUG-draft.md`. If Qt takes the work, this repository is deleted rather than maintained.

## Running it

```sh
scripts/refresh.sh 6.12.0     # fetch, unpack, apply the series, configure
<tree>/build.sh               # hours
scripts/verify.sh <tree>      # tests, twice
```

`PROCESS.md` has the rest, including what to do when a patch conflicts and what a Chromium bump
costs.

## The series

**0001, bind EventRouter and RendererHost.** A renderer reaches the browser through three
registries. Qt serves none of them fully, so an extension that calls `chrome.i18n.getMessage` from
its service worker hangs forever, and an extension page never receives events its own worker gets.
_A bug fix with a test. Submit as is._

**0002, define the pure-computation seatbelt profile name.** The macOS 26 SDK dropped the constant.
_A local build fix. Not part of the series, do not submit._

**0003, keep ExtensionPrefs valid when the PrefService is rebuilt.** Changing a profile's storage
path replaces the pref service. Qt replaces the `ExtensionPrefs` instance too, while other keyed
services keep the pointer they cached, and `setExtensionEnabled` then crashes. _A bug fix with a
test. Submit as is._

**0004, offer the tabs, windows, permissions and event namespaces.** Compiles Chrome's schemas with
the unimplemented functions marked `nocompile`, and implements the read side of `tabs` and `windows`
on a tab registry behind an embedder delegate. _A feature. Needs public API first, see below._

**0005, offer the scripting namespace.** Chrome's `scripting_api.cc` compiles with two include paths
changed. It reaches a tab through the delegate from 0004. _Follows 0004._

**0006, connect an extension to a native messaging host.** Chrome's host manifest parser, process
launcher and port dispatcher, with the manifest looked up through QtWebEngine path keys. _Follows
0004._

**0007, let an extension ask the application to open a page.** `tabs.create` and `windows.create`
arrive where a page's own `window.open()` arrives, so the application decides what opening a page
means. Bitwarden reaches this when its popup asks to open in a window of its own, which is how it
shows its settings: it has no options page, only routes inside the popup document. _Follows 0004._

**0008, test the order a reader actually takes.** The browser is open, a page is up, and then an
extension is turned on. Every earlier case loads an extension into a profile running nothing. _Tests
only._

**0009, answer webNavigation.getFrame and getAllFrames.** A password manager's worker registers its
listener inside asynchronous set-up, so the first page's message is dropped, in Chrome as here; the
worker then reaches back into every frame of every open tab, and that needs `getAllFrames`. Answered
off the tab registry and the frame's own state, without Chrome's tab-strip observer. The events stay
declared and unraised. _Follows 0004._

**0010, keep a running extension working when its path is loaded again.** Loading a loaded path sent
the extension round as a reload, which disabled it and handed the reload to an empty delegate: the
worker went and never came back. _A bug fix with a test. Submit as is._

**0011, let an extension document close its own window.** A popup that routes by hash cannot close
itself, because Blink only lets a page close a window it opened. Chrome exempts extension documents
in a file QtWebEngine does not build. _A bug fix with a test. Submit as is._

## The open question

`TabsDelegateQt` is internal, and `ExtensionsBrowserClientQt` fills it by treating every page of the
profile as a tab. That guess is fine for a prototype and wrong for Qt: the extension's own popup
turns up in `tabs.query()`.

Before 0004 can be proposed, an application needs a way to say which of its pages are tabs and which
one is active. That is what the QTBUG draft asks for. Ask before writing the API.

## Tests

30 tests pass with the series applied. Five of them fail on a stock build, which is why they are
worth having:

- `serviceWorkerLocalization` fails
- `enableAfterStoragePathChange` crashes, signal 11
- `tabsWindowsAndScripting` fails
- `nativeMessaging` fails
- `anExtensionOpensAPage` fails

`scripts/verify.sh` runs both halves and reports them.

## Rebase record

| Release | Applying | Build | Tests | People's time |
| ------- | -------- | ----- | ----- | ------------- |
| 6.11.2  | 6 of 6, no conflicts | clean | 22 of 22 | none |

The series has grown a patch since that row, so the next release is the next measurement.

That row is the easy case. 6.11.1 and 6.11.2 share a Chromium base, so nothing under patches 0005
and 0006 moved.

The expensive case is a Chromium bump, measured across 140 to 146, six major versions apart:

- the copied Chrome files moved 4 to 13 lines each, so re-copying them is mechanical
- patch 0003 lost two of the six calls it makes, because those migrations finished upstream
- all five embedder hooks the design rests on survived, with the same names

Call it an hour. Qt's `dev` is still on the 140-based fork, so the real bump lands in 6.12 or 6.13.

## Licence

The patches carry Qt WebEngine and Chromium source and are derivative works of both. Qt files are
LGPL-3.0, GPL-2.0, GPL-3.0 or the Qt commercial licence. Chromium files are BSD-3-Clause. Every file
keeps the headers it arrived with, and nothing here is under Omaweb's licence.
