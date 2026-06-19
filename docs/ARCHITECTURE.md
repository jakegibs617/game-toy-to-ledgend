# Architecture Reference

How Toy to Legend's code is actually organized, for anyone (human or
agent) starting a work session. Design rationale lives in Plan.md
(§N references); current feature list lives in README.md.

## Boot flow

`project.godot` autoloads the managers (order matters — see below),
then opens `Scenes/PrototypeDistrict.tscn`, whose only node runs
`Scripts/district.gd`. Everything else — ground, buildings, lights,
walls, player, NPCs, patrols, HUD — is **built at runtime in code**.
There is no .tscn wiring to edit; scenes are one-node shells. The
input map is also registered at runtime (`GameState._setup_input_actions`)
so `project.godot` stays minimal. Milestone 23 registers controller
bindings there too; `Player` reads the right stick for camera look and
d-pad left/right can cycling.

Generated district details use `district.gd`'s small material cache
for repeated solid/noisy looks (Milestone 24), so new street detail
does not create a unique `StandardMaterial3D` for every repeated quad.
Rooftop Row (Milestone 26) is also generated here as an elevated third
district; it has no `districts.json.travel` gate, so `ClimbZone`
`targetDistrictId` transitions are the unlock path.

`district.gd` also contains the smoke test (`SMOKE_TEST=1` env var):
per-system `_smoke_*()` functions (Plan_v2.md §3.3), each documenting
the world state it assumes, run in sequence by `_run_smoke_test` —
they drive every system headlessly and quit. Every milestone adds or
extends a section.

## Autoloads (in load order)

