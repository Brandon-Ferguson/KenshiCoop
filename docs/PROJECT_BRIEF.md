# Kenshi Co-op Mod — Project Brief

Read this first before working on the mod. It records the research and decisions from the
original planning (October 15, 2026).

## Who and what

- **Owner:** Brandon (GitHub: Brandon-Ferguson). First-time modder; experienced with Godot/GDScript,
  new to C++ and to this codebase. Explain C++/Windows build concepts plainly, but don't
  dumb down the engineering.
- **Goal:** host-your-own online co-op for Kenshi. One player hosts on their own PC, friends
  join over the internet (not LAN). Target **2 players rock-solid**, support **up to 4**.
  No persistent/dedicated server and no MMO features.
- **Testing:** Brandon tests with a remote partner, so every feature must work across a
  real internet connection (Steam P2P preferred, so no port forwarding is needed).
- **Build machine:** Windows only. Kenshi and the v100 toolchain do not run on macOS.

## What this repo is

Brandon-Ferguson/KenshiCoop: forked from nhoral/KenshiCoop, then fast-forwarded to
**kotetsyy/KenshiCoop4up** (remote `upstream`), which is a fork of nhoral's original.

- `nhoral/KenshiCoop` is the original co-op mod (last update Aug 10, 2026, v0.51). Two
  players is its design target.
- `kotetsyy/KenshiCoop4up` contains all of nhoral's history plus ~25 more releases
  through Oct 13, 2026 (v0.1.31): 3–4 player support (implemented, but its README says
  3–4 is not validated in real sessions), a player roster, native co-op UI, Unicode save
  bootstrap, 100 Hz entity snapshots, merchant stock fixes, combat target fixes, and more.
- We use the 4up line as our base because it is the actively maintained superset.
  Pull future upstream fixes with `git fetch upstream` and merge.

### License (must follow)

AGPL-3.0, and it links KenshiLib (GPLv3). Our fork must stay public and open source under
AGPL-3.0, keep the existing LICENSE, and keep credits to **nhoral** (original mod),
**kotetsyy** (4-player fork), and **BFrizzleFoShizzle** (RE_Kenshi + KenshiLib).
Don't remove attribution from README or source headers.

## How the mod works (architecture summary)

- Kenshi modding has two layers. The official FCS editor makes *data* mods (items,
  factions, game starts) and can't do networking. Multiplayer lives in *native code*:
  **RE_Kenshi** (free on Nexus, mod 847) loads plugin DLLs into the game, and
  **KenshiLib** exposes Kenshi's internal classes so we can read state and hook functions.
- `KenshiCoop.dll` (core, `src/plugin/`) is loaded by RE_Kenshi, hooks the engine through
  KenshiLib, and does all game mutation on the main thread. `KenshiCoopUI.dll`
  (`src/ui/`) is the F2 panel; the core loads it. They talk only through the C ABI in
  `src/ui/CoopUiApi.h`.
- Networking: ENet over UDP with an optional Steam P2P tunnel (`src/plugin/net/`).
  Wire protocol headers are in `src/netproto/` (plain C++03).
- Authority model: the **host is authoritative for the world**; **each player is
  authoritative for their own squad**. Remote players' characters are AI-suppressed
  "puppets" driven by the owner's updates.
- Saves: while connected, the joiner's local saves are suppressed and the **host's save
  is the only real save**; it is streamed to the joiners (`src/plugin/sync/SaveXfer.cpp`,
  save edges in `src/plugin/Plugin.cpp`).
- Key source areas: `sync/Replicator*.cpp` (what gets replicated and who owns it),
  `game/Engine*.cpp` (wrappers around Kenshi internals), `net/NetLink.cpp` (connections,
  disconnects), `test/Scenario*.cpp` (automated scenarios), `scripts/` (build, deploy,
  two-client test harness, regression suite).
- **Read `docs/REPLICATION_PITFALLS.md` before changing any sync code.** It records
  hard-won rules, e.g. budget in milliseconds not ticks, never conclude from a single
  engine read, fabrication must prove absence.

