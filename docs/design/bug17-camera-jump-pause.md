# Bug #17 design: a long camera jump pauses both players

Status: **step 1 (speed diagnostics run) in progress** — October 16, 2026.
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
