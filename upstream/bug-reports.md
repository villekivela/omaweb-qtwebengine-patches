# Two defect reports

Both reproduce against a stock build, and both come with a test that fails without the fix. File
them separately from the tab-delegate suggestion, and send the fixes to Gerrit against `dev` with
`Pick-to: 6.11 6.10`.

---

## 1. An extension whose service worker localises never starts

**Type:** Bug
**Component:** WebEngine
**Affects:** 6.10, 6.11.2, dev

### Summary

`chrome.i18n.getMessage()` is a synchronous call from the renderer into the browser, over
`extensions::mojom::RendererHost`. QtWebEngine binds no receiver for that interface, so the reply
never arrives and the calling thread waits forever. An extension that localises anything at the top
level of its service worker, which is a normal thing to do, never finishes evaluating that script.
Registration eventually fails with "Service worker registration failed. Status code: 2".

### Steps to reproduce

Load an unpacked Manifest V3 extension whose `service_worker.js` starts with

```js
const greeting = chrome.i18n.getMessage("greeting")
```

and whose `_locales/en/messages.json` defines `greeting`. Enable it. The worker never runs.

The `serviceWorkerLocalization` case in `tst_qwebengineextension` covers this.

### Cause

`ContentBrowserClientQt::ExposeInterfacesToRenderer` registers `extensions::mojom::EventRouter` and
nothing else. Chrome registers `RendererStartupHelper::BindForRenderer` for
`extensions::mojom::RendererHost` alongside it.

A renderer reaches the browser through three registries, and QtWebEngine serves none of them fully.
The render process registry has `EventRouter` alone. The render frame registry
(`RegisterAssociatedInterfaceBindersForRenderFrameHost`) has neither interface, which is a second
bug hiding behind the first: an extension page never registers an event listener, so it never
receives an event such as `storage.onChanged` that its own service worker does receive. The service
worker registry has `ServiceWorkerHost` alone.

Sampling the renderer while it hangs shows `V8ScriptRunner::CompileAndRunScript` →
`I18nHooksDelegate::HandleGetMessage` → `SharedL10nMap::GetMapForExtension` →
`mojom::RendererHostProxy::GetMessageBundle` → `mojo::SyncHandleRegistry::Wait`.

### Fix

Patch 0001 in https://github.com/villekivela/omaweb-qtwebengine-patches registers `EventRouter` and
`RendererHost` at all three points, which is what `ChromeContentBrowserClient` does.

---

## 2. setExtensionEnabled crashes after a profile's storage path changes

**Type:** Bug
**Component:** WebEngine
**Affects:** 6.10, 6.11.2, dev

### Summary

Changing a profile's storage name, off-the-record flag or storage path after construction rebuilds
its `PrefService`. `ProfileQt::setupPrefService` then builds a replacement `ExtensionPrefs` and
installs it with `ExtensionPrefsFactory::SetInstanceForTesting`. `ExtensionRegistrar`, `EventRouter`
and the other keyed services created with the profile keep the pointer they cached at construction,
so they go on reading the instance that was replaced. The next
`QWebEngineExtensionManager::setExtensionEnabled` dereferences the destroyed `PrefService`.

### Steps to reproduce

```cpp
QWebEngineProfile profile("Test");
QWebEngineExtensionManager *manager = profile.extensionManager();
profile.setPersistentStoragePath(dir.path());       // rebuilds the PrefService
manager->loadExtension(path);                        // succeeds
manager->setExtensionEnabled(extension, true);       // crashes
```

The crash is in `PrefService::GetPreferenceValue`, called from `ExtensionPrefs::GetExtensionPref`,
`blocklist_prefs::IsExtensionBlocklisted`, `ExtensionRegistrar::EnableExtension` and
`QWebEngineExtensionManager::setExtensionEnabled`.

This is the ordinary path for any application that names a storage path after constructing the
profile, which the QML `WebEngineProfile` type does by design.

The `enableAfterStoragePathChange` case in `tst_qwebengineextension` covers this.

### Fix

Patch 0003 in the same repository points the existing `ExtensionPrefs` at the new `PrefService`
instead of replacing an instance other services already hold. The hook it adds is guarded by
`IS_QTWEBENGINE`.
