# Two defect reports

Both stand on their own, are reproducible against a stock build, and carry a test. File them
separately from the tab-delegate suggestion, and submit the fixes to Gerrit against `dev` with
`Pick-to: 6.11 6.10`.

---

## 1. An extension whose service worker localises never starts

**Type:** Bug
**Component:** WebEngine
**Affects:** 6.10, 6.11.2, dev

### Summary

`chrome.i18n.getMessage()` is a synchronous call from the renderer to the browser, over
`extensions::mojom::RendererHost`. QtWebEngine never binds a receiver for that interface, so the
reply never comes and the caller waits forever. An extension that localises anything at the top
level of its service worker, which is ordinary, never finishes evaluating, and its registration
eventually fails with "Service worker registration failed. Status code: 2".

### Steps to reproduce

Load an unpacked Manifest V3 extension whose `service_worker.js` begins:

```js
const greeting = chrome.i18n.getMessage("greeting")
```

with a `_locales/en/messages.json` defining `greeting`, and enable it. The worker never runs.

`tst_qwebengineextension`'s `serviceWorkerLocalization` case covers this.

### Cause

`ContentBrowserClientQt::ExposeInterfacesToRenderer` registers `extensions::mojom::EventRouter` and
nothing else. Chrome registers `RendererStartupHelper::BindForRenderer` for
`extensions::mojom::RendererHost` beside it. The renderer reaches the browser through three
registries, not one, and QtWebEngine serves none of them fully:

- the render process registry (`ExposeInterfacesToRenderer`), which has `EventRouter` only,
- the render frame registry (`RegisterAssociatedInterfaceBindersForRenderFrameHost`), which has
  neither, so an extension page never registers an event listener and never receives an event its
  own service worker does receive, such as `storage.onChanged`,
- the service worker registry (`RegisterAssociatedInterfaceBindersForServiceWorker`), which has
  `ServiceWorkerHost` only.

The stack in the renderer is `V8ScriptRunner::CompileAndRunScript` →
`I18nHooksDelegate::HandleGetMessage` → `SharedL10nMap::GetMapForExtension` →
`mojom::RendererHostProxy::GetMessageBundle` → `mojo::SyncHandleRegistry::Wait`.

### Fix

Patch 0001 in https://github.com/villekivela/omaweb-qtwebengine-patches registers `EventRouter` and
`RendererHost` at all three registration points, mirroring `ChromeContentBrowserClient`.

---

## 2. setExtensionEnabled crashes after a profile's storage path changes

**Type:** Bug
**Component:** WebEngine
**Affects:** 6.10, 6.11.2, dev

### Summary

Changing a profile's storage name, off-the-record flag or storage path after it is constructed
rebuilds its `PrefService`. `ProfileQt::setupPrefService` then builds a replacement `ExtensionPrefs`
and installs it with `ExtensionPrefsFactory::SetInstanceForTesting`, but `ExtensionRegistrar`,
`EventRouter` and the other keyed services created with the profile keep the pointer they cached at
construction. The next `QWebEngineExtensionManager::setExtensionEnabled` dereferences the destroyed
`PrefService`.

### Steps to reproduce

```cpp
QWebEngineProfile profile("Test");
QWebEngineExtensionManager *manager = profile.extensionManager();
profile.setPersistentStoragePath(dir.path());       // rebuilds the PrefService
manager->loadExtension(path);                        // succeeds
manager->setExtensionEnabled(extension, true);       // crashes
```

Backtrace: `PrefService::GetPreferenceValue` ← `ExtensionPrefs::GetExtensionPref` ←
`blocklist_prefs::IsExtensionBlocklisted` ← `ExtensionRegistrar::EnableExtension` ←
`QWebEngineExtensionManager::setExtensionEnabled`.

This is on the ordinary path for any application that names a storage path after constructing the
profile, which the QML `WebEngineProfile` type does by design.

`tst_qwebengineextension`'s `enableAfterStoragePathChange` case covers this.

### Fix

Patch 0003 in the same repository re-points the existing `ExtensionPrefs` at the new `PrefService`
through a small hook guarded by `IS_QTWEBENGINE`, rather than replacing an instance other services
already hold.