## Build environment (Windows only)

Follow `docs/BUILD_SETUP.md` exactly. Summary of what must be installed:

- **Visual C++ 2010 x64 compiler (v100), Windows SDK 7.1, and KB2519277.** KenshiLib
  requires the v100 ABI; a modern compiler is NOT a substitute.
- **VS2022 Build Tools** (only for MSBuild orchestration; `vswhere` finds it).
- **Git LFS** (KenshiLib libraries and the Boost archive are LFS files).
- Restore dependencies at the **pinned revisions** listed in `docs/BUILD_SETUP.md`
  (KenshiLib_Examples_deps at b566d74…, apply `kenshilib-v100.patch`; ENet at 5a9c537…,
  apply both ENet patches). Set `KENSHILIB_DIR` and `BOOST_INCLUDE_PATH`.
- Build: `scripts\build_plugin.cmd Release` (or `Harness` for the test scenarios).
- Verify without touching the game: `pwsh -NoProfile -File scripts/verify.ps1`.
- Package: `pwsh -NoProfile -File scripts/make_mod_kit.ps1 -Configuration Release -SkipBuild`
  produces `dist/KenshiCoop-kit.zip` (core DLL, UI DLL, .mod, RE_Kenshi JSON).
- **Careful:** `scripts\deploy.cmd` writes into the Kenshi install AND
  `%USERPROFILE%\Kenshi-Join` if it exists. Keep both games closed, and confirm with
  Brandon before deploying.

### Game requirements

- **Kenshi 1.0.65 runtime, windowed mode.** The mod hard-codes 1.0.65 addresses
  (e.g. `EngineInventory.cpp`, `EngineWorld.cpp`), so the game must *run* as 1.0.65.
- **Steam's Kenshi is 1.0.68; RE_Kenshi handles it.** Install **RE_Kenshi v0.3.5+** with its
  installer (github.com/BFrizzleFoShizzle/RE_Kenshi releases). On 1.0.68 the installer builds
  a downgraded **1.0.65** exe at `<Kenshi>\RE_Kenshi\kenshi_x64.exe` and adds
  `Plugin=RE_Kenshi` first in `Plugins_x64.cfg`. The main menu then reads
  "RE_Kenshi v0.3.5 - Kenshi 1.0.65", which is the check that the setup is right. No Steam
  downgrade is needed. The root `kenshi_x64.exe` stays 1.0.68 (`--norekenshi` launches it
  vanilla). This is the setup on Brandon's dev machine.
- If Steam updates Kenshi again, rerun the RE_Kenshi installer and recheck the main-menu
  text before testing. Every player needs the same setup and should confirm the same
  "Kenshi 1.0.65" text.
- RE_Kenshi's log is `<Kenshi>\RE_Kenshi_log.txt`. Undo: the installer's Uninstall, or
  remove the `Plugin=RE_Kenshi` line from `Plugins_x64.cfg`.
- Mod logs: `<Kenshi>\KenshiCoop_*.log`. Crash dumps: `crashDump1.0.65_x64.dmp` in the
  Kenshi folder.
- Every player must run the **identical build** (protocol mismatch is rejected at
  handshake) and should run the identical mod list and load order.

## Bug list (our work queue)

