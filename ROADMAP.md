# Toy to Legend — Roadmap

The single living plan. Consolidated 2026-07-15 from `Plan.md`,
`Plan_v2.md`, `Plan_v3.md`, and `Plan_v4.md`, which are gone: the v1
design doc is archived at [docs/design/GDD.md](docs/design/GDD.md), the
v2/v3 milestone history is condensed into §7 below, and the v4 candidate
backlog is frozen (§4). All four remain in git history.

| Doc | What it's for |
|---|---|
| **ROADMAP.md** (this file) | Vision, current state, the milestones being built now, process. **Start here.** |
| [docs/design/GDD.md](docs/design/GDD.md) | The v1 design document, archived. §N section numbers preserved — code comments cite `GDD §11` etc. Historical reference, **not** a roadmap. |
| [Product_reqs.md](Product_reqs.md) | The owner's raw feature requests. Subculture source-of-truth. Do not paraphrase it away. |
| [CHANGELOG.md](CHANGELOG.md) | What each milestone actually shipped. |
| [FEATURES.md](FEATURES.md) | Feature-by-feature implementation status. |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System map, signal flow, data schemas. **Read before touching code.** |

---

# 1. Where we are

Milestones 1–32 are complete: three districts, 25 paintable walls, 15
autoload managers, save v12, a headless smoke test, and a data-driven
content pipeline. The engineering is genuinely solid — one event hub
(`WallManager.wall_painted`), JSON content, versioned saves with
migration, performance budgets, and an Ollama agent harness.

**A July 2026 design review found the problem: the core verb has no game
in it.**

In `player.gd:552`, painting is `_try_interact()` → `paint_wall()` → a
number. No duration, no input, no skill, no failure. You cannot paint
badly. Fifteen managers of consequence fan out from an event that is, in
itself, a keypress. Everything downstream — heat, territory, rivals,
crews, morale, loyalty, trains, gallery, duels, the nightclub — reacts
to something that isn't interesting on its own.

Three findings drove this replan:

1. **The core verb is a keypress.** Painting must become a continuous,
   physical, skill-expressing act with real failure. This is the whole
   plan.
2. **Style is claimed, never authored.** The visual payoff of the entire
   fantasy is a `Label3D` of your alias in a licensed font. The player
   picks their identity from a dropdown. In a game whose fantasy leads
   with *style*, the player cannot make any.
3. **The quality gate cannot fail.** `SMOKE_TEST=1` prints an assertion
   failure and then prints `SMOKE: OK` and exits 0. Godot's `assert()`
   doesn't abort headless and nothing checks. Every "✅ covered by
   smoke" claim is currently unverified. **M35 fixes this first.**

## The scope decision

The old framing — *"open-world graffiti RPG inspired by Fallout 4 and
Starfield"* (GDD high concept) — **is retired.** Those games cost
200–400 person-years. This project has one developer with an AI-assisted
pipeline. Chasing that comparison guarantees a shallow imitation of a
genre where shallow is fatal.

**The new framing:** a small, dense, hand-made game about one writer,
one neighbourhood, and one summer. Not a city — eight blocks you come to
know like your own street. The whole game is the act of painting.

Games that win at this scale — Obra Dinn, Papers Please, Inscryption,
Outer Wilds — win on one unforgettable verb and a specific voice. Never
on breadth. Every one of them would have been destroyed by a fourth
district.

---

# 2. Vision

**Working title:** *Blackbook* (already on the GDD's alternatives list;
it names what the game is actually about).

**The pitch:** You author your own hand in a blackbook. You spend the
game learning to reproduce it — cleanly, at speed, in the dark, with
your heart going. The city buffs you. You go back.

## Design pillars

1. **The can is the controller.** Painting is continuous, physical, and
   skill-expressing, with real failure. If a mechanic doesn't run
   through the can, question whether it belongs.
2. **Your hand is yours.** The player authors their signature and spends
   the game learning to execute it. Style is made by the player, never
   selected from a list.
3. **The wall remembers.** Every surface carries its history, visibly and
   permanently. The city is a save file you can walk through.
4. **Pressure, not punishment.** Heat is a spotlight that makes your
   hands shake, not a stat that fines you. Getting caught is a story;
   being fined is a chore.

