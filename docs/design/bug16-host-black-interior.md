# Bug #16 design: a building goes black when watched from the other client

Status: **not a co-op bug: friend_indoors run 2 shows the host draws the bar open with only the joiner inside; the black screen was the melee_together camera. Open: one melee_together run with the camera fix had no APART hits** —
October 16, 2026.
Bug source: seen by Brandon during melee_together runs; docs/PROJECT_BRIEF.md bug
table row 16.

## Symptom

During melee_together the host window intermittently showed the bar with no
building, floor or roof: a black void with the fighting characters, a terrain
slab and a rock still drawn. The join's window rendered the bar normally.
Captured at 22:20:34 in run 20261016_221816
(`tools/test-runs/bug16_222034_614.png`).

## What the logs show (both timed sightings)

| | Run 20261016_221532 | Run 20261016_221816 |
|---|---|---|
| Sighting | ~22:17:50-22:18:00 (Brandon's report) | 22:20:34 (screenshot) |
| Phase | APART (22:17:32-22:18:02) | APART (22:20:15-22:20:45) |
| Host character | parked 6000 u out of the bar at 22:17:18 | parked out at 22:20:01 |
| Host camera | `[cam] center=-51193.9,1581.0,2646.2` (the bar) before and after | same |
| Bar zone 20,32 on the host | still loaded (bed census reads it) | still loaded |

The bar's interior furniture (`[bed] ROW ... inside=...95.2594726656`)
records which state each client draws the bar in:

| Client | While own character is in the bar | After the host's character left |
|---|---|---|
| Host | `visibleFlag=0` (from 22:18:59) | `visibleFlag=1` (from 22:20:14) |
| Join | `visibleFlag=0` (from 22:19:32) | stays `0` |

So the zone did not unload. The host switched the bar back to its "no player
character inside" state when its own character left, even though the joiner's
character was still inside on the host's screen.

## Hypothesis (to confirm in step 1, not yet proven)

Kenshi decides which building interiors a client draws open from its player
characters' indoor state (`RootObject::isInsideBuilding`, fed through
`PlayerInterface::updateFloorVisibility` into `PlayerInterface::interiorsVisible`).
The other player's characters exist on each client as driven copies. The mod
moves them kinematically and never reads or syncs indoor state (no use of
`isIndoors` / `isInsideBuilding` / `notifyIndoors` anywhere in `src/plugin`), so a
copy may never be marked as inside. With none of your own characters inside, the
building is drawn closed, and a camera inside a closed building shows the black
"dark interior" with only the characters and outside terrain drawn.

If that holds, this is not test-only: in real play, either player who follows
the friend's character into a shop or bar, with none of their own characters
inside, would see the black void.

Two things the logs cannot yet tell apart:

1. The peer copy is **not marked inside** (indoor state never set on copies).
2. The peer copy **is marked inside**, but Kenshi only opens interiors for some
   subset (for example selected characters) that never includes a copy.

The fix differs between them, so step 1 measures before anything changes.

## Separate from this bug

- The scenario artifact: melee_together parks the host's character but never
  moves its camera (`park()` does not move the camera; `Engine.h` documents this
  and provides `cameraFocusOn`). That made the void easy to see but is not the
  cause. Fixing the scenario is step 3 and touches test code only.
- The "slightly desynced" characters Brandon saw during TOGETHER. Not part of
  this fix; the existing `[proxy] drift` lines already record it for afterwards.

## Plan

### Step 1 - read-only probe and the friend_indoors scenario (this branch)

No behaviour change. Everything lives in Harness-only translation units
(excluded from the Release build in `KenshiCoop.vcxproj`).

- `engine::probeIndoors` (new Harness-only `game/IndoorProbe.cpp`): for every
  player-faction character, read under SEH:
  - its hand and name,
  - `RootObject::isInsideBuilding` (a plain field, no virtual call),
  - the building it names, resolved through the engine's own hand resolver
    and checked to be a building: `getVisible()` and `interiorVisibility`,
  - `PlayerInterface::getInteriorsVisible(building)` (the engine's own read-only
    query; assumed to be a pure getter from its name and signature - it has
    no KenshiLib body to read, which is one reason this stays Harness-only),
  - plus the client's `selectedCharacter` and camera centre.
- New scenario `friend_indoors` (save `sync`, both squads start in the bar):
  - BASE 8-20 s: both stay in the bar, cameras on their own leaders.
  - OUT at 20 s: the host parks its tab ~1500 u along +x, outside the bar
    but in the same town and zone cell, and points its camera at its parked
    leader (the view a player would have after walking out).
  - WATCH 30-60 s: the host points its camera at the joiner's leader
    (`cameraFocusOn`, as if following the friend). The joiner stays inside.
  - 1 Hz `SCENARIO INDOOR ROW` / `CAM` lines on both sides.
- Oracle `Test-FriendIndoors` (probe tier): reports, per phase and side, which
  building each character is inside and whether that interior is open. Verdict:
  "Bug #16 REPRODUCED" when, in WATCH, the joiner's own log has its leader inside
  building B while the host has B closed. Answers hypothesis 1 vs 2 from the
  host's row for the joiner's copy. FAIL only when the setup didn't happen (no
  rows, the host still inside after OUT, the joiner not inside in BASE, the
  camera focus failed).

### Step 2 - the fix (designed after step 1; you approve before any code)

Candidates, smallest blast radius first:

- **B. Rendering only.** Make each client also open the interior of a building
  the peer's own client reports its characters inside. This touches only which
  interiors this client draws, never a character's state, AI or pathing.
  `updateFloorVisibility` is private and runs every frame, so the lever needs
  care; step 1 tells us whether a copy's state is even wrong.
