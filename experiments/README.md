# Experiments

Patches applied outside the series, only when a build opts in. Nothing here ships.

## The optimised toolchain

`OMAWEB_ENGINE_TOOLCHAIN=clang scripts/build-locally.sh <version>` builds the engine the way Chrome
is built: clang and LLD, ThinLTO, Chrome's PGO profile for the engine's Chromium, and V8's builtins
profile for its V8. Both profiles are fetched by `refresh.sh` and held to the MD5 Google Storage
publishes. `optimised-toolchain.patch` does three things:

- It turns on LLD and ThinLTO, which Qt allows only when Qt itself was built for LLD.
- It turns on PGO, which Qt never does.
- It lets V8 build the builtins its profile no longer fits without the profile, instead of stopping
  the build.

Measured on 6.11.2 with write barriers on, x86_64, against the same engine built with GCC
([omaweb#356](https://github.com/villekivela/omaweb/issues/356)):

| | Speedometer 3.1 ÷ Chromium 140 | JetStream 2.2 ÷ Chromium 140 |
| --- | --- | --- |
| GCC | 0.727 | 0.917 |
| clang, LLD, ThinLTO, PGO | 0.774 | 0.924 |

Whether the builders switch is to be decided on 6.140.0, measured the same way. The link needs
about 20 GiB.
