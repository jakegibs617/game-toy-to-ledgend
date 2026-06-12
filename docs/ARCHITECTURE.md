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
so `project.godot` stays minimal.

`district.gd` also contains the smoke test (`SMOKE_TEST=1` env var):
a long assert-driven script that drives every system headlessly and
quits. Every milestone extends it.

## Autoloads (in load order)

| Autoload | File | Owns |
|---|---|---|
| GameState | Scripts/Data/game_state.gd | Alias, rep, rank, paint, cash, selected type, unlocked types, fill palette, input map |
| WallManager | Scripts/Walls/wall_manager.gd | Wall defs/styles JSON, wall spawning, **wall_states** (the world's memory), player/rival/buff paint paths, rep formula |
| RivalManager | Scripts/Rivals/rival_manager.gd | Rival crews, initial territory, retaliation queue, cross-outs |
| CrewManager | Scripts/Crew/crew_manager.gd | NPC spawning, recruitment stages, crew roles (lookout bonus) |
| TerritoryManager | Scripts/Territory/territory_manager.gd | Per-district influence shares, claim threshold/bonus |
| HeatManager | Scripts/Heat/heat_manager.gd | Heat value/levels, rep multiplier, decay tick, city cleanup (buffing) |
| MissionManager | Scripts/Missions/mission_manager.gd | Mission chain from Data/missions.json, world actors/zones, `notify_actor` |
| PatrolManager | Scripts/Patrols/patrol_manager.gd | Heat-scaled guard spawning, witness checks, chase/catch |
| SupplyManager | Scripts/Supplies/supply_manager.gd | Lupe's shop catalog, owned upgrades (fat cap), paint_cost discounts, delivery runs |
| DialogueManager | Scripts/Dialogue/dialogue_manager.gd | Choice trees from Data/dialogue.json, rank/recruit checks, one-time flags |
| SaveManager | Scripts/SaveSystem/save_manager.gd | quick_save/quick_load to `user://toy_to_legend_save.json`, `SAVE_VERSION` |
| Sfx | Scripts/Audio/sfx.gd | Synthesized placeholder sounds; **must load after the managers** (connects to their signals); self-disables headless |

Non-autoload actors: `Player` (Scripts/Player/player.gd, builds its own
camera rig/raycast), `PaintableWall` (Scripts/Walls/paintable_wall.gd,
renders graffiti/cross-outs/buffs), `PatrolGuard`, `Npc`, `PickupItem`,
and the UI panels under Scripts/UI/.

## The signal hub: `WallManager.wall_painted`

Every paint — player tag/throw-up/piece, freehand commit, rival
repaint — flows through WallManager and emits
`wall_painted(wall_id, graffiti)`. Consumers:

* **HeatManager** — adds the style's `heatValue`
* **RivalManager** — rolls/queues retaliation in crew territory
* **MissionManager** — advances paint/defend objectives
* **PatrolManager** — line-of-sight witness check → spotted/chase
* **TerritoryManager** — recomputes influence, fires district_claimed
* **Sfx** — spray hiss for player paints

**Rule: never paint a wall by mutating wall_states directly** — go
through `paint_wall` / `paint_freehand` / `apply_rival_graffiti` /
`buff_wall` so the whole game reacts.

Other cross-system signals follow the same pattern: managers emit,
HUD and Sfx listen. The HUD never owns game state.

## Wall state (the world's memory, Plan.md §9)

`WallManager.wall_states[wall_id]`:

```
{
  ownerCrewId: "player" | "city" | "none" | <crewId>,
  state: "blank" | "player_<type>" | "rival_<type>" | "crossed_out" | "buffed",
  currentGraffiti: <graffiti dict> | null,
  history: [<graffiti dicts, image field stripped>],   # capped growth: see _archive_current
  crossOut: {by, text, color}                          # only while crossed out
}
```

Graffiti dict: `graffitiId, creatorId, crewId, wallId, type, alias,
fillColor, outlineColor, repValue, isCrossedOut, isBuffed`, plus for
freehand pieces: `freehand: true, image: <base64 PNG>, styleMultiplier`.
Everything is JSON-serializable on purpose — save/load round-trips
`wall_states` wholesale.

Rep formula (`_reputation_for`): base × visibility mult × risk mult ×
heat mult (× freehand style mult × buff retaliation bonus).

## Data files (`/Data`, all JSON — Plan.md agent rule 3)

| File | Shape | Consumed by |
|---|---|---|
| walls.json | array of wall defs (wallId, name, position, rotationY, size, color, risk, visibility, districtId, ownerCrewId) | WallManager |
| graffiti_styles.json | dict type → {label, baseValue, paintCost, heatValue, colors} | WallManager, SupplyManager, HUD |
| crews.json | rival crew defs (tag, colors, aggression, home walls) | RivalManager |
| districts.json | array (districtId, name, claimThreshold, claimRepBonus) | TerritoryManager |
| missions.json | {actors: [...], missions: [...]} | MissionManager |
| dialogue.json | speaker → node tree | DialogueManager |
| supplies.json | shop catalog + delivery def | SupplyManager |
| patrols.json | guard counts per heat level, speeds | PatrolManager |
| npc_data.json | recruitable NPCs (Moth) | CrewManager |

## UI layer

`Hud` (CanvasLayer, Scripts/UI/hud.gd) builds all panels in code:
stats, mission tracker, prompt, message toasts, and the modals —
shop, dialogue, blackbook (`blackbook_panel.gd`), map
(`map_panel.gd`), freehand canvas (`freehand_panel.gd`).

Modal conventions:
* `MODAL_SLOT_ACTIONS` = the number keys 1–4, reused by every modal
  for slot selection in display order.
* HUD's `_unhandled_input` consumes modal input **before** Player sees
  it (HUD is added to the tree after Player, so it handles unhandled
  input first). Each open modal closes the others. (Plan_v2.md §3.1
  proposes replacing this choreography with a modal stack.)
* Modals that need testing headless keep their model separate from UI
  nodes (see freehand_panel: `begin`/`spray_at`/`result` work off-tree).

## Save format

`user://toy_to_legend_save.json`, written by SaveManager with
`version: SAVE_VERSION`. Sections per system: player transform,
GameState fields, WallManager (wall_states + next id), crew stages,
territory claims, heat, mission progress, supplies owned, dialogue
flags. Loading refuses saves newer than SAVE_VERSION. **Bump
SAVE_VERSION whenever a section's shape changes.**

## Testing

* Smoke test: `SMOKE_TEST=1 godot --headless --path .` — asserts the
  full system chain, prints `SMOKE: OK` and quits 0. Run 3× before a
  PR (RNG paths), plus one windowed boot: `godot --path . --quit-after 300`.
* `Scenes/Test_GraffitiWall.tscn` — single-wall sandbox (agent rule 9).
* Every milestone adds assertions for its system; keep new checks
  self-contained about the state they assume (see Plan_v2.md §3.3).
