# Bug #17 design: a long camera jump pauses both players

Status: **fix A passes its gate and fails its off arm as designed; speed_sync fails identically without the fix (pre-existing)** — October 16-17, 2026.
Bug source: found during bug #16 (docs/design/bug16-host-black-interior.md);
docs/PROJECT_BRIEF.md bug table row 17.

## Symptom

melee_together with the host camera following its parked squad (the realistic
case) landed **no melee at all** in the APART phase in 3 of 3 runs (225651,
230209, 230458), against hits in 5 of 5 runs that left the camera on the bar.

## What the logs show (run 20261016_230209)

| Time | Event |
|---|---|
| 23:04:00.656 | Host parks its squad 6000 u away; its camera jumps there (`cam=1`) |
| 23:04:00.746 | Host: `[speed] REQ mult=1.00 paused=1 combat=0 kind=1` (kind 1 = PAUSE intent) |
| 23:04:00.746 | Host: `[speed] SET mult=1.00 paused=1 ... owner=0` (committed and broadcast) |
| 23:04:00.757 | Join: `[speed] SET mult=1.00 paused=1` |
| 23:04:09 to end | Game clock frozen on both: host `40.56538`, join `40.56456` |

In the run that landed hits (221816) the clock kept advancing through APART
(40.738 -> 40.784). In the zero-hit runs the joiner's leader stayed in one
combat state for the whole 30 s (DECISION or STUMBLE), which is what a frozen
simulation looks like.

## Cause (partly confirmed)

The speed sync (`Replicator::syncSpeed`, `engine::consumeSpeedIntent`) treats
any engine pause it cannot explain as a player's pause vote. Only
`togglePause` (save completion) is whitelisted as engine-made. The host's
camera jumping 6000 u most likely makes Kenshi pause while it loads the new
area. That pause is captured as a PAUSE intent, committed as the shared state
and sent to the join. Nobody unpauses in an automated test, so both games stay
paused.

Not yet known:

1. Which engine call pauses (`userPause` from inside the engine, `togglePause`,
   or a direct write the poll picks up).
2. Whether Kenshi unpauses by itself once loading finishes and the mod then
   re-applies the shared pause (the host re-sends the speed state every 3 s and
   writes it quietly), which would make a mod-made permanent pause out of a
   brief engine one.

In real play a player would press space, so the impact there is an unexpected
shared pause on long camera jumps (double-clicking a far squad member, map
travel), not broken combat. That is still worth fixing, and the test needs it
fixed to measure APART at all.

## Plan

### Step 1 - measure (no behaviour change)

Add `KENSHICOOP_DEBUG_SPEED=1` to melee_together's DiagEnv (an existing
diagnostic switch already on the harness whitelist). It logs every
`setGameSpeed` / `userPause` / `togglePause` call and every poll decision
(`[speeddbg] ...`). Run melee_together once and read what happens around the
park.

### Step 2 - the fix (designed after step 1; approved before any code)

- **A (preferred).** Treat the loading pause as engine-made, like save
  completion: explain it to the poll so it never becomes a vote. Only the
  speed-sync input changes; real pause clicks and keyboard pauses behave as
  today.
- **B (only if A cannot identify the loading pause).** Ignore an engine pause
  that ends by itself within a few seconds.

### Step 3 - test hygiene

melee_together reports "game paused in APART" as an explicit failure reason,
from the `[time]` clock and `[speed] SET paused=1` lines, so a frozen clock can
never read as "no hits" again.

## Safety checks for step 2

1. An off switch restoring today's behaviour.
2. A gate scenario: the host jumps its camera far away and the join must not be
   left paused beyond a moment; the off-switch arm must FAIL.
3. `speed_sync`, `speed_probe` and `time_sync` still pass, plus the smoke tier.
4. A manual check that pause, unpause and the speed buttons still sync both ways.

## Out of scope

The joiner's copy of the host leader staying pinned in a local fight
(`[drive] freeze why=combat-skip`) after the host leaves. It is a separate
desync, seen in runs with and without this pause.

## Step 1 result - run 20261016_231422 (speed diagnostics on)

APART again landed no hits (0 in 30 s), and the `[speeddbg]` lines show the
whole chain on the host. `guard=1` marks the mod's own quiet writes; `guard=0`
is the engine acting by itself; `i` is the pause argument.

