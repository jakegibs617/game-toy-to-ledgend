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

v2 is now partly built. Milestones 15–20 are complete (PRs #9–#15):
engineering hardening, the full graffiti type set, stats/perks/rep
decay, Canal Side, rooftop climbing, and train painting. The first real player
character art is in: the Kronako Iconz neon rooster now has a runtime
animation action set for idle, walking, backpedaling, running, jumping,
and ladder climbing. The vault clip is imported and bound but awaits a
gameplay trigger.

PR #15 also shipped the first NPC/world art pass: animated Meshy
character sets for Moth (lookout meerkat), Lupe (shop rat), Prime
(gorilla), and the security patrols (bull), all loaded through a shared
`Scripts/Characters/animated_model_set.gd` helper; plus procedural
street detail (sidewalks, lane paint, manholes, drains, litter), noise
textures and per-surface-type detail (brick mortar, concrete seams,
stucco pitting) on walls and buildings, and a Canal Side train siding.
Many imported clips (walk/run for every NPC, guard ladder climb, turn
variants) are loaded but not yet triggered by gameplay — NPCs are
stationary; only the guards and player actually move.

The playable loop is currently: start in Mill Yard, learn the core
mission chain, recruit Moth, unlock throw-ups/pieces/stencils/rollers/
murals, claim Mill Yard, travel to Canal Side, push back Ghost Line,
level Style/Stealth/Hustle through use, choose perks on rank-up, climb
to rooftop roller spots, escape grounded security by taking the high
ground, paint a stopped train car in Canal Side, and see it pay rep as
it rolls through the city.

## Designed in v1, not yet built or only minimally represented

| v1 design | Section | Status |
|---|---|---|
| Graffiti types: mural, stencil, roller/blockbuster | §8 | Built in Milestone 16; train-scale blockbuster use is still future-facing |
| Player stats (Style, Nerve, Speed, Stealth, Influence, Technique, Hustle) | §6 | Style/Stealth/Hustle subset built in Milestone 17 |
| Perk trees (Style/Stealth/Crew/Territory/Supplies) | §7 | Minimal chooser built in Milestone 17; not a full tree editor |
| XP sources separate from rep | §5 | Built for Style/Stealth/Hustle in Milestone 17 |
| Reputation decay / visibility-over-time value | §11 | Built as district payout/decay in Milestone 17; train pass-through rep built in Milestone 20 |
| Public rep vs crew rep split | §11 | Single rep number until gallery tension in Milestone 21 |
| Battle systems (graffiti/dance/rap) | §20 | None |
| Safehouse features (blackbook table, crew board, planning map) | §22 | Safehouse is a bare mission zone |
| Districts beyond Mill Yard (Canal Side, Train Yard, Rooftop Row, …) | §45 | Canal Side is built with a train siding (Milestone 20); a full Train Yard and Rooftop Row (Milestone 26) remain future |
| Crew members Rico "Caps" (filler), Jay "Metro" (getaway) + 5 unused roles | §14, §43 | Only Moth (lookout); murals currently need any recruited crew |
| Alias selection / main menu | §38, §40 | Hardcoded "NOVA", boots straight into the district |
| Controller support | §37 | Keyboard/mouse only |
| Gallery contact / art-world faction | §18, §43 | None |
| Player presentation | §28, §40 | Animated rooster action set is in; turn/vault/presentation polish remains |
| NPC presentation / ambient life | §28, §44 | Animated character models in (Milestone 20 PR); NPCs stand still — walk/run clips await movement behaviors |

## Remaining v1 Could-Have list

Dance battles, rap battles, gallery missions, procedural graffiti,
dynamic NPC crowd reactions.

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

§3.1–3.7 are findings from building milestones 8–14; all were
addressed by Milestone 15 and should stay true as guardrails for
future work. §3.8–3.11 are findings from the Milestone 20 (PR #15)
multi-angle review; 3.8 is done, 3.9–3.11 are open and folded into
Milestone 24 below.

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
stats/perks, Milestone 18 bumped to save v3 for per-district heat
and mission chains, and Milestone 20 bumped to save v4 for train
service state.

## 3.8 Shared animated-model loader

The swap-visibility GLB pattern (one model per visual state, primed
AnimationPlayer, toggle visibility) was copy-pasted identically into
player, NPC, mission actor, and patrol guard scripts.

**Status:** complete in the Milestone 20 review pass via
`Scripts/Characters/animated_model_set.gd` (static funcs, preloaded —
class-cache rule). All four character scripts delegate to it; new
character types must too.

## 3.9 Surface-detail material batching

The street/wall art pass creates a unique `StandardMaterial3D` (and
often a unique mesh node) per detail quad — mortar lines, seams,
litter, lane dashes. That's hundreds of materials and draw calls per
district for what are ~6 distinct looks. Before a third district
ships: share materials per color/look (a small material cache keyed by
color), and consider `MultiMeshInstance3D` for repeated quads (bricks,
ties, joints). Cosmetic only — safe to defer until a perf dip or
Milestone 24, whichever comes first.

## 3.10 Data-driven character visuals

Model paths and animation-clip names are hardcoded constants in four
scripts, keyed by `actor_id == "lupe"`-style branches. This violates
the v1 agent rule ("everything is data-driven"): a new NPC means code
edits, not a JSON entry. Move per-character model/clip manifests into
`npc_data.json` / `missions.json` actor defs (e.g. a `visuals` block:
state → {model, clip}), with the current constants as the fallback.
Do this before Milestone 22 adds two more crew members, or it becomes
six copies.

## 3.11 Interaction fallback line-of-sight

`player.gd::_nearest_interactable` (the pickup-focus fallback added in
Milestone 20) selects the nearest "interactable" group node within
range with no line-of-sight check — a pickup can be grabbed through a
thin wall. Low stakes today (one pickup type, 3.5 m range); add a
single `intersect_ray` occlusion check when more item types join the
group.

---

# 4. v2 Milestones

Continue v1 numbering. Each milestone follows the dev loop in
CLAUDE.md (branch → implement → smoke test additions → PR → review →
fixes → merge). Order matters: 15 unblocks cheap UI/content work,
16–18 are the demo's spine, 19–21 are the signature features, 22–23
round out the demo, and 24–26 (added after Milestone 20) harden the
world and spend the art that's already imported.

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

## Recommended Next Steps (updated after Milestone 20 / PR #15)

1. **Milestone 21 (gallery missions) is the next system milestone.**
   It is the last §46-criteria feature ("selling out was a real
   decision") and reuses the Milestone 14 freehand canvas — no new
   tech, mostly mission/judging logic. Do it before more content
   widens the world.
2. **Milestone 22 (crew depth) second**, but land §3.10 (data-driven
   character visuals) at the start of it — Rico and Metro should be
   JSON entries with a `visuals` block, not a fifth and sixth copy of
   hardcoded model constants.
3. **Fold the open review findings (§3.9, §3.11) into Milestone 24**
   rather than fixing them piecemeal: material batching pays off most
   right before a third district, and the LOS check matters once more
   item types exist.
4. **Use the already-imported idle/walk clips for ambient NPC life
   (Milestone 25)** — the art is paid for; behaviors are the missing
   half. Keep it after the system milestones.
5. **Keep presentation changes non-schema:** animation/model/material
   work should continue without save-version bumps unless persisted
   state gains new fields. Trains proved the v4 migration pattern;
   reuse it.

## Milestone 20: Train Painting (Could-Have — the signature moment) — Complete

* Train Yard area in/adjacent to Canal Side; trains on a schedule.
* Painting a stopped train = timed window, high heat.
* Painted cars then pass through both districts on the schedule —
  rep ticks each pass-through (§11 "visibility over time", finally
  earning its keep). The blackbook logs your cars in service.

**Status:** complete. Canal Side now has a train siding with a
scheduled Ghost Local car, a stopped-car paint window, high heat,
save-persisted train graffiti, pass-through rep ticks in Canal Side
and Mill Yard, HUD events, and blackbook service logging.

## Milestone 21: Gallery Missions (Could-Have)

* Gallery contact NPC (§43) appears at rank Known: bring a freehand
  piece — the Milestone 14 canvas becomes the gameplay; the style
  multiplier becomes the judge's score.
* Pays cash + public rep but **costs** crew rep (§18 art-world
  tension, §11 public/crew split in minimal form: one tracked value).

**Status:** complete in PR #17. `GalleryManager`, Vesper, gallery
commission canvases, accepted/refused sale outcomes, crew rep cost,
sales persistence, HUD/blackbook text, smoke coverage, and docs landed.

## Milestone 22: Crew Depth (§14, §43)

* Rico "Caps" (filler: assists murals, auto-fills throw-ups in held
  territory) and Jay "Metro" (getaway: one free escape per heat
  level) with recruitment mini-chains like Moth's.
* Crew board in the safehouse (§22 MVP features).

**Status:** complete in PR #18. Caps and Metro are data-driven crew
members with recruitment stages, passive filler/getaway roles, v6 save
migration, safehouse crew board, blackbook coverage, smoke coverage,
and data-driven NPC/mission actor visuals.

## Milestone 23: Presentation Pass

* Main menu + alias selection (replaces hardcoded NOVA — §40 opening).
* Animation/presentation pass on the rooster player model; music loop
  + per-district ambience (§28); controller bindings (§37).
* This is the "make the demo feel like a game" milestone — keep it
  last so systems stay the priority (§47 agent rule 2).

**Status:** complete in PR #19. Title/alias flow, controller bindings,
right-stick look, can cycling, rooster idle polish, music bed, and
per-district ambience landed with smoke coverage and boot verification.

## Milestone 24: World Render & Data Hardening (new)

The engineering follow-ups from the Milestone 20 review (§3.9–§3.11),
batched so they ship once instead of as drive-by fixes:

* Shared material cache + `MultiMeshInstance3D` for repeated surface
  details (§3.9); target: a district renders with ~tens, not hundreds,
  of unique materials, with no visible change.
* Data-driven character visuals (§3.10): `visuals` manifest blocks in
  the NPC/actor JSON, consumed by `animated_model_set.gd`; delete the
  per-script model-path constants.
* Line-of-sight check in the interactable fallback (§3.11).
* No new gameplay; deliverable is an unchanged windowed run + smoke
  test, like Milestone 15. Schedule before any third district.

**Status:** complete in PR #20. Generated world material caching,
interactable line-of-sight filtering, manifest-driven character visual
documentation, smoke coverage, and docs landed before the third
district work.

## Milestone 25: Ambient NPC Life (Could-Have, §44 crowd reactions in minimal form) (new)

* Put the already-imported walk/idle clips to work: Moth wanders her
  corner, Lupe restocks crates, Prime gestures mid-listen; simple
  waypoint loiter loops, no nav-mesh.
* 2–3 generic pedestrians per district (reuse character sets with
  tinted materials) that pause to look at fresh player pieces — the
  minimal §44 "people react to your work" beat; +1 small rep tick the
  first time a piece draws a crowd.
* Pedestrians scatter when heat spikes nearby — readable danger
  without new systems (PatrolManager signals already exist).
* Guard ladder-climb clip gets its trigger: guards use it at climb
  zones instead of giving up, raising rooftop stakes after Milestone
  19 made roofs safe.

**Status:** complete in PR #21. `Data/ambient_npcs.json` drives three
locals per street-level district; `AmbientNpc` waypoint loops, crowd
reaction rep, shared per-wall crowd ledger, district-scoped heat
scatter, guard climb-clip trigger, smoke coverage, and docs landed.

## Milestone 26: Rooftop Row District (§45) (new)

* Third district, unlocked via the Milestone 19 climbing system:
  entry is a climb, not a travel point — verticality is the identity.
* Rooftop-only wall set (roller/blockbuster heavy), wind/edge risk on
  long pieces, and the second train line passing below for Milestone
  20 cross-district value.
* Own rival presence and a 2–3 mission chain; per-district heat
  already generalizes.
* Builds on Milestone 24's render hardening (third district is the
  cost trigger for §3.9) — do not start it before 24 lands.

**Status:** complete in PR #22. `district_rooftop_row` is a climb-only
third district with elevated generated geometry, rooftop-surface walls,
Chrome Saints presence, patrol route, train service coverage,
`targetDistrictId` climb transitions, a three-mission chain, smoke
coverage, and docs.

---

# 5. v2 Priorities

## Current Status

Milestones 15-26 are complete. The demo spine, Should-Have list, and
the v2 Could-Have stretch goals have shipped through PR #22.

## Recommended Next Steps

1. Run a human playtest pass from new game through Rooftop Row claim,
   noting friction, confusing prompts, pacing spikes, and any places
   where smoke coverage feels greener than the actual moment.
2. Do a balancing pass on rep/paint/cash/heat now that gallery sales,
   crew roles, trains, ambient crowd ticks, and three districts all pay
   into the same economy.
3. Add visual/performance profiling for the three-district runtime
   scene before adding more content; Milestone 24 reduced material
   churn, but the world is now big enough to measure.
4. Only then choose between the new milestone candidates below.

## New Milestone Candidates

### Milestone 27: Playtest & Balance Pass

* Instrument or log the main path timings: first tag, first claim,
  Canal Side entry, gallery sale, train painting, Rooftop Row claim.
* Tune paint costs, mission rewards, heat gains, patrol counts, and
  territory decay against one target playthrough.
* Add smoke assertions for any balance invariants that should never
  regress (minimum paint before required roller work, no mission soft
  locks, rank thresholds reachable without grinding).

### Milestone 28: Procedural Rival Graffiti Variety

* Replace repeated placeholder rival labels with generated tag/throw-up
  variants using crew palette, alias, stroke blocks, drips, and simple
  layout noise.
* Keep it deterministic per graffiti id so saves and screenshots are
  stable.
* Extend wall history/blackbook display to show rival variety without
  storing heavy image blobs.

### Milestone 29: Rooftop Traversal Polish

* Add visible ledge/edge warning, wind gust tells, and a small stumble
  or slip chance for long rooftop work instead of relying only on wall
  risk values.
* Make climb/descent prompts clearer and add a grounded return route
  hint after the player first enters Rooftop Row.
* Verify camera framing and guard behavior on elevated patrol routes.

### Milestone 30: Battle Prototype Paper Cut

* Prototype the smallest fun version of a dance/rap battle (§20) on
  paper first: input pattern, scoring, fail state, reward, and why it
  belongs in this graffiti loop.
* Build only if the paper version has a clear 60-second interaction
  that is more fun than another paint/territory beat.

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
