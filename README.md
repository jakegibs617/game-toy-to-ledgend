# Toy to Legend — Prototype

Open-world graffiti RPG prototype. Original design in [Plan.md](Plan.md);
current roadmap in [Plan_v3.md](Plan_v3.md); completed v2 roadmap in
[Plan_v2.md](Plan_v2.md); system map in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md);
v3 balance targets in [docs/BALANCE_TARGETS.md](docs/BALANCE_TARGETS.md);
agent/dev workflow in [CLAUDE.md](CLAUDE.md).

Engine: **Godot 4.6** (chosen per Plan.md §29 — open source, text-based scenes/scripts, headless CLI testing).

## Running

Open the project in Godot 4.6+ and press Play, or from the terminal:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

Scenes:

- `Scenes/PrototypeDistrict.tscn` — main scene: graybox Mill Yard district.
- `Scenes/Test_GraffitiWall.tscn` — single test wall in an empty room (Plan.md agent rule 9).

Headless smoke test (per-system `_smoke_*()` checks in
`Scripts/district.gd` drive the full system chain and print `SMOKE: OK`):

```sh
SMOKE_TEST=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path .
```

The smoke path also prints the v3 playtest baseline metrics and balance
snapshot. For a live playtest capture, launch with metrics enabled:

```sh
PLAYTEST_METRICS=1 /Applications/Godot.app/Contents/MacOS/Godot --path .
```

That writes `user://toy_to_legend_playtest_metrics.json` with first-beat
timings, caught/fall/starvation counters, and the event ledger for the run.

To profile the runtime cost of the built city (node/mesh/wall counts,
material cache size, character-visual import status, frame readout),
launch with the budget enabled:

```sh
RUNTIME_BUDGET=1 /Applications/Godot.app/Contents/MacOS/Godot --path .
```

It prints one `RUNTIME_BUDGET: ...` line after the world builds and
changes nothing else. The headless smoke run prints the same readout
(`SMOKE: runtime budget — ...`). Budgets and findings are documented in
[docs/PERFORMANCE_BUDGETS.md](docs/PERFORMANCE_BUDGETS.md).

## Controls

| Input | Action |
|---|---|
| WASD | Move |
| Mouse | Look |
| Controller left/right stick | Move / look |
| Shift | Run |
| Space | Jump |
| E | Paint focused wall / talk / shop / pick up / grab a ladder / sit on a bench (in a conversation: walk away) |
| W/S (on a ladder) | Climb up / down — reverse any time; ride to the top to summit, back to the foot to step off |
| Space (on a ladder) | Hop off the ladder |
| 1–6 | Select can: Tag / Throw-up / Piece / Stencil / Roller / Mural (in shop: buy/delivery; in dialogue: choose; in blackbook: flip pages; seated on a bench: sketch that tag style) |
| [ / ] | Previous / next unlocked can — also how you reach Sticker & Wheatpaste, which sit past the six number slots |
| C | Cycle fill color after Lupe unlocks colors (also in the freehand canvas) |
| F | Freehand piece on the focused wall (needs the Piece can): hold LMB to spray, E/Enter commit, Esc bail |
| P | Perk chooser (spend rank-up perk points; stats level by doing) |
| F5 | Quick save |
| F9 | Quick load |
| Tab | Blackbook (1-4 flip pages: Writer / Styles / Crew / The City) |
| M | District map |
| Esc | Toggle mouse capture |

Controller: left shoulder runs, A jumps, X interacts, Y cycles color,
right shoulder opens freehand, Back opens the blackbook, d-pad up opens
perks, d-pad down opens the map, d-pad left/right cycles cans, Start
toggles mouse capture.

