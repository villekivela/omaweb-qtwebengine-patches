# QTBUG draft: let the application tell QtWebEngine what its tabs are

**Type:** Suggestion
**Component:** WebEngine
**Affects:** 6.10, 6.11, 6.12 (the extension API since it was introduced)

## Summary

`QWebEngineExtensionManager` loads a Manifest V3 package, but an extension that wants to do
anything with the pages the application is showing cannot: `tabs` carries one function,
`tabs.update`, which ignores its `tabId` and navigates the sender, and there is no way for the
application to say which of its pages are tabs or which one the user is looking at.

This proposes the missing half: a delegate through which the application describes its own model,
so the extension APIs that are about pages can be answered from it rather than from a guess inside
QtWebEngine.

## Why

QtWebEngine cannot know what a tab is. A page may be a tab, a preview shown over another page, a
popup the application opened for an extension, or a view that is not part of any tab strip. Chrome
answers these questions from `TabStripModel`, which is browser UI and does not belong in
QtWebEngine. The application already knows, and is the only thing that does.

## Proposed shape

A delegate the application sets on a profile, along these lines:

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

With no delegate set, behaviour is what it is today: no page is a tab, and the tab-shaped APIs
answer empty. An application that sets one opts in to the extension seeing its pages.

The delegate answers the existing embedder hooks in `extensions/browser`, which already exist for
exactly this purpose and which QtWebEngine does not currently override:
`ExtensionsBrowserClient::GetTabAndWindowIdForWebContents`, `IsValidTabId`,
`GetScriptExecutorForTab`, and `MessagingDelegate::MaybeGetTabInfo` and `GetWebContentsByTabId`.
Chrome's own implementations of `tabs`, `windows` and `scripting` then work unmodified, because
they reach a tab through those hooks rather than through anything Chrome-specific.

## What it makes possible

Compiling Chrome's schemas for `tabs`, `windows` and `scripting` with the functions that have no
implementation marked `nocompile`, which is how Chrome itself ships partial namespaces. A prototype
doing this, against 6.11.1 and 6.11.2, is at
https://github.com/villekivela/omaweb-qtwebengine-patches. It implements `tabs.get`, `getCurrent`,
`query` and `update`, `windows.get`, `getCurrent`, `getLastFocused` and `getAll`, and
`permissions.contains` and `getAll`, and compiles Chrome's `scripting` implementation unchanged.
With it, a real extension, Bitwarden, renders its interface, runs its service worker, collects a
page's form fields and fills them.

The prototype fills the delegate by treating every page of the profile as a tab, which is the guess
this proposal exists to remove.

## Questions for the maintainers

1. Is an application-supplied tab model something QtWebEngine wants at all, or is the extension API
   deliberately scoped to packages that do not look at the application's pages?
2. If it is wanted, is a delegate on the profile the right shape, or would you rather the
   application registered pages explicitly as they come and go?
3. Would you take the compiled-with-`nocompile` approach to Chrome's schemas, or do you want Qt to
   own smaller schemas of its own, as `qtwebengine/common/extensions/api/tabs.json` does today?

Two defects found while prototyping are reported separately, since they stand on their own:
an extension that calls `chrome.i18n.getMessage` from its service worker never finishes evaluating,
and `setExtensionEnabled` crashes after a profile's storage path changes.
