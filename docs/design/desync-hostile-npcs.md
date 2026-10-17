# Hostile-squad desync (mint_aggro): one-sided fights on the join

Status: root cause re-checked 2026-10-17; test changes done; game-code fix
awaiting approval. Field reports: nhoral/KenshiCoop#34, #54 ("I'm fighting
something my friend can't see").

## Symptom

In `mint_aggro` the host spawns a hostile squad 450 u out, the join mints
proxies for it, and later the host drops the squad beside the players. In both
Phase 1 runs the join shows enemies fighting while the host has the same
bodies idle:

| run | cell auth | longest join-only streak | join-only / pairs |
|---|---|---|---|
| 20261017_121900 | off | 5 samples (enemy 3, from 12:20:22) | 13 / 60 |
| 20261017_125247 | on  | 4 samples (enemy 3, from 12:54:06) | 12 / 30 |

Host-only streaks never exceed 2. The defect is one-directional: the join
invents fights.

## Root cause (corrected)

The first write-up blamed the `mid-rest` release in `ReplicatorDrive.cpp`
(stationary mid-tier NPCs handed back to local AI). The logs do not support
that: in run 125247, enemy 3 was not released (`[life] ... reason=mid-rest`)
until 12:54:10.135, after its one-sided fight. In run 121900 the release came
at 12:20:32.9, also after the fight. Every join-only streak in both runs
instead follows a replayed host combat intent:

```
125247  12:54:01.881  [combat] order hand=4,... tgt=1,3332275456 (join leader)
        12:54:01.980  [combat] order hand=3,... tgt=1,3332275456 (join leader)
        12:54:02.055  [combat] order hand=5,... tgt=1,2637329152 (host leader)
121900  12:20:17.624 / 17.862 / 18.049  the same three orders
```

What the host was doing at the time:

- Each enemy streamed a combat task (`TASK_COMBAT_MELEE`) for an instant,
  aimed at a player character about 440 u away.
- None of them moved. Host `MEMBER` samples keep enemy 3 at -50737 with
  task 65535 (idle) from 12:54:02 to 12:54:10.
- The host's own fight read (`enemystate fight=`) is 0 for enemies 3 and 4
  throughout, and 1 for enemy 5 for a single sample.

So on the host the enemy wanted to fight but never actually did. The join
replays that intent as a real attack order (`engine::applyCombat`). Its copy
charges 440 u, engages the join's characters, and fights for several seconds.
Three things then keep that fight going:

- **Missing pull-back.** Nothing on the host side pulls it back. The host keeps
  streaming the body as standing still far away.
- **The 4 s combat hold.** After the host's combat task disappears, the join
  holds the fight for 4 s (`COMBAT_DISARM_MS`). During that time the copy's
  AI is not suspended, by design: "their AI must run to animate".
- **The join's own characters fight back.** They retaliate locally
  (`[combat] order hand=3,3090698240 tgt=<enemy>` at 12:54:02.348), which
  re-engages the copy.

In short: the join turns "wants to fight" into "fights". Whenever the host's
body holds a combat intent it is not acting on, the two screens split.

### Why the host's enemy does not act on it (unconfirmed)

The scenario `park()`-teleports the squad 450 u out, onto a rise about 49 u
above the travel plane (see the `approachMint` comment in
`ScenarioCombat.cpp`). The leading guess is that the host's bodies cannot path
from there. That part may be test-specific. The replay rule is not: in real
play the same split happens whenever a host NPC holds an attack intent it
cannot carry out, for example because of a blocked path, water, a cliff, or a
target the host's AI rejects.

### Separate finding: proxy_drift "runaway" readings

The 448-463 u readings in run 125247 are a settle transient:

- The host teleports the squad.
- The census re-parks the proxy one or two sweeps later.
- On the sweep after that, drift is back to 0-48 u.

Real NPCs do not teleport. In run 121900 the drift gate still fails, but for
the real symptom: a proxy fighting 231 u from its owner's copy.

## Done (test only, no game code)

