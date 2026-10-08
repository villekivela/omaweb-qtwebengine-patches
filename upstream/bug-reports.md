# Six defect reports

All six reproduce on a stock build and each comes with a test that fails without the fix. File
separately from the tab-delegate suggestion in `QTBUG-draft.md`, which asks for new API and is a
different conversation.

Fixes go to Gerrit against `dev` with `Pick-to: 6.140`. From Qt 6.12, QtWebEngine is released on
its own and versioned after its Chromium, so 6.140 is its first series, on Chromium 140. `6.140` is
that series' branch and becomes 6.140.1 and later. The 6.140.0 release itself comes from `6.140.0`,
which split from `6.140` on 2026-09-08, and a pick to `6.140` does not reach it.

Four touch `qtwebengine` alone and can go up in any order. The `ExtensionPrefs` crash also needs a
change in `qtwebengine-chromium`, so it is two changes with a dependency and is worth sending last,
once the others have shown the reviewers what this is about.

The first five are filed. Four are on Gerrit, and two of those have merged into `dev` and been picked to
`6.140`. The fifth waits on an answer about where its fix belongs. The patches whose change has
merged stay in the series until Omaweb's engine is built on a Qt release that carries them, which
is 6.140.1 at the earliest. Where each stands in 6.140 is below the table.

