# Bug #1 design: joiner squad names, faction name and jobs survive the save

Status: **approved plan, step 1 (probe) in progress** — October 15, 2026.
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
| Player faction name | `Faction::getName` / `setName` | No |
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

## Channel: `PKT_SQUAD_META`

Reliable, change-gated, periodic safety resend, resend on the connect edge
(same shape as the existing channels).

- `SQUAD_NAME` — squad-tab identity (the same container identity the ownership
  partition uses) + name (≤ 64 bytes).
- `JOBS` — character key + ordered job list: task type, subject, location.
  - Save-resident subjects share hands on both sides. Session-placed buildings
    and fixtures translate through `localHandForBuildKey` /
    `localHandForFixtureKey`.
  - An unresolved subject is parked and retried against a deadline (§2), then
    logged `JOBS-SUBJECT-GAVEUP`; never silently dropped.
- `FACTION_RENAME` (join → host) / `FACTION_NAME` (host → all) with seq / ackSeq.

Rules:

- The host applies received values onto its copy of the joiner's squad and
  puppets, so the authoritative save contains them.
- Apply only when the value differs; never apply onto a body or tab the
  receiver owns.
- Unconditional log lines for every send/apply verdict (§9).
- Gate: `KENSHICOOP_SQUAD_META=0` disables the channel for A/B runs.
- Protocol bump in `src/netproto/Wire.h`: public 70 → **72**, diagnostic
  71 → **73** (keeps the even/odd public/diagnostic split). Both players must
  update together.

## Verification

- Scenario `squad_meta_persist`, modelled on `money_persist`: the join renames
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

## Steps (branch `fix/squad-meta-persist`, one commit each)

1. **Probe scenario `squad_meta_probe`** — read/write each value on own tabs,
   peer tabs and the faction; save → reload → re-read. Answers 1–4. No protocol
   change.
2. Squad names end to end + gate.
3. Faction rename op channel.
4. Jobs, including subject translation and parking.
5. Update docs/PROJECT_BRIEF.md's bug table only after a real two-player session.

Ideally reproduce the wipe once in a real session first (docs/PROJECT_BRIEF.md "baseline
play test") so the fix is checked against the observed symptom.
