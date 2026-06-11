# Changelog

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
