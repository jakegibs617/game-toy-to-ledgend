# Toy to Legend — Consolidated Feature Doc

One place that merges the four planning sources into a single feature
ledger with implementation status. It does **not** replace them:

* **[Plan.md](Plan.md)** — original v1 design doc (cite as `§N`).
* **[Plan_v2.md](Plan_v2.md)** — v2 roadmap, milestones 15–26 (shipped).
* **[Plan_v3.md](Plan_v3.md)** — v3 roadmap, milestones 27–34 (in progress).
* **[Product_reqs.md](Product_reqs.md)** — loose follow-up requests
  (ladder, idle anims, tag fonts/styles, gear suspicion, stickers,
  drips, dance/DJ).

System map and data schemas live in
**[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**; per-milestone history
is in **[CHANGELOG.md](CHANGELOG.md)**.

Status as of 2026-06-13, on branch `feature/random-idle-animations`
(current main is merged through PR #31).

## Status legend

| Mark | Meaning |
|---|---|
| ✅ | Complete and covered by smoke/gameplay |
| 🟡 | Partial — core in, gaps noted |
| ❌ | Not implemented |
| 🔒 | Deliberately deferred ("Do Not Build Yet") |

---

## 1. Milestone ledger

### v1 — Vertical slice (Plan.md, Milestones 1–14)

| # | Milestone | Status |
|---|---|---|
| 1–7 | Setup → paintable walls → rep/inventory → rival reactions → crew recruit → territory → 5-mission chain | ✅ |
| 8 | Polish pass (UI, SFX, save/load) | ✅ |
| 9–13 | Should-Have: heat, patrols, supply economy, dialogue, blackbook, map | ✅ |
| 14 | Freehand spray painting (first Could-Have) | ✅ |

### v2 — Playable demo (Plan_v2.md, Milestones 15–26)

| # | Milestone | Status |
|---|---|---|
| 15 | Engineering hardening (modal mgr, ui_kit, unified paint path, history cap, data validation, save migration) | ✅ |
| 16 | Full graffiti type set: stencil, roller/blockbuster, mural + surface rules | ✅ |
| 17 | Progression depth: Style/Stealth/Hustle stats, perk choices, rep decay | ✅ |
| 18 | Second district: Canal Side + per-district heat + travel | ✅ |
| 19 | Rooftop climbing (climb zones, fall penalty) | ✅ |
| 20 | Train painting — the signature pass-through-rep moment | ✅ |
| 21 | Gallery missions (Vesper, sell-out tension) | ✅ |
| 22 | Crew depth: Caps (filler) + Metro (getaway), crew board, data-driven visuals | ✅ |
| 23 | Presentation pass: title/alias, controller bindings, music/ambience | ✅ |
| 24 | World render & data hardening: material cache, LOS check | ✅ |
| 25 | Ambient NPC life: waypoint locals, crowd reactions, guard climb | ✅ |
| 26 | Rooftop Row — climb-only third district | ✅ |

### v3 — Playtest-ready slice (Plan_v3.md, Milestones 27–34)

| # | Milestone | Status |
|---|---|---|
| 27 | Playtest instrumentation & balance baseline (`PlaytestMetrics`, snapshot) | ✅ PR #25 |
| 28 | Balance pass 1 — main path (`docs/BALANCE_TARGETS.md`) | ✅ PR #26 |
| 29 | Procedural rival graffiti variety (deterministic, seeded) | ✅ PR #27 |
| 30 | Rooftop traversal polish (context prompts, hazard tells) | ✅ PR #28 |
| 31 | Performance & runtime budget pass | ✅ PR #34 |
| 32 | Battle prototype paper cut (dance/rap) | ❌ not started |
| 33 | Playtest feedback pass | ❌ not started |
| 34 | v3 demo candidate (freeze + tag) | ❌ not started |

---

## 2. Feature catalog by system

### Core loop & progression (Plan.md §4, §5)
* ✅ Explore → paint → rep → heat/rival response → upgrade → claim loop.
* ✅ Reputation ranks (Toy → Legend) with rank-gated unlocks.
* ✅ XP separate from rep for Style/Stealth/Hustle (raise by doing).
* ✅ Public rep vs crew rep split (crew rep cost on gallery sales).
* 🟡 Stats: only **Style/Stealth/Hustle** of the §6 seven (Nerve, Speed,
  Influence, Technique not modeled — folded into existing three).
* 🟡 Perks: one choice per rank-up, ~2 per tree — a chooser, **not** the
  full §7 tree editor.

### Graffiti types & surface rules (Plan.md §8, §9)
* ✅ Tag, throw-up, piece, stencil, roller/blockbuster, mural — all with
  per-type `baseValue`/`paintCost`/`heatValue` in `graffiti_styles.json`.
* ✅ Surface rules: roller is `rooftop`-only; mural `requiresCrew` + long
  exposure; stencil needs the bought kit.
* ✅ Freehand spray-painting canvas (Milestone 14) + gallery reuse.

### Tag font styles, practice & gear (Product_reqs.md)
* ✅ Tag-lettering font library (`graffiti_font_library.gd` +
  `Data/graffiti_font_styles.json`) implementing the Product_reqs
  mapping table: each style has `level`, `family`, `tool`,
  `practiceRequired`, plus the default toy hand (`ff_comma_trial`).
* ✅ **Practice-before-outside**: `GameState.practice_tag_font_style`
  requires Style level + 5 blackbook practice reps before a non-toy
  style unlocks for street use.
* ✅ **Practice reduces TOY overwrite risk**: `toy_response_multiplier`
  lowers rival cross-out likelihood per practice rep (to a floor).
* ✅ **Gear suspicion**: `gear_suspicion_multiplier` raises patrol
  suspicion for carrying many cans + a stencil + per-font `gearSuspicion`.
* ✅ **Bespoke style behaviors wired:** `scratch_hand` (`glass`,
  `oneColor`, `opacity: 0.5`) gates to glass surfaces and renders as a
  faint greyscale scratch; acid `hand` styles (`glass`,
  `orientations: [horizontal, vertical]`) gate to glass and run vertical
  on tall glass panels. Enforced via `WallManager.font_style_block_reason`
  + `GraffitiFonts.render_plan`, consumed by `paintable_wall.gd`, with a
  `glass` surface type + a territory-neutral storefront window.
* ✅ **Wildstyle exposure fully wired:** exposure raises heat + patrol
  attention (M16) *and* pays a rep bonus on `heavenSpot` walls
  (`WallManager.heaven_spot_exposure_bonus` × `GraffitiFonts.style_exposure`).

### Walls & world memory (Plan.md §9, §31)
* ✅ Wall state machine (blank/player/rival/crossed-out/buffed) with
  history, capped at 20 entries, JSON-serializable.
* ✅ All paint routed through `WallManager` (`wall_painted` hub).
* ✅ Wall properties: visibility, risk, surfaceType, owner crew.

### Reputation, heat & territory (Plan.md §11, §12, §24)
* ✅ Rep formula: base × visibility × risk × heat (× freehand style mult).
* ✅ Rep decay: unattended districts cool; buffed/crossed work stops paying.
* ✅ Per-district heat, levels, patrol scaling, city cleanup buffing.
* ✅ Territory influence shares, claim thresholds, district_claimed.

### Rival crews (Plan.md §13)
* ✅ Three crews (Buff Kings, Ghost Line, Chrome Saints) with territory,
  cross-outs, retaliation queue, the **TOY** mechanic.
* ✅ 30-second retaliation floor + visible `RivalTagger` run-up
  (windowed) that sprays then flees.
* ✅ Deterministic procedural rival graffiti variety (Milestone 29),
  seeded by graffiti/crew/type — no stored image blobs.
* ✅ Rival tagger uses Hooded Fox Warrior model (run→idle for the tag).
* ❌ Rival alliances / recruiting rivals / direct challenge duels.

### Crew (Plan.md §14)
* ✅ Moth (lookout), Caps (filler), Metro (getaway) with recruitment
  mini-chains and passive role bonuses.
* ✅ Crew board in safehouse (opens blackbook Crew page).
* ❌ Remaining roles: Supply Runner, Hype, Battle Specialist, Fixer;
  loyalty/morale/upgrade paths.

### Missions (Plan.md §15, §16)
* ✅ Data-driven mission chains (`missions.json`), triggered in order
  (e.g. enter_district), with animated mission actors and cross-outs.
* ✅ Mill Yard core chain, Canal Side chain, Rooftop Row chain.
* ❌ Larger branching quest trees (deferred).

### Districts & world (Plan.md §17, §45)
* ✅ Three runtime-built districts: Mill Yard, Canal Side, Rooftop Row.
* ✅ Procedural street detail, surface-type materials, train siding.
* 🔒 Fourth+ districts (Downtown, Train Yard proper, Gallery Quarter,
  Substation) deferred until after v3 candidate.

### Economy & supplies (Plan.md §21)
* ✅ Cash + paint resources; Lupe's shop; paint discounts; delivery runs;
  rare colors; fat cap upgrade; stencil kit.
* ✅ Gallery cash + train pass-through rep as alternate income.
* 🟡 Caps as a spray-behavior modifier system (only fat cap exists; not a
  full cap inventory). Mops/markers/rollers/gloves/masks not modeled.

### Blackbook, map & safehouse (Plan.md §22, §23, §24)
* ✅ Blackbook (alias, rank, crew, styles, missions, rivals, service log)
  + tag-style practice page.
* ✅ District map panel; safehouse mission/crew-board zone.
* ❌ Sketch editor, room customization, outfit change, sleep-to-skip.

### NPCs, dialogue & ambient life (Plan.md §25, §26, §44)
* ✅ Civilians/writers/security/cleanup; choice-based dialogue with
  rank/recruit checks.
* ✅ Ambient locals (waypoint loops, crowd reaction rep, heat scatter).
* 🟡 Many imported NPC walk/run clips still unused beyond ambient locals.

### Player presentation & animation (Plan.md §28, §40; Product_reqs.md)
* ✅ Kronako neon rooster action set: idle/walk/backpedal/run/jump/ladder.
* ✅ **Interactive ladder climb** (Product_reqs): real ladder geometry,
  ride by hand, reversible up/down, summit finish clip.
* ✅ **Random idle rotation** (Product_reqs): picks one of several idle
  clips per settle, holds the stance for the idle.
* 🟡 Vault/turn-variant/sprint-stop clips imported but not triggered.

### Audio (Plan.md §28)
* ✅ Synthesized SFX, low music bed, per-district ambience (Sfx autoload,
  self-disables headless).

### Save/load (Plan.md §32)
* ✅ Versioned save (`SAVE_VERSION`, currently v6 era) with per-version
  migration; wall_states round-trip wholesale.

### Stickers & wheatpaste (Product_reqs.md)
* ✅ **Paper lane:** `sticker` (cheap, near heat-free slap) and `wheatpaste`
  (poster, more rep for the size) types, both `paper`-flagged with no surface
  restriction and a paper-backed render.
* ✅ **Art-school unlock:** Indigo the printmaker (rank-gated to Up) teaches
  both via a one-time dialogue lesson (`unlockTypes` dialogue effect).
* ✅ **Gear suspicion:** the paste bucket adds bulk; stickers stay flat.

### Battles & nightlife (Plan.md §19, §20; Product_reqs.md)
* ❌ Graffiti battles, dance battles, rap battles — unbuilt (Milestone 32
  is a paper-cut decision, not yet started).
* ✅ **Dance / club / DJ rep-based invite** (Product_reqs): rep-gated
  nightclub (`nightlife.json` + `nightclub.gd`); bouncer turns away writers
  below `minRank`, cover charge to enter, and a beat-matching DJ-set modal
  (`nightclub_panel.gd`) whose hype scales a Style/crew/cash payout. Best
  hype persisted per club (`GameState.nightlife_best`, save v7).

---

## 3. Product_reqs.md item-by-item

| Request | Status | Notes |
|---|---|---|
| Ladder looks like a ladder, climb anim, reversible up/down | ✅ | Interactive ladder climb |
| Random idle animations for main character | ✅ | Idle rotation |
| Tag-style font mapping (against-myself→L1 throw, etc.) | ✅ | `graffiti_font_styles.json` |
| Hand / throw / wildstyle / vertical-hand / stencil / scratch families | ✅ | Families render/gate; wildstyle exposure → heat/patrol + heaven-spot rep payoff |
| Stencil art requires carrying a stencil | ✅ | Stencil kit gating + gear suspicion |
| Scratch hand: glass-only, one color, 50% greyscale | ✅ | Glass gate + greyscale render via `render_plan` |
| Acid hands on glass, vertical + horizontal orientation | ✅ | Glass gate + vertical-on-portrait render |
| Practice a style 5× in blackbook before outside | ✅ | `practice_tag_font_style` |
| Sit on a bench to sketch/practice styles | ✅ | `bench.gd` + blackbook practice mode (movement suppressed while seated) |
| Practice lowers toy-overwrite likelihood (to a floor) | ✅ | `toy_response_multiplier` |
| More cans/gear → bulky → higher suspicion; stencil adds | ✅ | `gear_suspicion_multiplier` |
| Lose the paint drip lines | ✅ | All drips removed for every type, player and rival |
| Each type renders only a font capable for that style | ✅ | `fontFamilies` per type + `GraffitiFonts.resolve_for_families` |
| Paint-applied lettering reveals one letter at a time | ✅ | `_reveal_label_letters` on fresh player paint (skipped headless) |
| Stickers & wheatpaste posters (art-school printmaking unlock) | ✅ | `sticker`/`wheatpaste` paper types; Indigo the printmaker teaches them at rank Up |
| Dance / club / DJ rep-based invite | ✅ | The Undertow: rank-gated club, cover charge, beat-matching DJ-set modal pays Style/crew/cash by hype |

---

## 4. Not yet implemented — consolidated backlog

**Near-term (v3 remaining):**
* Battle paper-cut decision (M32).
* Playtest feedback pass (M33) + demo-candidate freeze (M34).

**Product_reqs gaps:**
* _All Product_reqs.md items are now implemented._ (Drip removal across all
  types shipped with the tag-style pass.)

**Designed in Plan.md, deferred:**
* Full §6 stat set (Nerve, Speed, Influence, Technique) and full §7 perk
  trees.
* Remaining crew roles + loyalty/upgrade paths; rival alliances/duels.
* Safehouse depth (sketch editor, outfit, sleep-to-skip, room).
* Additional districts (Downtown, Train Yard, Gallery Quarter, Substation).

**🔒 Do Not Build Yet (Plan.md §36 / Plan_v3 §7):** full city, multiplayer,
complex combat, procedural world gen, advanced layered editor, full faction
diplomacy, large quest trees, character creator, vehicles, online sharing.