1. **`one_sided_fight` gate** (`scripts/oracles/Combat.ps1`, gating in
   `mint_aggro`).
   - It fails when one body fights on one screen for more than 2 consecutive
     one-second samples while its other copy is at peace, in either
     direction.
   - Unlike single-sample parity, a streak is not a sampling race.
   - Offline check: it fails on both baselines (streaks 5 and 4).
2. **Runaway settle window in `proxy_drift`.**
   - The 2 sweeps after a proxy's first sweep, or after an owner jump
     (`hstep` > 40 u), are exempt from the runaway check only.
   - The fighting-while-displaced check still judges every sample.
   - Offline over every saved run with drift telemetry, one verdict changes:
     125247 goes from FAIL to PASS. Run 121900 still fails on its real
     displaced fight.

## Proposed game-code fix (needs approval)

**Reach gate on the combat replay.** In the `taskIsCombat(out.task)` branch,
the join replays a melee intent as an attack order only when the host's
attacker is plausibly carrying it out:

- the host's attacker is within reach of its target, measured as the
  streamed attacker position against the target's local position; or
- the host's attacker is moving (it is closing in).

Otherwise the body is treated as not fighting yet:

- it stays on the ordinary drive, AI-suspended, tracking the host's
  position;
- no order is issued and the combat hold is not armed.

A genuine charge still reaches the join: the copy walks in with the host's
body, and the order fires once it is in reach. `TASK_COMBAT_WAIT` (a
ring stance near the target) is unaffected.

- **Off switch:** `KENSHICOOP_COMBAT_REACH_GATE=0` restores today's behaviour.
- **Threshold:** to be measured, not guessed. Step 1 is a read-only probe that
  logs attacker-to-target distance and attacker speed on every
  `[combat] order`. It would be run in `combat_crowd`, `combat_battle`,
  `assault_travel` and `mint_aggro`, to find the largest reach at which real
  fights start versus the ~440 u phantom ones.
- **Probe (done, step 1):** each `[combat] order` is followed by its own line:
  ```
  [combat] reach hand=<i,s> tgt=<i,s> reach=<u> copyReach=<u> srcVel=<u/s> wait=<0|1> isSquad=<0|1> n=<orders>
  ```
  - `reach`: the streamed attacker pose to the target's local pose.
  - `copyReach`: our copy to the same target.
  - `-1`: the target could not be read.
  - It is read-only, and it is a separate line so the parsers keyed on the
    `[combat] order` line are untouched.
- **Probe result (runs 20261017_132904 / 133127 / 133346 / 133558, cell auth
  on): a reach gate cannot separate real fights from phantom ones.**
  - The phantom in mint_aggro 133558: enemy 5 was ordered at `reach=111`
    with `srcVel=0`. It then fought 4 samples on the join only, from 13:37:14,
    while the host had it at peace. That run fails `one_sided_fight` again.
  - Real fights overlap that from both sides:
    - `combat_crowd`: first orders on still attackers at up to 95 u;
    - `combat_battle`: orders on still attackers at 470-527 u (13:33:30-33);
    - `assault_travel`: the host replays the join PC's intent at 897 u.
  - Any threshold that blocks the 111 u phantom also blocks real fights.
