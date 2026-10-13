# Build setup

## Prerequisites

- Windows x64; VC++ 2010 x64 compiler (v100), Windows SDK 7.1 and KB2519277.
- VS2022 Build Tools for MSBuild; `vswhere` resolves its path.
- External KenshiLib/Boost dependencies restored below, plus pinned, patched ENet;
  these dependency sources are not included in a fresh project checkout.
- `KENSHILIB_DIR` pointing to `third_party\KenshiLib_deps\KenshiLib` and
  `BOOST_INCLUDE_PATH` pointing to `third_party\KenshiLib_deps\boost_1_60_0`.

`scripts\v100_env.cmd` supplies PATH, INCLUDE, LIB and an absolute `MtToolPath`
from an installed SDK. Build commands fail if either DLL fails.

## Restore external dependencies

Clone the public source repository, then check out the exact existing release
tag whose binaries you intend to reproduce (replace `<source-tag>`):

```bat
git clone https://github.com/kotetsyy/KenshiCoop4up.git
cd KenshiCoop4up
git checkout <source-tag>
```

From a fresh checkout of the release tag, restore the dependency revisions used
for public builds. Git LFS is required for KenshiLib libraries and the Boost archive:

```bat
git clone https://github.com/BFrizzleFoShizzle/KenshiLib_Examples_deps.git third_party/KenshiLib_deps
git -C third_party/KenshiLib_deps checkout b566d74bf3d74629cc2fb632a97595b8202993f1
git -C third_party/KenshiLib_deps apply ../vc10_compat/kenshilib-v100.patch
git -C third_party/KenshiLib_deps lfs pull
tar -xf third_party/KenshiLib_deps/boost_1_60_0/boost.zip --directory third_party/KenshiLib_deps/boost_1_60_0
git clone https://github.com/lsalzman/enet.git third_party/enet/enet
git -C third_party/enet/enet checkout 5a9c537fd464b3c6d3c55e1d3bd47588faf71b42
git apply third_party/enet/patches/0001-enet-c89-for-loops.patch
git apply third_party/enet/patches/0002-enet-socket-hooks.patch
```

Keep these revisions pinned when reproducing an existing release. A future
dependency change requires an explicit source/release update, not a checkout
of dependency `latest`. External libraries remain outside the mod ZIP; the
patches and v100 compatibility headers are tracked in this repository.

`kenshilib-v100.patch` records the existing v100 header compatibility fixes:
a shared enum guard and a complete `CraftingItem` placeholder for a by-value
container declaration. The placeholder is not a recovered native ABI layout;
do not construct native crafting objects or access their item containers with it.

## Build without touching the game

```bat
scripts\build_plugin.cmd Release
scripts\build_plugin.cmd Harness
```

`build_plugin.cmd` builds both `src\plugin\x64\<Config>\KenshiCoop.dll` and
`src\ui\x64\<Config>\KenshiCoopUI.dll`. Default configuration is Harness;
Release excludes the scenario harness. `build_ui.cmd` builds only the UI;
`deploy.cmd ... ui` replaces only the UI. Keep the game closed while deploying.

The UI uses v100 `/MD` and the game's release STL layout, including in its Debug
configuration: it modifies engine-owned strings. Cross-DLL communication uses
only the packed, versioned POD C ABI in `src\ui\CoopUiApi.h`. RE_Kenshi loads
only the core; the core loads and pins the UI beside itself. No hot reload.

VS2022 supplies MSBuild orchestration, not a replacement C++ ABI. The compiler,
SDK and `/MD` runtime must remain v100 / SDK 7.1 / KB2519277 as above; an ordinary
modern-compiler hosted build is not an ABI-compatible substitute. This repository
has no root GitHub Actions workflows: builds and publication are manual and
controlled on a suitably provisioned Windows machine.

Game-independent verification (builds/runs local test artifacts, does not install
into or launch Kenshi):

```powershell
pwsh -NoProfile -File scripts/verify.ps1
```

No historical test count is evidence that the current checkout passes. Record
the actual output for the source/configuration being released.
The crawl-oracle fixtures format numeric log fields with invariant culture,
matching the decimal-point native logs regardless of the Windows locale.

## Deploy only to an explicitly chosen installation

These commands mutate the selected game installation; they are not verification
commands. Keep the game closed and use a disposable test installation for Harness:

```bat
scripts\deploy.cmd "D:\SteamLibrary\steamapps\common\Kenshi" Harness
scripts\deploy.cmd "D:\SteamLibrary\steamapps\common\Kenshi" Harness ui
```

## Distribution and updates

Package the matching Release pair from the repository root:

```powershell
pwsh -NoProfile -File scripts/make_mod_kit.ps1 -Configuration Release -SkipBuild
```

