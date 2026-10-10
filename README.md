# QtWebEngine extension patches

Twenty-one patches to QtWebEngine. Fifteen let it host a password manager's Chromium extension, two
add API that Omaweb's content blocking and certificate view ask for, one restores a trace macro that
slowed every page, one turns V8's write barriers back on, one keeps an offscreen document from
crashing the engine, and one builds the tests against Qt 6.12. Base is the released
`qtwebengine-everywhere-src-6.11.2` tarball.

Built for [omaweb#344](https://github.com/villekivela/omaweb/issues/344), which asks whether Omaweb
can host Bitwarden and 1Password. The findings live in `docs/research/password-manager-extensions.md`
in that repository.

Seven of the twenty-one are ordinary bug fixes headed for Gerrit, and 0018 and 0020 are Qt's own
changes. The rest wait on one question to Qt, in `upstream/QTBUG-draft.md`. If Qt takes the work,
this repository is deleted rather than maintained.

## Running it

```sh
scripts/refresh.sh 6.140.0    # fetch, unpack, apply the series, configure
<tree>/build.sh               # hours
scripts/verify.sh <tree>      # tests, twice
scripts/package-locally.sh 6.140.0  # package here, sign here
```

x86_64 is built with clang, LLD and ThinLTO and Chrome's PGO profile, aarch64 with GCC.
`build-inside.sh`, which the local and rented builds run, takes that default from
`scripts/engine-toolchain.sh`. `refresh.sh` run by hand configures Qt's own choice, GCC, unless
`OMAWEB_ENGINE_TOOLCHAIN=clang` is set. `toolchain/README.md` says why and how.

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

**0012, offer the notifications namespace.** 1Password registers `notifications.onClicked` at the top
level of its worker, so without the namespace the worker throws on its first line and never starts.
A notification goes to the application the way a page's does, and the reader's answer comes back as
`onClicked` and `onClosed`. _A feature. Follows 0004._

**0013, answer every function the schemas declare.** A function a schema declares and nothing
registers throws where the extension called it, so twenty-one of them did. `action` and
`contextMenus` keep what an extension asks the chrome to show and answer with it; `commands.getAll`
reports the manifest's. _A feature. Follows 0004._

**0014, serve a web accessible resource to a page.** QtWebEngine kept its own copy of the renderer's
resource policy, from before the base class had one, and nothing ever told that copy which
extensions had loaded. Every request for a web accessible resource was rewritten to
`chrome-extension://invalid/`. It stops any extension that declares a small content script and
imports its real bundle. A second test holds the other half: a resource declared with
`use_dynamic_url` stays unreachable at its fixed URL. _A bug fix with a test. Submit as is._

**0015, look up a trace category at compile time again.** Qt's copy of Perfetto drops the
`constexpr` variable that forces a trace point's category index to be computed while compiling, so
clang left the lookup to run on every call: a string search through 275 categories, with tracing
off, behind every `TRACE_EVENT`. Blink puts one on each canvas 2D call, and Speedometer 3.1 in a
bare `WebEngineView` went from 25.5 to 33.9. The header is Chromium 140's, unchanged. See
[omaweb#355](https://github.com/villekivela/omaweb/issues/355). _A bug fix, for
[QTBUG-149450](https://qt-project.atlassian.net/browse/QTBUG-149450). The Windows build needs a
form MSVC accepts._

**0016, let a request interceptor ask for the host's DNS aliases.** A tracker served from a
subdomain of the page's own site, with a CNAME pointing at the tracker's real host, never shows the
tracker's name to an interceptor. `QWebEngineUrlRequestInfo::requestDnsAliases()` asks for them:
the host is resolved through the profile's own network context and host cache, and the interceptor
is called once more with `dnsAliases()`, the names in the host's CNAME chain. No lookup is made for a main-frame
navigation, an IP address, or behind a proxy, and a profile remembers each host's answer for a
minute, so a page's later requests to that host wait for nothing. Qt runs Chromium's own DNS client
only under secure DNS, so that is where the whole chain comes back; through the system resolver the
lookup asks for the canonical name and gets the chain's last name only.
`scripts/check-real-dns.sh <tree>` asks real public hosts under both modes, which the gate cannot
because it has no DNS server and no internet. This is the one patch that is not about extensions,
and Omaweb's content blocking is what asks. See
[omaweb#354](https://github.com/villekivela/omaweb/issues/354) and ADR 0050. _A feature with tests,
written as Qt API. Propose it as one._

**0017, report the certificate chain a page arrived over.** A certificate failure carries the chain
it was raised for, and a page whose certificate verified raises nothing, so an application has no
way to show the reader the certificate of the page on show. `QWebEngineLoadingInfo::certificateChain()`
returns it for a finished main-frame load: the chain Chromium's verifier built, from the server's
certificate to the trust anchor, taken from the navigation's SSL info as the response headers are.
A load that made no TLS connection carries none. See
[omaweb#325](https://github.com/villekivela/omaweb/issues/325) and ADR 0054. _A feature with tests,
written as Qt API. Propose it as one._

**0018, turn V8's write barriers back on.** Qt's 6.11.2 builds V8 with `v8_disable_write_barriers =
true`, which also gives it a single generation. Every allocation goes to the old space, and the
collector can neither scavenge nor mark incrementally. Qt restored Chromium's default in
qtwebengine-chromium 770837 and 772657, which 6.140.0 carries, and 0018 is the two as one backport,
with their Change-Ids and bug numbers. On aarch64 it took JetStream 2.2 from 0.742 to 0.947 of
Chromium 140's score. On x86_64, turning them on by hand had taken it from 0.718 to 0.917. See
[omaweb#574](https://github.com/villekivela/omaweb/issues/574) and
[omaweb#356](https://github.com/villekivela/omaweb/issues/356). _Qt's change. It drops when the
series moves to 6.140.0._

**0019, let an extension create an offscreen document.** `chrome.offscreen.createDocument` crashed
the engine every time. An offscreen document lives in contents the extension system creates itself,
so its views have no delegate, and `RenderWidgetHostViewQt::Hide()` dereferenced the missing one
when Chromium hid the document's first speculative frame. `Hide()` now handles a missing delegate as
`ShowWithVisibility()` already did, and `IsShowing()` answers false. Bitwarden makes one, and the
browser crashed on resume from suspend because of it
([omaweb#646](https://github.com/villekivela/omaweb/issues/646)). _A bug fix with a test. Send it to
Gerrit; `upstream/bug-reports.md` has the report._

**0020, build the widget tests against Qt 6.12.** Qt 6.12 removed `QTEST_DISABLE_KEYPAD_NAVIGATION`,
which did nothing, so `W_QTEST_MAIN` stopped compiling and took every widget test program with it,
the extension tests the gate runs among them. Engine 6.11.2-6 was built against Qt 6.12, as Arch
builds its own ([omaweb#660](https://github.com/villekivela/omaweb/issues/660)), and the series keeps
building on 6.11.2, which readers have
([omaweb#674](https://github.com/villekivela/omaweb/issues/674)). Qt removed the same line in
qtwebengine c9300848e28e for QTBUG-147006, and 0020 is that change backported with its Change-Id. It
touches only the tests, so the engine a reader installs is the same with or without it. _Qt's change.
It drops when the series moves to 6.140.0._

**0021, report where a window is, as the application says.** `chrome.windows` answered with one
window carrying no `left`, `top`, `width` or `height`, and Chrome always reports all four. Bitwarden
places its passkey prompt at `window.left + window.width - popupWidth - 15`, which without them is
`NaN`, and the schema refuses the `windows.create` that follows. Only the application knows where
the window holding a page is, so `QWebEngineExtensionManager::setWindowGeometryProvider` lets it
say: the engine calls it with the page the call came from, or with null for a worker's call, and
puts the answer in every window it reports, `windows.create`'s and populated ones included. Without
a provider the window is at `0, 0` with the size of the asking view. See
[omaweb#684](https://github.com/villekivela/omaweb/issues/684) and ADR 0064. _Part of the tab model
the open question below is about. Propose it with 0004._

## The open question

`TabsDelegateQt` is internal, and `ExtensionsBrowserClientQt` fills it by treating every page of the
profile as a tab. That guess is fine for a prototype and wrong for Qt: the extension's own popup
turns up in `tabs.query()`.

Before 0004 can be proposed, an application needs a way to say which of its pages are tabs and which
one is active. That is what the QTBUG draft asks for. Ask before writing the API.

## Tests

39 tests pass with the series applied. Six of them fail on a stock build, which is why they are
worth having:

- `serviceWorkerLocalization` fails
- `enableAfterStoragePathChange` crashes, signal 11
- `tabsWindowsAndScripting` fails
- `nativeMessaging` fails
- `anExtensionOpensAPage` fails
- `anOffscreenDocumentCanBeCreated` crashes, signal 11

Patch 0016's eight cases live in Qt's own `tst_qwebengineurlrequestinterceptor`, and the gate runs
only those, beside the extension tests. Patch 0017's case lives in Qt's `tst_certificateerror`, which
has the test server's certificate, and the gate runs it the same way. `scripts/verify.sh` runs all
three and reports them. Neither compiles against a stock build, which has no API for them to call,
so there is no stock run to compare: removing the line that keeps the chain fails 0017's case.
Patch 0021's two cases, `aWindowIsWhereTheApplicationSaysItIs` and
`withoutAnAnswerAWindowIsWhereItsViewIs`, are in the extension tests and do not compile without the
patch either. Taking the four numbers out of `windows_api.cc` fails both.

Patch 0018 has no test case, because what it changes is how V8 is compiled. The gate reads that
instead. `scripts/check-write-barriers.sh` fails a tree whose V8 is compiled with
`-DV8_DISABLE_WRITE_BARRIERS`, as 6.11.2 is without the patch, and names the ninja file it read. It
stays after 0018 drops, so a later Qt that turns the barriers off again is noticed.

## Rebase record

| Release | Applying | Build | Tests | People's time |
| ------- | -------- | ----- | ----- | ------------- |
| 6.11.2  | 6 of 6, no conflicts | clean | 22 of 22 | none |
| 6.11.2, series grown to 9 | 2 more, no conflicts | incremental | 28 of 28 | none |
| 6.11.2, series grown to 12 | 3 more, no conflicts | incremental | 33 of 33 | none |
| 6.11.2, series grown to 18 | 1 more, no conflicts | incremental | 50 of 50 | none |
| 6.11.2-5, rebuilt for speed | already applied | incremental | 50 of 50 | none |
| 6.11.2-6, on Qt 6.12, series grown to 20 | 19 already applied, 1 more, no conflicts | incremental | 51 of 51 | minutes: 0020, after the tests did not build |
| 6.11.2-8, series grown to 21 | 20 already applied, 1 more, no conflicts | incremental | 53 of 53 | none |

The rows after the first are the series growing, and the last is the same series rebuilt with each
architecture's toolchain and published as 6.11.2-5 (omaweb#576), rather than Qt moving. They
measure `refresh.sh` picking up a tree it has already patched rather than a rebase. The next
release is the next real measurement.

6.11.2-6 is the first time Qt moved a minor under the series: the same engine rebuilt against Qt
6.12, with 0019 for omaweb#646 (omaweb#660). The x86_64 build applied 19 patches to a fresh tarball
and compiled the engine clean, then stopped where the tests compile, because Qt 6.12 removed
`QTEST_DISABLE_KEYPAD_NAVIGATION`. 0020 is Qt's own one-line removal, and the row is the run that
added it to that tree. aarch64 was built on the Mac from the same commit, `32be1d7`, against Arch
Linux ARM's Qt 6.11.2, and its gate read the same: 37 of 37, 10 of 10, 3 of 3 and 1 of 1.

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