| Time | Line | Meaning |
|---|---|---|
| every 3 s before | `userPause i=0 guard=1` + `togglePause i=0 guard=1` | the mod's safety resend writing "running" |
| 23:16:10.088 | `MELEE PARK ... cam=1` | host squad parked 6000 u away, camera jumps with it |
| 23:16:10.157 | `togglePause i=1 guard=0` | **Kenshi pauses itself** (69 ms later): the loading pause |
| 23:16:10.175 | `poll engineDiff=0 btnDiff=1 ... btn=1000 vote=0100` | the togglePause hook explained the engine state, but Kenshi also lit the pause button, and the button detector read that as a click |
| 23:16:10.175 | `[speed] REQ ... paused=1 kind=1`, `[speed] SET ... paused=1` | committed as a shared pause and sent to the join |
| 23:16:21.772 and 22.002 | `togglePause i=0 guard=0` | **Kenshi unpauses itself** once loading finishes (~11.6 s) |
| 23:16:22.206 | `userPause i=1 guard=1` | the mod's 3 s resend **re-applies the pause** |
| every 3 s to the end | `userPause i=1 guard=1` | the shared pause is held for the rest of the run |

So:

1. **What pauses:** Kenshi's own `togglePause(true)` while it loads the area
   the camera jumped to. The `togglePause` hook already treats engine state
   changes as engine-made (`engineDiff=0`). The leak is the **button-highlight
   detector**: Kenshi highlights the pause button as part of its own pause, and
   `consumeSpeedIntent` reads a newly highlighted pause button as the player
   clicking it (`btnDiff=1`, `newIdx == 0` -> `SPEED_INTENT_PAUSE`).
2. **Why it never ends:** Kenshi does unpause itself after about 11.6 s, but by
   then the pause is the shared state, and the mod's 3-second resend writes it
   back. A brief engine pause becomes permanent.

Impact in real play: whenever a long camera jump makes Kenshi load (double-
clicking a far squad member, following a teleport), both players are left
paused until someone presses unpause. It is recoverable, not a combat bug.

## Step 2 - fix A, concretely (for approval; no code yet)

When the engine itself calls `togglePause` (the unguarded hook path), note
that the pause button's highlight now belongs to the engine. Then:

- the button detector ignores the pause button lighting up while that engine
  pause is in effect (a real click on pause during it changes nothing anyway,
  since the game is already paused), and
- once the engine unpauses, the vote highlight is restored as it is today.

Only the input classification changes. A real pause click (button or space bar)
still goes through the existing paths, which do not depend on this flag. Plus
the off switch and the checks under "Safety checks for step 2".

## Step 2 - fix A as implemented (built, not yet run)

The space bar also reaches the engine through `togglePause`, so "the engine
called togglePause" alone cannot tell a loading pause from a real press. The
fix therefore keys on a condition only a loading pause meets: **the zone under
the camera is not fully loaded** at the moment of the call
(`isZoneLoadedAt(camera centre)` is false while unloaded or mid-load).

- `togglePause_hook` (EngineInternal.cpp): before the engine acts, on an
  unguarded `togglePause(true)` it reads the camera centre and that zone's load
  state. Not loaded: set the hold `g_engineLoadPause`. Any unguarded
  `togglePause(false)` clears it. Every unguarded call logs `[speed] ENGINE
  togglePause on= camZoneLoaded= loadPause=a->b`.
- `consumeSpeedIntent` (EngineCharState.cpp): while the hold is set and the
  engine is paused, a newly lit **pause** button (index 0) is not a click. A
  speed-tier button (index > 0) still counts. A running engine clears the hold
  however it resumed.
- `writeGameSpeedQuiet`: while the hold is set and the engine is paused, a
  quiet write keeps the pause instead of lifting it mid-load. It never pauses a
  running engine; if the engine is already running, the hold is cleared.
- Off switch `KENSHICOOP_LOAD_PAUSE_LOCAL=0` (Config, harness-whitelisted):
  no classification happens, so behaviour is exactly the old one apart from
  the extra log line.