New games open on the title/alias panel. Pick a writer name, then walk
up to a wall panel (the lighter slabs on building faces) until the
prompt appears at the bottom of the screen, then press E. Once the Mill
Yard is claimed, cross the canal footbridge east (E at the gate) into
Canal Side — Ghost Line turf with its own mission chain, walls, patrols,
and heat: each block heats and cools on its own, and a block you leave
cools twice as fast. Glowing rail-and-rung ladders mark climb routes up
to the rooftop roller spots — security won't follow you up. Press E at
the foot to grab the ladder (the slip risk shown is rolled on that
commit, and a slip costs rep); once on, climb up and down by hand with
W/S, change direction whenever you like, ride to the top to summit or
back to the foot to step off, and Space hops off mid-ladder. A fire
escape at the Canal Side rail edge climbs into Rooftop Row, the third
district: all parapets, high
wind, edge-warning paint, and roller-sized walls with no footbridge gate.
Use the Canal Descent climb to get back down. At Canal Side's
east-edge train siding, paint a stopped car with E before it rolls out;
painted cars pass through all three districts on the schedule and keep
paying visibility rep.
Once you're Known, Vesper the gallery scout appears by the Canal Side
dry dock: sell her freehand canvases for cash and public rep — and
watch your crew rep pay the price. Locals now walk small loops in both
districts, stop to clock nearby fresh player paint for a tiny one-time
crowd rep bump, and scatter when their block gets Hot. At the
safehouse, E on the crew board opens the blackbook's Crew page. Benches
on the sidewalks face the street — sit down (E) and the view drops to
first person, then your blackbook opens to sketch tag styles: number
keys fill in a page of a locked style, and after enough practice it
unlocks for the street. You can only practice while seated; closing the
book stands you back up and returns to third person.

The player character is the Kronako Iconz neon rooster. `player.gd`
prefers the animated action set in `Assets/Characters/`: idle, walk,
walk backward, run-fast, jump, ladder climb, ladder-climb finish, and
vault. Normal WASD movement walks, S without Shift uses the backward
walk, Shift+WASD runs, Space plays the jump clip while airborne, and the
ladder-climb clip plays continuously while riding a
ladder — forward up, reversed when climbing down, paused between rungs;
topping out plays an over-the-ledge finish clip. Standing still picks a
random idle clip instead of a single breathing pose and holds it for the
whole idle — the stance only changes the next time the player settles
back into idle. The vault clip is imported for future use but has no
gameplay trigger yet. If Godot asset import has not run once (opening the editor, or
`Godot --headless --path . --import`), the game falls back to the
static rooster GLB, then the old debug capsule.

## Systems implemented (First Agent Task, Plan.md §47)

- **GameState** (autoload, `Scripts/Data/game_state.gd`) — alias, reputation,
  rank progression (Toy → Block King), paint supply, selected graffiti type.
  Also registers the keyboard/controller input map at runtime.
