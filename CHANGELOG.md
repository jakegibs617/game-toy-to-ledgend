# Changelog

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
