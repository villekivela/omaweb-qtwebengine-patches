# Two defect reports

Both reproduce on a stock build. Both come with a test that fails without the fix. File separately
from the tab-delegate suggestion. Fixes go to Gerrit against `dev` with `Pick-to: 6.11 6.10`.

---

## 1. An extension whose service worker localises never starts

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

Patch 0001 in https://github.com/villekivela/omaweb-qtwebengine-patches registers `EventRouter` and
`RendererHost` at all three points, as `ChromeContentBrowserClient` does.

---

## 2. setExtensionEnabled crashes after a profile's storage path changes

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

Patch 0003 in the same repository points the existing `ExtensionPrefs` at the new `PrefService` instead of replacing an instance other services hold. The hook is guarded by `IS_QTWEBENGINE`.