Sources: nhoral/KenshiCoop GitHub issues (#65, #67, #72, #74, #84, #86), the v0.50
release notes, YouTube/Steam player feedback. "Unverified" means the fork may have
fixed it. Reproduce in a real session before claiming a fix.

| # | Bug | Source | Status in code | Priority |
|---|-----|--------|----------------|----------|
| 1 | Joiner's squad names, player faction name, and job queues are wiped on every save cycle. Host-set data survives; joiner-set data doesn't. | #74 | **CONFIRMED.** Nothing replicates squad display names, faction name, or job lists from joiner to host. The host's serialized save lacks them and is pushed back over the joiner's local state. | **High — start here** |
| 2 | Access-violation crash, frames `KenshiCoop.dll+0x211bf` / `+0x21388`, during save-transfer staging and right after `SCENARIO PROXY` squad creations. Fires repeatedly per evening. Possibly same as nhoral #31 ("crash from faction squad appearing"). | #74 | Those two frames are likely the plugin's own crash handler; the real fault is EXECUTE of an unmapped address (same low offset `...E567` each time → jump into an unloaded module or stale function pointer). Need the dump; the reporter attached `KenshiCoop-crash-evidence.zip` to nhoral/KenshiCoop issue #74. | High |
| 3 | Fighting side by side: the joiner's character lands ~1 hit in 50. Fighting apart is fine. | #67 | **NOT REPRODUCED** on this build (`fix/coop-melee-hits`, scenario `melee_together`, cell authority on). Side by side (one cell, host authors the NPCs, joiner hits go through the HIT SEND report path) the joiner landed 27.5 and 26.9 hits/min. Apart (own cell, native hits) it landed 20.7 and 20.0/min. Ratio 1.33 / 1.34, nowhere near 1 in 50. Likely fixed by the fork's v0.1.16 target translation. Runs 20261016_213946, 20261016_214243. | Ruled out |
| 4 | Host crashes instead of disconnecting cleanly when a friend quits or times out. | v0.50 notes | Disconnect paths changed in the fork (`net/NetLink.cpp`). Unverified. | High |
| 5 | Joiner connects but sees no characters; time of day differs. Tried Steam, UDP, Tailscale, Hamachi, Radmin. | #86 | Unverified. | High if we hit it |
| 6 | Can't see or heal the other player's characters' health. | #72 | Partial medic animation sync; health readout not replicated. | Medium |
| 7 | Lockpicking and stealth knockouts don't sync, causing follow-on desyncs. | #72 | Some handling exists. Unverified. | Medium |
| 8 | Shop shelf/table items don't sync (duplication exploit). | #72 | Fork v0.1.27 "complete merchant stock". Unverified. | Medium |
| 9 | Kidnap / imprisonment desync. | #65 | Unverified. | Medium |
| 10 | Large groups teleport (~2 position updates/sec). | v0.50 notes | Fork moved to 100 Hz snapshots (v0.1.25). Unverified. | Medium |
| 11 | Can't put the other player's unconscious character in a bed. | #72 | Unverified. | Low |
| 12 | Street props (e.g. Hub sleeping bags) placed differently per player each load. | #72 | Unverified. | Low |
| 13 | Research bench not using books. | #84 | Unverified. | Low |
| 14 | No mod-list/version parity check at connect (cost reporters hours of confusion). | #74 | Missing. Cheap win. | Medium |
| 15 | Double damage: while the host authors the NPCs, the joiner reports every guarded melee hit it sees, including NPC-vs-NPC hits and the host's own swings, and the host applies them a second time. | Found during Bug #3 | **FIXED** on `fix/coop-hit-double-damage`. Cause: the hook accumulated every guarded hit, and the attacker set was the whole player faction (both clients' squads). Fix: report a hit on an NPC copy only when this client's own squad swung; hits on squad bodies (floater path) are unchanged. `KENSHICOOP_HIT_OWNER_FILTER=0` restores the old rule. A/B gate `hit_report_owner`: filter ON PASS (13 non-own hits, 0 reported; host applied 12 for the joiner's 12 own hits; run 20261016_220005). Filter OFF FAIL (7 of 7 leaked; host applied 25 for 15 own hits; run 20261016_220250). melee_together with the fix (run 20261016_220531): all 10 own hits and all 18 squad-body hits still reported, 3 others held back. Its together/apart ratio was 0.58 (14.4 vs 24.8 hits/min, 6 hits in 25 s) against 1.33/1.34 before. Rechecked, and it was noise: two more runs with the fix gave together 22.5 and 36.4 hits/min (ratios 4.33 and 1.52; runs 20261016_221532, 221816). So together ranges 14-36/min with the fix vs 27.5/26.9 before, and the apart baseline itself swung 5-25/min. Bug #3 stays ruled out. | Fixed (not merged) |
| 16 | During melee_together (seen while the bar fight was on), the host screen repeatedly goes black inside the bar, with only the host's character model showing, and the characters look slightly desynced. | Seen by Brandon watching runs, 2026-10-16 | Not investigated. The harness frames (host_1..5.png) are taken at run end, so they don't show it (20261016_220531's show the bar rendering normally, with terrain clipping into the camera); capturing it needs frames during TOGETHER (14-44 s). One sighting was timed: run 20261016_221532, about 22:17:50-22:18:00 by Brandon's report, which falls in the APART phase (22:17:32-22:18:02), after the scenario teleported the host's only character 6000 u out of the bar (`park`). The host's own camera stayed on the bar the whole time (`[cam] center=-51193.9,1581.0,2646.2` both before and after). Lead: the camera is left inside the bar with no host character there, so this sighting may be a scenario artifact (park moves the body, not the camera). Second sighting captured: run 20261016_221816 at 22:20:34 (screenshot tools/test-runs/bug16_222034_614.png), again APART, 33 s after the park. The host window shows no bar building, floor or roof, only a terrain slab and the fighting characters (driven copies of the join and NPCs) against black; the join renders normally. Likely cause: the host unloads the bar once none of its own characters is near, while the mod keeps streaming the peer and NPC copies. That could also happen in real play when the host looks at the friend's fight far from its own squad. Still to check: that case outside the scenario, whether it ever happens in TOGETHER, and the desync. **Resolved as a test artifact** (docs/design/bug16-host-black-interior.md): friend_indoors (run 20261016_225407) shows the host draws the bar open with only the joiner inside, and its copy of the joiner is marked inside, so there is no co-op bug. The void came from melee_together leaving the host camera in the bar after its park. The scenario now moves the camera with the parked squad (one run so far, with no APART hits; being rechecked). | Not a bug (test fixed) |

## How we work

1. **Build first.** Before touching code, get a clean Release build and run
   `scripts/verify.ps1` so we know the toolchain is right.
2. **Baseline play test.** Brandon and his test partner play the current build for
   ~30–60 minutes, fighting together, trading, saving and loading, and disconnecting.
   Collect both players' `KenshiCoop_*.log`, `RE_Kenshi_log.txt`, and any crash dumps.
   This tells us which "unverified" bugs are real.
3. **One bug per branch** (`fix/<short-name>`), small commits, clear messages. Add or
   extend a scenario in `src/plugin/test/` plus an oracle in `scripts/oracles/` when a
   bug can be automated. The repo's own rule is that a gate must be able to fail.
4. **Protocol changes:** any change to wire packets bumps the protocol number in
   `src/netproto/Wire.h` (see the comment there). Both players must update together.
5. **Before every deploy or game launch, say what will be written where and ask
   Brandon.** He may be mid-campaign.
6. Keep the bug table above updated as bugs are confirmed, fixed, or ruled out.

## Ideas for later (not now)

- Separate wallets per player (Kenshi has one player wallet; currently shared).
- Who controls pause/game speed (host only, all must agree, or no pause in MP).
- A friendlier lobby than swapping Steam IDs.
- Validate 3–4 player sessions for real.

## First steps

1. Confirm the repo state (`git remote -v`, `git log --oneline -5`) and that we're on the
   `brandon-fixes` branch.
2. Check what's installed on this Windows machine (Git, Git LFS, VS2022 Build Tools,
   VC++ 2010 v100 toolset, Windows SDK 7.1, PowerShell 7, Kenshi + version, RE_Kenshi),
   then walk Brandon through installing whatever's missing per `docs/BUILD_SETUP.md`.
3. Get a clean build and a passing `verify.ps1`.
4. Then start on **Bug #1** (squad names / faction name / job queues) with a design plan
   before writing code.