## Player fantasy

> "I made that. It's still there. Everyone who walks down this street
> sees my hand, and I got better at it while you watched."

Note the change from the GDD's *"I am becoming known"* — becoming known
is a number going up. Making a mark is an act. The revised fantasy is
buildable by one person.

## The signature moment

You are 70% through the best piece you've made. Headlights. Bail now with
an unfinished piece that will be crossed out by morning, or spend eleven
more seconds on the fill and probably get caught. **Every system exists
to make those eleven seconds matter.**

## What this must not become

* **An open world.** Eight blocks, hand-authored. Not a city.
* **A drawing app.** The can lives in the world, not in a modal.
* **A management sim.** Morale, loyalty, deliveries, upkeep — cut.
* **Tony Hawk with spray cans.** No combo meters, no score popups.
* **A crime game.** Graffiti's meaning is authorship, not vandalism. The
  moment there's a wanted level it's a worse GTA.

---

# 3. The next 10 milestones (M35–M44)

Sequenced. **Do not reorder.** Each is a separate PR following the dev
loop in [CLAUDE.md](CLAUDE.md).

**Scope rule for this phase:** none of these require hiring. Art
direction, audio direction, and a writer consultant are the three gaps
that need people, and they are deliberately excluded — every milestone
below is code, data, or shader work that an agent can land.

## The feel/machine split — read this before M37

The one thing an implementation agent cannot do is *tune game feel*.
Iterating on "does this spray feel good" requires hands on a controller
and taste.

**So the split is: the agent builds the machine, a human turns the
knobs.** Every feel constant — spray radius, falloff curve, drip
threshold, pressure ramp, distance range — lives in **`Data/can.json`**
and nowhere else. No magic numbers in `can.gd`. This follows the
existing data-driven rule (agent rule 3) and it is what makes M37–M39
buildable without a designer in the loop.

If you find yourself writing a float literal that affects how spraying
feels, it belongs in `can.json`.

---

## M35 — Make the gate able to fail 🔴 **Do this first**

**Why:** every merge gate in this project's history has been
green-by-construction. Nothing below can be trusted until this lands.

**Files:** `Scripts/district.gd`

**Build:**
* Add `var _smoke_failures: Array[String] = []` and a helper
  `func _check(condition: bool, message: String) -> bool` that appends to
  `_smoke_failures` and returns the condition.
* Replace every `assert(...)` inside a `_smoke_*()` function with
  `_check(...)`. There are ~60 sites. Mechanical.
* Where a failed check would cascade into a crash (null deref on the next
  line), `return` early from that `_smoke_*` function.
* `_run_smoke_test` prints each failure, then `SMOKE: FAILED (N checks)` +
  `get_tree().quit(1)`, or `SMOKE: OK` + `quit(0)`.
* Fix or revert the currently-failing assertion at `district.gd:2436`
  (`local.active_goal_id() == "route"`), which the uncommitted
  `Scripts/AI/goal_stack.gd` WIP broke.

**Done when:** deliberately breaking one assertion makes the run print
`SMOKE: FAILED` and exit non-zero. Then run it clean and **report what
else was silently red** — that list is real information.

**Do not:** fix any other system in this PR. Just make the gate honest and
report what it finds.

---

## M36 — Paint render targets

**Why:** `Label3D` decals cannot layer, blend, drip, or hold a hand. Every
milestone after this needs a real paint surface. This is also the
technical spike that decides whether the whole plan is viable.

**Files:** new `Scripts/Walls/paint_surface.gd`; `paintable_wall.gd`;
`wall_manager.gd`; `save_manager.gd`; `playtest_metrics.gd`

**Build:**
* `PaintSurface`: owns one `Image` + `ImageTexture` per wall, sized from
  the wall's face at a configurable pixels-per-metre (start 96, same as
  `freehand_panel.gd`). Applied as an unshaded overlay on the wall's front
  face.
* `world_to_uv(hit: Vector3) -> Vector2` — project a world-space raycast
  hit onto the wall face's UV. This is the load-bearing function; unit
  test it in `Test_GraffitiWall.tscn`.
