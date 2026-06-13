# Changelog

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
