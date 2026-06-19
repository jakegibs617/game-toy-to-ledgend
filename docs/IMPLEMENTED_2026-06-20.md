# Implemented — 2026-06-20

Development continued from `main` (post PR #48) and followed the
branch → smoke → PR → multi-angle review → fix → merge → pull-main loop.
Each feature shipped its own PR with 3 clean headless smoke runs and 1
windowed boot, and was merged after a self-review pass.

Starting point: v3 milestones 27–32 complete, all Product_reqs.md items done,
rival wall duels + the full crew-role set shipped. The remaining buildable
backlog was the deferred/🟡 systems in `FEATURES.md` (M33/M34 need real human
testers, so they were not in scope this session).

## Implemented Today

### PR #49 — Wall Duel Deadlines & Forfeits

- Rival wall duels (PR #46) shipped with **no fail state**: an ignored callout
  was a permanent free wall, and `forfeit_wall_duel` was never triggered.
- Each open duel now carries a `ticksLeft` countdown
  (`RivalManager.WALL_DUEL_DEADLINE_TICKS`, 8 simulation ticks). It ages per
  `_on_tick`, warns the writer one tick before expiry, then forfeits the wall.
- Expiry reuses `forfeit_wall_duel` (now with an `expired` flag); both paths
  record the loss and reset the streak via `GameState.note_rival_duel_loss`.
- Blackbook City page shows the remaining answer window per callout.
- No save-schema bump: the countdown rides inside the already-saved
  `active_wall_duels` dict and defaults gracefully for older saves.

### PR #50 — Crew Morale Layer

- Closes the last 🟡 crew-depth gap: a single crew-wide `team_morale` (0–100,
  neutral 50) distinct from per-member loyalty.
- Morale folds into the existing `role_bonus_scale` hook as one bounded
  `morale_factor()` (0.9–1.1). **At neutral it is exactly 1.0**, so all existing
  role balance and smoke assertions are unchanged; the whole crew's bonuses
  shift together only as it wins or loses.
- Shifts: recruit (+6), loyalty milestone (+2), duel win (+7); duel
  loss/forfeit (−8), caught (−5). A crossed 20-point band announces the mood.
- Blackbook Crew page leads with the morale line; save schema bumps to **v11**
  with neutral migration.

### PR #51 — Spray-Cap Inventory

- Generalizes the lone Fat Cap into a real cap kit (Plan.md §21 "caps modify
  spray behavior"), closing the 🟡 cap-system gap.
- `Data/caps.json`: **Stock** (default, no trade-offs), **Skinny** (+10% rep,
  hideable), **Fat** (−1 paint, +suspicion), **Calligraphy** (+25% rep, +1
  paint, +suspicion).
- One cap is equipped at a time. `paint_cost` applies its `paintDelta` (floored
  at 1) instead of summing every owned discount; the rep multiplier folds into
  the single `_begin_player_paint` hook; suspicion adds to
  `gear_suspicion_multiplier`.
- Shop items carry `grantsCap` (buying equips); **K** / controller **B** cycle
  owned caps, shown in the wall prompt. Save schema bumps to **v12**, back-
  filling the Fat Cap from a pre-cap `fat_cap` purchase.

## Verification

- Each PR: 3 clean sequential headless smoke runs (`SMOKE: OK`) + 1 windowed
  boot. Runs were sequential, not parallel — concurrent headless runs race on
  the shared `user://` save file.
- Final `main`: `18c8d3c` Add spray-cap inventory (PR #51 merged).
- Save schema advanced v10 → **v12** across the session, each step with a
  migration and smoke coverage for the older-save path.

## Current Project State

- v3 milestones 27–32 complete; Product_reqs.md complete.
- Rival wall duels now have a deadline/forfeit fail state and a Battle
  Specialist crew hook.
- Crew depth is feature-complete for the prototype: roles, loyalty, and now
  team morale. The 🟡 crew-depth line in `FEATURES.md` is cleared.
- Caps are now a full spray-behavior modifier system (only mops/markers/
  gloves/masks remain unmodeled, kept as an explicit 🟡).
- The main remaining blockers are **M33 Playtest Feedback Pass** and **M34 v3
  Demo Candidate**, both of which need real outside-tester observations rather
  than more speculative feature work.

## Recommended Next Features / Milestones

Ordered roughly by leverage toward a shippable v3 candidate.

1. **M33 Playtest feedback pass.** Run a fresh tester from alias selection to
   Rooftop Row claim; capture confusion/pacing/failure points; make only
   prompt/data/UI fixes tied to findings. This is the real gate to M34.
2. **M34 v3 demo candidate.** Freeze after M33, run the full verification loop,
   write the known-issues list, and tag a candidate build.
3. **Cap/morale balance tuning pass.** Now that Calligraphy (+25% rep) and team
   morale (±10% role bonuses) both touch the economy, fold them into
   `docs/BALANCE_TARGETS.md` and re-validate the target run for rep inflation.
4. **Rival duel ladder.** Let a crew escalate from a one-off callout to a named
   three-wall challenge arc (best-of-three) with a larger stake, reusing the
   existing duel + deadline + Battle Specialist plumbing.
5. **Duel forfeit penalty teeth.** A forfeited duel currently only costs the
   wall + streak; add an optional small rep/crew-rep/morale hit (data-driven)
   so ignoring duels has real weight, tuned against playtest data.
6. **Sketch editor / blackbook motif.** Save a bench sketch or freehand image
   as a reusable custom piece the writer can throw up on the street.
7. **Rival alliance / ceasefire path.** A dialogue/data route to soften one
   crew's relationship (lower aggression / pause retaliation) without building
   full faction diplomacy — pairs naturally with crew morale and duel records.
8. **MultiMesh street-detail pass.** Collapse the ~2,100 repeated street-detail
   nodes flagged by `RUNTIME_BUDGETS` into MultiMesh instancing before any
   fourth district pushes meshes over budget.
9. **Outfit / alias presentation.** Let rank or crew loyalty/morale unlock
   visible outfit accents and a stronger alias identity on the rooster model.
10. **Safehouse room depth.** Small earned room upgrades that display posters,
    saved sketches, and crew mementos — progress you can see, not a decorating
    sim.
11. **Safehouse rest presentation beat.** A short clock/lighting/audio
    transition on rest so time-skip *feels* like time passed, without a full
    day/night system.
12. **Mops & markers (cap-kit sibling).** Extend the new cap trade-off model to
    a couple of hand tools (marker = fast/low-heat tags on small surfaces; mop =
    drippy fills) using the same equipped-tool plumbing.
13. **Morale-driven crew events.** At high morale a member offers a one-time
    favour (free supply run, extra auto-fill); at low morale a member goes quiet
    — small, data-driven beats off the existing morale value.
14. **Playtest metrics export polish.** Make `PlaytestMetrics` capture files
    easy to diff between testers and candidate builds for M33.
15. **Fourth district groundwork.** Scope Downtown or Gallery Quarter only after
    M34 and once the MultiMesh pass confirms runtime headroom.
