# Bug #1 design: joiner squad names, faction name and jobs survive the save

Status: **steps 2 (squad names) and 3 (faction name) pass in game; step 4 (jobs) in progress** —
October 16, 2026.
Bug source: nhoral/KenshiCoop issue #74; docs/PROJECT_BRIEF.md bug table row 1.

## Symptom

The joiner renames a squad tab, renames the player faction, or sets up
permanent jobs on its characters. After the next coordinated save and load all
three are back to the host's values. Anything the host set survives.

## Cause (confirmed in code)

While connected under save-sync the joiner's local saves are suppressed and
forwarded as `PKT_SAVE_REQ`; the host writes **its** world and streams that
folder to the joiner (`Plugin.cpp` `processNetEvents` / `driveSaveSync`). The
joiner's characters exist on the host as AI-suppressed puppets. Nothing
replicates the three values below from joiner to host, so the host's save
carries the host's stale copies, and the next load restores them.

| Data | Engine storage (KenshiLib 0.4.0) | Replicated today? |
|---|---|---|
| Squad name | `ActivePlatoon::getName` / `setName` (one per squad tab) | No |
| Player faction name | Displayed: `Faction::name` (`getName` / `setName`). **Saved:** `PlayerInterface::factionName`, copied into `Faction::name` on load (step 1b) | No |
| Permanent jobs | `OrdersReceiver` permajobs: `getPermajobCount`, `getPermajobData(slot)`, `getPermajob(slot)`, `clearPermajobs`, `removePermajob`, `movePermajob`, `addJob` | No |

The only name sync today is the nick channel (`applySquadNicks`), which renames
one *character*, not a squad.

## Authority (REPLICATION_PITFALLS §16: count the writers)

- **Squad name, jobs:** one writer — the owner of the squad tab (`ownRanks_`
  partition). Owner publishes state, peers apply, newest wins.
- **Faction name:** two writers — one shared player faction, either player can
  rename it. Replicate the **operation**: join sends `FACTION_RENAME`, the host
  applies it and broadcasts `FACTION_NAME` with an ack sequence. Simultaneous
  renames resolve by host arrival order and both sides converge. The local
  change baseline is updated on our own writes, or an applied host value reads
  back as a fresh local rename and oscillates.

## Channels

Reliable, change-gated, periodic safety resend, resend on the connect edge
(same shape as the existing channels). One fixed-size packet type per value,
like the rest of `Wire.h`, rather than one packet with sub-kinds:

- `PKT_SQUAD_NAME` (step 2) — squad-tab identity (container + containerSerial,
  the identity the ownership partition uses; step 1 confirmed it matches on
  both sides) + name (≤ 64 bytes).
- `PKT_JOBS` (step 4) — character key + ordered job list: task type, subject,
  location.
  - Rebuild on apply by `clearPermajobs` then `addJob` in list order (step 1b:
    order is preserved by clear + re-add and by save + reload).
  - **Check the count after every add.** The engine silently ignores some
    types without a fitting subject (step 1b: JOB_KEEP_EVERYTHING_RUNNING with
    no subject left the count unchanged); log `JOBS-ADD-REJECTED`, never assume.
  - Carry the subject exactly as read; no value means "none" (steps 1 and 1b
    read back `0,126`, `0,132` and `0,0` for the same no-subject add).
  - Save-resident subjects share hands on both sides. Session-placed buildings
    and fixtures translate through `localHandForBuildKey` /
    `localHandForFixtureKey`.
  - An unresolved subject is parked and retried against a deadline (§2), then
    logged `JOBS-SUBJECT-GAVEUP`; never silently dropped.
- `PKT_FACTION_RENAME` (join → host) / `PKT_FACTION_NAME` (host → all) with
  seq / ackSeq (step 3). Every apply writes **both** `Faction::name` (what is
  displayed now) and `PlayerInterface::factionName` (what the save keeps);
  step 1b showed `setName` alone is lost on reload. The template
  `GameData::name` is never written (shared game data).

Rules:

