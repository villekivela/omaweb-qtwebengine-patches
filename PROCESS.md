# Keeping the series alive

Qt publishes a release every couple of months. What follows is who does what,
when, and what it costs when something goes wrong.

## The run, in order

| When | What | Who | Cost |
| ---- | ---- | --- | ---- |
| Qt publishes | The baseline check in the Omaweb repository notices and opens an issue with a due date | automated, daily | none |
| Same day | `series-applies.yml` applies the series to the new release and reports a conflict | automated, daily | minutes |
| Same evening | Read the Qt release notes for what the release carries | you | minutes |
| Same evening | Qualifying build on whatever machine you are at, then `verify.sh` | you, one command | hours, unattended |
| Next morning | `build-on-hetzner.sh` for x86_64 and aarch64 | you, two commands | hours each, unattended, under a euro |
| Next morning | Package and sign, publish to the repository | you | minutes |
| After | Record the release in the table in `README.md` | you | a line |

Two of those are automated and they are the two that answer questions rather
than make decisions. Everything that decides something has a person in it, on
purpose: whether a release is worth shipping, whether a conflict was resolved
correctly, and what gets signed.

## Where a conflict can appear, and what it costs

**The series does not apply.** Found the day Qt publishes, by the daily check,
before anyone spends a night. This is the cheap case and the common one. Fix it
in a local tree and export the series back, as below.

**It applies, and the build fails.** Found hours in, at your own machine rather
than on a rented one, because the qualifying build runs first and there is a
person at it. Usually an API the patches call has moved. Fix, rebuild, export.

That build is whatever you are working on, macOS or Linux. `refresh.sh` and
`verify.sh` read `uname` and configure accordingly. What a macOS build cannot do
is ship, so it qualifies the series and the rented Linux machines produce what
readers install.

**It builds, and the gate fails.** `verify.sh` says either that the patched
engine regressed or that a test no longer fails on a stock one. The second means
the test has stopped proving anything, which is worth more attention than the
first.

**Chromium moved underneath.** The expensive case, described below. Found as a
build failure, and the fix is mechanical rather than clever.

**System Qt is older than the engine.** The remote build refuses before it
starts: QtWebEngine builds against the Qt it belongs to, and Arch is a day or
two behind Qt. Either wait for the distribution or build the rest of Qt too.

## Resolving a conflict

Always on your own machine, never on a builder. A builder has no person at it
and no history to look at, and the rented machine costs money while it waits.

```sh
scripts/refresh.sh 6.12.0            # stops and names the patch that failed
cd ~/Projects/villekivela/qtwebengine/qtwebengine-everywhere-src-6.12.0
# fix the conflict in the tree
git am --continue
git format-patch -o /path/to/omaweb-qtwebengine-patches/patches v6.12.0-tarball..HEAD
```

Then build and verify before the builders run. The patches in this repository
are always the current ones: there is no branch to merge and no older copy to
reconcile.

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

## Setting the builders up, once

```sh
scripts/setup-builders.sh
```

It walks through a Hetzner project of its own, a token, a keypair that only ever
opens rented machines, and a GitHub token that can open issues in Omaweb and
nothing else. It writes the three secrets the workflows ask for and checks each
credential against the service before storing it. Run it again to rotate any of
them.

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

Package here, publish there. `makepkg` needs Arch, so the package is built in
the same container the engine was:

```sh
scripts/package-locally.sh 6.11.2
```

That leaves `out/omaweb-qtwebengine-<version>-<arch>.pkg.tar.*`, unsigned. The
signing key is in the Omaweb repository, so signing and publishing happen there:

```sh
gh release create engine-6.11.2 --repo villekivela/omaweb \
    --title "Engine 6.11.2" out/*.pkg.tar.zst
gh workflow run "Publish the engine" --repo villekivela/omaweb \
    -f tag=engine-6.11.2
```

The split follows what each repository owns. The PKGBUILD and the notices are
here, so packaging is here. The key and the pacman repository are there, so
signing is there. One file crosses, and the workflow refuses anything that is
not this engine built for the architecture its name claims.

Where a key that can sign is on the machine, `OMAWEB_REPO_KEY` names it and
`package-locally.sh` makes the detached signature on the host as well, never in
the container. Then `publish_repo.sh` in the Omaweb repository takes the signed
package directly and the workflow is not needed.

Either way that repository serves the browser and the engine together, so a
reader's `pacman -S omaweb` installs both and an engine update reaches them
through an ordinary `pacman -Syu` without an Omaweb release.

The engine installs into `/usr/lib/omaweb`, so the distribution's
`qt6-webengine` is untouched and every other Qt application on the machine keeps
the engine it had.

One constraint the remote script checks before it spends hours: QtWebEngine
builds against the Qt it belongs to, so the container's `qt6-base` has to be the
same version as the engine. When Qt has published a release the distribution has
not packaged yet, that check fails early rather than at link time.
