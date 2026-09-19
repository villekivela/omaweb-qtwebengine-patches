# Keeping the series alive

What to do when Qt publishes a release. The whole routine is two commands and a night of machine
time.

```sh
scripts/refresh.sh 6.12.0     # fetch, unpack, apply the series, configure
~/Projects/villekivela/qtwebengine/qtwebengine-everywhere-src-6.12.0/build.sh   # hours
scripts/verify.sh ~/Projects/villekivela/qtwebengine/qtwebengine-everywhere-src-6.12.0
```

`refresh.sh` stops and tells you which patch conflicted, if any. `verify.sh` runs the tests twice,
once against the patched build where all of them must pass, and once against the stock engine where
four of them must fail. The second run is the one that proves the tests are worth having.

Record the result in the table in `README.md`: patches applying, build, tests, and the time it took
a person rather than the machine.

## When a patch conflicts

Resolve it in the tree, `git am --continue`, then export the series back:

```sh
git format-patch -o /path/to/omaweb-qtwebengine-patches/patches v<version>-tarball..HEAD
```

The patches in this repository are always the current ones. There is no branch to merge.

## When Chromium moves under the series

Qt bumps its Chromium fork every few releases, and that is the only expensive case. Patches 0005 and
0006 carry copies of Chrome files, which go stale:

- `chrome/browser/extensions/api/scripting/scripting_api.{cc,h}` and `scripting.idl`
- `chrome/browser/extensions/api/messaging/{launch_context*,native_message_process_host,native_messaging_host_manifest,native_process_launcher,chrome_native_message_port_dispatcher}.{cc,h}`
- `chrome/browser/extensions/api/permissions/permissions_api_helpers.{cc,h}`
- the nine schemas under `chrome/common/extensions/api/` copied into `qtwebengine/common/extensions/api/`

Re-copy each from the new Chromium and redo the two include rewrites: the file's own header and the
generated schema header both move from `chrome/` to `qtwebengine/`. Then rebuild and let the
compiler find the rest.

Measured once, from Chromium 140 to 146, six major versions apart: those files changed by 4 to 13
lines each, and patch 0003's hunk in `extension_prefs.cc` lost two of the six calls it makes,
because those migrations finished upstream and were deleted. Under an hour of work. The five
embedder hooks the design rests on were all still there, with the same names.

## When it goes wrong

Stop. The engine is not allowed to wait for this series. Ship the release on stock Qt with Known
extensions reported absent, and come back to the rebase afterwards. A browser that is late on a
Chromium security fix because an extension patch would not apply has its priorities backwards.

## What a release needs beyond this

Only if the patched engine is distributed rather than kept for development:

- Builds for x86_64 and aarch64, not just whatever laptop ran the last one.
- A package installed into a private prefix, never replacing the system `qt6-webengine`.
- The modified source published, which is this repository, and the engine marked as modified. That
  is what LGPL-3 asks for.
- A stated limit on how long after a Qt release the rebuild may take, because from then on that lag
  is the security lag for every reader.
