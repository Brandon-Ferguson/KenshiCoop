# Bug #17 design: a long camera jump pauses both players

Status: **fix A implemented and built (verify passes); not yet run in game** — October 16, 2026.
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