* Keep the `Label3D` path behind `WallManager.USE_PAINT_SURFACE` so the
  existing game still runs while this is built.
* Save: painted walls store base64 PNG in `wall_states`, same as freehand
  does today. **Bump `SAVE_VERSION` to 13** + migration.
* Extend `RUNTIME_BUDGET` output with `paintTextureMemoryMB` and
  `saveSizeKB`.

**Done when:** all 25 walls carry a paint surface; a test pattern written
through `world_to_uv` lands where the ray hit; save round-trips; the
budget line reports texture memory and save size.

**Report:** the memory and save-size numbers. **If 25 walls cost more than
~150 MB of texture or the save exceeds ~5 MB, stop and report** — that
changes the plan (tile the textures or drop pixels-per-metre).

---

## M37 — The Can: deposition

**Why:** this is the milestone the whole project exists for.

**Files:** new `Scripts/Player/can.gd`, new `Data/can.json`;
`player.gd`; `paint_surface.gd`

**Build:**
* Hold `interact` (LMB / trigger) → continuous deposition onto the focused
  wall's `PaintSurface` at the camera ray's hit UV, every physics frame.
* **Distance → line width and opacity.** Closer is tighter and denser;
  further is wider and more translucent. Range and curve from `can.json`.
* **Angle → elliptical footprint.** Spraying obliquely stretches the
  stamp along the incidence direction.
* **Deposition is rate-based, not per-frame-fixed** — a fixed
  alpha-per-frame makes the framerate the paint rate. Multiply by `delta`.
* Interpolate between last frame's UV and this frame's so fast strokes
  don't dot.
* Every constant in `can.json`: `pixelsPerMeter`, `minDistance`,
  `maxDistance`, `minRadius`, `maxRadius`, `falloffExponent`,
  `flowRatePerSecond`, `opacityPerSecond`, `angleStretchMax`.

**Done when:** you can walk to a wall, hold the trigger, and paint a
continuous stroke whose width and density change as you move closer,
further, and off-axis. **No rep, no paint cost, no heat — not yet.**

**Do not:** add drips, paint limits, caps, or rep in this PR. Deposition
only.

---

## M38 — The Can: caps, paint, and drips

**Why:** this is where spraying becomes a skill you can fail at.

**Files:** `can.gd`, `can.json`, `caps.json`, `supply_manager.gd`,
`sfx.gd`

**Build:**
* **Finite paint per can + a pressure curve.** Paint level drops with
  deposition; below a threshold, flow and opacity fall off (`can.json`).
  A cold can needs a rattle-prime that costs ~1s.
* **Caps become physical.** Rewrite `Data/caps.json`: each cap carries
  `radiusScale`, `flowScale`, `falloffExponent`, `stretchScale`. **Delete
  the `repMultiplier` / `paintCostDelta` fields** — a cap is a stroke
  decision, not a rep scalar.
* **Drips.** Deposition into an area already above a saturation threshold
  spawns a drip: a point that runs down the surface under gravity, laying
  paint, decelerating, drying. `dripSaturationThreshold`, `dripGravity`,
  `dripDryTime` in `can.json`.
* **Skips.** Moving the aim point faster than `maxCleanSpeed` thins
  coverage.
* Spray hiss gets pitch/volume driven by pressure and flow.

⚠️ **Design conflict — flag, don't resolve alone.** `Product_reqs.md` says
*"lose the paint drip lines."* That request was about **decorative** drips
drawn under `Label3D` text, which looked fake. These are **earned** drips
caused by the player over-dwelling — a failure state, not decoration.
They are different things and the review argues the second is the point.
**Ask the owner before building drips.** If the answer is still no, ship
M38 without them; the can survives.

**Done when:** the same player painting the same word with a skinny cap
and a fat cap produces visibly different walls. Over-dwelling ruins a
stroke. Running out mid-letter is possible and feels bad.

---

## M39 — The Can Lab + the feel gate 🔴 **Human gate**

**Why:** the project has never had an honest gate. This one decides
whether the next two years are worth starting.

**Files:** `Scenes/Test_GraffitiWall.tscn`, `district.gd`,
`playtest_metrics.gd`, `agent/pilot.py`, `Scripts/Debug/agent_server.gd`