- **WallManager** (autoload, `Scripts/Walls/wall_manager.gd`) — loads
  `Data/walls.json` and `Data/graffiti_styles.json`, spawns walls, applies
  graffiti, computes reputation (base × visibility × risk multipliers,
  Plan.md §11), and keeps every wall's state + graffiti history in memory.
  Wall state survives scene reloads within a session. Milestone 16 adds
  the full §8 type set — stencil (cheap/fast, needs Lupe's kit), roller
  (rooftop surfaces only) and mural (needs crew present; long exposure
  draws patrol eyes) — with per-style surface rules rivals obey too.
  Tag-font styles also carry bespoke behavior (Product_reqs.md): scratch
  and acid hands are **glass-only** (a storefront window, not turf you
  claim), the scratch hand draws as a faint **greyscale** scratch, and
  acid hands run **vertical** down a tall glass panel. **Wildstyle** takes
  the longest to paint — more heat and patrol attention — but pays an
  exposure rep bonus on **heaven spots** (the high, very visible
  landmark/rooftop walls). **Stickers & wheatpaste** (Product_reqs.md) are
  paper work, not spray: a slap goes up cheap and near heat-free, a poster
  pays more rep for the size, both render on a paper backing, stick to
  surfaces a fill won't bite (glass included), and buff easily. They unlock
  by meeting **Indigo**, an art-school printmaker, near the Mill Yard
  safehouse once you're an Up writer; lugging the paste bucket raises your
  gear suspicion.
- **PaintableWall** (`Scripts/Walls/paintable_wall.gd`) — data-driven wall
  body; placeholder graffiti rendered as Label3D "decals" (alias text styled
  per graffiti type) with a per-graffiti tilt, paint drips, fill panels for
  throw-ups/pieces, and a strike bar on cross-outs (Milestone 8 art pass).
- **Player** (`Scripts/Player/player.gd`) — third-person controller with
  spring-arm camera, raycast wall focusing, and a runtime-loaded
  rooster animation state table for idle/walk/backpedal/run/jump/climb/
  climb-finish movement. The fallback nearby-interactable search is line-of-sight
  checked so pickups/zones cannot be focused through walls.
- **HUD** (`Scripts/UI/hud.gd`) — styled stat/mission/prompt panels,
  feedback messages, rank-up notice, rival event notifications, a
  low-paint warning, and a controls hint (Milestone 8 UI pass).
- **Sfx** (autoload, `Scripts/Audio/sfx.gd`, Milestone 8) — placeholder
  sound effects synthesized at startup (no audio assets): spray hiss on
  painting, denied blip, rank-up/block-claim stings, rival buzz, UI
  blips for crew/save events, a low music bed, and per-district
  ambience. Headless runs self-disable audio playback.
- **PlaytestMetrics** (`Scripts/Debug/playtest_metrics.gd`,
  Milestone 27) — optional v3 instrumentation. It records nothing in
  normal play, but `PLAYTEST_METRICS=1` writes a JSON playthrough ledger
  to `user://toy_to_legend_playtest_metrics.json`; the smoke test uses
  the same recorder for a repeatable baseline and balance snapshot.
- **RivalManager** (autoload, `Scripts/Rivals/rival_manager.gd`,
  Milestone 4) — loads `Data/crews.json` (The Buff Kings, Ghost Line,
  Chrome Saints). Crews claim their home walls at session start. When
  the player paints in crew territory or over crew work, a retaliation
  is queued and resolved on a 12-second simulation tick (Plan.md §33),
  no sooner than 30 seconds after the player paints: tags or low-rank
  work get **"TOY"** crossed out, stronger work gets covered by the
  crew's own graffiti. Repainting reclaims the wall. When a response is
  due, a rival tagger wearing the Hooded Fox Warrior model runs in from
  the side, sprays the wall, and flees (`Scripts/Rivals/rival_tagger.gd`,
  capsule fallback when the GLBs are missing).
- **CrewManager** (autoload, `Scripts/Crew/crew_manager.gd`,
  Milestones 5 and 22) — loads `Data/npc_data.json`. Mina "Moth"
  joins as your Lookout (rivals back off more often and she warns you
  about patrols/retaliation), Rico "Caps" joins as your Filler
  (auto-fills throw-ups on a few open/non-player walls in claimed
  territory), and Jay "Metro" joins as your Getaway (one free escape
  per heat level before normal security penalties apply). The
  blackbook's Crew page and the safehouse crew board track their
  status.
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
  territory, mission progress, stats/perks, and train service state.
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
- **TrainManager** (`Scripts/Trains/train_manager.gd`, Milestone 20) —
  scheduled train cars from `Data/trains.json`. A stopped Canal Side
  car can be painted for a high paint/heat cost; once in service it
  pays rep every time it passes through Canal Side and Mill Yard. The
  blackbook's City page logs painted cars and pass counts, and train
  state persists in save v4.
- **GalleryManager** (`Scripts/Gallery/gallery_manager.gd`,
  Milestone 21) — gallery commissions (Plan.md §18, §43) from
  `Data/gallery.json`. Once you're Known, Vesper the gallery scout
  appears by the Canal Side dry dock: take a commission and the
  freehand canvas opens with no wall behind it. The freehand style
  multiplier is the judge's score — weak canvases get refused (paint
  spent, nothing paid); accepted ones pay cash (scaled by Hustle) and
  public rep but cost **crew rep**, the public/crew split from Plan.md
  §11 in minimal form. Crew rep shows in the HUD and blackbook, builds
  through recruiting and crew-backed murals, and goes negative when
  the street decides you sold out. Sales persist in save v5.
Wall, style, crew, NPC, character-visual manifest, district, climb,
train, and gallery content is data-driven from `/Data` (agent rule 3).
Generated world props share cached materials where their look matches,
keeping the two-district demo cheaper to render as more detail is added.

## Not built yet (by design — Plan.md §47)

All Plan.md §35 milestones are in, and the §36 "Should-Have" list is
complete: Heat/City Cleanup, security patrols, supply economy,
dialogue, and the blackbook UI. From the §36 "Could-Have" list,
freehand spray painting is in (Milestone 14), rooftop climbing is in
(Milestone 19), train painting is in (Milestone 20), and gallery
missions are in (Milestone 21). Crew depth is in (Milestone 22) with
Caps and Metro, and the presentation pass is in (Milestone 23) with
alias/title flow, controller bindings, ambience, and rooster idle
polish. World/data hardening is in (Milestone 24) with cached generated
materials, JSON character visual manifests, and interactable line of
sight. Ambient NPC life is in (Milestone 25) with waypoint locals,
crowd-reaction rep ticks, and district-scoped heat scatter. Rooftop
Row is in (Milestone 26) with climb-only entry, rooftop walls, a
mission chain, patrol route, and train visibility; what remains is the
rest of that list
(battles, procedural graffiti, deeper crowd simulation) — deliberately out of
prototype scope per Plan.md §47.
