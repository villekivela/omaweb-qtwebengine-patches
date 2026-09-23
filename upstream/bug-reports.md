# Five defect reports

All five reproduce on a stock build and each comes with a test that fails without the fix. File
separately from the tab-delegate suggestion in `QTBUG-draft.md`, which asks for new API and is a
different conversation.

Fixes go to Gerrit against `dev` with `Pick-to: 6.11 6.10`.

Four touch `qtwebengine` alone and can go up in any order. The `ExtensionPrefs` crash also needs a
change in `qtwebengine-chromium`, so it is two changes with a dependency and is worth sending last,
once the others have shown the reviewers what this is about.

All five are filed. Four are on Gerrit; the fifth waits on an answer about where its fix belongs.

| Order | Patch | Report | Change | What it is |
| ----- | ----- | ------ | ------ | ---------- |
| 1 | 0014 | [QTBUG-150590](https://bugreports.qt.io/browse/QTBUG-150590) | [772845](https://codereview.qt-project.org/c/qt/qtwebengine/+/772845) | A page cannot load a web accessible resource |
| 2 | 0001 | [QTBUG-150591](https://bugreports.qt.io/browse/QTBUG-150591) | [772848](https://codereview.qt-project.org/c/qt/qtwebengine/+/772848) | A localising service worker hangs forever |
| 3 | 0010 | [QTBUG-150592](https://bugreports.qt.io/browse/QTBUG-150592) | [772849](https://codereview.qt-project.org/c/qt/qtwebengine/+/772849) | Loading a loaded extension leaves it dead |
| 4 | 0011 | [QTBUG-150593](https://bugreports.qt.io/browse/QTBUG-150593) | [772850](https://codereview.qt-project.org/c/qt/qtwebengine/+/772850) | An extension document cannot close its own window |
| 5 | 0003 | [QTBUG-150594](https://bugreports.qt.io/browse/QTBUG-150594) | waiting | `setExtensionEnabled` crashes after a storage path change |

Each change carries `Fixes: QTBUG-…` and `Pick-to: 6.11 6.10`.

Patch 0015 answers a report someone else had already filed, so it went there as a comment rather
than a sixth report. [QTBUG-149450](https://qt-project.atlassian.net/browse/QTBUG-149450) measures
the same Speedometer 3.1 gap on Windows, and the comment names qtwebengine-chromium `baf701b9fb74`
as the cause, with the macOS numbers. Its fix goes to `qtwebengine-chromium`, not `qtwebengine`.
The report is on Windows, where the removed line was an MSVC workaround, so what MSVC accepts has
to be settled before a change is proposed. The Linux numbers from
[omaweb#355](https://github.com/villekivela/omaweb/issues/355) go on the report once measured.

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