**Build (agent):**
* `CAN_LAB=1` boots `Test_GraffitiWall.tscn` directly: one wall, one can,
  full cap set, **no HUD, no rep, no heat, no missions, no paint cost.**
  Just a person and a wall.
* `PlaytestMetrics` records can telemetry: stroke count, stroke length,
  drip count, paint used, time-on-wall, cap switches, distance histogram.
* Add `POST /act` verbs to the agent server so the Ollama pilot can spray
  — cheap regression coverage that the can still works.
* Smoke coverage for the lab boot + telemetry write.

**Run (human — this is not an agent task):**
> **Five strangers each paint one wall for five minutes with no UI. Three
> of them ask to paint another.**

**Exit criteria:** if they don't ask, **the project does not proceed to
M40.** Iterate on `can.json` — that's what it's for — or stop. This is the
line. Every previous milestone gate in this project was a wish; put this
one in a calendar with names in it.

**Do not:** start M40–M44 until this passes.

---

## M40 — Cut the accretion

**Why:** every system built on the old framing is a system that fights the
new one. Cut now, while the cutting is cheap.

**Files:** `crew_manager.gd`, `supply_manager.gd`, `territory_manager.gd`,
`nightclub.gd`, `nightclub_panel.gd`, `hud.gd`, `save_manager.gd`, several
`/Data` files

**Remove:**
| System | Why |
|---|---|
| Crew morale (`crew_morale_events.json`) | A ±10% scalar on a passive bonus. Imperceptible. |
| Crew loyalty scaling | Same. Keep members, cut the arithmetic. |
| Delivery runs | Carrying a box for $25 is a chore in a game about art. |
| The nightclub (`nightlife.json`, The Undertow) | Well built, fully orthogonal. Your own M32 paper cut said so. |
| Territory influence % + claim thresholds | A spreadsheet. The *feeling* of a block being yours comes from looking at it. |
| Cash economy | Reduce to paint scarcity. Delete `cash`. |

**Keep:** crew members as *presence* (Moth on the corner means you paint
calm), the gallery as a *character* (Vesper's sell-out tension is real —
it just needs to stop being two numbers), trains (best idea in the build;
it deserves to become an act later).

**Build:** `SAVE_VERSION` → 14 with a migration that drops the removed
sections cleanly. Delete the dead smoke sections. Update FEATURES.md and
README.md in the same PR.

**Done when:** smoke passes, a v13 save migrates to v14 without error, and
the removed systems leave no dangling references.

---

## M41 — Heat as pressure

**Why:** heat is well built and does the wrong job. It fines you 25 rep and
closes the incident. Being fined is a chore; nearly getting caught is a
story. This is a redesign of *meaning*, not of code.

**Files:** `heat_manager.gd`, `can.gd`, `patrol_guard.gd`, `sfx.gd`,
`hud.gd`

**Build:**
* **Heat modulates the can.** Higher heat → aim sway, deposition jitter,
  a shakier hand. You paint *worse* when scared, which makes it worse.
  Curve in `can.json` (`heatSwayMax`, `heatJitterMax`).
* **Audio-led escalation.** Footsteps, radios, sirens rising with heat.
  The player should look up before any UI tells them anything. Synthesized
  is fine for now — this is the one place placeholder audio still earns its
  keep.
* **Caught = lose the night**, not a rep fine. You keep whatever you'd
  already sprayed; it stays on the wall, unfinished, until you go back.
* **Delete the HUD heat readout.** If the player needs a number to know
  they're in danger, the system failed.

**Bail is not a feature.** With continuous painting it emerges for free —
you leave, and whatever you sprayed is what's on the wall. Don't build a
system for it. Just make sure the wall keeps partial work and heat doesn't
reset when you walk away.

**Accessibility (required, not optional):** hand-shake must be fully
disableable. It's a motor-accessibility issue, not a difficulty knob.
Assist mode substitutes a visual tell.

**Done when:** a tester says "I almost got caught" before they say "I got
40 rep."

---

## M42 — The city remembers

**Why:** this system is already built, working, tested, and **invisible**.
`wall_states` carries 20 entries of history per wall and the player never
sees any of it. Cheapest high-value item in the plan — presentation on top
of finished engineering.

