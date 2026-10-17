# NPC rest-flap and coop_presence snap_rate: diagnosis and fix plan

Status: diagnosis and design plan from existing smoke-run logs (2026-10-16). No code change yet.
The run directories named below are local `tools/test-runs` output and are not committed.

## 1. npc_sync `rest_flap` (774-1750 walk->rest flips/min, limit 60)

### What the gate measures
`Test-RestFlap` (scripts/oracles/Motion.ps1:389) diffs the cumulative `restFlip=` counter on the join's
`[interp]` line after the clock-slew window. The counter is `restFlipNpc_`, incremented at
src/plugin/sync/ReplicatorDrive.cpp:1952 whenever a near-tier NPC's `npcMoving` goes true->false.
It is summed over all driven NPCs (30-44 in these runs), not per NPC.

`npcMoving` (ReplicatorDrive.cpp:1911) is true while some tick within `moveHold` (300 ms floor, or
5x segMs) saw `vlen > NPC_MOVE_VEL` (0.75 u/s). `vlen` comes from `EntityInterp::latest()`
(Interp.cpp:149), which is the displacement between the two NEWEST ring snapshots over their dt.

### Root-cause hypothesis
The debounce was sized for a 20 Hz stream and stopped working when the stream went to 100 Hz.

- 2026-08-02, upstream 6d4dc5e: hold floor cut 1000 -> 300 ms "at ~50 ms segments" (20 Hz).
- 2026-10-09, upstream bc8f059 (v0.1.25): entity snapshots target 100 Hz. The newest-pair velocity
  now spans ~10-12 ms instead of ~50 ms. It is a single engine read (pitfall #2) taken over a much
  shorter baseline, so it reads ~0 far more often (duplicate/unchanged positions, host transform
  updating less often than the capture), and the 300 ms hold no longer bridges the dips.

### Log evidence
1. The code's own baseline (ReplicatorDrive.cpp:2289): debounced classifier 37 flips/min on npc_sync,
   instantaneous classifier 1071/min. Observed now: 1750 / 724 (fix branch, 20261016_174228 + retry),
   1529 / 774 (base, 20261016_182535 / 182810). That is the undebounced level: the debounce is defeated.
2. Segment length in these runs is 10-12 ms: every `[interp] worstZero ... seg=` line in all four
   runs reads seg=10..12 (one 20-22).
3. The flips track walking NPCs, not idle ones. In 182535, per 5 s window, flips vs. host NPCs that
   moved >0.75 u/s (host `SCENARIO WNPC` 1 Hz series): 90/15, 144/21, 179/26, 182/33, 183/32,
   92/21, 86/21. That is about one flip per walking NPC per second. Genuine host stops over the same
   window are about 23/min in total, roughly 40-70x fewer than counted flips.
4. Identical on base (eaf14f8) and fix branch (aad9033), so it is unrelated to bug #1.
5. No local history before Oct 16 to show the gate passing after bc8f059. That is the A/B below.

### Visible cost
Every flip runs the rest branch (`applyRest` at ReplicatorDrive.cpp:2402) on a body that is still
walking, and the next walk re-entry re-issues `walkTo`, which restarts locomotion. That is the
stutter the gate was written for (2026-07-11), and bug-list #10 (large groups teleport / not smooth).

## 2. coop_presence `snap_rate` (2 NPC snaps in 25 s = 4.79/min, limit 3)

- Both snaps in 20261016_183043 are one NPC: `[snap] npc hand=5,700683584 name='Dust Bandit'`,
  gap 158.5 / 154.3, gate 52.7 / 51.1, srcVel 66 / 67 u/s, 3 s apart. It entered the drive 3.3 s
  before the first snap (`[life] ... UNKNOWN to HI reason=drive`). Host/local tasks disagree:
  `[gate] hand=5,700683584 host=141 local=1 agree=42%`.
- The NPC snap fires only past 3x the gate (ReplicatorDrive.cpp:2118). Between the snaps the body
  moved about 44 u in 3 s (about 15 u/s, walking pace) while the source ran 66 u/s. So the driven
  copy steadily falls behind until the 3x gate fires again. It is not a one-off divergence.
- The same signature (running bandit, srcVel 60-75, gap 150-170, gap/srcVel ~2.5 s) shows up across
  today's runs on both branches: 173838 coop_presence (3), 174737 combat_kill, 180446 inv_regear,
  181438 world_item_stale, 183043. coop_presence fails only when a bandit runs through during its
  short 25 s scored window, so it is flaky: 2 events in 25 s are enough to fail it.
- Hypothesis (unproven): the same flap drives it. A running source with zero-displacement pairs
  flips to rest, and each rest entry halts the body and each re-entry restarts the walk from
  standstill, so the copy averages walking speed. Alternative: the local copy walks instead of runs
  regardless (move order speed vs. Kenshi run mode, task 141 not mirrored). The instrumentation
  below separates the two.
- Related 100 Hz side effect: the young-ring exemption `d.interp.samples() < 16`
  (ReplicatorDrive.cpp:2160, commented "~0.8 s of 20 Hz coverage") now lasts about 0.16 s, so
  reconciliation snaps of newly acquired bodies count as steady-state `npc` snaps. It did not cause
  these two snaps (3.3 s and 6.3 s after acquisition), but it is the same class of regression.

## 3. Proof plan (A/B gate)

Step 1, instrumentation (no behavior change, Harness build):
- A rate-limited per-flip line `[flap] hand=.. vlen=.. segMs=.. hold=.. sinceFast=.. hostSpeed=out.cSpeed
  zeroPairs=k/16` (count of zero-displacement pairs in the ring).
- A counter `restFlipFast` for flips where host `cSpeed` > walk threshold at the flip, added to the
  `[interp]` line. Gate it: a flip while the host reports locomotion speed is by definition phantom.
- For snaps: log the driven body's achieved speed over the last 1 s in `logHardSnap`.
Prediction if the hypothesis holds: most flips have zeroPairs high, sinceFast just over 300 ms, and
hostSpeed at walk/run speed, and the Dust Bandit flaps between its snaps.

Step 2, fix behind an env toggle (e.g. `KENSHICOOP_NPC_VEL_WINDOW_MS`, 0 = old newest-pair arm):
interleaved arms, at least 5 clean runs each (the repo's own single-run warning), on npc_sync and
coop_presence, plus one pre-bc8f059 Harness build as a historical control if Brandon agrees.
- Fixed arm: rest_flap <= 60/min on npc_sync. Old arm must still FAIL (the gate can fail).
- Guardrails: march idleFrac (holdStop) <= 0.01, smoothness zeroFrac within noise, snap_rate no worse.
- coop_presence: `[snap] npc` with srcVel > 40 should drop to ~0 per run across the bandit scenarios.

## 4. Proposed fix

1. Classifier velocity over a TIME window, not the newest pair (pitfall #1: ms, not samples).
   Add `EntityInterp::velocityOver(windowMs, ...)`: displacement from the newest snapshot back to the
   newest ring entry at least ~60 ms older (sender stamps), divided by that real dt. The ring (CAP 16)
   holds ~160 ms at 100 Hz, so 60-100 ms fits. Use it for `npcMoving` and `velPeak`. This restores the
   ~50 ms baseline the 300 ms hold was tuned against, independent of sender rate. Leave
   `latest()`'s lead-point velocity alone in the first change, or move it to the same estimate as a
   separate, separately gated step.
2. Do NOT raise the hold back toward 1000 ms. That reintroduces the holdStop idle march that
   6d4dc5e fixed.
3. Make the young-ring snap exemption time-based (ring span or ms since acquisition, ~800 ms) instead
   of `samples() < 16`. Separate commit.
4. If step 1 instrumentation shows the bandit copy walks even without flaps, the snap_rate fix is in
   the move-order speed / run-mode path instead. That would get its own design note.

Oracle notes (record, do not loosen to pass): `rest_flap` is a population total (60/min across 30-40
driven NPCs). Consider reporting flips per driven NPC-minute alongside it. `coop_presence`'s 25 s
scored window makes snap_rate a 2-event gate. Both are follow-ups, not part of the fix.
