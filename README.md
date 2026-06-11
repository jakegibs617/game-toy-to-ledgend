# Toy to Legend — Prototype

Open-world graffiti RPG prototype. Full design in [Plan.md](Plan.md).

Engine: **Godot 4.6** (chosen per Plan.md §29 — open source, text-based scenes/scripts, headless CLI testing).

## Running

Open the project in Godot 4.6+ and press Play, or from the terminal:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

Scenes:

- `Scenes/PrototypeDistrict.tscn` — main scene: graybox Mill Yard district.
- `Scenes/Test_GraffitiWall.tscn` — single test wall in an empty room (Plan.md agent rule 9).

Headless smoke test (paints a wall in code and asserts state/rep/paint):

```sh
SMOKE_TEST=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path .
```

## Controls

| Input | Action |
|---|---|
| WASD | Move |
| Mouse | Look |
| Shift | Run |
| Space | Jump |
| E | Paint focused wall / talk / pick up |
| 1 / 2 / 3 | Select Tag / Throw-up / Piece |
| C | Cycle fill color after Lupe unlocks colors |
| F5 | Quick save |
| F9 | Quick load |
| Tab | Crew menu |
| M | District map |
| Esc | Toggle mouse capture |

Walk up to a wall panel (the lighter slabs on building faces) until the
prompt appears at the bottom of the screen, then press E.

## Systems implemented (First Agent Task, Plan.md §47)

- **GameState** (autoload, `Scripts/Data/game_state.gd`) — alias, reputation,
  rank progression (Toy → Block King), paint supply, selected graffiti type.
  Also registers the input map at runtime.
- **WallManager** (autoload, `Scripts/Walls/wall_manager.gd`) — loads
  `Data/walls.json` and `Data/graffiti_styles.json`, spawns walls, applies
  graffiti, computes reputation (base × visibility × risk multipliers,
  Plan.md §11), and keeps every wall's state + graffiti history in memory.
  Wall state survives scene reloads within a session.
- **PaintableWall** (`Scripts/Walls/paintable_wall.gd`) — data-driven wall
  body; placeholder graffiti rendered as Label3D "decals" (alias text styled
  per graffiti type) with a per-graffiti tilt, paint drips, fill panels for
  throw-ups/pieces, and a strike bar on cross-outs (Milestone 8 art pass).
- **Player** (`Scripts/Player/player.gd`) — third-person controller with
  spring-arm camera and raycast wall focusing.
- **HUD** (`Scripts/UI/hud.gd`) — styled stat/mission/prompt panels,
  feedback messages, rank-up notice, rival event notifications, a
  low-paint warning, and a controls hint (Milestone 8 UI pass).
- **Sfx** (autoload, `Scripts/Audio/sfx.gd`, Milestone 8) — placeholder
  sound effects synthesized at startup (no audio assets): spray hiss on
  painting, denied blip, rank-up/block-claim stings, rival buzz, and UI
  blips for crew/save events.
- **RivalManager** (autoload, `Scripts/Rivals/rival_manager.gd`,
  Milestone 4) — loads `Data/crews.json` (The Buff Kings, Ghost Line,
  Chrome Saints). Crews claim their home walls at session start. When
  the player paints in crew territory or over crew work, a retaliation
  is queued and resolved on a 12-second simulation tick (Plan.md §33):
  tags or low-rank work get **"TOY"** crossed out, stronger work gets
  covered by the crew's own graffiti. Repainting reclaims the wall.
- **CrewManager** (autoload, `Scripts/Crew/crew_manager.gd`,
  Milestone 5) — loads `Data/npc_data.json`. Mina "Moth" waits near
  the corner store; recover her blackbook from the north alley and she
  joins as your Lookout (Plan.md §14): rivals back off more often
  (response chance ×0.6) and she warns you when a crew is about to hit
  one of your walls. Tab opens the crew menu.
- **TerritoryManager** (autoload, `Scripts/Territory/territory_manager.gd`,
  Milestone 6) — loads `Data/districts.json` and scores district
  influence (Plan.md §24): every wall contributes its visibility as
  weight toward its current owner; blank walls stay unclaimed and
  crossed-out work counts half. Reaching the district's claim
  threshold (Mill Yard: 50%) once grants a one-time rep bonus and a
  "BLOCK CLAIMED" notification.
- **MapPanel** (`Scripts/UI/map_panel.gd`, Milestone 6) — M opens the
  district map: walls drawn top-down (length = wall width, thickness =
  visibility, color = owner: green you, crew fill colors, gray open,
  red X = crossed out), crew NPC locations, the player marker, and an
  influence summary footer.
- **HeatManager** (autoload, `Scripts/Heat/heat_manager.gd`) — heat
  system + City Cleanup faction (Plan.md §12, §18, §33). Painting
  builds heat (style `heatValue` × wall risk); heat raises rep payouts
  for risky work (×1 to ×1.5) but speeds up cleanup sweeps that buff
  painted walls back to gray (per-wall `cleanupChance`, one wall max
  per sweep). Buffed walls show roller patches, count as "City"
  pressure in territory influence, and repainting one pays a 1.25×
  cleanup-retaliation bonus. Heat decays while laying low. The HUD
  heat readout escalates Cold → Low → Watched → Hot → Blazing.
- **MissionManager** (`Scripts/Missions/mission_manager.gd`,
  Milestone 7) — loads `Data/missions.json` and runs the five-mission
  vertical slice from Plan.md §16: First Mark, Don't Be a Toy, Get
  Supplies, Find a Lookout, and Claim the Block. Mission-only actors
  include the safehouse zone and Lupe; HUD objective text updates as
  each objective advances. Mission rewards unlock throw-ups, pieces,
  and fill-color cycling.
- **SaveManager** (`Scripts/SaveSystem/save_manager.gd`,
  Milestone 8) — F5 writes `user://toy_to_legend_save.json`; F9
  restores player position, reputation/rank/paint/unlocks, wall
  ownership/history/cross-outs, crew recruitment stages, claimed
  territory, and mission progress.

All wall, style, crew, and NPC content is data-driven from `/Data`
(agent rule 3).

## Not built yet (by design — Plan.md §47)

All Plan.md §35 milestones are in, plus Heat/City Cleanup from the §36
"Should-Have" list. Next up from that list: patrols, a richer supply
inventory, dialogue, and the blackbook UI.
# game-toy-to-ledgend
