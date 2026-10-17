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
