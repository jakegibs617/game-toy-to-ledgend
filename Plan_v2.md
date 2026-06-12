# Plan v2.0: From Prototype to Playable Demo

**Toy to Legend** — second development phase.

Plan.md (v1) is the original game design document and remains the
design reference: section numbers cited below (§N) refer to it. This
document does not repeat v1's designs — it records where v1 landed,
recommends what to build next and in what order, and defines the v2
milestones. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how
the code is actually organized before starting any milestone.

---

# 1. Where the Project Stands

All 14 v1 milestones are complete (PRs #1–#7): the §35 vertical slice,
the entire §36 Should-Have list (heat, patrols, supply economy,
dialogue, blackbook), and the first Could-Have (freehand spray
painting, Milestone 14). The §46 success criteria are testable today:
paint, get crossed out, resupply, recruit, reclaim, claim the block.

v2 is now partly built. Milestones 15–19 are complete (PRs #9–#13):
engineering hardening, the full graffiti type set, stats/perks/rep
decay, Canal Side, and rooftop climbing. The first real player
character art is in: the Kronako Iconz neon rooster now has a runtime
animation action set for idle, walking, backpedaling, running, jumping,
and ladder climbing. The vault clip is imported and bound but awaits a
gameplay trigger.

The playable loop is currently: start in Mill Yard, learn the core
mission chain, recruit Moth, unlock throw-ups/pieces/stencils/rollers/
murals, claim Mill Yard, travel to Canal Side, push back Ghost Line,
level Style/Stealth/Hustle through use, choose perks on rank-up, climb
to rooftop roller spots, and escape grounded security by taking the
high ground.

## Designed in v1, not yet built or only minimally represented

| v1 design | Section | Status |
|---|---|---|
| Graffiti types: mural, stencil, roller/blockbuster | §8 | Built in Milestone 16; train-scale blockbuster use is still future-facing |
| Player stats (Style, Nerve, Speed, Stealth, Influence, Technique, Hustle) | §6 | Style/Stealth/Hustle subset built in Milestone 17 |
| Perk trees (Style/Stealth/Crew/Territory/Supplies) | §7 | Minimal chooser built in Milestone 17; not a full tree editor |
| XP sources separate from rep | §5 | Built for Style/Stealth/Hustle in Milestone 17 |
| Reputation decay / visibility-over-time value | §11 | Built as district payout/decay in Milestone 17; train pass-through rep remains Milestone 20 |
| Public rep vs crew rep split | §11 | Single rep number until gallery tension in Milestone 21 |
| Battle systems (graffiti/dance/rap) | §20 | None |
| Safehouse features (blackbook table, crew board, planning map) | §22 | Safehouse is a bare mission zone |
| Districts beyond Mill Yard (Canal Side, Train Yard, Rooftop Row, …) | §45 | Canal Side is built; Train Yard/Rooftop Row remain future |
| Crew members Rico "Caps" (filler), Jay "Metro" (getaway) + 5 unused roles | §14, §43 | Only Moth (lookout); murals currently need any recruited crew |
| Alias selection / main menu | §38, §40 | Hardcoded "NOVA", boots straight into the district |
| Controller support | §37 | Keyboard/mouse only |
| Gallery contact / art-world faction | §18, §43 | None |
| Player presentation | §28, §40 | Animated rooster action set is in; turn/vault/presentation polish remains |

## Remaining v1 Could-Have list

Dance battles, rap battles, gallery missions, procedural graffiti,
train painting, dynamic NPC crowd reactions.

---

# 2. v2 Goal

A 30–60 minute **playable demo**: two districts, a progression choice
that matters (stats/perks), the three remaining graffiti types with
surface rules, and one signature "only this game" moment — painting a
train that then carries your name through the city. v1 proved the
loop; v2 proves the loop has depth.

The emotional arc extends v1's: **known on the block → choosing what
kind of writer you are → your name moves without you.**

---

# 3. Engineering Recommendations

Findings from building milestones 8–14. None block gameplay today;
all were addressed by Milestone 15 and should stay true as guardrails
for future work.

## 3.1 HUD modal manager

`hud.gd` routes modal input through a hand-ordered if-ladder, and
every modal (shop, dialogue, blackbook, map, freehand) manually closes
the others. Adding the 6th modal means touching 5+ places; forgetting
one leaves two modals open and fighting for input. Replace with a
small modal stack: one `open_modal(panel)` that closes the current
one, one input dispatch to whatever is open. The
`MODAL_SLOT_ACTIONS` number-key convention already points this way.

**Status:** complete in Milestone 15 via HUD's modal registry.

## 3.2 Shared UI helpers

`_make_label` and the StyleBoxFlat panel recipe are copy-pasted in
`hud.gd`, `blackbook_panel.gd`, and `freehand_panel.gd` with drifting
margins. Extract a `Scripts/UI/ui_kit.gd` (static funcs, preloaded —
see the class-cache rule in CLAUDE.md) before a 4th copy appears.

**Status:** complete in Milestone 15 via `Scripts/UI/ui_kit.gd`.

## 3.3 Split the smoke test

`district.gd::_run_smoke_test` is 600+ lines covering 14 milestones in
one function with shared mutable state — adding an assertion near the
top now risks breaking assumptions 400 lines down. Split into
per-system check functions (`_smoke_walls()`, `_smoke_heat()`, …)
called in sequence, each documenting the state it assumes. Same
SMOKE_TEST=1 entry point.

**Status:** complete in Milestone 15; later milestones add their own
`_smoke_*` sections.

## 3.4 Unify the player paint paths

`paint_wall` and `paint_freehand` share the commit tail
(`_commit_player_graffiti`) but still duplicate the
unlock/spend/buff-bonus head. A perk that discounts paint or boosts
buff retaliation (§7) would need editing both. Extract the head
before stats/perks (Milestone 17) multiply the call sites.

**Status:** complete in Milestone 15 via
`WallManager._begin_player_paint`.

## 3.5 Cap wall history

History entries no longer carry freehand images (PR #7), but the
array itself is unbounded and deep-copied on every quick_save. Cap at
~20 entries per wall (drop oldest). Walls remember (§9) — they don't
need to remember everything forever.

**Status:** complete in Milestone 15 with
`WallManager.MAX_WALL_HISTORY = 20`.

## 3.6 Data validation on load

`walls.json` etc. are loaded with `.get()` defaults everywhere; a
typo'd wall def fails silently into a 4×3 gray box. Add a
`_validate()` pass per data file that `push_error`s missing required
fields at startup — content work in v2 (new districts, new types)
multiplies the JSON surface area.

**Status:** complete in Milestone 15 via `DataLoader.require_fields`;
the smoke test asserts clean shipped data.

## 3.7 Save migration

`SaveManager` already writes `version: 1` and refuses newer saves.
v2 will change the schema (stats, second district, new wall fields).
Keep the discipline: bump SAVE_VERSION when the shape changes, and
add per-version migration (or an explicit "save too old" message) so
mid-demo saves don't break.

**Status:** active discipline. Milestone 17 bumped to save v2 for
stats/perks, and Milestone 18 bumped to save v3 for per-district heat
and mission chains.

---

# 4. v2 Milestones

Continue v1 numbering. Each milestone follows the dev loop in
CLAUDE.md (branch → implement → smoke test additions → PR → review →
fixes → merge). Order matters: 15 unblocks cheap UI/content work,
16–18 are the demo's spine, 19–21 are the signature features.

## Milestone 15: Engineering Hardening — Complete

All of §3 above. No new gameplay. Deliverable: identical smoke-test
behavior (now split per system), modal manager, ui_kit, unified paint
path, history cap, data validation, no regressions in a windowed run.

## Milestone 16: Full Graffiti Type Set (§8) — Complete

* Stencil: cheap, fast, low rep, needs a bought stencil item (shop).
* Roller/blockbuster: high rep, big paint cost, only on `rooftop`
  surfaces (new wall property per §9).
* Mural: highest rep, requires crew member present (filler role) and
  long paint time (heat risk while painting).
* Wall defs gain `surfaceType` + allowed-types rules; prompt and
  blackbook Styles page updated; rivals may use the new types.

## Milestone 17: Progression Depth (§5, §6, §7, §11) — Complete

* A 3-stat subset: **Style** (rep multiplier), **Stealth** (witness
  radius/heat), **Hustle** (prices, delivery pay). Stats raise by
  doing (§6 "improve through use").
* One perk choice per rank-up, 2 perks per §7 tree max — a choice
  screen, not a tree editor.
* Reputation decay (§11): unattended districts cool; crossed-out and
  buffed work stops paying. Makes territory defense a real loop.
* Save version bump + migration.

**Status:** complete. The implemented subset is Style, Stealth, and
Hustle with use-based XP, perk choices, district payout/decay, and save
v2 migration.

## Milestone 18: Second District (§45) — Complete

* Canal Side: new wall set, own crew presence (Ghost Line territory),
  own mini mission chain (3 missions), travel point between districts.
* District map becomes multi-district; territory/influence per
  district already supports this (`districts.json` is an array).
* Per-district heat (cool down by leaving the block — §12).

## Milestone 19: Rooftop Climbing (Could-Have) — Complete

* Ledge-grab + climb zones on the existing graybox buildings; reach
  rooftop-only roller spots from Milestone 16.
* Patrols can't follow up; risk shifts to the climb itself (fall =
  caught-equivalent fine).
* Unlocks Rooftop Row district later — don't build that district yet.

**Status:** complete for climb zones, rooftop roller access, fall rep
penalties, and guards giving up from below. Rooftop Row remains future.

## Current Non-Milestone Presentation Update — Complete

The debug capsule has been replaced by the Kronako Iconz neon rooster
GLB action set. `player.gd` loads separate skinned clips at runtime,
keeps the existing movement and collision, and falls back to the static
rooster/capsule if Godot import metadata has not been generated yet.
Current triggers: idle, walk, backpedal, Shift-run, jump while
airborne, and ladder climb on successful climb-zone interactions.
Imported-but-untriggered clips (vault, turn variants, sprint-stop,
stand-up) should become gameplay event hooks rather than passive
movement guesses.

## Recommended Next Steps

* **Animation polish pass (small, before Milestone 20 if desired):**
  add event hooks for vault/turn/stop clips only where gameplay
  supports them; avoid swapping clips on every tiny input change until
  blend/cooldown rules exist.
* **Milestone 20 remains the next system milestone:** train painting
  is still the signature demo moment and should drive the next gameplay
  branch.
* **Keep presentation changes non-schema:** animation/model work should
  continue without save-version bumps unless player state gains new
  persisted fields.

## Milestone 20: Train Painting (Could-Have — the signature moment) — Next

* Train Yard area in/adjacent to Canal Side; trains on a schedule.
* Painting a stopped train = timed window, high heat.
* Painted cars then pass through both districts on the schedule —
  rep ticks each pass-through (§11 "visibility over time", finally
  earning its keep). The blackbook logs your cars in service.

## Milestone 21: Gallery Missions (Could-Have)

* Gallery contact NPC (§43) appears at rank Known: bring a freehand
  piece — the Milestone 14 canvas becomes the gameplay; the style
  multiplier becomes the judge's score.
* Pays cash + public rep but **costs** crew rep (§18 art-world
  tension, §11 public/crew split in minimal form: one tracked value).

## Milestone 22: Crew Depth (§14, §43)

* Rico "Caps" (filler: assists murals, auto-fills throw-ups in held
  territory) and Jay "Metro" (getaway: one free escape per heat
  level) with recruitment mini-chains like Moth's.
* Crew board in the safehouse (§22 MVP features).

## Milestone 23: Presentation Pass

* Main menu + alias selection (replaces hardcoded NOVA — §40 opening).
* Animation/presentation pass on the rooster player model; music loop
  + per-district ambience (§28); controller bindings (§37).
* This is the "make the demo feel like a game" milestone — keep it
  last so systems stay the priority (§47 agent rule 2).

---

# 5. v2 Priorities

## Complete Demo Spine

Milestones 15, 16, 17, 18.

## Complete Should-Have

Milestone 19.

## Next Should-Have

Milestones 20, 21.

## Could-Have

Milestone 22, 23; procedural rival graffiti variety; NPC crowd
reactions; dance/rap battles (§20) — battles stay parked until a
minigame is actually fun on paper.

## Do Not Build Yet (carried over from v1 §36, still true)

Full city, multiplayer, complex combat, procedural world generation,
advanced layered-editor painting, full faction diplomacy, large quest
trees, character creator, vehicles, online sharing.

---

# 6. v2 Success Criteria

The demo is successful if a tester can say, in addition to v1's §46:

* "I chose Stealth and my friend chose Style, and our runs felt different."
* "I left Mill Yard for an hour and lost ground — and wanted it back."
* "I climbed somewhere I shouldn't have been to paint something huge."
* "I saw my train car come back around and pointed at the screen."
* "Selling out to the gallery was a real decision."

---

# 7. Process Notes for Future Sessions

* Dev loop, commands, and engine gotchas: **CLAUDE.md** (repo root).
* System map, signal flow, data schemas: **docs/ARCHITECTURE.md**.
* Per-milestone history: **CHANGELOG.md**; current systems: **README.md**.
* v1 design rationale: **Plan.md** — cite §N when implementing, as the
  codebase comments already do.