**Files:** `paint_surface.gd`, `paintable_wall.gd`, `wall_manager.gd`,
`blackbook_panel.gd`

**Build:**
* **Layering is nearly free with M36.** New paint composites over old on
  the same texture. Blend at slightly under 1.0 alpha so older work ghosts
  through — that's the whole effect.
* **Buffs become paint, not a state flag.** `buff_wall()` composites a
  municipal-grey rectangle onto the surface. Get the palette from photo
  reference: **the grey never quite matches the wall, and that wrongness is
  the entire point.**
* **Wall inspection.** Look at a wall, hold a key, read the history that's
  already in the dict — who painted it, when, what's under there.
* **Photo mode → blackbook.** Capture a framed shot into a dated, located
  blackbook page. This is the marketing engine and it costs almost nothing.
* **Bound the cost.** History is capped at 20; keep that discipline for
  layers. If a wall painted 40 times blows the budget, composite-and-flatten
  older layers rather than storing each.

**Done when:** a wall painted 20 times shows its strata; your first tag is
still there at hour 10 and it's embarrassing; a player can reconstruct
their session by walking the block.

---

## M43 — The Hand: capture

**Why:** the mechanic nobody else has. It converts the font-licensing
liability into the best idea in the game.

**Files:** `blackbook_panel.gd`, new `Scripts/Player/hand.gd`,
`game_state.gd`, `save_manager.gd`, `paint_surface.gd`

**Build:**
* Blackbook hand editor: draw your tag. Capture **vector strokes** —
  ordered arrays of points with timing and per-point pressure. Not a
  bitmap.
* Store in `GameState.player_hand`; `SAVE_VERSION` → 15.
* **Render the hand as strokes on the wall**, through the same
  `PaintSurface` deposition path the can uses — so your tag is *sprayed*,
  not stamped. This replaces `Label3D` alias text.
* Undo, clear, restart-my-hand. No time pressure, no scoring — the
  blackbook is the safe place.
* Works with mouse, stick, and touch.

**No fidelity scoring in this PR.** Capture and render only.

**Accessibility:** a pick-a-preset-hand path for players who don't want to
draw. ⚠️ Note the trap: if the preset list is just the 16 licensed fonts,
we've rebuilt the original problem. Presets should be *hand-drawn vector
hands*, few and characterful.

**Done when:** you draw a tag in the blackbook, walk outside, and spray
your own handwriting on a wall.

---

## M44 — The Hand: fidelity ⚠️ **Highest risk — 4-week kill date**

**Why:** this is what makes the hand a *skill* rather than a decal.

**Files:** `hand.gd`, `wall_manager.gd`, `stats_manager.gd`

**The risk, stated plainly:** fidelity scoring is a research problem. Get
it wrong and it feels arbitrary and punishing — worse than no system.
**Prototype in a 2D toy first, before it touches the game. Set the kill
date on day one.** If it isn't working after four weeks, cut it and ship
the can alone. The game survives without this; it does not survive a
scoring system players find unfair.

**Build — the algorithm is specified so it doesn't need invention:**
1. Resample each stroke of both hands (canonical and street execution) to
   a fixed N = 64 points by arc length.
2. Normalize: translate to centroid, scale to unit bounding box. Position
   and size on the wall must not matter — only shape.
3. Per-stroke distance = mean Euclidean distance between corresponding
   resampled points.
4. Penalties: stroke-count mismatch, stroke-order mismatch.
5. Fidelity = `clamp(1.0 - (weighted distance + penalties), 0.0, 1.0)`.
6. All weights and tolerances in `Data/hand.json`.

**Wire it:**
* Fidelity → rep. **Retire `WallManager.freehand_style_multiplier`
  entirely.** It currently rewards scribbling every colour across every
  grid cell — the dominant strategy is the opposite of good graffiti, and
  Vesper uses it as her aesthetic judgment.
* Heat-induced sway (M41) degrades fidelity naturally. That's the loop
  closing: danger → shaky hand → worse letters → less rep. No extra code.
* Style stat raises the *ceiling* (a steadier hand), never the score
  directly.

