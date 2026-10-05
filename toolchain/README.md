# The toolchain

The engine is built the way Chrome is built where that was measured to be faster: clang and LLD,
ThinLTO, Chrome's own PGO profile for the engine's Chromium, and V8's profile for its builtins.
`scripts/engine-toolchain.sh` names the toolchain each architecture takes, and
`OMAWEB_ENGINE_TOOLCHAIN=gcc` or `=clang` overrides it for one build, locally or through the
`toolchain` input of "Build the engine". The decision is omaweb's ADR 0060.

| Architecture | Toolchain | Speedometer 3.1 ÷ Chromium 140 | JetStream 2.2 ÷ Chromium 140 |
| --- | --- | --- | --- |
| x86_64 | GCC | 0.727 | 0.917 |
| x86_64 | clang, LLD, ThinLTO, Chrome's PGO | 0.774, and 0.777 measured again | 0.924, and 0.942 |
| aarch64 | GCC | 0.789 | 0.943 |
| aarch64 | clang, LLD, ThinLTO, no PGO | 0.756 and 0.785 | 0.959 and 0.973 |

All with V8's write barriers on. x86_64 is a Ryzen 7 PRO 7840HS on its GPU
([omaweb#356](https://github.com/villekivela/omaweb/issues/356) and
[omaweb#575](https://github.com/villekivela/omaweb/issues/575)), where Speedometer gains about 6%
and the builders take clang. aarch64 is an Apple M2 Max in an arm64 container, GCC measured between
two clang sessions on one evening (omaweb#575). Chrome publishes no Linux PGO profile for aarch64,
so clang there gets ThinLTO and V8's builtins profile only, and Omaweb's own scores moved within the
run-to-run spread: Speedometer 24.74 against 24.10 and 24.77, JetStream 368.2 against 372.6 and
370.7. aarch64 keeps GCC until Chrome publishes a profile for it or the Chromium moves.

## The patch

`clang.patch` is applied by `refresh.sh` to a clang build only, after the series. It is not part of
the series: it changes how the engine is compiled, not what its code does. It does four things:

- It turns on LLD and ThinLTO, which Qt allows only when Qt itself was built for LLD.
- It turns on PGO when a profile is given, which Qt never does.
- It turns on V8's builtins profile on its own, which V8 takes only with Chrome's.
- Where V8's builtins profile no longer fits a builtin, it has V8 build that builtin without the
  profile instead of stopping the build. Qt's V8 is not built quite as Chrome's.

## The profiles

`scripts/fetch-profiles.sh` takes the profiles for the tree being built, so they follow the
engine's Chromium rather than being chosen by hand:

- Chrome's profile is named in `chrome/build/linux.pgo.txt` at the Chromium tag the tree carries,
  `chrome/VERSION`. Qt's copy of Chromium leaves that file out, so the name is read from
  Chromium's tag on Gitiles and put back where Chromium's build expects it. A function Qt or the
  series changed has no matching profile and is compiled without one, which clang reports.
- V8's builtins profile is kept per V8 version, `v8/include/v8-version.h`. V8 applies its x64
  profile on arm64 too.

Each is held to the MD5 Google Storage publishes before it is used, and kept in the work space's
`pgo/`, so a rebuild needs no network.

## Memory

`scripts/build-locally.sh` caps its container at `OMAWEB_ENGINE_MEMORY`, 20g by default, and
`build-inside.sh` counts its compile jobs from the cap, about 2.2 GB a job. The compile, not the
link, is what fills it. Sampled every five seconds on 6.11.2 with an empty ThinLTO cache, as the
container's anonymous memory, what its processes hold without the page cache
([omaweb#575](https://github.com/villekivela/omaweb/issues/575)):

| Machine | Cap, jobs | Compile, peak | ThinLTO link of `libQt6WebEngineCore.so`, peak |
| --- | --- | --- | --- |
| x86_64, Ryzen 7 PRO 7840HS, 16 threads | 20g, 9 | not measured | 3.5 GB, under three minutes |
| aarch64, Apple M2 Max, 6 of 12 CPUs | 22g, 6 | 13.0 GB | 2.5 GB, about two minutes |

The x86_64 build was incremental, so its compile peak was not measured. The link uses every thread
the container has (`--thinlto-jobs=all`), and its cache in `build/thinlto-cache` makes a relink of
unchanged code take under a minute. On a machine with less memory, set `OMAWEB_ENGINE_MEMORY` below
what it has free: fewer jobs compile, and the link fits.
