# QTBUG draft: let the application tell QtWebEngine what its tabs are

**Type:** Suggestion
**Component:** WebEngine
**Affects:** 6.10, 6.11, 6.12

## Summary

`QWebEngineExtensionManager` loads a Manifest V3 package, but an extension can do almost nothing
with the pages the application shows. The `tabs` namespace has one function, `tabs.update`, and it
ignores its `tabId` and navigates whichever page asked. Nothing lets the application say which of
its pages are tabs, or which one the user is looking at.

I would like to add that. A delegate on the profile, through which the application describes its
own model, and which the page-related extension APIs then read.

## Why a delegate

QtWebEngine cannot work out what a tab is, and I do not think it should try. A page might be a tab.
It might be a preview drawn over another page, or the popup the application opened to show an
extension's own UI, or a view that belongs to no tab strip at all. Chrome answers these questions
from `TabStripModel`, which is browser UI and has no place here. The application knows, and nothing
else does.

I prototyped the alternative first, out of curiosity, by treating every page of a profile as a tab.
It breaks immediately. The extension's own popup shows up in `tabs.query()`, so an extension asking
for the active tab can be told about its own UI instead of the page the user is reading.

## Proposed shape

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

Set no delegate and nothing changes from today. No page is a tab, and the APIs that ask about tabs
answer with nothing. Setting one is how an application opts in to extensions seeing its pages.

Underneath, the delegate answers five hooks that `extensions/browser` already defines and
QtWebEngine does not override today. `ExtensionsBrowserClient` declares
`GetTabAndWindowIdForWebContents`, `IsValidTabId` and `GetScriptExecutorForTab`; `MessagingDelegate`
declares `MaybeGetTabInfo` and `GetWebContentsByTabId`. Chrome's own `tabs`, `windows` and
`scripting` implementations reach a tab through those hooks and nothing Chrome-specific, so they
compile here unchanged once something answers them.

## What it buys

Chrome's schemas for `tabs`, `windows` and `scripting` can then be compiled with the functions that
have no implementation marked `nocompile`, which is how Chrome ships partial namespaces itself.

I have a prototype doing this against 6.11.1 and 6.11.2:
https://github.com/villekivela/omaweb-qtwebengine-patches. It implements `tabs.get`, `getCurrent`,
`query` and `update`, `windows.get`, `getCurrent`, `getLastFocused` and `getAll`, and
`permissions.contains` and `getAll`. Chrome's `scripting` implementation compiles with two include
paths changed and nothing else. With that applied, Bitwarden's extension draws its interface, runs
its service worker, reads a login form's fields and fills them.

The prototype is not the proposal. It fills the delegate with the every-page-is-a-tab guess
described above, which is the part I want to replace with something the application supplies.

## Questions

1. Do you want an application-supplied tab model at all? If the extension API is deliberately scoped
   to packages that never look at the application's pages, say so and I will stop here. A quick no
   is more useful to me than a maybe.
2. If you do want one, is a delegate on the profile the right shape? The alternative I considered is
   the application registering and unregistering pages as they come and go, which is more work for
   the application but removes any question about when the delegate gets called.
3. Would you take Chrome's schemas compiled with `nocompile`, or would you rather Qt kept schemas of
   its own, as `qtwebengine/common/extensions/api/tabs.json` does now? The first tracks upstream for
   free and carries functions that throw. The second is smaller and honest about what exists.

I found two defects while building this and will report them separately, since they are ordinary
bugs in what 6.11 already ships. An extension that calls `chrome.i18n.getMessage` from its service
worker hangs forever, and `setExtensionEnabled` crashes after a profile's storage path changes.