- The host applies received values onto its copy of the joiner's squad and
  puppets, so the authoritative save contains them.
- Apply only when the value differs; never apply onto a body or tab the
  receiver owns.
- Unconditional log lines for every send/apply verdict (§9).
- Gate: `KENSHICOOP_SQUAD_META=0` disables the channels for A/B runs.
- Protocol bump in `src/netproto/Wire.h`: public 70 → **72**, diagnostic
  71 → **73** (keeps the even/odd public/diagnostic split), made once in step 2
  for the whole branch (nothing is released between steps). Both players must
  update together.

## Verification

- Scenario `squad_meta_persist`, modelled on `money_persist`, grows with each
  step (step 2: the tab name only; steps 3 and 4 add the faction and jobs). The
  join renames
  its tab, renames the faction and gives one character a job; the host
  **latches** what it received before saving (a run that never latched fails,
  it proves nothing); coordinated save → ACK → load; both sides re-read all
  three post-load and must match the latch.
- Oracle `Test-SquadMetaPersist` in `scripts/oracles/Session.ps1`. With
  `KENSHICOOP_SQUAD_META=0` it **must FAIL**, and must reach the post-load
  assertion rather than stall in setup (§7, §16 corollary).
- Prototest: encode/decode round trip and size checks for each packet kind.
- `scripts/verify.ps1` stays green; then one real two-player session.

## Open questions (answered by the step 1 probe before real code)

1. Is the joiner's squad tab the same `ActivePlatoon` (same container identity)
   on the host? What happens to a squad tab the joiner creates mid-session?
2. Does `ActivePlatoon::setName` / `Faction::setName` persist into the save, and
   does the squad bar refresh without a reload?
3. Which call appends to the permajob list (`OrdersReceiver::addJob` is the
   candidate), and is order preserved?
4. Is writing permajobs onto an AI-suppressed host puppet safe, or does it wake
   GOAP?
5. Related but separate: the nick channel renames a squad character to the
   player's nick and may overwrite a joiner-chosen character name. Record, do
   not fix here.

## Step 1 results (run `20261016_151922`, Harness, local two-client loopback)

Save `sync` (two squad tabs: host rank 0 `Nameless_0`, join rank 1 `Nameless_1`).
Verdict PASS (`squad_meta_probe` primary); advisory `march` FAIL is the
unrelated walking-smoothness metric (idleFrac 0.0137 vs 0.01).

1. **Tab identity — same on both sides.** Containers `1,3079467776` (rank 0) and
   `7,2303466752` (rank 1) and both leader hands are identical on host and join.
   Container identity is a valid wire key for squad tabs. The mid-session
   new-tab case is still untested.
2. **Persistence.**
   - `ActivePlatoon::setName` **persists**: the host's `SMProbe Host Squad`
     came back after reload on both sides.
   - `Faction::setName` **does not persist**: it reads back
     `SMProbe Host Faction` immediately, but after reload both sides read
     `Nameless`. The saved faction name comes from another field → step 1b.
   - Squad-bar refresh without reload: not observed (no UI check in the probe).
3. **Permajobs.** `OrdersReceiver::addJob(type, hand(), loc, shift=true)`
   appends: JOB_MEDIC (TaskType 58) went 0 → 1 on both sides and **persists**
   through the save. A job added with a default `hand()` reads back subject
   `index,serial = 0,126` (host) / `0,132` (join), **not all zero** — the
   channel must carry the subject as read, never treat all-zero as "none".
   **Order is untested**: the join leader had no jobs, so the clear + re-add
   round trip was skipped → step 1b.
4. **Puppets.** After the host appended JOB_MEDIC to the join's puppet, its
   current task stayed TASK_NONE (65535) with 1 job in all 10 samples (1 Hz).
   No GOAP wake-up within 10 s.

**Bug #1 reproduced.** The join renamed its tab and the faction and added a job
(all read back). The host still saw `Nameless_1` at save time. After reload the
join's tab was `Nameless_1` again, its faction `Nameless`, and its leader's job
list was the one the **host** had written onto the puppet (subject `0,126`),
not the join's own (`0,132`). The host's own rename survived on both sides.

