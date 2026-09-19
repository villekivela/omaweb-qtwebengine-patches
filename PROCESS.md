# Keeping the series alive

Qt publishes a release every couple of months. Each one needs two commands and a night of machine
time.

```sh
scripts/refresh.sh 6.12.0
~/Projects/villekivela/qtwebengine/qtwebengine-everywhere-src-6.12.0/build.sh
scripts/verify.sh ~/Projects/villekivela/qtwebengine/qtwebengine-everywhere-src-6.12.0
```

`refresh.sh` stops and names the patch if one conflicts. `verify.sh` runs the tests twice: against
the patched build, where all 22 must pass, and against a stock engine, where four must fail. The
second run is what keeps the tests honest. Without it, a test that quietly stopped proving anything
would still be green.

Add the result to the table in `README.md`.

## When a patch conflicts

Fix it in the tree, `git am --continue`, then export the series back:

```sh
git format-patch -o /path/to/omaweb-qtwebengine-patches/patches v<version>-tarball..HEAD
```

The patches in this repository are always the current ones. There is no branch to merge and no
older copy to reconcile.

## When Chromium moves

Qt bumps its Chromium fork every few releases. This is the only expensive case, because patches 0005
and 0006 carry copies of Chrome files that go stale:

- `chrome/browser/extensions/api/scripting/scripting_api.{cc,h}` and `scripting.idl`
- `chrome/browser/extensions/api/messaging/` — `launch_context*`, `native_message_process_host`,
  `native_messaging_host_manifest`, `native_process_launcher`,
  `chrome_native_message_port_dispatcher`
- `chrome/browser/extensions/api/permissions/permissions_api_helpers.{cc,h}`
- the nine schemas copied from `chrome/common/extensions/api/` into
  `qtwebengine/common/extensions/api/`

Re-copy each from the new Chromium and redo two include rewrites per file: the file's own header and
the generated schema header both move from `chrome/` to `qtwebengine/`. Rebuild and let the compiler
find whatever else moved.

Measured once, across Chromium 140 to 146: those files changed by 4 to 13 lines each, and patch 0003
lost two of the six calls it makes because those migrations finished upstream. Under an hour. All
five embedder hooks the design depends on were still there with the same names.

## When a rebase is late

Omaweb ships its own engine, so the release cadence is Omaweb's. A late patched engine means a late
update, not a broken one. Readers keep the Omaweb they have, with the engine it came with, and
everything goes on working.

The cost is a security lag instead. While the rebase is being fixed, readers stay on the older
Chromium, and they cannot see that from the outside.

The target is one night. A Qt release carrying security fixes gets rebased and built the same
evening and published the next day. That delay is acceptable.

If a rebase cannot make that window, drop patches 0004 to 0006 and ship anyway. 0001 and 0003 are
small and apply to anything, so the engine still carries the Chromium fix, and Known extensions go
missing until a follow-up engine update restores them. Say so in the release notes: the vault data
is untouched and comes back with the extension.

That is the escape hatch, not the routine. Reach for it when the alternative is sitting on a
security fix for days.

## If the engine is distributed

None of this applies while the patched engine stays a development tool. It all applies the day a
reader installs one:

- Build on x86_64 and aarch64, not on whichever laptop is free. Mac builds produce macOS frameworks
  and cannot ship in an Arch package.
- Install into a private prefix. Never replace the system `qt6-webengine`, or every other Qt
  application on the machine gets the patched engine too.
- Publish the modified source, which is this repository, and mark the engine as modified. LGPL-3
  asks for both.
- Sign on your own machine. The builder hands back an unsigned package.
- State how long after a Qt release the rebuild may take. From then on that lag is the security lag
  for every reader.

## Building the package

The build runs on a machine rented for it and destroyed afterwards, because a
macOS build cannot ship and a laptop should not be the release machine.

```sh
export HCLOUD_TOKEN=...            # a Hetzner project token
scripts/build-on-hetzner.sh 6.11.2 x86
scripts/build-on-hetzner.sh 6.11.2 arm
```

Each run creates a server, sends the series, builds inside an Arch container,
runs `verify.sh`, and refuses to package anything if the gate does not pass. It
returns an unsigned tarball of the install tree and a checksum, then deletes the
server. Deleting is what stops the billing; a stopped server still bills for its
disk.

Package and sign on your own machine, with `packaging/PKGBUILD` and the tarball
in the same directory:

```sh
cd packaging && makepkg --sign
```

The engine installs into `/usr/lib/omaweb`, so the distribution's
`qt6-webengine` is untouched and every other Qt application on the machine keeps
the engine it had.

One constraint the remote script checks before it spends hours: QtWebEngine
builds against the Qt it belongs to, so the container's `qt6-base` has to be the
same version as the engine. When Qt has published a release the distribution has
not packaged yet, that check fails early rather than at link time.