| Order | Patch | Report | Change | Status | What it is |
| ----- | ----- | ------ | ------ | ------ | ---------- |
| 1 | 0014 | [QTBUG-150590](https://bugreports.qt.io/browse/QTBUG-150590) | [772845](https://codereview.qt-project.org/c/qt/qtwebengine/+/772845) | merged | A page cannot load a web accessible resource |
| 2 | 0001 | [QTBUG-150591](https://bugreports.qt.io/browse/QTBUG-150591) | [772848](https://codereview.qt-project.org/c/qt/qtwebengine/+/772848) | merged | A localising service worker hangs forever |
| 3 | 0010 | [QTBUG-150592](https://bugreports.qt.io/browse/QTBUG-150592) | [772849](https://codereview.qt-project.org/c/qt/qtwebengine/+/772849) | in review | Loading a loaded extension leaves it dead |
| 4 | 0011 | [QTBUG-150593](https://bugreports.qt.io/browse/QTBUG-150593) | [772850](https://codereview.qt-project.org/c/qt/qtwebengine/+/772850) | in review | An extension document cannot close its own window |
| 5 | 0003 | [QTBUG-150594](https://bugreports.qt.io/browse/QTBUG-150594) | waiting | – | `setExtensionEnabled` crashes after a storage path change |
| 6 | 0019 | not filed | not pushed | – | Creating an offscreen document crashes the browser |

Each change carries `Fixes: QTBUG-…` and `Pick-to: 6.140`. Two more changes follow the first report:

- [773048](https://codereview.qt-project.org/c/qt/qtwebengine/+/773048), merged, removes the renderer
  resource policy that 772845 left with no users.
- [773908](https://codereview.qt-project.org/c/qt/qtwebengine/+/773908), in review, is the test that
  a `use_dynamic_url` resource stays unreachable at its fixed URL, which patch 0014 carries too. It
  uses `Task-number: QTBUG-150590`, because it tests that fix rather than fixing anything.

## Where each change stands in 6.140

Checked on 2026-10-05. The series' first 17 patches carry no Change-Id, so the merged ones were
matched by their reports and changes, and compared line by line. For the rest, the series was
applied in order to each tree, and every upstream commit since the RC that touches a file the series
touches was listed. Nothing else of the series is upstream.

| Patch | Upstream | 6.140.0-rc | `6.140.0` | `6.140` | `dev` |
| ----- | -------- | ---------- | --------- | ------- | ----- |
| 0001 | 772848: `dev` `85c4b70af`, `6.140` `4f674b4e8` (change 773404) | no | no | yes | yes |
| 0002 | qtwebengine-chromium 772104, in another form | no | yes | yes | yes |
| 0010 | 772849, in review | no | no | no | no |
| 0011 | 772850, in review | no | no | no | no |
| 0014 | 772845: `dev` `182770309`, `6.140` `1aa9958ff` (change 773151) | no | no | yes | yes |
| 0014 follow-up | 773048: `dev` `7bc989efe` | no | no | no | yes |
| 0018 | qtwebengine-chromium 770837 and 772657, through the pin to `1e645e7ec` | no | yes | yes | yes |

The rest, 0003 to 0009, 0012, 0013 and 0015 to 0017, are in none of them. 0018 carries the
Change-Ids of the two changes it backports.

- **0001 and 0014** merged on 2026-09-22 and were picked to `6.140` the same day and the next. The
  RC is tagged on `6.140.0`, which split from `6.140` before the picks, so both still applied to it.
  Their source changes are the series' own, line for line. Only the tests differ. 0001's upstream
  test has `QVERIFY2` with the extension's error where the patch has `QVERIFY`. 0014's upstream
  test leaves out the dynamic URL case, which is 773908. Neither is picked to `6.140.0`, so the
  final 6.140.0 still needs both patches, and they drop at 6.140.1.
- **0002** was never sent: it is a local build fix for the macOS 26 SDK, which removed
  `kSBXProfilePureComputation`. qtwebengine-chromium 772104, "[Backport] Fix macOS 27 build of
  `chrome` target" on `140-based`, merged 2026-09-18, removes the `kProfilePureComputation` member
  and its uses outright. It reached `6.140.0`, `6.140` and `dev` with a Chromium update after the
  RC, where 0002 no longer applies. It drops when the final 6.140.0 is qualified.

- **0018** is Qt's own: qtwebengine-chromium 770837 and 772657 on `140-based`, merged on 2026-09-14
  and 2026-09-21, which set `v8_disable_write_barriers` back to Chromium's default. It was
  backported for [omaweb#574](https://github.com/villekivela/omaweb/issues/574) and sent nowhere.
  The RC's tarball still has `true`. `6.140.0`, `6.140` and `dev` pin qtwebengine-chromium
  `1e645e7ec`, where it is `false`, so 0018 no longer applies to the final 6.140.0 and drops when it
  is qualified.

Patch 0015 answers a report someone else had already filed, so it went there as a comment rather
than a sixth report. [QTBUG-149450](https://qt-project.atlassian.net/browse/QTBUG-149450) measures
the same Speedometer 3.1 gap on Windows, and the comment names qtwebengine-chromium `baf701b9fb74`
as the cause, with the macOS numbers. Its fix goes to `qtwebengine-chromium`, not `qtwebengine`.
The report is on Windows, where the removed line was an MSVC workaround, so what MSVC accepts has
to be settled before a change is proposed.

GCC folds the lookup without the patch, which the disassembly of this repository's own package
shows, so the engine it ships gains nothing from 0015. A second comment on the report said so, with
a Speedometer before and after from the Omarchy VM. That before and after ran on Arch's engine, not
this one, because the released Omaweb did not load `/usr/lib/omaweb` yet, so it measured nothing
about 0015. A third comment corrects it. With the host idle, this repository's engine scores 22.7,
Arch's 22.5, and Chromium 153 24.5 on the same machine. The details are on
[omaweb#355](https://github.com/villekivela/omaweb/issues/355) and
[omaweb#356](https://github.com/villekivela/omaweb/issues/356). The patch stays, because it is the
code Chromium ships and it keeps a clang build of the engine off the slow path.

Qt builds nothing until a change has a +2 and someone stages it. The Sanity Bot runs on upload and
checks style only; it caught a missing trailing newline in a fixture. So the first real build of
these happens after a reviewer has already read them, which is the argument for the changes being
small and for reusing the fixtures the test directory already has.

None of the four has been compiled against `dev`. Five of the six source files they touch are
byte-identical between 6.11.2 and `dev`, and the sixth differs by fourteen lines in functions none
of this goes near, so the risk sits in the tests rather than the code. Changes 3 and 4 use only
fixtures and helpers `dev`'s own tests already use. Change 1 is the one that links the HTTP server
into that test directory for the first time.

---

## 1. A page cannot load a web accessible resource

**Type:** Bug **Component:** WebEngine **Affects:** 6.10, 6.11.2, dev

This is the one worth reading first. It is small, and it stops a whole class of extension working.

### Symptom

An ordinary page cannot load a resource an extension declares in `web_accessible_resources`, by
`fetch`, as an image, or as a script. The request never arrives as itself: the browser is asked for
`chrome-extension://invalid/`.

### Reproduce

Extension declaring `{"resources": ["shared.txt"], "matches": ["<all_urls>"]}`. From any http page:

```js
fetch("chrome-extension://<id>/shared.txt")   // rejects
```

Test: `tst_qwebengineextension::aPageCanLoadAWebAccessibleResource`, covering both `fetch` and a
`script` element.

### Cause

Two copies of the renderer's resource policy.

`ExtensionsRendererClient` owns a `ResourceRequestPolicy`, is told which extensions have loaded
through `OnExtensionLoaded`, and answers `WillSendRequest` from it.

`ExtensionsRendererClientQt` creates a second `ResourceRequestPolicyQt` of its own and overrides
`WillSendRequest` to use that one instead. Nothing ever calls `OnExtensionLoaded` on it, so its set
of ids with web accessible resources is permanently empty, `CanRequestResource` returns false for
every request, and the renderer rewrites the URL to `kExtensionInvalidRequestURL`. The Qt copy
appears to predate the base class owning one.

### Fix

Patch 0014 deletes the Qt copy and the override, so the base class answers. Its `WillSendRequest`
also takes `upstream_url`, which `ContentRendererClientQt::WillSendRequest` already receives and
currently drops, so a resource reached through a redirect becomes allowed by the extension that
redirected to it.

### Why it went unnoticed

It breaks a class of extension rather than an API. An extension whose scripts are all declared in
the manifest never notices. One that declares a small loader and imports its real bundle gets
nothing into the page at all, with no error naming the cause.

---

## 2. An extension whose service worker localises never starts

**Type:** Bug
**Component:** WebEngine
**Affects:** 6.10, 6.11.2, dev

### Symptom

The extension loads and enables. Its service worker never runs. At shutdown the log says "Service worker registration failed. Status code: 2".

### Reproduce

Unpacked Manifest V3 extension, `service_worker.js` starting with

```js
const greeting = chrome.i18n.getMessage("greeting");
```

and `_locales/en/messages.json` defining `greeting`. Enable it.

Test: `tst_qwebengineextension::serviceWorkerLocalization`.

### Cause

`chrome.i18n.getMessage()` is a synchronous call into the browser over `extensions::mojom::RendererHost`. QtWebEngine binds no receiver for it, so the worker thread waits forever inside script evaluation.

`ContentBrowserClientQt::ExposeInterfacesToRenderer` registers `extensions::mojom::EventRouter` and nothing else. Chrome registers `RendererStartupHelper::BindForRenderer` for `RendererHost` next to it.

A renderer reaches the browser through three registries. QtWebEngine serves none of them fully:

- render process: `EventRouter` only.
- render frame (`RegisterAssociatedInterfaceBindersForRenderFrameHost`): neither. This is a second
  bug behind the first. An extension page registers no event listener, so it never receives an event
  such as `storage.onChanged` that its own service worker receives.
- service worker: `ServiceWorkerHost` only.

Renderer stack while hung: `V8ScriptRunner::CompileAndRunScript` → `I18nHooksDelegate::HandleGetMessage` → `SharedL10nMap::GetMapForExtension` → `mojom::RendererHostProxy::GetMessageBundle` → `mojo::SyncHandleRegistry::Wait`.

### Fix

Patch 0001 registers `EventRouter` and
`RendererHost` at all three points, as `ChromeContentBrowserClient` does.

---

## 3. Loading an extension that is already loaded leaves it dead

**Type:** Bug **Component:** WebEngine **Affects:** 6.10, 6.11.2, dev

### Symptom

`loadExtension()` on a path that is already loaded reports success and the manager goes on listing
the extension as loaded. Its service worker has stopped, its popup has no `chrome` bindings, and it
stays that way until the application restarts.

### Reproduce

Load a path, enable it, let its worker run, then load the same path again.

Test: `tst_qwebengineextension::loadingTheSamePathTwiceLeavesOneWorkingExtension`.

### Cause

`ExtensionLoader::addExtension` sends an already-loaded id through
`ExtensionRegistrar::ReloadExtensionWithQuietFailure`. The registrar disables the extension with
`DISABLE_RELOAD` and asks its delegate to load it again. Both
`ExtensionLoader::LoadExtensionForReload` and `LoadExtensionForReloadWithQuietFailure` have empty
bodies, so nothing finishes the reload.

The existing `reloadExtension` test counts extensions and checks `isLoaded()`, both of which still
hold while the extension is disabled, which is why this was not caught.

### Fix

Patch 0010 treats the same path loaded again as the same extension updated in place, through
`ExtensionRegistrar::AddExtension`, and implements the two reload delegate methods so
`reloadExtension()` also finishes what it starts.

---

## 4. An extension document cannot close its own window

**Type:** Bug **Component:** WebEngine **Affects:** 6.10, 6.11.2, dev

### Symptom

`window.close()` from an extension page is refused with "Scripts may close only the windows that
were opened by them" once the document's history is longer than one entry.

### Reproduce

Open an extension's `actionPopupUrl()` in a `QWebEnginePage`, push a few history entries the way a
hash router does, then call `window.close()`. `windowCloseRequested` never arrives.

Test: `tst_qwebengineextension::aPopupMayCloseItselfAfterRoutingByHash`.

### Cause

Blink allows a page to close a window it did not open only while `BackForwardLength()` is 1. Chrome
exempts extension documents in `extensions/browser/extension_webkit_preferences.cc`:

```cpp
// Tabs aren't typically allowed to close windows. But extensions shouldn't be
// subject to that.
webkit_prefs->allow_scripts_to_close_windows = true;
```

That file is not among the extensions sources QtWebEngine builds, so nothing sets the preference and
every extension document is held to the ordinary rule. A password manager's popup routes by hash and
closes itself once it has filled a form, which is past one history entry within a click or two.

### Fix

Patch 0011 sets `allow_scripts_to_close_windows` in
`ContentBrowserClientQt::OverrideWebPreferences` for documents served from an enabled extension that
is not a hosted app, which is the condition Chrome applies.

---

## 5. setExtensionEnabled crashes after a profile's storage path changes

**Type:** Bug
**Component:** WebEngine
**Affects:** 6.10, 6.11.2, dev

### Symptom

Crash in `PrefService::GetPreferenceValue`, reached from `ExtensionPrefs::GetExtensionPref`, `blocklist_prefs::IsExtensionBlocklisted`, `ExtensionRegistrar::EnableExtension` and `QWebEngineExtensionManager::setExtensionEnabled`.

### Reproduce

```cpp
QWebEngineProfile profile("Test");
QWebEngineExtensionManager *manager = profile.extensionManager();
profile.setPersistentStoragePath(dir.path());       // rebuilds the PrefService
manager->loadExtension(path);                        // succeeds
manager->setExtensionEnabled(extension, true);       // crashes
```

Test: `tst_qwebengineextension::enableAfterStoragePathChange`.

This is the normal path for an application that sets a storage path after constructing the profile.
The QML `WebEngineProfile` type does exactly that.

### Cause

Changing a profile's storage name, off-the-record flag or storage path rebuilds its `PrefService`. `ProfileQt::setupPrefService` then builds a replacement `ExtensionPrefs` and installs it with `ExtensionPrefsFactory::SetInstanceForTesting`. `ExtensionRegistrar`, `EventRouter` and the other keyed services cached the old pointer at construction and keep using it. It points at a destroyed `PrefService`.

### Fix

Patch 0003 points the existing `ExtensionPrefs` at the new `PrefService` instead of replacing an
instance other services hold.

This one is two changes: `ExtensionPrefs::ResetPrefService` in `qtwebengine-chromium`, guarded by
`IS_QTWEBENGINE`, and the call from `ProfileQt::setupPrefService` in `qtwebengine`. If the reviewers
would rather not add a method to Chromium's `ExtensionPrefs`, the alternative is to rebuild the
keyed services that hold the pointer, which is a larger change and worth asking about rather than
guessing at.

---

## 6. Creating an offscreen document crashes the browser

**Type:** Bug **Component:** WebEngine **Affects:** 6.11.2, 6.140, dev

Small, and the one most readers would hit: every MV3 extension that uses `chrome.offscreen` takes
the browser down the first time it does. Bitwarden is one.

### Symptom

The browser process dies with SIGSEGV, a null read, as soon as an extension calls
`chrome.offscreen.createDocument()`, every time:

```text
#0  QtWebEngineCore::RenderWidgetHostViewQt::Hide()
#1  content::RenderFrameHostManager::CreateSpeculativeRenderFrame(...)
#2  content::RenderFrameHostManager::CreateSpeculativeRenderFrameHost(...)
#3  content::RenderFrameHostManager::GetFrameHostForNavigation(...)
...
#9  content::NavigationControllerImpl::LoadURL(...)
#10 extensions::ExtensionHost::LoadInitialURL()
#11 extensions::ExtensionHost::CreateRendererNow()
#12 extensions::ExtensionHostQueue::ProcessOneHost()
```

### Reproduce

An MV3 extension with the `offscreen` permission and an extension page that calls:

```js
chrome.offscreen.createDocument({url: "offscreen.html", reasons: ["CLIPBOARD"], justification: "x"});
```

Load it with `QWebEngineExtensionManager::loadExtension`, enable it, and open the page in a
`QWebEnginePage`. Calling it from the extension's service worker crashes the same way. Arch's stock
`qt6-webengine` 6.11.2 crashes on it, so this is Qt's code, not the series.

Test: `tst_qwebengineextension::anOffscreenDocumentCanBeCreated`. Without the fix the test program
dies with signal 11 before its totals.

### Cause

`ExtensionHost` creates its `WebContents` itself, with no `WebContentsAdapter`, so
`WebContentsViewQt` never gets a factory client and `CreateViewForWidget` creates every
`RenderWidgetHostViewQt` in those contents without a delegate. The offscreen document's first
navigation creates a speculative main frame, and `CreateSpeculativeRenderFrame` hides its view
"like a new RenderViewHost would be, until navigation commits". `Hide()` has only
`Q_ASSERT(m_delegate)` before `m_delegate->hide()`, so a release build reads through null.
`ShowWithVisibility()` on the line above checks for the missing delegate, and `IsShowing()` has the
same unchecked dereference as `Hide()`.

### Fix

Patch 0019 makes `Hide()` hide the delegate when there is one and otherwise cancel a deferred show,
so a delegate set later does not show a view Chromium hid, and makes `IsShowing()` answer false
without a delegate. `Hide()` and `IsShowing()` are the same in 6.11.2, 6.140 and `dev`.

The change for Gerrit is
[`0001-Don-t-crash-hiding-a-view-that-has-no-delegate.patch`](0001-Don-t-crash-hiding-a-view-that-has-no-delegate.patch),
a `git format-patch` against `dev` at `eafb229` that applies there with `git am`. It carries
`Fixes: QTBUG-XXXXX` and `Pick-to: 6.140` and no `Change-Id`, which the commit hook adds. The fix
and the test are in one commit, using the fixtures and helpers `dev`'s test already has plus one new
fixture, `offscreen_ext`. It has not been compiled against `dev`; the same source and test pass on
6.11.2.

### Why it went unnoticed

The tests never created an offscreen document, and a debug build would stop on the assertion with
the same stack. Omaweb found it from a core dump: Bitwarden made an offscreen document as the laptop
resumed from suspend ([omaweb#646](https://github.com/villekivela/omaweb/issues/646)).

---

## What is needed to send these

Nothing here goes anywhere without a Qt account and a signed contributor agreement, and the patches
in this repository are not in a form Gerrit accepts: they apply to an unpacked release tarball, not
to a clone of `dev`.

For each change:

1. Clone `https://code.qt.io/qt/qtwebengine.git` and check out `dev`.
2. Apply the patch's `qtwebengine` half and commit with a Qt-style message: one summary line, a body
   explaining the cause, then `Fixes: QTBUG-xxxxx`, `Pick-to: 6.11 6.10`, and the `Change-Id` the
   commit hook adds.
3. `git push gerrit HEAD:refs/for/dev`.

The test in each patch goes up with the fix, in the same change.
