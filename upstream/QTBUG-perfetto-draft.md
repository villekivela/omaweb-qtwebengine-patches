# QTBUG draft: every trace point looks up its category at run time

**Type:** Bug
**Component:** WebEngine
**Affects:** 6.11.2, and every release carrying qtwebengine-chromium `baf701b9fb74`

Search for an existing report before filing. The tracker does not answer anonymous queries, so this
draft has not been checked against one.

## Summary

Every `TRACE_EVENT` in QtWebEngine finds its category with a string search, on every call, while
tracing is off. On Speedometer 3.1, a bare `WebEngineView` scores 25.5 against 39.2 for Chrome for
Testing on the same Chromium branch, 140.0.7339. Restoring the upstream macro raises it to 33.9.

## Cause

Perfetto's `track_event_macros.h` computes a trace point's category index in a `constexpr`
variable:

```cpp
PERFETTO_INTERNAL_STATIC_FOR_MSVC constexpr auto PERFETTO_UID(
    kCatIndex_ADD_TO_PERFETTO_DEFINE_CATEGORIES_IF_FAILS_) =
    PERFETTO_GET_CATEGORY_INDEX(category);
```

qtwebengine-chromium `baf701b9fb74`, "Fix QtWebEngine build on Windows" (December 2022), removes
the variable and passes `PERFETTO_GET_CATEGORY_INDEX(category)` straight to
`CallIfCategoryEnabled`, on every platform. The lookup is then a `constexpr` call in an ordinary
expression, which the compiler may fold or not. Clang does not. Each trace point calls
`IsDynamicCategory` and walks the 275 categories of `base/trace_event/builtin_categories.h`
comparing strings, and the change has been carried through every Chromium baseline since.

The cost falls hardest where a trace point sits on a hot call. Blink wraps every `[HighEntropy]`
binding in `blink::Dactyloscoper::HighEntropyTracer`, which opens and closes a trace event, and that
includes most of the canvas 2D API.

## Evidence

Measured on an M2 Max with macOS 26.6.2 and QtWebEngine 6.11.2, built Release with clang.

- In Speedometer's Charts-chartjs suite, `sample` of the renderer puts 54% of its busy time in the
  `HighEntropyTracer` constructor and destructor. The suite's sync time is 3.2 times Chrome's before
  the change and 1.1 after.
- The constructor is 103 instructions with calls to `IsDynamicCategory` and
  `TrackEventCategoryRegistry::CheckIsValidCategoryIndex` before the change, and 32 with neither
  after.
- Across the whole run, sync time goes from 1.53 times Chrome's to 1.18, and async time from 1.66 to
  1.14.

<!-- Add the Linux and GCC numbers from omaweb#355 before filing. -->

## Suggested fix

Restore upstream's variable on every compiler that accepts it, and keep the workaround only where
the Windows build still needs it. The change is two lines in qtwebengine-chromium plus a guard, for
example on `PERFETTO_BUILDFLAG(PERFETTO_COMPILER_MSVC)`. Whether current MSVC and clang-cl still
reject the variable should be checked, since the workaround predates several toolchain releases.

The patch Omaweb carries restores Chromium 140's header unchanged, and is in this repository as
`patches/0015-perfetto-look-up-a-trace-category-at-compile-time-ag.patch`.