**Done when:** a player's hour-10 tag is measurably and visibly cleaner
than their hour-1 tag on the same wall, **with no stat having changed** —
they just got better.

---

# 4. Not in this phase

## Needs hiring — deliberately excluded

| Gap | Why it's excluded | When |
|---|---|---|
| **Art direction** | AI-generated meshes will not carry a game whose subject *is* visual style. Biggest gap; least fixable with code. | After M39 passes |
| **Audio direction** | Zero assets in a music-defined genre. | After M39 passes |
| **A real writer, consulting** | `Product_reqs.md` proves the interest is genuine; a practitioner turns interest into authority. | After M39 passes |

Start the art-director search early anyway — it has the longest lead time
of anything in this document.

## Owner actions (not agent tasks)

* **Font licence audit.** `FFCommaTrial-Regular.ttf` is a *trial* licence
  and it's the default toy hand every new player sees.
  `StreetToxicDemo.otf` is a *demo* build. Neither is commercially
  licensed; there are no licence files in the repo. The other 14 need
  individual verification, and games need an *embedding* licence, which is
  a separate grant from desktop use. **Don't buy anything yet** — M43/M44
  may make most of this moot.
* **Run the M39 feel gate.** Five strangers. Calendar. Names.
* **Answer the drip question in M38.**

## Do Not Build Yet

Carried forward and still true: full city, multiplayer, complex combat,
procedural world generation, full faction diplomacy, large quest trees,
character creator, vehicles, online sharing.

**Added by the review:** fourth district, day/night, weather, paint mixing,
safehouse decoration, outfit accents, crew side-missions, rival alliances,
duel ladders, named rival writers, sketch-motif reuse.

## The old v4 backlog — frozen

