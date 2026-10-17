# Desync investigation - Phase 1 measurements (October 17, 2026)

Reports this targets: nhoral/KenshiCoop #34 (starving bandits fighting on one
screen only, near Squin), #54 (NPCs invisible to one player, one-sided fights),
#82 (hard position desync of NPCs and players, players teleporting far away).

The scenario tier pins `KENSHICOOP_CELL_AUTH=0`, but real games run with cell
authority ON (the default). So the eight scenarios that model travel and hostile
groups ran twice on main's Harness build: off (as the tier runs) and on (as
players run), via `run_test.ps1 -DiagEnvOverride KENSHICOOP_CELL_AUTH=<0|1>`.
Runs 2026-10-17 12:0x-13:2x, logs in tools/test-runs.

| Scenario | Off | On | Notes |
|---|---|---|---|
| combat_crowd | PASS | PASS | |
| combat_battle | PASS | PASS | anim_truth advisory FAIL when on |
| assault_travel | PASS | PASS | |
| run_apart | PASS | PASS | existence_parity + lifecycle advisory FAIL both ways |
| town_arrive | PASS | PASS | existence, smoothness, snap_rate advisory FAIL both; suppress_churn too when on |
| town_arrive_far | PASS | PASS | same as town_arrive |
| travel_parity | FAIL | FAIL | test setup, not a desync: join travelled 16,000 of the required 40,000 u; follow gap median 12 u |
| mint_aggro | **FAIL** | **FAIL** | the bandit desync, see below |

## Hostile squad (mint_aggro) - the #34 / #54 desync, reproduced

Primary gate proxy_drift fails in both setups. With cell authority on:
- "the enemy fights on the JOIN while the host has it at peace in 12/30 samples"
  (link 4 parity: joinOnly=12, hostOnly=0);
- proxy `4,3393432576` reached 463 u from its owner's copy (runaway limit 300)
  with nothing pulling it back.

## Arriving in towns - worse with cell authority on

| | NPC hard snaps/min (join) | peak ghost NPCs (one side only) | ghost samples |
|---|---|---|---|
| town_arrive, off | 24.0 | 5 | 5.9% |
| town_arrive, on | **86.2** | **20** | 5.9% |
| town_arrive_far, off | 5.4 | 29 | 2.0% |
| town_arrive_far, on | **29.2** | **37** | **10.6%** |

So the main gates pass (the town's people arrive), but with cell authority on,
NPCs teleport on the joiner's screen 3.6-5.4x as often and more NPCs exist on
only one side - the "desync when loading new towns" seen in play.

## Phase 2 order (proposed)

1. Hostile squad aggro desync (mint_aggro): primary FAIL both ways, matches #34/#54.
2. Town-arrival snaps and ghosts with cell authority on.
3. Later: travel_parity's short travel (test), the pinned host copy
   (`[drive] freeze why=combat-skip`) from bug #17's runs.