- If the camera or zone read fails, nothing is classed as a loading pause
  (today's behaviour).

Known edge case (accepted): a player who presses pause while the engine's
loading pause is already in effect does not share that pause, and the game
resumes when the engine finishes loading. Pausing an already-paused game was a
no-op before, too.

Tests:

- `camera_jump_pause` (gate) and `camera_jump_pause_off` (A/B arm, switch
  off): the host parks 6000 u away with its camera. `Test-CameraJumpPause`
  FAILs when the join is paused in more than 3 samples or the host is still
  paused in its last 10 samples, and FAILs setup when no engine loading pause
  happened. The off arm must FAIL.
- melee_together's oracle now names a paused APART explicitly: "game was PAUSED
  for N of M APART samples". It flags runs 230209 and 231422 (30 of 30) and
  leaves 221816 alone.
- Synthetic oracle cases: pass, shared, stuck and no-engine-pause all classify
  correctly.
- The shipped Release DLL carries the fix; the gate scenario is Harness-only.

## Step 2 results - October 17, 2026 (fix A build)

| Scenario | Run | Result | What it showed |
|---|---|---|---|
| camera_jump_pause | 20261017_080626 | **PASS** | Engine pause classified (`camZoneLoaded=0 loadPause=0->1`); host paused 13 of 40 samples then resumed (last 10: 0); join paused 0 of 40; 0 pause votes |
| camera_jump_pause_off | 20261017_080857 | **FAIL (expected)** | Switch off (`camZoneLoaded=-1`): 1 pause vote; join paused 39 of 40; host still paused at the end. The gate catches the bug. |
| melee_together | 20261017_081123 | FAIL (test, not fix) | Host loading pause 08:13:09-08:13:23 stayed local; the join was never paused; the join's clock slewed to 0.25 while the host was paused and caught up by ~08:13:32. But the join's leader was **knocked out** at 08:13:12 (`EVT_KNOCKOUT ... bs 0->1`, by the NPC its copy of the host leader was still fighting) in the gap before APART, so it fought 0 s there. A real fight outcome now that the game keeps running. melee_together needs the join leader healthy at APART start. |
| speed_sync | 20261017_081407 | FAIL (pre-existing) | Clicks worked (`REQ mult=3.00` -> `SET mult=3.00`). The oracle's SET pattern expects `combat=N (my=`, but the log has printed `combat=N owner=N (my=` since upstream v0.52 (`ae20e29`); the base branch has the same mismatch, so it counts 0 changes. With `owner=` stripped, one reason is left: the join's same-value 1x click was sent (`REQ mult=1.00 kind=0`, the setter path), but the host had already recorded 1x from the join's routine resend echo, so it logged no new `REQ RECV`. The hold never engaged on either side (`loadPause=0->0` throughout), so none of fix A's code paths were active. Not yet compared on the base build. |
| speed_probe | 20261017_081638 | PASS | |
| time_sync | 20261017_081908 | PASS | |

## speed_sync base-build comparison - October 17, 2026

The base build (`fix/host-camera-void`, no fix A; its host log has no
`[speed] ENGINE togglePause` lines) ran speed_sync as run 20261017_083139:

| | Fix A build (081407) | Base build (083139) |
|---|---|---|
| Oracle result | FAIL, 4 reasons | FAIL, the **same 4 reasons** |
| With `owner=` stripped | 1 reason: same-value 1x click, no host `REQ RECV mult=1.00` | the **same 1 reason** |

So speed_sync's failure is pre-existing and unrelated to fix A. Two follow-ups
for whoever picks it up (not part of this fix):

1. Update Test-SpeedSync's SET pattern for the `owner=N` field (upstream v0.52).
2. Look at the same-value vote check. The host logs `REQ RECV` only when the
   request changes, and the join's routine resend had already reported 1x, so
   the check waits for a line that never comes. It could be a check problem or a
   real "stuck vote" regression; it needs its own look.

## Combined regression on merged main (955ff1a) - October 17, 2026

Smoke tier (`regress.ps1 -Tier smoke -SkipBuild`): 15 of 16 PASS. The one
failure, npc_sync (`rest_flap`, also on its retry), is the known pre-existing
failure (docs/design/npc-rest-flap.md; it fails on the base build too).
coop_presence, the other known flaky one, passed.

Bug checks: squad_meta_persist PASS, hit_report_owner PASS, camera_jump_pause
PASS, friend_indoors PASS.

melee_together (run 20261017_095434) FAIL, a new shape. The host's loading
pause stayed local (`loadPause=1->0` at 09:56:32), the join was never paused,
and its clock was back to slew 1.00 within ~6 s. The join's copy of the host
leader was not pinned this time (0 `combat-skip` freezes). Yet across all
30 s of APART fighting the join's leader never swung. It sat in the
attack-slot queue (`wait=1 sword=5` CIRCLE_MENACINGLY x17), pathfinding
(`sword=11` x7) or deciding (`sword=4` x3), while the Ninja Guard landed 4
hits on it. Fixes #1 and #15 do not touch local melee AI, and #17 is
verified working here.

The common thread of the three APART failures since the camera fix (game
paused before the fix; joiner knocked out; joiner stuck waiting) is that the
host's camera now leaves the bar with its squad, as in real play. Whether a
joiner fighting alone after the host walks far away is really impaired is an
**open question** for its own investigation. It is not a regression from the
merge: melee_together's APART only became measurable once the pause was
fixed.