`Plan_v4.md` ranked 30 candidates. **All 30 are frozen.** Most were
`[plumbing]` on systems whose foundation had never been tested — the exact
trap that document warned about ("speculative features without tester
evidence") and then fell into. Three survive, re-scoped, inside the
milestones above: difficulty presets (built, retarget onto accessibility
assists at M41), photo capture (M42), MultiMesh street detail (revisit
after M36 changes the render picture). The rest are deferred without
prejudice — they're recorded in git history if they're ever needed again.

---

# 5. Process

Unchanged, and it works. The one addition: **the gate can now fail (M35),
which means it means something.**

## Dev loop

```
branch → implement + extend smoke coverage → 3 clean smoke runs
→ 1 windowed boot → PR → multi-angle review → fixes → user merges → pull main
```

Direct push to `main` is blocked. Update README and CHANGELOG in the same
PR as the feature.

## Commands

```sh
# Run windowed
/Applications/Godot.app/Contents/MacOS/Godot --path .
# Headless smoke test — after M35 this exits non-zero on failure
SMOKE_TEST=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path .
# Boot check that self-quits
/Applications/Godot.app/Contents/MacOS/Godot --path . --quit-after 300
# The Can Lab (after M39)
CAN_LAB=1 /Applications/Godot.app/Contents/MacOS/Godot --path .
```

## Branch naming

`feature/milestone-35-smoke-gate`, `feature/milestone-36-paint-surface`, …

## PR template

```
## Summary
- What changed
- Why this milestone needed it

## Testing
- [ ] Smoke run 1  - [ ] Smoke run 2  - [ ] Smoke run 3
- [ ] Windowed boot

## Review Notes
- Risky files or systems
- Data/schema changes
- Save migration notes
- Follow-up intentionally left out
```

## Multi-angle review

1. **Player experience** — clarity, pacing, feedback, friction.
2. **Architecture** — data flow, manager ownership, signals, saves.
3. **Test** — smoke coverage, determinism, soft-lock coverage.
4. **Content** — data consistency, naming, copy, world placement.
5. **Performance** — node/material churn, texture memory, runtime cost.

## Agent rules (from GDD §47 — still load-bearing)

1. Do not attempt to build the full game at once.
2. Prioritize playable systems over visual polish.
3. **Keep all major systems data-driven.** (This is what makes the
   feel/machine split work — see §3.)
4. Use placeholder art until systems work.
5. Make walls persistent as early as possible.
6. Make rival reactions simple but visible.
7. Avoid scope creep.
8. Document every major system.
9. Create test scenes for each mechanic.
10. Maintain a running changelog.

## Engine gotchas

* **Headless class cache:** fresh headless runs don't rebuild the global
  `class_name` cache — new cross-file script references must use
  `preload("res://...")`, not the bare class name.
* **Paint only through WallManager** (`paint_wall`, `paint_freehand`,
  `apply_rival_graffiti`, `buff_wall`) — the whole game hangs off
  `wall_painted`. Never mutate `wall_states` directly. **M36–M38 must
  respect this**: the can deposits into `PaintSurface`, but the *commit* at
  stroke end still routes through `WallManager`.
* **Save schema changes bump `SAVE_VERSION`.** Wall-state dicts stay
  JSON-serializable.
* `Sfx` self-disables headless and must stay last in autoload order.

---

# 6. Success criteria

The phase succeeds if, after M44, a tester says:

* "I could tell my hand was getting better."
* "I almost got caught and I bailed and it stayed on the wall like that."
* "They buffed my best piece and I was actually annoyed."
* "That's *my* tag. I drew that."
* "I want to paint another wall."

The old GDD §46 criteria ("I understand why painting this wall matters")
are retired — they were satisfied by a keypress and a number, which is how
the project got here.

---

# 7. Engineering history

Condensed. Full detail in [CHANGELOG.md](CHANGELOG.md) and git history.

| Phase | Milestones | Shipped |
|---|---|---|
| **v1** — vertical slice | 1–14 | Paintable walls, rep/ranks, rival cross-outs, crew recruit, territory, 5-mission chain, heat, patrols, supply economy, dialogue, blackbook, map, freehand canvas |
| **v2** — playable demo | 15–26 | Engineering hardening (modal registry, `ui_kit`, unified paint path, history cap, `DataLoader` validation, save migration), full graffiti type set + surface rules, stats/perks/decay, Canal Side, rooftop climbing, train painting, gallery, crew depth, presentation pass, material cache + LOS, ambient NPCs, Rooftop Row |
| **v3** — playtest-ready | 27–32 | `PlaytestMetrics`, balance pass + regression ledger, procedural rival variety, rooftop polish, runtime budgets, battle paper cut (decided: no separate minigame) |
| **v3** — abandoned | 33–34 | Playtest feedback + demo candidate. **Superseded** — the July review made them moot. The thing to playtest is the can (M39), not the current build. |
| **v4** — candidate backlog | — | 30 candidates, **all frozen.** See §4. |

All of the old v2 engineering findings landed: the modal registry, `ui_kit`,
split smoke test, unified paint head, history cap, `DataLoader` validation,
save migration, shared model loader, material cache, data-driven visuals,
and interaction line-of-sight. Code comments that used to cite
`Plan_v2.md §3.x` now cite `ROADMAP.md §7` and point here.

## A note on citations

Live code comments and reference docs were rewritten on 2026-07-15:
`Plan.md §N` → `GDD §N` (the archive preserves the numbering), and
`Plan_v2/3/4.md` → `ROADMAP.md`.

**`CHANGELOG.md` and the dated notes in `docs/` were deliberately left
alone.** They are historical records — an entry written on 2026-06-12 that
cites `Plan_v2.md` should keep saying so, because that's the document that
existed when the work shipped. Rewriting history to reference a file that
didn't exist yet would be a lie that costs more than the broken link. If a
link there doesn't resolve, that's expected: read it as a date-stamped
artifact, and check git history for the file it names.

---

# 8. Open questions

Not blockers, but they shape what comes after M44:

* **Is this commercial or craft?** Everything above assumes you want it to
  be great. If it's a learning exercise, the old path was fine.
* **First person or third?** Third-person is built, but the can wants to be
  close to the wall. **Let M37 answer this** — it's a finding, not an
  opinion.
* **What's the ending?** "Legend" is a rep threshold, which isn't an
  ending. The review's suggestion: a walk through a year of your own work.
  M42 stores everything needed to build it.
* **Whose story is this?** The rooster is a placeholder with no interiority.
  Does this game have something to say about authorship, or is it a
  sandbox? Both are valid; they're different games.