- **C. Indoor state on copies.** Carry the owner's `isInsideBuilding` across and
  apply it to the copy. More direct, but indoor state also feeds pathing,
  trespass and NPC reactions, so it carries more risk.

### Step 3 - scenario hygiene (test code only)

melee_together's park also refocuses the host camera on its parked leader, so
the test stops showing a view no player would have.

## Safety checks for any step-2 fix

This touches what the player sees, so before it ships:

1. An off switch (`KENSHICOOP_PEER_INTERIORS=0`) restoring today's behaviour.
2. An A/B gate built on `friend_indoors`: it FAILs if the host draws the bar
   closed while the joiner is inside, and the off-switch arm must FAIL.
3. Negative checks on both clients: your own characters entering and leaving a
   building still open and close it exactly as before; a building with no
   player characters stays closed; a peer standing outdoors changes nothing; no
   camera movement in normal play (the fix never moves a camera).
4. Regression: the smoke tier plus the scenarios that go through buildings and
   doors (door, bed and rest, jail), on both builds, with no new faults in the
   crash/fault counters.
5. A line-by-line review of the diff before deploy, and a manual look in both
   windows by Brandon.

## Step 1 result - run 20261016_223645 (October 16, 2026)

The oracle FAILed its setup checks, but the rows answered the bigger question.

| Time | Host (own leader Flashbox) | Join (own leader Remote Player 1) |
|---|---|---|
| BASE | Flashbox inside the bar (`0.2069.11111.95.2594726656`), bar drawn open | Remote Player 1 **outdoors** (`inside=11.0.0.0.0`); its copy of Flashbox inside the bar; bar drawn open |
| 22:38:11.9 | host parks Flashbox 1500 u out | |
| 22:38:12.9 | Flashbox outdoors; bar drawn **closed** (open 1 -> 0 within a second) | its copy of Flashbox outdoors within the same second |
| WATCH | host camera follows the joiner; the bar stays closed | both leaders outdoors |

What this shows:

1. **The joiner's leader is never inside the bar in the `sync` save.** Both
   clients agree it stands just outside (the ~158 u leader distance
   melee_together logs). Only the host's leader starts inside.
2. **The melee_together black screen is the scenario, not co-op.** In APART the
   host's camera stays where Flashbox stood inside the bar (park moves the
   body, not the camera). Once Flashbox leaves, the host closes the bar within a
   second, and nobody from either client is inside. The camera is left inside a
   closed building, which draws the black void with only the characters and
   the outside terrain. That matches both timed sightings. The fix belongs in the
   scenario (step 3): refocus the camera after the park.
3. **A teleported or driven body's indoor state does update.** The host's own
   leader went from inside to outdoors one second after `park`, and the join's
   copy of it followed in the same second. So copies are not stuck with a stale
   indoor state (evidence against H1, for leaving).
4. **On the join, the host's copy alone opened the bar.** With none of the
   join's own characters inside, the bar was drawn open while the host's copy
   stood in it (evidence against the real-play bug). Caveat: the join had that
   copy selected (`sel=1` on every join row: the save's selection; the camera
   focus does not change it), so selection may be what opened it.

Not yet tested: a client watching the friend inside a building when that
friend's character is not selected. Next: the joiner walks its leader into the
bar with a normal move order (`orderMoveTo`, so it enters the way a player
would) before the host leaves; plus the step 3 camera refocus in melee_together.

## Step 1b - friend_indoors revised (built, not yet run)

- BASE is now 8-30 s. The joiner latches the bar from its copy of the host's
  leader, then orders its own leader to walk to the host's leader with
  `orderMoveTo` (a normal player move order, re-issued every 5 s until its own
  row says it is inside the bar). OUT moves to 30 s, WATCH to 40-70 s.
- The oracle checks the joiner is inside during OUT (it walks in during BASE),
  and FAILs if the host has the joiner's leader selected in WATCH, so selection
  cannot be what opens the bar.
- melee_together (step 3): the host's park now also points its camera at its
  parked leader (`SCENARIO MELEE PARK ... cam=1`), so APART no longer leaves the
  host camera inside the bar it just left.

## Step 1b results (October 16, 2026)

**friend_indoors, run 20261016_225407: PASS, bug NOT reproduced.**

- The joiner's leader walked into the bar on the first move order and stayed
  inside through OUT and WATCH (inside share 1.0 on both).
- After the host's leader left, the host still drew the bar **open** in every
  OUT and WATCH sample (open 1.0), with only the joiner inside.
- The host's copy of the joiner was marked inside the bar in every WATCH sample
  (1.0), and the host did not have it selected (0.0), so selection played no
  part.

So the friend's characters keep their indoor state on the other client, and
that alone keeps the interior open. Neither H1 nor H2 holds; there is no
real-play bug here, and no step-2 fix is needed. Bug #16 was the
melee_together scenario leaving the host camera inside a building nobody was in.

**melee_together with the camera fix, run 20261016_225651: FAIL (no APART baseline).**

- The park line reads `cam=1`: the host camera followed its parked leader.
- TOGETHER was normal (28.9 hits/min).
- APART: the joiner fought its target (`4,1276245120`, the Ninja Guard by
  earlier runs) for 29 s and **no melee landed either way**. There were zero
  `[dmg] HIT` lines in the phase, although the target was join-authored as cell
  authority intends (`[med] SEND ... npc=1` from the join).
- The five earlier runs (camera left at the bar) all had APART hits: 10, 6, 12,
  2 and 10.

One run cannot tell noise from an effect. A plausible link: the host's camera
was the host's interest anchor on the bar, and Kenshi also keeps zones loaded
around the camera, so moving it changes what the host keeps active there. Next:
rerun melee_together a couple of times before deciding whether the camera fix
stays.
