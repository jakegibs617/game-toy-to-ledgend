# Toy to Legend — Prototype

Open-world graffiti RPG prototype. Original design in [Plan.md](Plan.md);
current roadmap in [Plan_v2.md](Plan_v2.md); system map in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); agent/dev workflow in
[CLAUDE.md](CLAUDE.md).

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
| E | Paint focused wall / talk / shop / pick up (in a conversation: walk away) |
| 1 / 2 / 3 | Select Tag / Throw-up / Piece (in shop: buy; in dialogue: choose) |
| 4 | (in Lupe's shop) Take a delivery run · (in dialogue) choice 4 |
| C | Cycle fill color after Lupe unlocks colors (also in the freehand canvas) |
| F | Freehand piece on the focused wall (needs the Piece can): hold LMB to spray, E/Enter commit, Esc bail |
| F5 | Quick save |
| F9 | Quick load |
| Tab | Blackbook (1-4 flip pages: Writer / Styles / Crew / The City) |
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
  one of your walls. The blackbook's Crew page (Tab) tracks her status.
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
- **PatrolManager** (autoload, `Scripts/Patrols/patrol_manager.gd`) —
  security patrols (Plan.md §12, §18, §25). Guards walk fixed routes
  from `Data/patrols.json` (street sweep, north alley, bodega side) and
  the patrol count follows the heat level — more heat, more guards. A
  guard that sees you painting spikes heat and gives chase; getting
  caught costs 25 rep and 3 paint but settles heat (the incident is
  closed). You can outrun them — chase speed is below your run speed.
  With Moth recruited, she calls out patrols near your painting spot.
  Guards show as orange dots on the district map.
- **SupplyManager** (autoload, `Scripts/Supplies/supply_manager.gd`) —
  supply economy (Plan.md §21). Cash arrives with mission payouts and
  buys from Lupe's catalog (`Data/supplies.json`): paint packs, a fat
  cap that cuts the paint cost of throw-ups and pieces by 1, and the
  rare "Burner Chrome" fill color. Interact with Lupe outside mission
  beats to open the shop (number keys buy). She also hands out
  repeatable delivery runs: carry a package to a rotating drop spot
  for $25 — but the handoff draws heat.
- **BlackbookPanel** (`Scripts/UI/blackbook_panel.gd`, Milestone 13) —
  the blackbook (Plan.md §23) on Tab: four pages flipped with the
  number keys. Writer (alias, rank, wallet, heat, district influence,
  mission notes), Styles (unlocked graffiti types with live paint
  costs, fill palette), Crew (recruitment status — replaces the old
  standalone crew menu), and The City (rival crews with attitude and
  walls held, plus your presence on the block).
- **DialogueManager** (autoload, `Scripts/Dialogue/dialogue_manager.gd`) —
  RPG-style choice dialogue (Plan.md §26), data-driven from
  `Data/dialogue.json`. Number keys pick choices; choices can branch,
  end, open Lupe's shop, or start a delivery, and can gate behind
  checks (Prime's lesson needs rank Known+). One-time rewards are
  tracked as flags and persist through save/load. Speakers: Lupe
  (shop/delivery/street gossip), Darnell "Prime" the old head near the
  safehouse (lore + a one-time +40 rep lesson), and Moth once
  recruited.
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
- **FreehandPanel** (`Scripts/UI/freehand_panel.gd`, Milestone 14) —
  freehand spray painting (Plan.md §10 "Later Advanced System", first
  §36 Could-Have). F at a wall opens a canvas sized to the wall face;
  hold LMB to spray (speckled spray-can stamps), C cycles the fill
  palette, E/Enter commits, Esc bails. The committed image is a piece:
  costs piece paint, earns piece rep scaled by a style multiplier
  (0.5x–2x) from canvas coverage and colors used, renders on the wall
  as a textured quad, and persists through save/load as base64 PNG in
  the wall state. Rivals, heat, patrols, missions, and territory all
  react like any other piece.

All wall, style, crew, and NPC content is data-driven from `/Data`
(agent rule 3).

## Not built yet (by design — Plan.md §47)

All Plan.md §35 milestones are in, and the §36 "Should-Have" list is
complete: Heat/City Cleanup, security patrols, supply economy,
dialogue, and the blackbook UI. From the §36 "Could-Have" list,
freehand spray painting is in (Milestone 14); what remains is the rest
of that list (battles, train painting, rooftop climbing, gallery
missions, procedural graffiti, crowd reactions) — deliberately out of
prototype scope per Plan.md §47.
# game-toy-to-ledgend
