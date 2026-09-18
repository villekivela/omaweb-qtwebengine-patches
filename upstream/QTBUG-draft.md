# QTBUG draft: let the application tell QtWebEngine what its tabs are

**Type:** Suggestion
**Component:** WebEngine
**Affects:** 6.10, 6.11, 6.12

## What I want

A delegate on `QWebEngineProfile` where the application says which of its pages are tabs and which
one is active. The extension APIs that deal with pages read it.

Before I write the API properly, I want to know whether you want this at all. If the extension
support is meant only for packages that never touch the application's pages, tell me and I will drop
it.

## The problem

`QWebEngineExtensionManager` loads a Manifest V3 package. The `tabs` namespace has one function,
`tabs.update`, and it ignores `tabId` and navigates whichever page called it. `windows` does not
exist. An extension cannot find out what the application is showing.

## Why the application has to answer this

QtWebEngine cannot know what a tab is. A page can be a tab, a preview drawn over another page, the
popup the application opened for an extension's own UI, or a view in no tab strip at all. Chrome
gets this from `TabStripModel`, which is browser UI and does not belong here.

I tried the shortcut first: treat every page of the profile as a tab. It breaks at once. The
extension's own popup appears in `tabs.query()`, so an extension asking for the active tab is told
about its own UI instead of the page the user is reading.

## Proposed API

```cpp
class QWebEngineTabsDelegate
{
public:
    virtual ~QWebEngineTabsDelegate();
    // The pages an extension should see as tabs, in the application's own order.
    virtual QList<QWebEnginePage *> tabs() = 0;
    // The page the user is looking at, or nullptr.
    virtual QWebEnginePage *activeTab() = 0;
};

// QWebEngineProfile
void setTabsDelegate(QWebEngineTabsDelegate *delegate);
```

No delegate means today's behaviour. No page is a tab and the tab APIs answer nothing.

The delegate feeds five hooks `extensions/browser` already declares and QtWebEngine does not
override: `ExtensionsBrowserClient::GetTabAndWindowIdForWebContents`, `IsValidTabId`,
`GetScriptExecutorForTab`, `MessagingDelegate::MaybeGetTabInfo` and `GetWebContentsByTabId`.
Chrome's `tabs`, `windows` and `scripting` implementations reach a tab only through those hooks, so
they compile unchanged once something answers them.

## Prototype

https://github.com/villekivela/omaweb-qtwebengine-patches, against 6.11.1 and 6.11.2.

Chrome's schemas for `tabs`, `windows`, `permissions` and `scripting` compiled with the unimplemented
functions marked `nocompile`, which is how Chrome ships partial namespaces. Implemented: `tabs.get`,
`getCurrent`, `query`, `update`, `windows.get`, `getCurrent`, `getLastFocused`, `getAll`,
`permissions.contains`, `getAll`. Chrome's `scripting` needed two include paths changed and nothing
else. Bitwarden then draws its interface, runs its service worker, reads a login form's fields and
fills them. 22 tests pass, four of which fail without the patches.

The prototype uses the every-page-is-a-tab guess described above. That guess is what this API
replaces.

## Questions

1. Do you want an application-supplied tab model?
2. If yes: delegate on the profile, or the application registering and unregistering pages as they
   come and go? The second is more work for the application and removes any question about when the
   delegate is called.
3. Chrome's schemas with `nocompile`, or Qt's own smaller schemas as
   `qtwebengine/common/extensions/api/tabs.json` does now? The first tracks upstream for free and
   exposes functions that throw. The second is smaller and matches what exists.

Two separate defects found while building this, reported on their own tickets: an extension calling
`chrome.i18n.getMessage` from its service worker hangs forever, and `setExtensionEnabled` crashes
after a profile's storage path changes.