## Step 1b results (run `20261016_153910`, same setup)

Verdict PASS (`squad_meta_probe2` primary); advisory `march` FAIL as before.

1. **Faction name.** The host wrote `P2 Member Name` to `Faction::name` and
   `P2 Iface Name` to `PlayerInterface::factionName`; the template
   `GameData::name` stayed `Nameless` throughout. After save + reload **both**
   sides read `Faction::name = PlayerInterface::factionName = P2 Iface Name`:
   the save keeps `PlayerInterface::factionName` and the load copies it into
   `Faction::name`.
2. **Job order.** Both sides appended JOB_MEDIC (58) and JOB_REPAIR_ROBOT (57);
   JOB_KEEP_EVERYTHING_RUNNING (89) was **silently rejected** (call returned,
   count stayed 2). Clear + re-add gave back `58,57` exactly (`firstDiff=-1`)
   on both sides, and the host's leader still had `58,57` after reload.
   No-subject jobs read back subject `0,0` this time (step 1: `0,126`).
3. **Bug #1 again, for jobs.** The join's leader had `58,57` before the save
   and 0 jobs after reload; it saw the host's leader's `58,57` correctly.

All open questions are answered except the mid-session new squad tab, which
step 2 covers.

## Step 2: squad names (implemented; gate passes in game)

- `PKT_SQUAD_NAME` = 50, 81 bytes; protocol 72 public / 73 diagnostic.
- `Replicator::publishSquadNames` / `applySquadNames`, a symmetric row in
  `driveSampledChannels` after deeds. Each client publishes the tabs in its
  `ownHands_` (1 Hz sample, send on change, 10 s safety resend, stamps aged on
  the connect edge) and applies received names only onto tabs it does not own,
  through any member in `allSquad_`. The host's generic relay forwards a join's
  row to the other joins.
- Log lines: `[squadname] SEND` (on change), `APPLY` (with the old name),
  `UNRESOLVED` (once per name when no member of the tab resolves here; the
  resend retries).
- Gate: `squad_meta_persist` (full tier) + `Test-SquadMetaPersist`; the A/B
  negative control is `KENSHICOOP_SQUAD_META=0`.

In-game A/B (Harness, local two-client loopback, save `sync`):