- **What does separate them:** the host streams `TASK_COMBAT_MELEE` exactly
  while its own body reads in combat (`EngineEntity.cpp`, the same
  `inCombat || modeActive` the scenario's `enemystate fight=` samples). In the
  phantom the host's 1 Hz samples read 0 almost throughout, so the host's
  combat state is a brief blip. The join turns that blip into a committed
  attack order. The next measurement is how long host combat episodes last
  as the join receives them, phantom versus real, to see whether an onset
  debounce (arm only after N ms of continuous combat stream) splits them.
- **Episode probe (step 2, built, not yet run).** Read-only. One line per
  combat episode, written when the copy disarms:
  ```
  [combat] episode hand=<i,s> isSquad=<0|1> dur=<ms> maxGap=<ms> ticks=<n> fought=<n> hold=<n> holdFought=<n> orders=<n> why=<timeout|break>
  ```
  - `dur`: the first to the last drive tick that saw a streamed combat task.
  - `maxGap`: the longest silence inside the episode.
  - `fought`: the copy's engaged ticks while combat was streamed.
  - `hold` / `holdFought`: the same counts during the 4 s hold after the
    stream stopped.
  - A host blip turned into a committed fight should show a short `dur` with
    `fought` and `holdFought` high; a real fight, a long `dur`.
  - Episodes that end without a disarm (body culled, ownership flip) log
    nothing.
- **Episode probe result (runs 20261017_134937 / 135158 / 135417 / 135630,
  cell auth on): episode length does not separate them either.**
  - Real fights: `combat_crowd` median about 30 s, `combat_battle` 16-26 s.
    But real fights also have internal gaps of up to 3.3 s, and host
    episodes in mint_aggro run 9-21 s.
  - What does separate them is whether the host's body **moves**. In
    mint_aggro 135630:
    - enemies 3 and 5 walked about 250 u off the rise (-50736 to -50959,
      -50720 to -51039) and fought for real on the host;
    - enemy 4 never left its park spot (-50705,1629,2651 from 13:57:46 to
      13:58:02), with its task flickering 65024/65535;
    - the only PHANTOM episode is enemy 4 (13:57:53: dur 3245 ms, copy
      engaged 13 streamed ticks and 185 hold ticks).
  - In 125247 the same: enemy 3 stood at -50737 throughout its join-only
    fight.
  - **The phantom is a host attacker that is in combat but stuck.** It holds
    a target and cannot reach it, while its copy on the join can move and
    does.
- **Revised fix (proposal): stuck-attacker mirror.**
  - While the host streams combat for a body whose streamed position has
    moved less than a few units over the last ~2 s, and whose target is
    beyond melee range, the join's copy does not pursue. It converges to
    the host's pose (the existing soft-band walk) instead of being ordered
    to attack.
  - As soon as the host body moves or closes to melee range, the normal
    replay resumes.
  - Off switch `KENSHICOOP_COMBAT_STUCK_MIRROR=0`.
  - Thresholds to be sized offline from the saved runs first: no real fight
    in `combat_crowd` / `combat_battle` / `assault_travel` may satisfy the
    stuck rule for more than a moment.
  - Open question: how much of "stuck" is the scenario's park onto a rise.
    In real play, NPC pathing failures do happen, and the join's copy, placed
    from the stream, may not be stuck in the same way.
- **Offline sizing (35 saved combat runs, host 1 Hz `MEMBER` series).**
  - **Proxy measure.** The target is not logged for crowd and battle fights,
    so the nearest other tracked body stands in for it. A real fight
    (`combat_crowd`, `combat_battle`, `combat_kill`, `assault_travel`) is
    flagged when the host attacker is on a melee task, has moved under 5 u
    in 2 s, and has nothing within 50 u.
    - The longest such streak is 3 samples (`combat_crowd` 125517), and
      2 samples in `combat_battle`.
    - Of 1,281-1,971 melee samples per battle run, 1-16 qualify.
  - **Exact measure.** Possible only where the scenario logs the enemy's
    target (`mint_aggro` `enemystate`). It finds 0 even for the known stuck
    enemy 4. That body reads in combat only intermittently at 1 Hz (task
    65024 at 13:57:46 and 13:57:55 only, idle between), so 1 Hz host
    samples are too coarse to time the stuck state. What they do show
    clearly is that it never moved: 0 u from 13:57:46 to 13:58:02.
  - **Consequence.** A stillness *duration* threshold cannot be sized from
    these logs, and a duration rule would not stop the phantom anyway: the
    join's copy charges on the very first combat sample. The rule has to be
    about movement **at the moment of the replay**.
- **Proposed rule (stuck-attacker mirror).** In the `taskIsCombat` branch,
  replay the host's combat intent (order and pursuit) only when at least one
  of these holds:
  1. **In reach:** the host attacker's streamed pose is within **60 u** of the
     target's local pose. That is melee range plus slack; the reach probe put
     the median real order at 21-31 u.
  2. **Moving:** the host attacker's streamed speed is at least **2 u/s**.
     That is the `srcVel` the combat branch already derives from
     `d.interp.latest()`, held for 1 s after it was last above the line, so
     a pause between steps does not flip the rule. `d.velPeak` cannot be
     used: it is updated only after the combat branch, which `continue`s, so
     it is stale for any body in combat. A stuck body reads exactly 0 (enemy
     4 held -50705,1629,2651 for 16 s). A real charger crosses the line
     within its first streamed segment.
  3. **Ranged:** the local copy is in ranged mode (`readCombat().ranged`). A
     crossbow user legitimately stands still far from its target, so it is
     left to today's behaviour.

  Otherwise the copy **mirrors the host**:
  - no attack order is issued, and the body takes the ordinary drive
    (AI-suspended, tracking the host's pose);
  - if it was already armed, it disarms immediately (clearGoals), as the
    existing hold BREAK does, instead of running the 4 s hold with its AI
    live;
  - it logs `[combat] mirror hand=… reach=… vel=…` once per episode.

  - **Cost to real fights:** a real charge starts on the join when the host
    body's first movement arrives in the stream. That is up to one stream
    segment later (≤50 ms near tier, ~0.5-1 s mid tier). A real attacker
    standing still beyond 60 u (proxy: at most 3 samples) is mirrored for
    that time, which matches what its owner's body is doing.
  - **Off switch:** `KENSHICOOP_COMBAT_STUCK_MIRROR=0`.
- **Implemented (built, not yet run in game).**
  - **Where:** `ReplicatorDrive.cpp`, just before the combat branch. The
    constants are in `ReplicatorUtil.h` (`COMBAT_MIRROR_REACH` 60 u,
    `COMBAT_MIRROR_MOVE_VEL` 2 u/s, `COMBAT_MIRROR_MOVE_HOLD_MS` 1000).
  - **Off switch:** `KENSHICOOP_COMBAT_STUCK_MIRROR` (Config, Plugin, then
    `Replicator::setCombatStuckMirror`). It is on the harness allow-list, so
    the A/B is `-DiagEnvOverride "KENSHICOOP_COMBAT_STUCK_MIRROR=0"`.
  - **Scope:** world NPCs only (`!isSquad`) and `TASK_COMBAT_MELEE` only.
    WAIT stances, ranged copies and unreadable targets keep today's
    behaviour.
  - **What a mirrored body does:**
    - its streamed task is presented to the ordinary drive as `TASK_NONE`
      (what its owner visibly is), so `applyRest` never sees the synthetic
      combat task;
    - an armed copy disarms at once (`clearGoals`, episode `why=mirror`)
      instead of the 4 s live-AI hold;
    - it is excluded from the mid-rest release, so it stays AI-suspended
      rather than going back to its own hostile AI.
  - **Logs:**
    `[combat] mirror START hand=… tgt=… reach=… armed=…` and
    `[combat] mirror END hand=… after=<ms> why=peace|engage`.
  - **Known limitation:** "ranged" is the copy's *current* ranged combat
    mode. A host crossbowman standing off far from its target, whose copy has
    not drawn, is mirrored (held still) rather than shooting. Today that copy
    is sent a melee order instead, so this is not worse, but it is not right
    either. A weapon-type check would fix it.
- **A/B result, first cut (2026-10-17 14:14-14:36, cell auth on,
  interleaved): NOT good enough to keep as is.**

  | arm | runs | one_sided_fight | mint_aggro parity |
  |---|---|---|---|
  | mirror on  | 141424, 141924, 142426 | FAIL x3 (join streaks 4, 4, 4) | PASS x3 |
  | mirror off | 141654, 142156, 142700 | FAIL x3 (streaks host 3, join 5, join 4) | FAIL x3 (0.36, 0.54, 0.36) |

  - Parity moved the right way, but the gate the fix was built for did not.
  - Two holes, both seen in 141424, enemy 3:
    1. **Bad "moving" reads.** `d.interp.latest()` reported 623, 744 and
       129 u/s for a body the host had idle. These are interpolation
       corrections, not locomotion. Each spike passed the 2 u/s test, so the
       mirror ended (`after=66-135ms why=engage`) and the order went out.
    2. **The 4 s hold outlives a blip.** At 14:15:42.9 the host streamed
       combat for 32 ms (`episode dur=32ms`). The copy then fought through
       the hold: 230 of 238 hold ticks engaged, which is the 4-sample join
       streak at 14:15:43-46.
  - **Regressions:**
    - `combat_battle` and `assault_travel` passed.
    - `combat_crowd` 142931 FAILED: copy 2,2703369216 was re-ordered 31 times
      (limit 18), through 19 `hold BREAK` disarm/re-arm cycles at
      14:31:04-14:31:40. Earlier crowd runs had 1-3 breaks in total per hand
      and passed.
    - That body never entered the mirror (no START/END for it). Whether the
      change caused this is not established from one run.
- **Proposed second cut (not implemented):**
  1. **Moving.** Judge it by streamed **displacement** (the owner's pose
     moved ≥ 5 u in the last ~1 s), not by interp velocity.
  2. **Cap the hold by the episode's own age.** Hold for at most
     max(500 ms, the time the owner has streamed combat so far), up to 4 s.
     A 32 ms blip then buys about 0.5 s, not 4 s, while long fights keep
     the full lossy-batch bridge.
  3. **Rerun.** `mint_aggro` x3 on and x3 off, plus `combat_crowd` x3, to
     settle the crowd question.
- **Second cut (built, not yet run in game).**
  - **Moving.** Horizontal displacement of the streamed pose against an anchor
    that rolls every 1.5 s (`COMBAT_MIRROR_WINDOW_MS`). Travelling ≥ **15 u**
    inside one window (`COMBAT_MIRROR_MOVE_DIST`) counts as moving for 1.5 s
    (`COMBAT_MIRROR_MOVE_HOLD_MS`). It is tracked for every driven NPC, so a
    body already charging when its intent arrives counts at once.
  - **Why 15 u and not the 5 u first proposed.** The stuck body in 141424
    really does lurch in place: the streamed host pose stepped 7 u (14:15:39),
    5 u (14:15:44) and 10 u (14:15:48, 7.6 u of it horizontal), with its
    target hundreds of units away. 5 u per second would have let each lurch
    through, as the velocity test did. 15 u is double the largest
    horizontal lurch, and about one second of a walking attacker.
  - **Hold cap.** For NPC copies, behind the same switch, the hold lasts at
    most max(500 ms, the owner's combat-stream age this episode), up to the
    old 4 s (`COMBAT_HOLD_MIN_MS`). Episodes that end on the cap log
    `why=cap`. Player characters keep the full 4 s hold.
  - **Off switch.** `KENSHICOOP_COMBAT_STUCK_MIRROR=0` turns off the
    mirror and the cap together.
  - **Risk to watch.** Real crowd fights had internal gaps up to ~521 ms
    (p90). An episode younger than that, hit by such a gap, now disarms and
    re-arms: one extra order. `combat_crowd`'s re-order limit (18) is the
    check.
- **A/B gate:** `mint_aggro` x3 with the gate on and x3 with it off.
  `one_sided_fight` must fail with the gate off and pass with it on.
- **Regression:**
  - `combat_crowd`, `combat_battle`, `assault_travel`, `combat_kill`,
    `player_combat`, `pc_assault`, cell auth on and off;
  - the smoke tier.
  - Fights the host really runs must still start on the join, with no rise in
    `combat_snap_rate` or start latency.

### Hostility check (found, not used by this fix)

`FactionRelations::isEnemy` is already resolved as `g_relIsEnemyFn`
(`EngineInternal.cpp`, `CAP_FACTION`). It is read in `listPlayerRelations`
(`EngineWorld.cpp`) as `g_relIsEnemyFn(playerFaction->relations, f)` and the
reciprocal. It was meant to keep hostile copies AI-suspended in the
`mid-rest` release. With the corrected cause that change has no evidence
behind it, so it is dropped from the plan.

### Risks

- A real attack that starts from beyond the threshold while the attacker is
  standing still would start on the join only once the host's body closes in.
  That is a short delay, not a missing fight. The probe sizes this.
- The target's local position is used for reach. If the target itself is a
  driven copy that lags, reach is judged slightly off. The threshold leaves
  slack for this.