| Autoload | File | Owns |
|---|---|---|
| GameState | Scripts/Data/game_state.gd | Alias selection, rep, rank, paint, cash, selected type, unlocked types, fill palette, current district, safehouse rest count, input map |
| WallManager | Scripts/Walls/wall_manager.gd | Wall defs/styles JSON, wall spawning, **wall_states** (the world's memory), player/rival/buff paint paths, rep formula |
| RivalManager | Scripts/Rivals/rival_manager.gd | Rival crews, initial territory, retaliation queue, cross-outs |
| CrewManager | Scripts/Crew/crew_manager.gd | NPC spawning, recruitment stages, crew roles, loyalty-scaled role bonuses, crew save state |
| TerritoryManager | Scripts/Territory/territory_manager.gd | Per-district influence shares, claim threshold/bonus |
| HeatManager | Scripts/Heat/heat_manager.gd | Per-district heat (`heat` reads the player's block), levels, rep multiplier, decay tick (absent blocks cool 2×), city cleanup (buffing) |
| MissionManager | Scripts/Missions/mission_manager.gd | Mission **chains** from Data/missions.json (triggered in order, e.g. enter_district), world actors/zones, `notify_actor` |
| PatrolManager | Scripts/Patrols/patrol_manager.gd | Heat-scaled guard spawning, witness checks, chase/catch |
| SupplyManager | Scripts/Supplies/supply_manager.gd | Lupe's shop catalog, owned upgrades (fat cap), paint_cost discounts, delivery runs |
| DialogueManager | Scripts/Dialogue/dialogue_manager.gd | Choice trees from Data/dialogue.json, rank/recruit checks, one-time flags |
| StatsManager | Scripts/Stats/stats_manager.gd | Style/Stealth/Hustle XP+levels (raise by doing), perk points/trees, the multipliers other managers query (rep, heat, spot range, prices, delivery pay, rival damp, payout/decay) |
| TrainManager | Scripts/Trains/train_manager.gd | Scheduled train cars, train-side painting, pass-through rep ticks, train service log |
| GalleryManager | Scripts/Gallery/gallery_manager.gd | Gallery commissions (rank-gated), freehand judging (style multiplier = score), cash/public-rep payouts, crew-rep cost, sales log |
| SaveManager | Scripts/SaveSystem/save_manager.gd | quick_save/quick_load to `user://toy_to_legend_save.json`, `SAVE_VERSION`, per-version `_migrate` |
| Sfx | Scripts/Audio/sfx.gd | Synthesized placeholder sounds, music bed, per-district ambience; **must load after the managers** (connects to their signals); self-disables headless |

Non-autoload actors: `Player` (Scripts/Player/player.gd, builds its own
camera rig/raycast and runtime rooster animation state table),
`PaintableWall` (Scripts/Walls/paintable_wall.gd, renders
graffiti/cross-outs/buffs; rival work uses deterministic render-time
variants from `Scripts/Walls/rival_graffiti_style.gd`), `PatrolGuard`, `Npc`, `AmbientNpc`,
`PickupItem`, and the UI panels under Scripts/UI/.

Player animation clips live as separate skinned GLB scenes in
`Assets/Characters/`. `Player._try_build_animated_visual` loads each
available action into a `CharacterModel` container and records:
state name → model node, animation player, animation name. Movement
selects idle/walk/backpedal/run/jump; idle plays as a slow breathing
loop instead of a frozen pose. World interactions can request
short contextual clips via `Player.play_context_animation` (the
deterministic `ClimbZone.resolve` and guards still play `"climb"` this
way). Ladder climbs instead use `Player.begin_climb(entry, exit, zone)`:
the player rides the entry→exit line by hand (forward/back, reversible),
the `"climb"` clip runs continuously with its speed driven by climb
direction, and reaching the exit calls back to `ClimbZone.complete_climb`.
Add future actions by importing a GLB, registering
its path + animation name in `player.gd`, and triggering the state from
the gameplay event rather than hard-coding animation logic into the
world object.

`Player._nearest_interactable` is a fallback for nearby group-based
interactables when the camera ray is not directly on one; Milestone 24
adds a ray occlusion check so that fallback cannot grab items through
walls.

Recruitable NPCs and mission actors use the same
`AnimatedModelSet.build_from_manifest` helper, but their paths and clip
names live in JSON `visuals` blocks (`npc_data.json` members and
`missions.json` actors). A `visuals` block has sourceHeight,
rotationY, initialState, and `states` mapping state → {model, clip};
missing imports fall back to the capsule visuals.

Ambient locals are loaded from `Data/ambient_npcs.json` by
`district.gd`. They use the same `visuals` manifest shape, walk small
waypoint loops, react to nearby fresh player walls, and scatter only
when heat spikes in their own district.

## The signal hub: `WallManager.wall_painted`

Every paint — player tag/throw-up/piece, freehand commit, rival
repaint, crew assist — flows through WallManager and emits
`wall_painted(wall_id, graffiti)`. Consumers:

* **HeatManager** — adds the style's `heatValue`
* **RivalManager** — rolls/queues retaliation in crew territory
* **MissionManager** — advances paint/defend objectives
* **PatrolManager** — line-of-sight witness check → spotted/chase
* **TerritoryManager** — recomputes influence, fires district_claimed
* **AmbientNpc** — pauses for nearby player work and pays the one-time
  crowd-reaction rep tick
* **Sfx** — spray hiss for player paints

**Rule: never paint a wall by mutating wall_states directly** — go
through `paint_wall` / `paint_freehand` / `apply_rival_graffiti` /
`apply_crew_graffiti` / `buff_wall` so the whole game reacts.

Other cross-system signals follow the same pattern: managers emit,
HUD and Sfx listen. The HUD never owns game state.

## Wall state (the world's memory, Plan.md §9)

`WallManager.wall_states[wall_id]`:

```
{
  ownerCrewId: "player" | "city" | "none" | <crewId>,
  state: "blank" | "player_<type>" | "rival_<type>" | "crossed_out" | "buffed",
  currentGraffiti: <graffiti dict> | null,
  history: [<graffiti dicts, image field stripped>],   # capped at MAX_WALL_HISTORY (20), oldest dropped
  crossOut: {by, text, color}                          # only while crossed out
}
```

Graffiti dict: `graffitiId, creatorId, crewId, wallId, type, alias,
fillColor, outlineColor, repValue, isCrossedOut, isBuffed`, plus for
freehand pieces: `freehand: true, image: <base64 PNG>, styleMultiplier`.
Rival visual variety is recomputed from `graffitiId + crewId + type`
instead of stored as an image. Everything is JSON-serializable on
purpose — save/load round-trips `wall_states` wholesale.

Rep formula (`_reputation_for`): base × visibility mult × risk mult ×
heat mult (× freehand style mult × buff retaliation bonus).

## Data files (`/Data`, all JSON — Plan.md agent rule 3)

Every manager loads through `Scripts/Data/data_loader.gd`
(`load_json` + `require_fields`, Plan_v2.md §3.6): missing required
fields `push_error` at startup, and the smoke test asserts
`DataLoader.error_count == 0` — shipped data must validate clean.

| File | Shape | Consumed by |
|---|---|---|
| walls.json | array of wall defs (wallId, name, position, rotationY, size, color, risk, visibility, districtId, surfaceType, ownerCrewId) | WallManager |
| graffiti_styles.json | dict type → {label, baseValue, paintCost, heatValue, colors; optional: surfaces[] (surface rule), requiresCrew, exposure (patrol witness range ×), notes/lockedHint (blackbook)} | WallManager, SupplyManager, PatrolManager, HUD |
| crews.json | rival crew defs (tag, colors, aggression, home walls) | RivalManager |
| districts.json | array (districtId, name, claimThreshold, claimRepBonus, payoutPerWeight, decayRep, arrival, optional travel) | TerritoryManager, district.gd (travel points) |
| missions.json | {actors: [...], chains: [{chainId, trigger?, completeMessage, missions: [...]}]}; actors may include `visuals` manifests | MissionManager |
| ambient_npcs.json | ambient locals (npcId, label, districtId, waypoints, reactRange, optional `visuals`) | district.gd (spawns AmbientNpc) |
| dialogue.json | speaker → node tree | DialogueManager |
| supplies.json | shop catalog + delivery def (items may carry unlockType) | SupplyManager |
| patrols.json | guard counts per heat level, speeds | PatrolManager |
| npc_data.json | recruitable NPCs (Moth, Caps, Metro, Stash, Echo, Fix, Clash), item pickups, loyalty starts, role metadata, optional `visuals` manifests | CrewManager |
| stats.json | stat defs (xpPerLevel, maxLevel, per-level effect coefficients) | StatsManager |
| perks.json | tree → perk list (perkId, name, desc, effects dict) | StatsManager |
| climbs.json | climb routes (climbId, label, position, top, fallChance, fallRepPenalty, optional targetDistrictId) | district.gd (spawns ClimbZone) |
| trains.json | scheduled cars (trainId, label, districtId, yardPosition, size, stop/travel ticks, paint/pass rep, heat, serviceDistricts; Ghost Local services all three districts) | TrainManager, district.gd (spawns TrainCar) |
| gallery.json | gallery config (contactName, minRank, canvasLabel, canvasSize, basePay, repBase, crewRepCost, acceptScore) | GalleryManager |

## UI layer

`Hud` (CanvasLayer, Scripts/UI/hud.gd) builds all panels in code:
stats, mission tracker, prompt, message toasts, and the modals —
alias/title, shop, dialogue, blackbook (`blackbook_panel.gd`), map
(`map_panel.gd`), freehand canvas (`freehand_panel.gd`).

Modal conventions:
* `MODAL_SLOT_ACTIONS` = the number keys 1–6 (`slot_1..slot_6`),
  reused by every modal for slot selection in display order; with no
  modal open the same keys select cans in canonical style order
  (`GameState.select_type_slot`).
* HUD's `_unhandled_input` consumes modal input **before** Player sees
  it (HUD is added to the tree after Player, so it handles unhandled
  input first).
* **Alias/title modal** (Milestone 23): new games start with
  `GameState.alias_chosen == false`; HUD opens the alias modal before
  world input, `GameState.choose_alias` stores the name, and
  `MissionManager.notify_alias_chosen` advances the first mission.
* **Modal registry** (Plan_v2.md §3.1): `Hud._register_modals` lists
  every modal — alias, freehand, dialogue, shop, blackbook, map — in input
  priority order with `is_open`/`close`/`input` callables. The first
  open modal owns input; every opener routes through
  `close_modals(except)` so two modals can never stay open together.
  A new modal = one registry entry (plus an `open` callable if the
  HUD opens it directly, like blackbook/map).
* Shared label/panel builders live in `Scripts/UI/ui_kit.gd` (static
  funcs, preloaded — see the class-cache rule in CLAUDE.md).
* Modals that need testing headless keep their model separate from UI
  nodes (see freehand_panel: `begin`/`spray_at`/`result` work off-tree).

## Save format

`user://toy_to_legend_save.json`, written by SaveManager with
`version: SAVE_VERSION`. Sections per system: player transform,
GameState fields (including crew_rep — the §11 public/crew split),
WallManager (wall_states + next id), crew stages/loyalty, territory claims,
heat, mission progress, supplies owned, dialogue flags, stats/perks,
train service state, the gallery sales log, and crew getaway route
usage. Loading refuses saves newer than SAVE_VERSION. **Bump
SAVE_VERSION whenever a section's shape changes.**

## Testing

* Smoke test: `SMOKE_TEST=1 godot --headless --path .` — asserts the
  full system chain, prints `SMOKE: OK` and quits 0. Run 3× before a
  PR (RNG paths), plus one windowed boot: `godot --path . --quit-after 300`.
* `Scenes/Test_GraffitiWall.tscn` — single-wall sandbox (agent rule 9).
* Every milestone adds assertions for its system; keep new checks
  self-contained about the state they assume (see Plan_v2.md §3.3).
