# Changelog

## Iteration 5: Culture / Narrative Clarity

### Goal
Improve feedback clarity for the three mechanics the playtest noted as weakest:
wall-state context, rival reaction messaging, and the rep/heat tension.

### Changes Made
- `Scripts/UI/hud.gd`: added live `Influence: N%` label to the stats panel.
  Updates on every wall change via `TerritoryManager.territory_changed`; switches
  to `Influence: CLAIMED` (gold) when the district is held. Hidden until the player
  has any stake in the current district.
- `Scripts/UI/hud.gd`: paint feedback message now appends `(+N influence back)`
  when repainting a city-buffed wall, or `(+N influence taken)` when covering a
  rival wall. Uses `_focused_wall_prev_state` captured before the paint clears it.
- `Scripts/UI/hud.gd`: `_on_heat_level_changed()` replaced with per-level cultural
  voice lines: "Patrols are clocking you. Stay sharp or lay low." / "TOO HOT —
  finish up and ghost." / "BLAZING — get somewhere safe." / "Block is cold —
  nobody watching. Go make some noise."
- `Scripts/UI/hud.gd`: danger-wall culture feedback updated to tie rep and heat
  together: "High-exposure spot — rep and heat both moved. Worth it?"
- `Scripts/Rivals/rival_manager.gd`: rival attack messages now include `(-N
  influence)` so the player immediately sees what was lost. Wall duel won message
  now includes `(+N influence back)`.

### Verification
- Headless smoke: `SMOKE: OK`; rival event line in smoke output confirms the new
  `(-3 influence)` suffix.
- Windowed AGENT=1 launch: zero parse errors in captured stderr.

## Iteration 4

### Goal
Continue the 70-turn `Own the block` verification while watching for hardware
pressure, then separate actual gameplay/harness blockers from machine stalls.

### Changes Made
- `Scripts/Debug/agent_server.gd`: world-freeze between `/observe` and `/act` is
  now opt-in via `AGENT_FREEZE_THINK=1`; normal `AGENT=1` play no longer freezes
  while the model thinks.
- `Scripts/Debug/agent_server.gd`: `cycle_color` now directly calls
  `GameState.cycle_fill_color()` so the choose-color objective is deterministic
  through the agent server.
- `Scripts/Debug/agent_server.gd`: `_nearest_unowned_wall()` now skips the
  district filter when `GameState.current_district_id` is `""` (Fix I).  When the
  player is between districts the function previously returned `""` for every wall
  (the comparison `"district_mill_yard" != ""` was always true), making `goto_wall`
  disappear from `legal_actions` and freezing the harness free-roam redirect for
  46+ turns.
- `agent/pilot.py`: safehouse objectives redirect visible safehouse `interact`
  loops to `rest`.
- `agent/pilot.py`: `Own the block` switches to tag can before painting, because
  territory influence is ownership/visibility based and pieces were generating
  unnecessary heat/paint pressure.
- `agent/pilot.py`: close-wall aim skips walls already counted for `Paint 3
  different walls`, even if cleanup has buffed them back to city-owned.
- `agent/pilot.py`: influence wall-skip now requires actual nav-stuck evidence
  instead of firing from same-object duration alone. This keeps cleanup-reopened
  high-value walls such as `wall_landmark_01` and `wall_bodega_01` eligible during
  the `Own the block` cleanup race, while preserving the duration-based recovery
  for non-influence free-roam stalls.

### Verification
- `python -m py_compile agent\pilot.py`: pass.
- Windowed AGENT=1 launch: port 8088 listening; no script parse errors.
- Monitored 70-turn run before the tag-can fix: no hardware saturation observed
  (Godot ~920-931 MB, Python ~24 MB, Ollama resident process ~70-75 MB in
  sampled process tables), but `Own the block` did not claim before cleanup
  re-buffed useful walls.
- Monitored run after the tag-can fix reached `Paint 3 different walls` but was
  stopped at turn 30 when cleanup-buffed `wall_corner_01` was re-aimed despite
  already counting for the distinct-wall objective; close-wall aim was patched
  afterward.
- Run 18 (70 turns, task bwq9o67v5): opening chain through wall_corner_01 (1/3)
  cleared, close-wall aim patch confirmed (no re-aim at counted wall), but agent
  stalled on `move` for turns 25–70 due to Fix I bug above.  Fix I applied this
  session; next run should verify 2/3 and 3/3 walls complete.
- Run 19 (fresh 80 turns): Fix I verified. After `wall_corner_01` painted at turn
  24, `goto_wall` stayed legal and the free-roam redirect fired at turn 29. The
  run painted wall 2/3 at turn 31 and wall 3/3 at turn 34, cleared rival retake
  at turn 36, painted the crew piece at turn 45, and reached `Own the block` at
  turn 46. Hardware stayed stable (Godot ~926 MB WS near turn 28 and ~932 MB WS
  near turn 57; Ollama ~72 MB WS; Python ~24 MB WS).
- Run 19 also exposed the influence skip-list blocker fixed above: high-value
  walls were added to `influence_skip_walls` from same-object duration during
  cleanup churn, so the fresh run ended at turn 80 still on `Own the block`.
- Post-fix continuation from the run 19 blocker state cleared `Own the block`:
  bodega painted on continuation turn 1, landmark on turn 4, median on turn 8,
  and objective text became empty on turn 9.

### Known Issues
- A fully fresh 70-80 turn transcript with Fix J active from turn 1 would be nice
  final proof, but the targeted continuation verified the run 19 blocker fix.
- Crew-piece can still spend several turns aiming before painting; run 19 recovered
  naturally and painted on turn 45.

## Iteration 3

### Goal
Fix the renewed free-roam navigation stall where the player was physically
blocked near `wall_corner_01` by an NPC/local obstacle after painting the first
wall, leaving the pilot focused on the owned wall and repeatedly retrying far
`goto_wall` targets.

### Changes Made
- `Scripts/Debug/agent_server.gd`: stuck recovery now escalates across repeated
  failures instead of repeating the same side-step forever. It releases
  `move_forward`, then cycles side-step, back+side dodge, and run+back+side+jump
  escapes so NPC/contact blocks can create real separation.

### Verification
- AGENT=1 launch: pass, no parse errors in captured stderr.
- Interrupted 70-turn Ollama run: reproduced the local blocker during "Paint 3
  different walls" (turns 29-39), with the player pinned near `wall_corner_01`.
- Fresh 45-turn Ollama verification: cleared "Paint 3 different walls" by turn
  35, cleared rival retake turn 36, cleared crew-piece turn 38, reached "Own the
  block" turn 39, painted `wall_landmark_01` turn 41 and `wall_median_01` turn 44.

### Known Issues
- The 45-turn verification ended before the influence objective completed. A
  60-70 turn run is still needed to prove full block-claim completion.
- The model still recommends wider/pre-focus wall visibility; it used the
  territory-neutral `wall_mill_glass_01` as one of the three different walls,
  which counts for that objective but does not help later influence.

## Iteration 2

### Goal
Fix the "Paint 3 different walls" stall: after painting the first wall the agent
had no data to choose the next, latched onto a non-objective actor, and the harness
had no recovery for this objective type.

### Changes Made
- `Scripts/Debug/agent_server.gd`: `_nearby_walls()` now exposes `wallCategory`
  (open_wall / community_wall / respected_piece / danger_wall) and `owner` (player /
  rival / city / open) for every nearby wall, so the Ollama model can filter by
  eligibility without focusing each wall first.
- `Scripts/Debug/agent_server.gd`: stuck-sidestep now presses `jump` briefly in
  addition to the side-step, helping escape low geometry lips and obstacles.
- `agent/pilot.py`: free-roam actor-nav-stop extended from "own the block" only to
  all free-roam objectives (fires at same_obj >= 5 if dist <= 2.5 OR same_obj >= 12);
  comment updated to document the wider scope.
- `docs/AGENT_CHEATSHEET.md`: step 7 documents the new `wallCategory` and `owner`
  fields with decision guidance ("prefer open/rival/city, avoid player").

### Verification
- python compile: pass
- Godot smoke: pass (SMOKE: OK)
- AGENT=1 launch: pass (post-fix run)
- Ollama playtest: see Playtest Iteration 2 results

### Playtest Result
Baseline (50 turns): opening chain clean through turn 21, then "Paint 3 different
walls" stalled at turn 29 for 20+ turns — model chose `goto_actor` with no recovery.
Confirmed the exact gap addressed by the three fixes.

### Follow-up Tasks
- Verify the post-fix run reaches "rival retake" and "crew-piece" objectives.
- Add in-world wall-state indicators (floating labels above blank/rival/owned walls).
- Improve objective-target markers for NPCs and pickups when off-screen.

### Known Issues
- `nearby_walls` NEARBY_RADIUS is 14m; the model may not see useful walls when
  exploring if none are within that range. Consider increasing to 18–20m.
- In-world wall indicators (visual highlights, floating labels) still not implemented.

## Iteration 1

### Goal
Improve wall/objective clarity after an Ollama diagnostic playtest showed repeated confusion around which walls count for multi-wall, rival-retake, crew-piece, and territory-control objectives.

### Changes Made
- Added focused-wall HUD guidance for territory impact: open walls, already-owned walls, rival-held walls, cleanup-buffed walls, and territory-neutral surfaces now explain what painting will do.
- Added Ollama pilot planning metadata (`planning_style`, `planning_reason`, `plan`) and prints it in turn logs so future playtests capture 3-move vs 1-move decision style.
- Renamed the generic free-roam wall-stall recovery log from `influence wall-skip` to `free-roam wall-skip` so playtest triage does not misclassify crew-piece stalls as influence-only problems.

### Playtest Result
Diagnostic run reached the crew-piece step but stalled around free-roam wall selection and repeatedly recommended clearer wall-state/paintability indicators. Post-fix run reached the crew-piece step by turn 38 and painted a piece by turn 40; the model still recommended spatial wall highlights and objective-target indicators.

### Follow-up Tasks
- Add lightweight in-world indicators for nearby paintable wall state: open, already yours, rival-held, neutral.
- Add clearer mission/objective markers for NPCs and pickups when they are not in view.
- Tighten the playtester prompt/schema so `one_move` plans contain one step consistently.

### Known Issues
- The agent still sometimes restarts `goto_wall` before focus is acquired on open multi-wall objectives.
- The HUD text clarifies focused walls, but unfocused walls still rely on geometry/map visibility rather than in-world eligibility cues.

## Unreleased — Agent play harness (Phase 1–4)

Lets an external pilot (a local Ollama model, or a rule-based baseline) play the
game the way a human does — see `docs/OLLAMA_AGENT_PLAN.md`.