This creates `dist/KenshiCoop-kit.zip` with exactly four runtime files under
`KenshiCoop/`: core DLL, UI DLL, mod and RE_Kenshi JSON. Packaged hashes are
checked against build outputs; no `PROVENANCE.json` is shipped. `-SkipBuild`
requires the matching pair to have been built already. F2 creates
`coop_config.json` when saving settings; updates must preserve it.

### Manual future publication

Use an exact existing source tag at the commit used to build the DLLs, not an
automatically created tag at whatever branch tip happens to be current. Replace
`<source-tag>` below with that tag, and check its source and build version agree.
Publish three assets: the four-file ZIP and the standalone core/UI DLL pair.
Release installation instructions belong in the notes file:

```powershell
gh release create <source-tag> dist/KenshiCoop-kit.zip src/plugin/x64/Release/KenshiCoop.dll src/ui/x64/Release/KenshiCoopUI.dll --repo kotetsyy/KenshiCoop4up --verify-tag --title <source-tag> --notes-file dist/RELEASE_NOTES.md
```

The command above publishes remotely: do not run it during a documentation audit.
For local publisher inspection only:

```powershell
pwsh -NoProfile -File scripts/publish_release.ps1 -Owner kotetsyy -Repo KenshiCoop4up -WhatIf
```

The helper checks that the ZIP has exactly those four runtime files and that
all four packaged hashes match the selected DLL, mod and loader JSON inputs.
It prints, but never executes, the
three-asset `gh` commands with an explicit repository, an existing source tag
(`--verify-tag`) and `-ReleaseNotes` / `--notes-file`. `-Notes` is only the short
manifest summary. `-Owner` and `-Repo` override independently; omitted values
come from the existing manifest. `-WhatIf` performs these checks and previews
the manifest and commands without writing the manifest or publishing anything.

Never run the publisher without `-WhatIf` during an audit: its normal mode writes
the stable manifest. A real release must upload and verify all assets first,
then publish the stable manifest referencing the available core/UI URLs and
hashes. Both payloads are verified before replacing the installed pair; restart
the game to use them. Manual installation must replace both DLLs together.

### Source and dependency obligations

Link the exact public source tag in the release body; GitHub's automatic source
downloads contain the tracked project files, not the external dependencies.
The pinned fetch instructions above, ordered patches and compatibility headers
are part of reproducing the build. Do not add a separate player-facing source
archive as a release asset. Preserve nhoral's original authorship and
https://github.com/nhoral/KenshiCoop credit; kotetsyy maintains this derivative.

Preserve the project's AGPL-3.0 and all applicable GPL/dependency notices,
including ENet's MIT notice and the notices accompanying KenshiLib, Boost and
other linked dependencies. Before distribution, ensure corresponding source and
required notices for the actual distributed components remain available under
their respective licenses; do not assume a precompiled dependency bundle or
the project's automatic source ZIP alone satisfies every obligation.

The current public Release pair uses protocol 70; the Harness pair uses
`NET_DIAG` protocol 71. Both share the load-specific READY barrier and a 1 ms
maximum idle ENet wait; only the diagnostic pair mirrors the client's local log.
Harness forcibly disables the public updater; distribute it as a manual kit.
The packed `TimePacket` is 21 bytes in both configurations (`readyLoadId` is
always present). Earlier public 59/64/66/68 and diagnostic 63/65/67/69 pairs are rejected at handshake.
`InvItemEntry` is 165 bytes: stock snapshots also carry the native loose section
and two grid coordinates. Complete building stock restores the host's physical
stacks at those positions instead of attempting a different greedy packing.
`SpawnInfoPacket` is 211 bytes: a merchant description includes its shop home
and the actual host platoon template SID. Native `isATrader` reads that
template's `is trader` flag; the character SID and squad role alone are insufficient.

Historical v0.1.25 behavior: it targets 100 Hz entity snapshots with a 10 ms send interval on the existing
monotonic QPC clock, not the coarse `GetTickCount` clock. The sender retains its
snapshot buffer capacity between sends and preserves capture-time wire stamps.
Fresh captures remain game-frame-paced; interpolation adapts to those stamps
and ignores duplicate captures. The 50 ms distant-NPC slice selection and other
channel budgets are unchanged. Its public 64/diagnostic 65 packet formats did not change.

### Manual Harness kit installation

```powershell
pwsh -NoProfile -File scripts/make_mod_kit.ps1 -Configuration Harness -SkipBuild
```

After building the matching Harness core/UI pair, this creates the four-file
`dist/KenshiCoop-dev-kit.zip`. With both games closed, install the same kit on
HOST and JOIN by copying `KenshiCoop/` into `<Kenshi>/mods/`, replacing the two
DLLs, mod and RE_Kenshi JSON while leaving `coop_config.json` intact. Launch
through Steam or `kenshi_x64.exe`; no separate launcher or private update feed
is required or provided by this public source process.

This remains experimental two-player co-op. Three/four-player sessions are not
validated; see the README's known issues and report-bugs directions rather than
treating a build or a historical regression report as game-level validation.