| Run | Channel | Verdict | What happened |
|---|---|---|---|
| `20261016_155913` | on | **PASS** | Join renamed tab `7.2303466752` to `SMPersist Join Squad` at 8.0 s and sent it; the host logged `APPLY ... was='Nameless_1' ok=1` within a second, latched it at 9.0 s (`moved=1`), saved, got the ACK at 13.3 s and loaded. Both sides read `SMPersist Join Squad` after reload. |
| `20261016_160200` | off (`KENSHICOOP_SQUAD_META=0`, confirmed in both logs' `off=[...]`) | **FAIL** (intended) | Same rename on the join; the host still saw `Nameless_1` at its 18 s deadline (`moved=0`), saved and loaded; both sides read `Nameless_1` after reload — the original Bug #1 wipe, named as such by the oracle. |

The switch alone decides whether the join's tab name survives, so the channel
is the fix and the gate detects a regression. No `UNRESOLVED` lines, health
PASS on both sides in both runs.

Known limits:
- A rename made within about one sample (~1 s) plus a round trip before the
  host saves can miss that save; it is carried by the next one.
- Names are capped at 63 bytes on the wire; a longer name is truncated on the
  peer's copy.
- A squad tab the join creates mid-session is covered only if the host's copy
  of that tab has a member with the same container; otherwise it logs
  `UNRESOLVED` and keeps retrying. Not yet measured.
- Whether the squad bar redraws a renamed tab without a reload is not measured.

## Step 3: faction name (implemented; gate passes in game)

- `PKT_FACTION_RENAME` = 51 (73 bytes, join → host, **not relayed**) and
  `PKT_FACTION_NAME` = 52 (89 bytes, host → all, per-player `ackSeq[4]`).
  Same protocol 72 / 73 as step 2; the same `KENSHICOOP_SQUAD_META` switch.
- `Replicator::publishFactionName` / `applyFactionName`, a symmetric row after
  squad names. Every write goes through `engine::writePlayerFactionName`
  (both `Faction::name` and `PlayerInterface::factionName`) and moves the
  `facNameSeen_` baseline with it (the echo guard).
  - Join: a displayed-name change it did not write is the player's rename →
    write the saved field too, send `RENAME` (seq), keep it **pending**; host
    totals are ignored while pending, and the ack (`ackSeq[localId] >= seq`)
    clears it.
  - Host: folds renames in arrival order (per-join seq guard), writes both
    fields, marks the total dirty for an immediate broadcast (a no-op fold is
    still acked). A host-local rename (the host player in the UI) is written to
    the saved field too, so the host's own renames also survive.
  - Totals are resent every 10 s and on the connect edge; the first sample of a
    session seeds the baseline without reporting a rename.
- Log lines: `[facname] SEED`, `RENAME` (join), `FOLD` (host, with the old
  name), `SEND` (host, on change), `ACK` and `ADOPT` (join), `LOCAL` (host).
- Gate: `squad_meta_persist` now also renames the faction on the join the way
  the UI does (displayed field only), latches it on the host (`SMPFLATCH`) and
  requires **both** fields to hold the join's name after reload on both sides
  (`SMPFPOST`). The oracle names a "displayed right but saved field wrong"
  result separately, because that one is lost on the NEXT load.

Known limits: a rename within about a second of the host's save can miss that
save (as for squad names); two renames from different players inside one
round trip resolve to whichever the host folds last.

In-game A/B (Harness, local two-client loopback, save `sync`; the gate now
covers the squad name and the faction name together):

| Run | Channel | Verdict | What happened |
|---|---|---|---|
| `20261016_162442` | on | **PASS** | Both seeded `Nameless`. At 8.0 s the join renamed the faction (displayed field only, like the UI); its channel wrote the saved field (`saveField=1`) and sent `RENAME seq=1`. The host logged `FOLD from=1 seq=1 ... was='Nameless' ok=1` and broadcast the total with `ack=0,1,0,0`; the join logged `ACK seq=1`. The host latched both names at 9.0 s (`moved=1` twice), saved and loaded. After reload both sides re-seeded from `SMPersist Join Faction` and held it in **both** fields; the squad name also survived on both sides. |
| `20261016_162725` | off (`off=[...]` in both logs; no `[facname]` lines) | **FAIL** (intended) | Same renames on the join, both read back. At the 18 s deadline the host still saw `Nameless_1` / `Nameless` (`moved=0` twice), saved and loaded; both sides came back `Nameless_1` and `Nameless` in both faction fields — the Bug #1 wipe for each name. |

The switch alone decides whether the join's squad and faction names survive.
Health PASS on both sides in both runs.

## Steps (branch `fix/squad-meta-persist`, one commit each)

1. **Probe scenario `squad_meta_probe`** — read/write each value on own tabs,
   peer tabs and the faction; save → reload → re-read. Answers 1–4. No protocol
   change. **Done** (results above).
1b. **Follow-up probe `squad_meta_probe2`** — which faction field the save
   keeps, and whether clear + re-add preserves the order of 2+ jobs. **Done.**
2. Squad names end to end + gate (`PKT_SQUAD_NAME`, protocol bump). **Done; gate passes in game.**
3. Faction rename op channel (`PKT_FACTION_RENAME` / `PKT_FACTION_NAME`). **Done; gate passes in game.**
4. Jobs, including subject translation and parking.
5. Update docs/PROJECT_BRIEF.md's bug table only after a real two-player session.

Ideally reproduce the wipe once in a real session first (docs/PROJECT_BRIEF.md "baseline
play test") so the fix is checked against the observed symptom.