- `Scripts/Debug/agent_server.gd`: a localhost HTTP server (`AGENT=1`,
  self-disables under `SMOKE_TEST`) exposing `GET /observe` (player's-eye JSON
  state + a screenshot path) and `POST /act` (macro-actions executed by
  **synthesizing real input**, never mutating managers). Wired into
  `district.gd` boot, preloaded per the class-cache rule.
- Macro-actions: `select_can`, `cycle_color`/`cycle_cap`, `move`/`look`,
  `aim_at`/`goto_wall` (per-frame camera/leg controllers), `paint`, `freehand`,
  `rest`, `stop`, `wait`.
- `Scripts/UI/agent_overlay.gd`: a watchable on-screen overlay (`AGENT=1` only,
  owned by the server) showing what the pilot last perceived, the action it
  chose with its reason, and a rolling log of recent turns — so you can sit and
  watch *why* the agent acts. Top-right, cyan, clear of the HUD readouts.
- `agent/pilot.py`: stdlib-only pilot with two brains — `heuristic` (baseline)
  and `ollama` (multimodal, structured-output actions). `agent/README.md` +
  `docs/AGENT_CHEATSHEET.md` (the model's system prompt).
- Verified live: the heuristic pilot autonomously completes the opening
  objective (dismiss alias → walk to wall → tag, rep 0→29). Smoke unaffected
  (server gated off headless).
- Ollama tuning pass: `legal_actions` now reflects the current focus/prompt
  instead of advertising unusable actions, the pilot adds opening hints plus
  no-op/unavailable-action fallbacks, and turn logs flush live for watchable
  model iteration.

## 2026-06-20 — v4 Crew Hangout Beats

Adds Plan_v4 crew/social candidate 11 in the existing safehouse board flow.

- Opening the crew board now emits a short crew hangout line before the
  blackbook Crew page appears.
- The line is derived from existing morale and rival-duel state, with a quiet
  fallback before anyone has joined.
- Smoke coverage verifies the safehouse beat path without adding a new
  dialogue system or save data.

## 2026-06-20 — v4 Pocket Paint Flask

Adds a first Plan_v4 consumables-lane slice without new UI.

- Lupe now sells a one-shot Pocket Paint Flask: a cheap emergency +6 paint
  refill that uses the existing non-repeatable shop ownership path.
- Smoke coverage verifies the refill, one-time purchase guard, and restores
  the target route's paint/cash baseline before the rest of the supply checks.

## 2026-06-20 — v4 Gloves & Masks

Adds Plan_v4 supply candidate 17 by extending the equipped paint-tool lane
with stealth gear.

- Lupe now sells Nitrile Gloves and a Painter's Mask through the existing
  `grantsCap`/equipped-tool path.
- Gloves lower patrol suspicion with a small rep trade-off; the mask lowers
  heat and suspicion at a larger identity/rep cost.
- Smoke coverage buys both, verifies their heat/suspicion/rep trade-offs,
  preserves the target cash baseline, and keeps tool save/load coverage.

## 2026-06-20 — v4 Safehouse Rest Beat

Adds Plan_v4 atmosphere candidate 21 in a small, deterministic form.

- Safehouse rest messages now rotate through short time-passing beats while
  still reporting heat cooled and paint recovered.
- The rest result exposes the selected presentation beat for smoke/UI checks.
- `Sfx` plays a softer rest cue from the existing `safehouse_rest_changed`
  signal, so the action reads as a transition without adding a day/night sim.

## 2026-06-20 — v4 Save Backup Guard

Adds the first small slice of Plan_v4 candidate 28, focused on corruption
recovery rather than new UI.

- `SaveManager.quick_save()` now writes the normal save and a mirrored backup
  after validating the serialized JSON can be read back.
- `quick_load()` falls back to `user://toy_to_legend_save.backup.json` when
  the primary save is missing, invalid, or from a newer prototype version.
- Smoke coverage corrupts the primary save after a real route save and verifies
  the backup restores progression state.

## 2026-06-20 — v4 Mops & Markers

Adds Plan_v4 supply candidate 16 by extending the equipped cap kit into a
small paint-tool lane.

- `Data/caps.json` now supports optional `appliesTo` and `heatMultiplier`
  fields so a tool can affect only the graffiti types it fits.
- Lupe now sells a Pocket Marker for low-heat, lower-rep tags and an Ink Mop
  for louder throw-ups/pieces with a small rep bump.
- `WallManager` and `HeatManager` consume type-scoped rep and heat modifiers
  through `SupplyManager`, while the existing K-cycle/save path stays intact.
- Smoke coverage buys both tools, verifies type-scoped modifiers, preserves
  the target cash baseline, and keeps cap-kit save/load coverage.

## 2026-06-20 — v4 Morale-Driven Crew Events

Adds Plan_v4 crew-depth candidate 9: morale now has data-driven moments
that affect the crew without becoming a separate progression tree.

- New `Data/crew_morale_events.json` defines one-shot high-morale favors and
  the low-morale quiet/recovery thresholds.
- `CrewManager` consumes those events: a fired-up crew can earn a small supply
  favor once, while a rattled crew temporarily loses one recruited member's
  role until morale recovers.
- Save schema bumps to **v14** with `morale_events_used` and
  `quiet_member_id`; older saves migrate with no events spent and nobody quiet.
- Smoke coverage verifies the one-shot favor, quiet role suppression,
  recovery, save/load, and v13 migration.

## 2026-06-20 — v4 Duel Forfeit Penalties

Adds Plan_v4 rival-conflict candidate 5: ignoring a wall duel now has tuned
teeth instead of only incrementing the loss counter.

- `Data/crews.json` now carries data-driven `duelForfeitRepPenalty`,
  `duelForfeitCrewRepPenalty`, and `duelForfeitMoralePenalty` values per crew.
- `RivalManager` stamps those penalties onto each open wall duel next to the
  existing reward values, so saved active callouts keep their stakes.
- Forfeiting manually or by deadline now docks public rep, crew rep, and morale
  through the existing progression hooks, with smoke coverage for deadline
  expiry.

## 2026-06-20 — v4 Difficulty Presets

Adds Plan_v4 candidate 3 as a small data-driven accessibility/balance layer.

- New `Data/difficulty_presets.json` defines Relaxed, Standard, and Hard
  presets for heat gain, patrol density, shop prices, and cash rewards.
- `GameState` owns the selected preset, exposes multiplier helpers, saves it
  in the game section, and migrates older saves to Standard via save v13.
- The new-game alias modal keeps slots 1-3 for alias shortcuts and uses slots
  4-6 to choose Relaxed/Standard/Hard before starting.
- Smoke coverage verifies the preset multipliers, save/load, migration, and
  restores Standard so the existing v3 target route remains unchanged.

## 2026-06-20 — v4 Economy Regression Guard

Adds a diffable balance ledger for Plan_v4 candidate 2 so headline economy
values cannot drift silently.

- New `Data/balance_regression_targets.json` lists key snapshot paths with
  target values and tolerances for paint costs, paint-pack recovery, delivery
  pay, Ghost Local rewards, gallery rep, Rooftop Row claim rep, Calligraphy,
  and max morale scaling.
- `PlaytestMetrics` now reports `balance_regression_report()` and keeps
  `basePaintCost` in graffiti balance rows so the ledger is stable even when
  smoke leaves Fat Cap equipped for later checks.
- Smoke coverage fails if any ledger row moves outside tolerance and prints a
  compact balance regression summary.

## 2026-06-20 — v4 Cap/Morale Balance Integration

Folds the late v3 cap and crew-morale modifiers into the balance audit trail
for Plan_v4 candidate 1.

- `PlaytestMetrics.balance_snapshot()` now exposes `caps` rows for every spray
  cap and a `crew` balance row for morale min/neutral/max role-bonus factors.
- The smoke path asserts the Calligraphy Cap's +25% rep/+1 paint headline and
  the morale 0.9x/1.0x/1.1x bounds, plus invariant ceilings that keep the v3
  target route from silently inflating.
- `docs/BALANCE_TARGETS.md` now records how Calligraphy and morale should be
  interpreted against the 35-50 minute target run.

## 2026-06-20 — Cap Inventory: Spray-Behavior Caps

Generalizes the lone Fat Cap into a real cap kit, closing the 🟡 "caps as a
spray-behavior modifier system" gap (Plan.md §21 "caps modify spray behavior").

- New data-driven caps in `Data/caps.json`: **Stock** (always owned, no
  trade-offs), **Skinny** (+10% rep, easy to hide), **Fat** (−1 paint, but
  loud/bulky → gear suspicion), and **Calligraphy** (+25% rep, +1 paint, easy
  to spot). Each has `paintDelta`, `repMultiplier`, and `suspicion`.
- One cap is **equipped** at a time and drives the next paint. `SupplyManager`
  owns the kit (`owned_caps`, `equipped_cap`) and exposes `cap_paint_delta`,
  `cap_rep_multiplier`, and `cap_suspicion`.
- `paint_cost` now applies the equipped cap's `paintDelta` (floored at 1)
  instead of summing every owned discount; the cap's rep multiplier folds into
  the single `WallManager._begin_player_paint` rep hook, and its suspicion adds
  to `GameState.gear_suspicion_multiplier`.
- Shop items carry `grantsCap`: the Fat Cap purchase now grants+equips the fat
  cap, and Skinny/Calligraphy Caps are new buys. Buying a cap equips it.
- Equip cycling on **K** (controller B), shown in the wall prompt (`[K] Cap: …`).
- Save schema bumps to **v12**; older saves keep the stock cap (and back-fill
  the Fat Cap from an owned `fat_cap` purchase).
- Smoke coverage: default/owned state, the three trade-offs, the rep multiplier
  through a live paint (normalized per wall), paint-cost delta, cycle, equip
  guard, save/load, and v11→v12 migration.

## 2026-06-20 — Crew Morale Layer

Adds the team-level morale path that was the last 🟡 crew-depth gap, sitting
on top of per-member loyalty without becoming a second progression tree.

- New crew-wide `CrewManager.team_morale` (0–100, starts neutral at 50),
  saved/loaded and exposed through a `morale_changed` signal and
  `morale_text()` mood label.
- Morale folds into the existing `role_bonus_scale` hook as one bounded
  factor (`morale_factor()`, 0.9–1.1). At neutral it is exactly 1.0, so all
  existing role balance and smoke assertions are unchanged; only a crew that
  has been winning or losing together shifts every role bonus together.
- Shared events move the mood: recruiting a member (+6) and a member hitting a
  loyalty milestone (+2) lift it; winning a wall duel (+7) lifts it, losing or
  forfeiting one (−8) and getting caught (−5) drop it. Crossing a 20-point band
  announces the new mood once.
- The blackbook Crew page now leads with the team morale line when any writer
  is recruited.
- Save schema bumps to **v11**; older saves migrate with a neutral mood.
- Smoke coverage asserts recruiting lifts morale, the neutral 1.0x invariant,
  clamping, the band-cross announcement, save/load round-trip, and v10→v11
  migration.

## 2026-06-20 — Wall Duel Deadlines & Forfeits

Gives rival wall duels a fail state so an ignored callout is a real choice,
not a permanent free wall.

- Each open wall duel now carries a `ticksLeft` countdown
  (`RivalManager.WALL_DUEL_DEADLINE_TICKS`, default 8 simulation ticks). It
  ages one step per `_on_tick`, warns the writer one tick before expiry, and
  forfeits the wall to the crew when it runs out.
- Deadline expiry routes through the existing `forfeit_wall_duel`, which now
  takes an `expired` flag for the right message; both paths record the loss and
  reset the win streak through `GameState.note_rival_duel_loss`.
- The blackbook City page now shows the remaining answer window per active
  callout (`… (N to answer)`).
- The countdown rides inside the already-saved `active_wall_duels` dict and
  defaults gracefully for older saves, so no save-schema bump is needed.
- Smoke coverage opens a duel, ages it to the last-chance warning, and asserts
  the forfeit records a loss and clears the callout.

## 2026-06-19 — Battle Specialist Crew Role

Finishes the planned crew-role set by giving wall duels a dedicated crew hook.

- New data-driven crew member **Inez "Clash"** in `Data/npc_data.json`, using
  the generic recruitment and pickup flow.
- New `battle_specialist` role helpers in `CrewManager`: wall-duel rep and
  crew-rep rewards are loyalty-scaled when a callout opens, then saved on the
  active duel.
- Answering a wall duel now notes Battle Specialist role help, raising Clash's
  loyalty like the other gameplay-facing roles.
- Smoke coverage recruits Clash, verifies her model/role helpers, asserts
  boosted saved duel rewards, and checks loyalty gain on a duel win.

## 2026-06-19 — Safehouse Rest

Adds the first safehouse-depth slice: a rest action that skips time through
the existing simulation clocks instead of introducing a separate day/night
model.

- The safehouse prompt now keeps `E` for the crew board and adds `R` to rest.
- Resting advances heat/cleanup ticks, runs one territory upkeep tick, restores
  a small amount of paint, records the saved rest count, and shows one compact
  HUD outcome message.
- `HeatManager` and `TerritoryManager` expose small `advance_*_ticks` helpers
  so scripted systems can reuse their existing tick rules.
- Save schema bumps to **v10** and migrates older saves with
  `game.safehouse_rests = 0`.
- Smoke coverage verifies the prompt/action, heat cooling, paint top-up, rest
  counter, save/load restoration, and v10 migration.

## 2026-06-19 — Rival Wall Duels

Builds the post-M32 battle direction as a lightweight contested-wall feature
instead of a separate minigame.

- Rival responses now open a saved wall-duel callout when they cross out or
  cover the player's work.
- Repainting the challenged wall answers the duel through the normal
  `WallManager.paint_wall` path, pays a small rep and crew-rep bonus, records
  the win/streak, and avoids immediately queuing another retaliation from the
  same answer stroke.
- `RivalManager` now saves pending responses and active wall duels; save schema
  bumps to **v9** and migrates older saves with empty duel records.
- The blackbook City page shows wall-duel wins/losses/streaks and any active
  callout.
- Smoke coverage verifies duel opening, answer resolution, no stale pending
  response after direct `respond()`, save/load restoration, and blackbook
  visibility.

## 2026-06-19 — Milestone 32: Battle Prototype Paper Cut

Completed the v3 battle decision milestone without adding a new minigame.

- Added `docs/BATTLE_PAPER_CUT_2026-06-19.md`, comparing dance, rap/verbal,
  and graffiti wall duel prototypes against the current paint/territory loop.
- Decision: do **not** build a separate v3 battle minigame. The Undertow's
  DJ set already covers the clearest 60-second timing interaction, while a
  second dance battle would duplicate it without touching walls or heat.
- Recommended post-candidate direction: rival wall duels that reuse paint,
  territory, rival, crew, heat, and crowd-reaction systems, giving the future
  Battle Specialist role a real job.

## 2026-06-19 — Crew Loyalty & Role Upgrades

Turns the previously static crew loyalty data into a saved, gameplay-facing
upgrade layer for the recruited crew.

- `CrewManager` now tracks `loyalty_by_member` up to 100, exposes crew
  loyalty text/role scaling, and gently upgrades role bonuses as loyalty
  rises. At 50 loyalty the data-defined bonus is unchanged; higher loyalty
  nudges the role above baseline without becoming a full relationship sim.
- Crew members earn loyalty when their role visibly helps: Moth for lookout
  warnings, Metro for getaway escapes, Stash for shop/delivery help, Echo for
  crowd/nightclub hype, and Fix for softened penalties or cleanup mitigation.
- The blackbook Crew page shows each recruited member's loyalty, loyalty
  state, and current role scale alongside the existing role description.
- Save schema bumps to **v8** for the crew loyalty ledger, with migration and
  smoke coverage for older saves.
- Smoke coverage verifies loyalty gain, save/load restoration, v8 migration,
  and reward assertions that use the multiplier before role-help loyalty is
  awarded.

## 2026-06-18 — Fixer Crew Role

Finishes the standalone crew-role backlog that can ship before battles.

- New data-driven crew member **Vale "Fix"** in `Data/npc_data.json`.
- New `fixer` role helpers in `CrewManager`: caught rep loss, caught paint
  loss, and city cleanup sweep chance can all be reduced by member data.
- Patrol catches now apply the Fixer caught-penalty multipliers after Metro's
  one-free-escape route has been spent.
- Cleanup sweeps now apply the Fixer cleanup multiplier when rolling against
  player-owned walls.
- Smoke coverage recruits Fix, verifies the role modifiers and model, checks
  blackbook visibility, and asserts the reduced caught penalty through the
  live patrol catch path.

## 2026-06-18 — Hype Crew Role

Adds another crew-depth role using the existing generic recruitment flow and
reward systems.

- New data-driven crew member **Tali "Echo"** in `Data/npc_data.json`.
- New `hype` role helpers in `CrewManager`: crowd reactions can pay extra rep,
  and nightclub set payouts can scale with a member-defined multiplier.
- Ambient locals now use the crew crowd-reaction helper when paying their
  one-time fresh-paint rep tick.
- `NightclubPanel.result()` applies the Hype payout multiplier to Style XP,
  crew rep, and tip cash while keeping the same beat-scoring model.
- Smoke coverage recruits Echo, verifies the role effects and model, checks
  boosted nightclub payouts, confirms blackbook visibility, and asserts crowd
  reactions pay the crew-modified rep amount.

## 2026-06-18 — Supply Runner Crew Role

Adds the first remaining crew-role expansion after Moth/Caps/Metro: a
recruitable supply runner who plugs into Lupe's shop and delivery economy.

- New data-driven crew member **Nia "Stash"** in `Data/npc_data.json`, using
  the generic recruitment stage machine: meet, recover route ledger, recruit.
- New `supply_runner` role hooks in `CrewManager`: recruited runners can
  supply a `shopPriceMultiplier` and `deliveryMultiplier` from JSON.
- `SupplyManager.item_price` now applies crew shop discounts after Hustle/perk
  discounts, and delivery payouts apply the crew delivery multiplier.
- Lupe's shop UI and playtest balance snapshot now show/account for the crew
  delivery and price multipliers.
- Smoke coverage recruits Stash from data, verifies the role modifiers, checks
  the adjusted delivery payout, and confirms the blackbook Crew page lists the
  Supply Runner.

## 2026-06-18 — Nightlife: The Undertow (Product_reqs.md)

Closes the Product_reqs.md "dance / club / DJ rep-based invite" item — the
last open Product_reqs request. Adds a rep-gated nightclub in Canal Side
where a writer who's made a name can dance a DJ set for Style XP, crew rep,
and tip cash.

- Data-driven club in new `Data/nightlife.json` (`clubId`, `label`,
  `districtId`, `position`, `minRank`, `cover`, `beats`, `styleXp`,
  `crewRep`, `tipCash`). The shipped club, **The Undertow**, gates to rank
  `Known`.
- **Rep-based invite:** `Scripts/World/nightclub.gd` is a world interactable
  (same protocol as the bench) whose bouncer waves off anyone below
  `minRank` (new `GameState.rank_meets`). A qualifying writer pays the cash
  cover and the HUD opens the dance floor (`GameState.nightclub_requested`).
- **Dance / DJ set:** `Scripts/UI/nightclub_panel.gd` is a modal whose
  dance model (`begin`/`register`/`result`) lives off the UI nodes so the
  smoke test can drive it headless. A marker sweeps a bar; tapping on-beat
  builds hype, and final hype (hits ÷ beats) scales the payout. A late tap
  after the set ends can't over-score.
- **Reward design (no farm):** Style XP (level-capped) and DJ tip cash pay
  every set, but the cover charge is kept above the max tip so dancing is a
  cash sink, not a money printer. Crew rep — the only unbounded reward —
  pays **only when the writer beats their own floor record**, so re-dancing
  the same hype can't grind it.
- **Personal best:** `GameState.nightlife_best` remembers each club's top
  hype across sessions (and gates the crew-rep payout); `SAVE_VERSION` bumps
  to **7** with a migration that seeds the ledger empty for older saves.
- Smoke coverage (`_smoke_nightclub`): the bouncer gate, cover charge, a
  perfect set paying full and a sloppy set paying nothing, and best-hype
  bookkeeping.

## 2026-06-18 — Stickers & Wheatpaste Posters (Product_reqs.md)

Closes the Product_reqs.md "stickers and wheat pasting posters" item — the
art-school printmaking unlock. Adds a fast, low-heat **paper** lane that
complements spray work: cheap presence-spreading that goes up anywhere and
buffs easily.

- Two data-driven graffiti types in `graffiti_styles.json`: `sticker`
  (baseValue 8, paintCost 1, heatValue 1 — a two-second slap) and
  `wheatpaste` (baseValue 35, paintCost 2, heatValue 4 — a poster that pays
  more rep for its size). Both carry a `paper` flag and no surface
  restriction, so they stick to glass, doors, and poles a fill won't bite.
- **Unlock via a mentor, not the shop:** new art-school printmaker actor
  **Indigo** (`missions.json`, rank-gated to `Up`) near the Mill Yard
  safehouse, with a dialogue tree (`dialogue.json`) whose one-time lesson
  teaches both types. `DialogueManager._apply_effects` now honors
  `unlockTypes`, the same unlock the mission rewards use.
- **Paper render:** `PaintableWall._add_paper_backing` draws a paper stock
  panel + thin torn border behind the lettering (ink = the style's outline
  color, paper = its fill), visually distinct from drip-free spray work.
- **Gear suspicion:** carrying the bulky paste bucket adds
  `wheatpaste.gearSuspicion` (0.06) on top of the per-can tally
  (`GameState.gear_suspicion_multiplier`); flat stickers add no extra bulk.
- Reachable in-world via `[`/`]` can cycling (past the six number slots).
- Smoke coverage (`_smoke_stickers`): rank-gated one-time lesson, the unlock,
  rising gear suspicion, cheap/low-heat data, the paper-backed render, and a
  slap on the storefront glass.

## 2026-06-18 — Wildstyle Heaven-Spot Payoff (Product_reqs.md)

Closes the reward half of the wildstyle `exposure` mechanic. Exposure
already raised heat and patrol attention (Milestone 16); it now also pays
off when the writer risks a heaven spot.

- New `heavenSpot` wall flag (`Data/walls.json`) on the six high, very
  visible walls — the Mill Yard landmark + mill roof and the elevated
  Rooftop Row pieces.
- `WallManager.heaven_spot_exposure_bonus(def, style_id)` multiplies a
  player paint's reputation by the font style's exposure (wildstyle
  `maelstrom` = 1.35x) when, and only when, the wall is a heaven spot.
  Ordinary styles (exposure 1.0) and ordinary walls pay 1x.
- New `GraffitiFonts.style_exposure(style_id)` (clamped to >= 1.0) so the
  payoff and the existing heat/patrol exposure read one source.
- Smoke coverage (`_smoke_wildstyle_payoff`) — pure, state-neutral checks
  of the flag, the exposure value, and the bonus gating.

## 2026-06-18 — Bespoke Tag-Style Behaviors (Product_reqs.md)

The scratch- and acid-hand font styles now behave the way their data
always described, closing the Product_reqs.md 🟡 items.

- **Glass-only gating:** styles flagged `glass` (the `secret_labs` scratch
  hand and the `street_toxic`/`the_battle_continuez` acid hands) can only
  be applied to a `glass` surface. `WallManager.font_style_block_reason`
  enforces it on the player's selected style inside `paint_block_reason`,
  with a clear "only takes on glass" message.
- **Greyscale scratch render:** a one-color scratch hand (`oneColor` +
  `opacity`) draws as a luminance-matched grey at the style's opacity
  (~0.5), instead of full color.
- **Acid orientation:** acid hands list `orientations: [horizontal,
  vertical]` and now render **vertical** down a tall (portrait) glass
  panel, horizontal otherwise. The rule lives in
  `GraffitiFonts.render_plan`, shared by `paintable_wall.gd` and the
  smoke test.
- New helpers on the font library (`style_is_glass_only`,
  `style_is_one_color`, `style_opacity`, `style_orientations`,
  `render_plan`) keep the behavior data-driven and testable off-tree.
- Added a `glass` surface type (storefront-window detailing in
  `paintable_wall.gd`) and a portrait glass wall, the **Corner Store
  Window** in Mill Yard (`Data/walls.json`). It is `territoryNeutral`:
  `TerritoryManager` excludes such surfaces from influence/standing
  weight, so scratching a window doesn't shift who holds the block.
- Smoke coverage (`_smoke_bespoke_styles`) checks the gate, the render
  plan, and the live greyscale/vertical rendering — all state-neutral so
  the rest of the run is unaffected.

## 2026-06-18 — Milestone 31: Performance & Runtime Budget Pass (Plan_v3.md)

Measures what the current three-district city costs before more content
is added, per Plan_v3.md §3.4 / Milestone 31.

- Added a runtime budget snapshot to the `PlaytestMetrics` autoload
  (`runtime_budget_snapshot(scene_root)` / `runtime_budget_summary_text`),
  next to the Milestone 27 playtest ledger and Milestone 28 balance
  snapshot. It records world node count, a node-type histogram,
  `MeshInstance3D` count, spawned wall/train counts, `interactable`
  count, the Milestone 24 material-cache size, the player's character-
  visual import status (`animated`/`static`/`capsule` + clip count via
  new `Player.visual_report()`), and a live `Performance` frame readout
  (fps, process ms, rendered objects, static MB — 0 on the headless
  server).
- Documented soft desktop budgets in `PlaytestMetrics.RUNTIME_BUDGETS`
  (world nodes, meshes, walls, material cache), set to current usage plus
  headroom so the snapshot's `overBudget` list flags the next big content
  addition. The smoke test fails if the built city exceeds them.
- The profile is dormant in normal play. `RUNTIME_BUDGET=1` prints one
  `RUNTIME_BUDGET: ...` line after the world finishes building; the
  headless smoke run always prints `SMOKE: runtime budget — ...`.
- Added `docs/PERFORMANCE_BUDGETS.md` (how to run, fields, budgets,
  findings) and a README profiling note. Smoke coverage asserts the
  snapshot is well-formed, tracks manager spawn counts, and stays within
  budget (`_smoke_runtime_budget`).
- Finding: runtime-built street detail is the dominant mesh source
  (~2100 of ~3660 nodes). No bottleneck is measured, so per Plan_v3.md
  §3.4 no renderer change is made; MultiMesh instancing is the documented
  first lever if a fourth district pushes meshes over budget.

## 2026-06-14 — Benches: Sit to Sketch Styles (Product_reqs.md)

The writer can now sit on a bench to practice tag styles in the
blackbook.

- Added data-driven benches (`Data/benches.json`, `Scripts/World/bench.gd`)
  — two in Mill Yard, one in Canal Side — spawned by `district.gd`. They
  sit on the sidewalk facing the street, each an `interactable` with a
  "[E] Sit & sketch styles" prompt.
- Interacting seats the player: `Player.begin_sit` snaps them onto the
  seat facing the street and suppresses movement/world actions (same
  pattern as the ladder climb). The Kronako `Chair_Sit_Idle` clip is
  imported as `neon_rooster_sit.glb` and registered as the looped `sit`
  visual state; it falls back to idle if the GLB is missing.
- The view plays the sit in third person, then drops to **first person**
  (`Player.set_first_person`) once the sit settles, and returns to third
  person when the player stands up.
- Settling opens the blackbook in a new **practice mode** on the Styles
  page: the number keys sketch the tag styles still worth practicing
  (delegating to `GameState.practice_tag_font_style`, one page per press)
  instead of flipping pages. Closing the book (`Tab`/`Esc`) stands the
  player back up via `GameState.sit_practice_ended`.
- Practice mode shows a white **sketch page** at the top of the book:
  the writer's tag drawn large in the font of the style being practiced,
  updating to whichever style you sketch. Blackbook body text now wraps
  (long lines like the full tag-style list no longer balloon the panel
  width and push centered content off-screen).
- Styles can only be practiced while seated — you sketch in your book on
  a bench, not mid-stride.
- Smoke covers bench spawn/prompt, seating + movement suppression, the
  practiceable list, a sketch incrementing the count, a bad-slot reject,
  and standing up on close.

## 2026-06-13 — Tag Rendering: No Drips/Panels, Type-Capable Fonts, Letter Reveal (Product_reqs.md)

Graffiti rendering changes from Product_reqs.md.

- **No more paint drips.** `paintable_wall.gd` no longer draws the
  hanging paint runs under any graffiti — player or rival, every type.
  The `_add_drips` helper and its `drip_spread`/`letter_bottom`
  bookkeeping are gone.
- **No more rectangular background panels.** Throw-ups, pieces,
  stencils, rollers, and murals (player and rival) are now bare
  lettering like tags — the solid color/dark panel quads behind the
  letters are removed. Rival work keeps its crew color, slant, and
  stripes/chips/cut-marks (Milestone 29 variety) but no panel. Buff
  patches still use panels (they are meant to be rectangles).
- **Each type only renders a font capable for that style.** Every
  graffiti type now carries a `fontFamilies` list in
  `graffiti_styles.json` (tag → hand/scratch, throw-up → throw, piece →
  wildstyle/throw, stencil → stencil_art, roller → throw, mural →
  wildstyle/throw). New `GraffitiFonts.resolve_for_families` keeps the
  selected style if its family fits the type, otherwise falls back to
  the simplest capable style — so a marker hand never letters a
  throw-up, piece, roller, etc. Rival lettering uses the same rule.
- **Letters spray on one at a time.** A fresh player paint reveals its
  lettering character by character (`show_graffiti(graffiti, true)` →
  `_reveal_label_letters` tween); reloads and visual refreshes still
  render instantly, and the reveal is skipped headless.
- Smoke coverage asserts type-capable font resolution and that a fresh
  tag renders bare (single label node, no drip/panel children).

## 2026-06-13 — Climb Finish, Ladder Pose, Rival Fox Model (Product_reqs.md)

Polish pass on the climb and rival visuals.

- Topping out a ladder now plays an over-the-ledge finish clip. The
  Kronako `Ladder_Climb_Finish` GLB is imported as
  `neon_rooster_ladder_climb_finish.glb` and registered as the
  `climb_finish` visual state; `player.gd` plays it on summit
  (`_summit_climb`), skipping silently if the GLB isn't imported.
- The climbing pose is nudged onto the ladder. `CLIMB_VISUAL_OFFSET`
  shifts just the climb model left and a touch toward the wall so the
  body no longer floats off to the right of the rungs.
- Rival taggers wear the Hooded Fox Warrior model instead of a colored
  capsule. Four clips (`Idle_02`, `walking_man`, `running`, `RunFast`)
  import as `hooded_fox_warrior_*.glb`; `rival_tagger.gd` runs in on the
  run clip and settles into idle for the spray beat, falling back to the
  capsule when the GLBs are missing. The crew color still rides on the
  spray can and name tag.
- Smoke coverage asserts the climb finish triggers on summit and that a
  spawned tagger builds the fox model and swaps run→idle for the tag.

## 2026-06-13 — Random Idle Animations (Product_reqs.md)

The main character no longer stands in a single breathing pose.

- Three Kronako idle clips (`Idle_4`, `Idle_6`, `Idle_11`) are imported
  to `Assets/Characters/` as `neon_rooster_idle_*.glb` and registered as
  extra idle visual states alongside the legacy idle.
- `player.gd` picks a random idle when the player settles from movement
  and holds that stance for the whole idle (`_set_idle_state`); the pose
  only changes the next time idle re-activates, not while standing still.
  Each idle clip is forced to loop so it never freezes. Missing imports
  just shrink the pool — with none, it falls back to the legacy idle.
- Smoke coverage asserts the idle variants build with their clips, that
  the stance holds across repeated idle frames, and that moving away and
  settling back re-rolls it.

## 2026-06-13 — Rival Tagger Run-Up + Retaliation Floor (Product_reqs.md)

Rival retaliation is now something the player watches happen, and it can
no longer land instantly.

- A queued rival response can never fire sooner than 30 seconds after the
  player paints (`RivalManager.MIN_RESPONSE_DELAY_MS`): each pending
  entry carries a `readyAt` stamp and `_on_tick` holds it until both the
  tick countdown and that floor have passed. TOY no longer appears over a
  fresh tag within a few seconds.
- When a response is due, a `RivalTagger` (new
  `Scripts/Rivals/rival_tagger.gd`) spawns to the side, runs up to the
  wall face, sprays for a beat, and flees. The actual wall mutation runs
  through `RivalManager.respond` the moment the tagger reaches the wall,
  so WallManager's `wall_painted` flow is unchanged — the tagger is just
  the visible body for it.
- `district.gd` registers the tagger spawner (windowed only via
  `DisplayServer`); headless keeps the instant-response path, so the
  smoke test is unaffected.
- Smoke coverage asserts the 30-second floor: the queued retaliation
  carries a `readyAt` at least that far out and survives an early tick.

## 2026-06-13 — Interactive Ladder Climb (Product_reqs.md)

Climb routes are now ladders the player rides by hand instead of an
instant dice-roll teleport.

- Climb zones render an actual rail-and-rung ladder running from the
  foot up to the exit, replacing the old slim-pipe hint.
- Committing to a climb (E) rolls the Milestone 19 slip once at the
  foot; clearing it attaches the player to the ladder for a controllable
  ride. Forward/back climbs up/down, direction can change at any time,
  reaching the exit summits (and still fires district transitions), and
  dropping back to the foot — or Space — steps off without summiting.
- The ladder-climb clip now plays continuously while climbing: forward
  going up, reversed going down, paused when holding a rung. World
  actions (paint/interact/freehand) are suppressed while on the ladder.
- `ClimbZone.resolve(success)` is unchanged so the deterministic
  test/scripted path (and the guard climb clip) still work.
- Smoke coverage drives the interactive climb headlessly: attach at the
  foot, reverse mid-climb, summit at the top, and step off at the foot.

## 2026-06-13 — Milestone 30: Rooftop Traversal Polish (Plan_v3.md)

Rooftop Row now communicates its risk and return path more clearly.

- Climb prompts are context-aware: Rooftop Row access says "Climb to
  Rooftop Row" and the return route says "Descend to Canal Side."
- Successful Rooftop Row entry now toasts a return-route hint pointing
  players back to the CANAL DESCENT climb.
- Added non-text rooftop hazard tells: edge-warning strips along the
  parapets and pale wind streaks across the deck.
- Smoke coverage now checks the access/descent prompts, first-entry
  return hint, generated hazard tell nodes, and the existing Rooftop
  Row claim route.

## 2026-06-13 — Milestone 29: Procedural Rival Graffiti Variety (Plan_v3.md)

Rival walls now read more like crew marks instead of repeated labels.

- Added deterministic rival graffiti layout generation in
  `Scripts/Walls/rival_graffiti_style.gd`, seeded by graffiti id,
  crew id, and graffiti type so saves and screenshots stay stable.
- `PaintableWall` now uses a rival-only render path for non-player
  graffiti: crew-color panels, offsets, stripes, chips, stencil cuts,
  and drips vary by type without storing image blobs.
- Player freehand rendering and image persistence remain untouched.
- Smoke coverage now asserts deterministic variant generation, visual
  node variety, no rival image blob storage, and save/load variant
  stability.

## 2026-06-13 — Milestone 28: Balance Pass 1 — Main Path (Plan_v3.md)

First v3 tuning pass, aimed at the documented target run in
`docs/BALANCE_TARGETS.md`.

- Added v3 balance targets: 35-50 minute first run, 1-3 mistakes,
  1-3 paint-pack purchases, Known by Mill Yard claim, and Block King
  near the end instead of too early.
- Tuned data first: lowered stacked rep from district claims, trains,
  gallery sales, Rooftop Row, rollers, pieces, and murals while making
  paint recovery less brittle through cheaper/larger paint packs and
  lower late-game paint costs.
- Softened patrol and rooftop punishment: spotted heat, caught fines,
  Rooftop Row fall chance, and fall penalty now leave more room for a
  normal first-run mistake.
- Adjusted mission rewards around Canal Side and Rooftop Row so late
  required work has a clearer recovery path without flooding public rep.
- Added smoke-test balance invariants for paint-pack affordability,
  late-path paint coverage, required unlock order, rep-inflation caps,
  and Rooftop Row return-route availability.
- Updated older smoke assertions to read tuned values from data instead
  of hard-coded pre-balance constants.

## 2026-06-13 — Milestone 27: Playtest Instrumentation & Balance Baseline (Plan_v3.md)

The v3 loop now starts with measurement instead of tuning by feel.

- Added `PlaytestMetrics` as an optional autoload that listens to
  existing gameplay signals but records nothing unless a capture is
  started.
- `PLAYTEST_METRICS=1 Godot --path .` writes
  `user://toy_to_legend_playtest_metrics.json` with first-beat timings,
  caught/fall/starvation counters, and the event ledger for a live run.
- The headless smoke path now starts a `smoke_baseline` capture and
  asserts the main beats: first paint/rank, three district claims,
  Canal Side and Rooftop Row entry, train painting, gallery refusal,
  gallery sale, caught count, and fall count.
- Added a balance snapshot helper covering graffiti costs/heat,
  mission rewards, district payout/decay, heat ticks, patrol config,
  trains, gallery config, stats/perks, and supply prices.
- README now documents the live playtest capture command and metrics
  output path.

## 2026-06-12 — Milestone 26: Rooftop Row District (Plan_v2.md)

The third district is in, and it is reached vertically instead of by a
street gate.

- Added `district_rooftop_row` to `Data/districts.json` with no travel
  point; `ClimbZone` can now set `targetDistrictId` on successful
  climbs, and the Row fire escape/descent routes move between Canal
  Side and Rooftop Row.
- Built a compact elevated Rooftop Row deck in `district.gd` with
  parapets, lamps, a train-below visual, and five rooftop-surface wall
  defs tuned for roller-heavy, high-visibility play.
- Added Chrome Saints rooftop presence, a Rooftop Row patrol route,
  and extended the Ghost Local train service through the third
  district for pass-through visibility value.
- Added a three-mission `rooftop_row` chain: climb entry, skyline
  roller work, and district claim.
- Smoke test now covers climb-only entry, district trigger, roller
  claim, descent, and train service including Rooftop Row.

## 2026-06-12 — Milestone 25: Ambient NPC Life (Plan_v2.md)

The blocks now have a small street-life layer instead of only mission
actors and guards.

- Added `Data/ambient_npcs.json` with three waypoint-loop locals in
  Mill Yard and three in Canal Side, all reusing existing character GLB
  idle/walk sets through visual manifests.
- New `Scripts/World/ambient_npc.gd`: ambient locals walk simple
  no-nav loops, pause for nearby fresh player paint, and pay a one-time
  +1 crowd-reaction rep tick per wall.
- Ambient locals scatter only when their own district spikes to Hot or
  Blazing heat, so danger reads locally instead of globally.
- Security now triggers the imported bull ladder-climb clip when a
  chase ends because the player reached high ground.
- Smoke test now covers ambient spawns, crowd reaction rep, district
  heat scatter, and the guard climb clip trigger.

## 2026-06-12 — Milestone 24: World Render & Data Hardening (Plan_v2.md)

World hardening pass before adding more districts.

- `district.gd` now reuses cached `StandardMaterial3D` instances for
  repeated generated world details and common solid/noisy surfaces,
  reducing one-off material churn from street props, rails, litter,
  drains, sidewalks, and graybox surfaces without changing visuals.
- Player fallback interactable selection now checks line of sight with
  a physics ray before focusing nearby `interactable` group nodes, so
  pickups/zones are no longer selected through thin geometry.
- Milestone 22 already landed the data-driven character `visuals`
  manifests requested by this milestone; this pass keeps that status
  documented as complete.
- Smoke test adds `_smoke_world_hardening` for material-cache reuse and
  occluded interactable LOS.

## 2026-06-12 — Milestone 23: Presentation Pass (Plan_v2.md)

The demo now opens like a game instead of dropping straight into the
block.

- Added a title/alias modal in HUD: new games start with
  `alias_chosen = false`, choose a writer name, then advance the first
  mission's alias objective. Presets NOVA/KILO/ECHO keep startup
  controller-friendly.
- Added controller bindings through `GameState._setup_input_actions`:
  left stick movement, right stick camera look, face/shoulder buttons
  for jump/interact/run/freehand/color, d-pad left/right can cycling,
  and d-pad/system buttons for panels.
- Rooster presentation pass: the idle animation now plays gently
  instead of freezing on frame 0.
- `Sfx` now layers a synthesized low music bed with per-district
  ambient loops that switch on district travel.
- Smoke test now explicitly chooses the alias before first paint and
  asserts controller movement bindings are present.

## 2026-06-12 — Milestone 22: Crew Depth (Plan_v2.md)

The crew now has more than a lookout.

- Added Rico "Caps" (filler) and Jay "Metro" (getaway) to
  `Data/npc_data.json`, each with the existing recruitment mini-chain:
  meet them, recover their item, return it, then unlock their role.
- Rico auto-fills a small number of open/non-player walls with
  no-rep throw-ups when a district is already claimed, keeping passive
  crew work inside `WallManager.apply_crew_graffiti` so territory
  updates without counting as player heat, XP, or mission paint.
- Metro gives one free security escape per heat level before normal
  catch penalties apply.
- The safehouse zone is now an interactable crew board: E opens the
  blackbook directly to the Crew page.
- Character visuals for recruitable NPCs and mission actors are now
  data-driven through `visuals` manifest blocks in `npc_data.json` and
  `missions.json`, consumed by `animated_model_set.gd`; Lupe, Prime,
  Moth, Caps, and Metro no longer need per-script model-path constants.
- Smoke test now covers the new recruitment paths, manifest-driven
  visuals, Caps territory fills, Metro's escape-then-catch behavior,
  Crew-page UI text, and v5→v6 save migration.
- Save schema bumped to v6 for the crew getaway ledger.

## 2026-06-12 — Milestone 21: Gallery Missions (Plan_v2.md)

Selling out is now a real decision (the last §46 success criterion).

- New `GalleryManager` autoload (`Scripts/Gallery/gallery_manager.gd`)
  and `Data/gallery.json`: Vesper the gallery scout buys freehand
  canvases. The Milestone 14 canvas is the gameplay — `freehand_panel`
  gained `begin_canvas` for wall-less commissions — and the freehand
  style multiplier is the judge's score. Canvases under the accept
  score are refused: paint spent, nothing paid.
- Public/crew rep split (Plan.md §11, minimal form):
  `GameState.crew_rep` is the one tracked value. Accepted sales pay
  cash (Hustle-scaled) + public rep and cost crew rep; recruiting
  (+10) and crew-backed murals (+2) build it back. Shown in the HUD
  stats panel and the blackbook Writer page; City page logs sales.
- Vesper is a rank-gated mission actor (`minRank` on actor defs hides
  the NPC and its collision until the rank is reached — §43 "appears
  at rank Known") with a dialogue tree routing into the commission
  (`start_gallery` action).
- Third mission chain `gallery_debut` (m9 White Walls) with the new
  `rank` chain trigger and `gallery_sale` objective type.
- Save schema bumped to v5 (gallery sales log + crew_rep) with
  migration; smoke test covers the rank gate, refusal and sale
  branches, payout math, crew-rep ledger, blackbook text, and v4→v5
  migration.

## 2026-06-12 — Milestone 20: Train Painting (Plan_v2.md)

The signature demo moment has its first playable slice: your name
moves without you.

- New `TrainManager` autoload (`Scripts/Trains/train_manager.gd`) and
  `Data/trains.json`: scheduled train cars have stopped/travel phases,
  a short yard painting window, paint/heat costs, pass-through rep, and
  service districts.
- Added the first Canal Side train siding and runtime `TrainCar`
  interaction target. Painting a stopped car spends paint, creates a
  persisted train graffiti record, adds high heat in Canal Side, and
  sends HUD events as it enters service.
- Painted cars now pay visibility-over-time rep each time they roll
  through Canal Side and Mill Yard, making Plan.md §11's moving fame
  loop tangible.
- Blackbook City page logs painted train cars, aliases, phases, and
  pass counts.
- Save schema bumped to v4 with train-state migration; smoke test now
  covers train painting, pass-through payouts, blackbook logging, and
  save/load.

## 2026-06-12 — Player animation action set

The rooster is now animated across the core movement verbs.

- Added skinned GLB action clips under `Assets/Characters/`:
  idle/rest, walk, walk backward, run-fast, jump, ladder climb, and
  vault. Godot import extracts one texture per clip.
- `player.gd` builds a single `CharacterModel` container and loads the
  available action clips into a state table. The active clip swaps by
  movement context: idle, normal movement, backward movement, Shift
  run, airborne jump, and contextual climb.
- `climb_zone.gd` now asks the player to play the ladder-climb context
  animation on successful climbs.
- Vault is imported and bound for the future, but no gameplay trigger
  exists yet.
- Smoke test: `_smoke_player_model` now asserts the full animated
  action set is imported and bound. No save schema change; collision
  and movement numbers are unchanged.

## 2026-06-12 — Player character: Kronako Iconz rooster

First real character art replaces the debug capsule.

- **Neon rooster GLB** (`Assets/Characters/neon_rooster.glb`, ~10k
  tris, textured): instantiated at runtime in `player.gd`
  (`_build_visual`), scaled to the 1.8 m capsule collider, rotated
  180° (glTF +Z forward → Godot -Z).
- Falls back to the old debug capsule when the GLB import is
  unavailable (fresh checkouts before an editor / `--import` run), so
  headless smoke runs never hard-fail on a missing import.
- Smoke test: `_smoke_player_model` — exactly one visual child, and
  the rooster whenever the import resolves.
- No save schema change; collision/movement untouched.

## 2026-06-12 — Milestone 19: Rooftop Climbing (Plan_v2.md Should-Have)

The high ground opens up — and the risk moves into the climb.

- **Climb zones** (`Data/climbs.json` → `Scripts/World/climb_zone.gd`):
  drainpipe/ladder spots at the foot of the Mill West block and the
  Grain Silo. E attempts the climb: make it and you're on the roof at
  the Milestone 16 roller spots; slip (`fallChance`) and you take the
  caught-equivalent fine (`fallRepPenalty` rep) — Plan_v2.md's "risk
  shifts to the climb itself". `resolve(success)` is deterministic for
  tests; `interact()` rolls.
- **Security won't climb**: a chasing guard gives up the moment the
  player holds the high ground (>2.5 m above them) — and that counts
  as an escaped chase (Stealth XP).
- New `GameState.player_event` signal: world-object outcomes (climbs,
  future trains) toast on the HUD without each needing a manager.
- Smoke test: `_smoke_rooftop_climbing` — fall fine math, climb to the
  parapet + roller paint from the roof, grounded-guard give-up.
- No save schema change.

## 2026-06-12 — Milestone 18: Second District — Canal Side (Plan.md §45, §12)

The city grows east across the water. Two blocks, two stories.

- **Canal Side**: 8 new walls (`walls.json`) on a new graybox block —
  lock house, towpath, pump station, dry dock, the Grain Silo
  landmark — plus the canal itself and a footbridge. Ghost Line's
  home turf: their stencils claim three canal walls at boot
  (`crews.json` territory).
- **Travel points** (`Scripts/World/travel_point.gd`): footbridge
  gates defined per district in `districts.json` (`travel` +
  `arrival`). E crosses; `GameState.current_district_id` +
  `district_changed` drive everything downstream.
- **Mission chains**: `missions.json` is now an array of chains;
  chains activate in order when the previous is done and their
  trigger fires (`enter_district`). The Canal Side chain (m6 New
  Waters → m7 Ghosts in the Water → m8 Canal King) starts the first
  time you cross after claiming the Mill Yard. Paint objectives can
  be district-scoped (`districtId`).
- **Per-district heat** (§12): `HeatManager.heat_by_district` — paint
  heats the block the wall is on; the bare `heat` property reads the
  player's current block, so every old call site still works. Blocks
  the player left cool at **double rate** per tick: leaving the block
  is laying low. Cleanup pressure and the rep formula use the wall's
  own district heat.
- **Patrols per block**: routes carry `districtId` (3 mill + 3
  canal); crossing the bridge swaps the active guard set.
- Map becomes a city map: bounds fit every wall, one influence line
  per district. HUD announces the block you enter and its heat.
- Save schema **v3**: per-district heat dict, chain index/flags,
  chain-prefixed painted-objective keys; v2 saves migrate (heat into
  Mill Yard, painted keys gain the `0:` chain prefix).
- Smoke test: `_smoke_canal_side` — footbridge travel, chain trigger,
  Ghost Line's scripted cross-out + the full m6–m8 run, heat
  isolation between districts, double-rate absent cooling, v3
  round-trip, v2→v3 migration.

## 2026-06-12 — Milestone 17: Progression Depth (Plan.md §5, §6, §7, §11)

Choosing what kind of writer you are. New `StatsManager` autoload
(`Scripts/Stats/stats_manager.gd`), all numbers in `Data/stats.json` /
`Data/perks.json`.

- **Stats raise by doing** (§6): **Style** (+5% rep per level; XP from
  every paint, by paint cost), **Stealth** (guards spot you 5% closer
  and paint draws 5% less heat per level; XP from unwitnessed paints
  and escaped chases via new `PatrolManager.paint_observed` /
  `chase_escaped` signals), **Hustle** (4% cheaper shop prices and
  +10% delivery pay per level; XP from purchases and deliveries via
  new `SupplyManager.item_bought` / `delivery_completed` signals).
- **Perks** (§7): one perk point per rank-up (highest-rank watermark —
  no farming via demotion), two perks per tree across the five §7
  trees: Clean Lines / Burner Hand (style), Soft Steps / Ghost
  (stealth), Street Respect / Scout Network (crew — rival retaliation
  damp), Block Pride / Deep Roots (territory), The Connect / Runner
  (supplies). **P** opens the chooser (a modal-registry entry): one
  option per tree at a time, so choices always fit the number keys.
- **Reputation decay** (§11): every 36 s tick, standing player work
  pays a trickle (`payoutPerWeight` × visibility weight) while
  **crossed-out and buffed work pays nothing**, and any district
  where your share is below the claim threshold cools you by
  `decayRep`. Territory defense is now upkeep, not a trophy.
- Save schema **v2**: new `stats` section; v1 saves migrate forward in
  `SaveManager._migrate`.
- Blackbook Writer page shows stat levels and perk points; shop rows
  show discounted prices; HUD announces stat-ups, perk points, perk
  picks, and fading districts.
- Smoke test: `_smoke_progression` — XP earned through play, level-up
  changes the rep math, perk gating (owned/tree-order/point spend),
  price cut math, payout tick, crossed-out exclusion, decay branches,
  stats save/load, v1→v2 migration.

## 2026-06-12 — Milestone 16: Full Graffiti Type Set (Plan.md §8, Plan_v2.md §4)

The three missing §8 types, all data-driven from
`Data/graffiti_styles.json`:

- **Stencil** — cheap, fast, low rep. Gated behind Lupe's new Stencil
  Kit (`supplies.json` items can now carry `unlockType`; buying the
  gear IS the unlock).
- **Roller** — high rep, big paint cost, only on `rooftop` surfaces
  (per-style `surfaces` list checked against the wall's
  `surfaceType`). New Mill West Rooftop parapet wall; reachable by
  hand once Milestone 19 ships climbing — paintable by rivals and
  code today.
- **Mural** — highest rep, needs crew present (`requiresCrew`; the
  filler-role specialization arrives with Rico in Milestone 22), and
  the long paint time is modeled as `exposure`: the patrol witness
  check doubles its range and ignores facing for murals
  (`PatrolGuard.noticed_during`).
- Roller + mural unlock when "Claim the Block" completes; rank stays
  the rep ladder.
- **Rivals play by surface rules too**: Ghost Line now answers with
  stencils (`responseType`), and any crew whose signature type is
  blocked on a wall falls back to a throw-up.
- **Number keys generalized**: `slot_1..slot_6` actions replace
  `graffiti_*`/`shop_delivery`. Outside a modal they select cans in
  canonical style order; in modals they pick that modal's slots
  (shop rows incl. the new 4-item catalog + delivery, dialogue
  choices, blackbook pages). Wall prompt now lists every unlocked can
  with its key, shows the wall's surface, and says up front why the
  selected can won't work on this wall; blackbook Styles page carries
  per-style notes and locked hints.
- Placeholder art for the three new types (crisp stencil, full-width
  roller strip, layered mural color field).
- Smoke test: new `_smoke_graffiti_types` section — kit gate, surface
  gate, crew gate, slot selection, mural exposure (unseen tag vs
  clocked mural at 12 m), and the rival fallback.

## 2026-06-11 — Milestone 15: Engineering Hardening (Plan_v2.md §3)

No new gameplay — all seven findings from Plan_v2.md §3, paid down
before v2 content multiplies their cost. Identical smoke-test behavior
plus new assertions; no save schema change.

- **Modal stack (§3.1):** `Hud` now keeps a modal registry — shop,
  dialogue, blackbook, map, freehand — in input priority order. One
  `close_modals(except)` powers every opener, the first open modal
  owns `_unhandled_input`, and Tab/M go through `_toggle_modal`. The
  hand-ordered if-ladder and the per-modal "close all the others"
  choreography are gone; a 6th modal is one registry entry. Fixes the
  latent bug where Tab/M could stack the blackbook/map on top of an
  open freehand canvas.
- **UI kit (§3.2):** new `Scripts/UI/ui_kit.gd` (static, preloaded —
  CLAUDE.md class-cache rule) owns the outlined-label and accent-panel
  recipes. The four drifting copies in hud/blackbook/freehand/map are
  deleted.
- **Smoke test split (§3.3):** `district.gd::_run_smoke_test` is now a
  sequence of 13 per-system `_smoke_*()` functions, each documenting
  the world state it assumes. Same `SMOKE_TEST=1` entry point, same
  assertions, same `SMOKE: OK`.
- **Unified paint head (§3.4):** `WallManager._begin_player_paint`
  now owns the unlock check, paint spend, and rep payout (style
  multiplier + buff-retaliation bonus) for both `paint_wall` and
  `paint_freehand`. A paint-discount or retaliation perk (Plan.md §7)
  has exactly one hook point.
- **Wall history cap (§3.5):** `MAX_WALL_HISTORY := 20` — repainting
  past the cap drops the oldest entries, so wall history (deep-copied
  on every quick_save) stays bounded. Smoke test paints past the cap
  and asserts.
- **Data validation (§3.6):** new `Scripts/Data/data_loader.gd` —
  shared `load_json` plus `require_fields`, replacing eight duplicated
  `_load_json` helpers. Every manager validates its `/Data` file's
  required fields at autoload; a typo'd entry now `push_error`s at
  boot instead of silently defaulting. Smoke test asserts shipped data
  validates clean.
- **Save migration hook (§3.7):** `SaveManager._migrate(data)` runs on
  every load — a documented seam for per-version upgrades when v2
  bumps `SAVE_VERSION`.

## 2026-06-11 — Freehand Spray Painting (Plan.md §10, §36 Could-Have)

First "Could-Have" feature from Plan.md §36, promoted from §10's
"Later Advanced System" list now that the Should-Have list is done.

- New `FreehandPanel` (`Scripts/UI/freehand_panel.gd`): pressing F at
  a paintable wall (once the Piece can is unlocked) opens a spray
  canvas sized to the wall face. Hold LMB to spray — speckled,
  falloff-weighted stamps that build to solid color on repeated
  passes — C cycles the fill palette, E/Enter commits, Esc bails.
  The painting model (image, coverage grid, colors-used set) lives
  apart from the UI nodes so the headless smoke test can drive it
  off-tree.
- `WallManager.paint_freehand`: commits the drawn image as a piece —
  piece paint cost, piece heat — with a style multiplier (Plan.md §11
  "Style multiplier", 0.5x–2x) computed from canvas coverage and the
  number of colors used: a lazy scribble pays half a stock piece, a
  multi-color burner pays double. Buff retaliation bonus still
  applies. The shared player-commit tail (history, ownership, rep,
  signal) is now one helper used by both paint paths, and the commit
  emits the same `wall_painted` signal, so rivals, heat, patrols,
  missions, territory, and SFX all react like any other piece.
- `PaintableWall` renders freehand work as the player's actual sprayed
  image on a wall-sized quad (alpha-transparent, unshaded), falling
  back to placeholder art if the stored image is bad. The image is
  stored as base64 PNG inside the wall state, so it survives quick
  save/load and scene re-entry with zero SaveManager changes.
- HUD: wall prompt advertises `[F] Freehand` once pieces are unlocked;
  opening the canvas releases the mouse and closes the other modals;
  the commit toast shows the style multiplier earned.
- Smoke test extended: sprays a two-color piece off-tree, checks the
  coverage/color counting, asserts the rep payout equals the plain
  piece value times the style multiplier, and round-trips the sprayed
  PNG through save/load.

## 2026-06-11 — Blackbook UI (Plan.md §23)

Fifth and final post-slice "Should-Have" system from Plan.md §36 — the
list is complete.

- New `BlackbookPanel` (`Scripts/UI/blackbook_panel.gd`): Tab now opens
  the writer's blackbook instead of the bare crew menu. Number keys
  flip four pages:
  - **Writer** — alias, rank/rep, cash/paint, heat, per-district
    influence summaries, and mission notes (current objective, or the
    epilogue once the chain is done).
  - **Styles** — every graffiti type with live (cap-discounted) paint
    cost and base rep, locked types marked, and the fill palette with
    the current color highlighted (locked until Lupe's mission).
  - **Crew** — the former crew menu content (alias, role, recruitment
    status) unchanged.
  - **The City** — known rival crews (leader, aggression, attitude,
    walls currently held) and your presence: walls carrying your name
    and how many the city has buffed.
- Page text builds purely from the autoload managers, so the headless
  smoke test reads all four pages without a HUD; live refreshes on
  crew events and quick-load.
- Smoke test extended: writer page shows alias/rank/territory, styles
  page lists types and the bought rare color, crew page shows Moth
  recruited, city page shows the Buff Kings, VEK, and wall presence.

## 2026-06-11 — Dialogue System (Plan.md §26)

Fourth post-slice "Should-Have" system from Plan.md §36.

- New `DialogueManager` autoload (`Scripts/Dialogue/dialogue_manager.gd`)
  running data-driven choice trees from `Data/dialogue.json`. Nodes
  carry speaker/text plus numbered choices that branch (`next`), run an
  action (`end` / `open_shop` / `start_delivery`), or gate behind
  requirement checks (Plan.md §26 "Dialogue Checks": `minRank`,
  `recruited`). Nodes can pay one-time effects via `once` flags.
- Speakers: Lupe's E-interaction now opens a conversation hub (catalog,
  delivery work, street gossip about the rival crews and cleanup);
  Darnell "Prime" (Plan.md §43, the old-head mentor) stands near the
  safehouse with lineage lore and a lesson that needs rank Known+ and
  pays +40 rep exactly once; Moth gets post-recruitment small talk
  (her blackbook story) while her recruitment stages stay with
  CrewManager.
- HUD: dialogue panel with speaker, wrapped text, and numbered choices
  (locked ones show their unlock hint); number keys choose, E/Esc
  walks away, walking out of range ends the chat. Dialogue, shop, crew,
  and map panels close each other.
- Save/load persists dialogue flags; an active conversation ends on
  load.
- Smoke test extended: Prime's rank gate locks/refuses at Toy and opens
  at Block King, the lesson pays exactly once, Lupe's tree routes into
  the shop and delivery systems, Moth chats once recruited, and flags
  survive the save/load round trip.

## 2026-06-11 — Supply Economy (Plan.md §21)

Third post-slice "Should-Have" system from Plan.md §36 ("supply
inventory").

- New `SupplyManager` autoload (`Scripts/Supplies/supply_manager.gd`)
  with a data-driven catalog in `Data/supplies.json`. `GameState` now
  tracks cash ($25 to start); mission payouts pay cash (m1 +$15,
  m4 +$15, m5 +$50 via the new `"cash"` mission effect).
- Lupe is the shop front (Plan.md §43): interacting with her outside a
  mission beat opens her catalog — number keys buy, E/Esc closes,
  walking off closes it too. Catalog: Paint Pack ($12, +10 paint,
  repeatable), Fat Cap ($25, throw-ups and pieces cost 1 less paint —
  §21 "caps modify spray behavior", never below 1), and Burner Chrome
  ($30, a rare fill color that joins the C-cycle palette).
- Delivery runs (Plan.md §15 "Supply Run"): Lupe hands out a package
  for a rotating drop spot (train yard gate, north alley, corner-block
  lot). Making the drop pays $25 and raises heat — handoffs get
  noticed. One package at a time; the drop shows as a glowing pad.
- HUD: cash readout in the stats panel, shop panel styled like the
  crew menu, wall prompts and the shop both show discounted paint
  costs. Purchase/delivery messages, denied blip when broke.
- Save/load persists cash, owned upgrades, extra palette colors, and
  the in-flight delivery (the drop zone respawns on load).
- Smoke test extended: mission-chain cash totals, paint-pack purchase,
  fat-cap discounts (piece 6→5, tag stays 1), one-time-purchase and
  insufficient-cash rejections, rare-color palette growth, discounted
  cost actually spent on painting, delivery round trip (+$25, +heat),
  and a supplies save/load round trip.

## 2026-06-11 — Security Patrols (Plan.md §12, §18, §25)

Second post-slice "Should-Have" system from Plan.md §36.

- New `PatrolManager` autoload (`Scripts/Patrols/patrol_manager.gd`)
  and `PatrolGuard` NPC (`Scripts/Patrols/patrol_guard.gd`). Guards
  walk fixed ping-pong routes from `Data/patrols.json` (street sweep,
  north alley, bodega side) with a flashlight showing their facing.
- More heat, more patrols (Plan.md §12): the live guard count follows
  the heat level (Cold/Low 1, Watched 2, Hot/Blazing 3), spawning onto
  routes round-robin and thinning out idle guards as the block cools.
- Spotted (Plan.md §25): a guard in range, facing you, with clear line
  of sight when your paint lands spikes heat (+12) and gives chase.
  Chase speed (6.2) sits between walk and run, so sprinting away works;
  guards give up past 18 m or after 9 seconds.
- Caught: -25 rep, -3 paint confiscated, and heat settles to 25 — the
  incident is closed (`HeatManager.settle`). Since patrols introduce
  the first rep *loss*, rank changes are now direction-aware: the HUD
  says "RANK LOST" and the Sfx sting only rises on actual rank-ups.
- Lookout synergy (Plan.md §14): with Moth recruited, painting with a
  patrol inside 12 m (but unseen) gets her "five-oh close by" callout,
  on a 10-second cooldown.
- HUD shows patrol events (spotted / caught / lost them / patrol level
  changes); a whistle SFX plays when spotted; guards appear as orange
  dots on the district map.
- Smoke test extended: guard count tracks the heat level up (Blazing →
  3) and back down, the lookout warning fires, a sighted paint queues a
  chase with a heat spike, and a deterministic `resolve_catch` docks
  exactly 25 rep / 3 paint and settles heat with patrols thinning out.

## 2026-06-11 — Heat System + City Cleanup (Plan.md §12, §18, §33)

First post-slice "Should-Have" system from Plan.md §36.

- New `HeatManager` autoload (`Scripts/Heat/heat_manager.gd`). Painting
  builds heat — each style has a `heatValue` in
  `Data/graffiti_styles.json` (tag 4 / throw-up 7 / piece 12), scaled
  by wall risk, so landmark and high-risk work draws the most
  attention. Heat decays 2/tick when the player lays low (same
  12-second "in-game hour" tick as RivalManager).
- Risk pays (Plan.md §12): reputation is now multiplied by
  `1 + heat/200` (up to 1.5×), folded into the §11 formula in
  `WallManager._reputation_for`.
- City Cleanup faction (Plan.md §18/§33): every 6 ticks (a compressed
  "in-game day") cleanup rolls each painted wall against its new
  per-wall `cleanupChance` in `Data/walls.json` — inflated by heat for
  player-owned walls — and buffs at most one wall per sweep. Buffed
  walls show mismatched gray roller patches, move their graffiti into
  wall history (`isBuffed: true`), and count as "City" pressure in
  district influence and on the map (warm-gray on the map, "City" in
  the legend).
- Cleanup retaliation (Plan.md §15): repainting a buffed wall pays a
  1.25× rep bonus.
- HUD: heat readout in the stats panel (color escalates Cold → Low →
  Watched → Hot → Blazing), heat-level change banners, and cleanup
  notifications. New roller-swipe SFX when a wall gets buffed.
- Save/load now persists heat and the cleanup countdown; buffed wall
  states already round-trip through WallManager.
- Smoke test extended: heat accrues from the mission-chain painting,
  rep multiplier > 1, deterministic `force_cleanup` buffs a wall
  (state/owner/history/territory asserts), repaint pays the exact
  retaliation bonus, heat decays on tick, and heat survives the save/
  load round trip. 3 consecutive clean headless runs plus a windowed
  120-frame boot with no errors.

## 2026-06-11 — Milestone 8: Polish Pass (Plan.md §35) — vertical slice complete

- Sound effects: new `Sfx` autoload (`Scripts/Audio/sfx.gd`) synthesizes
  placeholder PCM sounds at startup (Plan.md §28/§49, no audio assets):
  spray hiss when the player paints, denied blip on failed paints,
  rising stings for rank-ups and block claims, a descending buzz for
  rival events, and UI blips for crew/save events. Disabled under the
  headless driver (it never mixes, so playbacks would be reported as
  leaks at exit).
- Lighting pass: dusk scene to match the night-time opening (Plan.md
  §40) — low warm sun + cool moon fill, dusk procedural sky, filmic
  tonemap, glow, distance fog, and four emissive street lamps with warm
  omni lights along the street.
- Wall art pass: each graffiti gets a deterministic tilt and paint
  drips below the letters; throw-ups get a halo panel, pieces get a
  bordered background panel; cross-outs now include a strike bar
  through the work. All graffiti materials are unshaded so the art
  pops at dusk.
- UI pass: stats, mission, and wall-prompt readouts now sit in styled
  accent-bordered panels; prompt/mission panels hide when empty; gold
  rank text; paint counter turns red with a LOW warning under 5; a dim
  controls-hint line sits bottom-right; crew menu shares the panel
  style.
- Bug fix: quick-loading no longer fires a spurious "RANK UP"
  banner/sting — `GameState.load_state` only emits `rank_changed` when
  the rank actually differs.
- Verified: headless smoke test passing (3 consecutive clean runs, no
  leaked instances, no script errors) and a windowed 120-frame boot
  with the new lighting renders without errors.

## 2026-06-11 — Save/Load Slice

- Added `SaveManager` autoload (`Scripts/SaveSystem/save_manager.gd`).
  F5 quick-saves to `user://toy_to_legend_save.json`; F9 quick-loads.
- Save files persist player position, GameState progression
  (rep/rank/paint/unlocks/colors), WallManager state
  (ownership/current graffiti/history/cross-outs), CrewManager
  recruitment stages, TerritoryManager claimed districts, and
  MissionManager progress.
- Wall visuals now refresh from loaded state, including cleared walls,
  restored graffiti, and restored "TOY" cross-outs.
- HUD shows save/load feedback messages and README controls now include
  F5/F9.
- Smoke test extended with a disk round trip: save, mutate wall/player/
  progression state, load, and assert the saved state is restored.
  Passing.

## 2026-06-11 — Milestone 7: Vertical Slice Mission Chain (Plan.md §35)

- `MissionManager` is now autoloaded and active in the main scene,
  spawning mission actors from `Data/missions.json` and starting the
  five-mission vertical slice from Plan.md §16.
- HUD now shows the current mission and objective, plus mission event
  banners for starts, completions, NPC lines, and prototype completion.
- Mission progression is wired into existing systems: wall painting,
  safehouse/reach zones, Lupe, color selection, Moth recruitment,
  territory claiming, and the scripted defend-your-wall beat.
- Added progression locks/unlocks in `GameState`: tags start unlocked,
  throw-ups unlock after the first cross-out, pieces and fill-color
  cycling unlock after Lupe. C cycles fill color once colors are
  unlocked.
- Player focus now supports mission actors with prompt/interact
  methods, and `CrewManager` emits exact recruitment stage changes for
  mission objectives.
- Smoke test extended through the full vertical slice mission chain;
  passing.

## 2026-06-10 — Milestone 6: Territory System (Plan.md §35)

- New `TerritoryManager` autoload (`Scripts/Territory/territory_manager.gd`)
  loading `Data/districts.json`. District influence (Plan.md §24): each
  wall's visibility is weight credited to its current owner; blank
  walls stay unclaimed (you must actually cover the block) and
  crossed-out work counts half (disrespect costs you).
- Threshold reward: reaching the district's `claimThreshold` (Mill
  Yard: 50% player share) fires once — +150 rep and a "BLOCK CLAIMED"
  HUD banner.
- District map on M (`Scripts/UI/map_panel.gd`): walls drawn top-down
  with length = wall width, thickness = visibility, color = owner
  (green you, crew fill colors, gray open, red X over crossed-out
  work), plus crew NPC locations, live player marker, and an influence
  summary footer. Map and crew menu close each other.
- `WallManager` now emits `wall_crossed_out` so cross-outs update
  territory immediately, not just repaints.
- Smoke test extended: influence reflects ownership after the
  Milestone 4/5 steps, then painting the landmark + bodega + median
  pushes the player past 50%, claims Mill Yard exactly once, and
  grants the bonus. Passing.

## 2026-06-10 — Milestone 5: Crew Recruitment (Plan.md §35)

- New `CrewManager` autoload (`Scripts/Crew/crew_manager.gd`) loading
  `Data/npc_data.json`; recruitment runs as a stage machine:
  not_met → mission_active → item_recovered → recruited.
- Mina "Moth" (Plan.md §14) stands near the corner store. Talking to
  her starts her mission: recover her stolen blackbook from the north
  alley (Ghost Line turf), bring it back, and she joins as Lookout.
- `Npc` and `PickupItem` placeholder nodes (capsule / box with
  floating labels); the player's interaction ray now focuses walls,
  NPCs, and pickups, with E doing the right thing for each.
- Lookout role bonus: rival response chance ×0.6 while Moth is
  recruited, and she calls out a warning the moment a crew queues a
  retaliation against a player wall.
- Crew menu on Tab: lists every known writer with alias, role, and
  current status (hint / mission / recruited bonus).
- Smoke test extended: full recruitment chain, response-chance
  reduction (0.95 → 0.57), and lookout warning emission. Passing.

## 2026-06-10 — Milestone 4: Rival Crew Reactions (Plan.md §35)

- 3 rival crews in `Data/crews.json` (Plan.md §13): The Buff Kings,
  Ghost Line, Chrome Saints — each with leader alias, tag, colors,
  aggression, response graffiti type, and home territory walls.
- New `RivalManager` autoload (`Scripts/Rivals/rival_manager.gd`):
  crews claim their territory walls at session start, and painting in
  crew territory (or over crew work) queues a retaliation resolved on
  a 12-second simulation tick (one "in-game hour", Plan.md §33), with
  chance driven by crew aggression + per-wall `rivalResponseChance`.
- "TOY" mechanic (Plan.md §13): weak work (tags, or any work while
  ranked Toy/Rookie) gets an angled "TOY" cross-out; stronger work
  gets covered by the crew's own graffiti.
- WallManager: `apply_rival_graffiti`, `cross_out_wall`, `wall_def`
  lookup; cross-out state persists and restores on scene re-entry;
  repainting clears the cross-out and reclaims the wall.
- HUD: rival event notifications (5 s) and live prompt refresh when a
  wall's owner changes; relationshipToPlayer drops when offended.
- Smoke test extended: initial rival claim → player paints over it →
  retaliation queued → forced "TOY" response → player reclaims with a
  throw-up. Passing.

## 2026-06-10 — First Agent Task (Plan.md §47)

- Created Godot 4.6 project (engine choice per Plan.md §29).
- Graybox Mill Yard district: ground, 4 placeholder buildings, street +
  two alleys, sun + sky environment (`Scripts/district.gd`).
- 10 paintable walls defined in `Data/walls.json` (including a landmark
  wall, alley walls, and a freestanding median), spawned data-driven by
  the `WallManager` autoload.
- 3 graffiti types (tag / throw-up / piece) defined in
  `Data/graffiti_styles.json` with base rep value and paint cost.
- Third-person player controller with spring-arm camera, runtime-built
  input map, and raycast wall focusing.
- Graffiti placement: E paints the focused wall with the selected type;
  placeholder Label3D decal scaled/colored per type, backdrop quad for
  pieces.
- Reputation system: rep = base × visibility × risk multipliers; rank
  thresholds Toy → Rookie → Up → Known → Block King.
- Paint supply: starts at 20, costs 1/3/6 per type; painting blocked when
  out of paint.
- In-memory wall state: owner, state string, current graffiti, and full
  graffiti history per wall; restored visually on scene re-entry.
- HUD: rank/rep/paint/type, wall prompt with owner/risk/visibility,
  feedback + rank-up messages.
- Test scene `Scenes/Test_GraffitiWall.tscn` (agent rule 9).
- Headless smoke test (`SMOKE_TEST=1`) verifying spawn, paint, state,
  rep, and paint-cost — passing.
