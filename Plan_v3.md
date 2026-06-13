# Plan v3.0: From Playable Demo to Playtest-Ready Slice

**Toy to Legend** - third development phase.

Plan.md remains the original design reference. Plan_v2.md records how
the prototype became a playable demo through Milestone 26. This
document starts from the current repo state on main after PR #23 and
defines the next phase: make the demo measurable, balanced, readable,
and sturdy enough for repeated outside playtests.

Read [CLAUDE.md](CLAUDE.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
and [CHANGELOG.md](CHANGELOG.md) before starting any milestone. v3
continues the same development loop:

branch -> implement -> extend smoke coverage -> 3 clean smoke runs ->
1 windowed boot -> PR -> code review -> fixes -> user merge -> pull main.

---

# 1. Where the Project Stands

The v1 vertical slice, v2 playable-demo spine, and v2 stretch systems
are complete through Milestone 26. Current main includes:

* Three districts: Mill Yard, Canal Side, and climb-only Rooftop Row.
* The full graffiti type set: tag, throw-up, piece, stencil, roller,
  mural, and freehand pieces.
* Territory, heat, patrols, supply economy, dialogue, missions,
  blackbook, save/load, stats/perks, gallery sales, train painting,
  crew roles, ambient NPCs, alias/title flow, controller bindings,
  music/ambience, and Rooftop Row progression.
* Data-driven wall, district, mission, crew, NPC, ambient, train,
  gallery, style, supply, stat, perk, patrol, and climb content.
* A headless smoke test that currently completes with `SMOKE: OK`.

Live review on June 13, 2026:

* `SMOKE_TEST=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path .`
  passed once on current main before this plan was written.
* `git status` was clean except for untracked local `tools/` launch
  helpers, which this plan does not rely on.
* The largest single script is still `Scripts/district.gd` at roughly
  1,500 lines, because runtime world generation and smoke coverage live
  together. This is acceptable for v3 if new milestones keep changes
  localized and smoke sections self-contained.

## Remaining v1/v2 gaps that matter now

| Area | Status | v3 decision |
|---|---|---|
| Human playtest evidence | Not yet captured in repo | Do first; balance without observations is guessing |
| Economy/heat balance | Systems exist, numbers are mostly milestone-local | Tune against one target playthrough |
| Runtime performance | Material cache exists; no profiling budget yet | Add measurable budgets before more content |
| Rival graffiti variety | Functional labels, visually repetitive | Build deterministic procedural variants |
| Rooftop traversal readability | Playable but high-risk spaces need clearer tells | Polish prompts, hazards, and return routes |
| Battle systems | Still unbuilt from Plan.md §20 | Prototype on paper before code |
| Vault animation | Imported and bound, no gameplay trigger | Use only if traversal polish needs it |

---

# 2. v3 Goal

A repeatable **playtest-ready slice**: a new tester can play from alias
selection through Rooftop Row claim, understand why they are succeeding
or failing, make at least one meaningful style/perk/gallery decision,
and finish with numbers that tell us where the demo needs tuning.

v2 proved the game loop has depth. v3 proves the loop can survive
players who do not already know the plan.

The v3 emotional arc is:

**I learned the block -> I made choices -> the city pushed back -> I
left a mark worth talking about.**

---

# 3. v3 Engineering Recommendations

These are not all standalone milestones. Fold them into the relevant
PRs when they make the work easier to review.

## 3.1 Add a playthrough metrics ledger

The current systems emit plenty of events, but the repo does not retain
a simple playthrough timeline. Add a lightweight metrics recorder that
can be enabled for playtests and smoke runs:

* first paint time
* first rank-up
* first district claim
* Canal Side entry
* first gallery refusal/sale
* first train painted
* Rooftop Row entry
* Rooftop Row claim
* caught/fall counts
* paint starvation moments
* cash starvation moments

Keep it JSON-serializable and optional. Do not create a heavyweight
analytics system.

## 3.2 Make balance values traceable

Economy numbers now live across styles, walls, districts, trains,
gallery config, perks, supplies, missions, and patrols. Before tuning,
add a small balance snapshot/debug helper that prints or returns the
current key values by system. Reviewers should be able to see why a run
paid what it paid.

## 3.3 Protect against soft locks with invariants

Smoke tests already cover feature behavior. v3 should add invariants
for "the run can continue":

* required paint minimums before required roller/mural/train beats
* required unlocks before objective activation
* fallback cash/paint paths still reachable after fines/refusals
* district travel and climb return routes available when needed

## 3.4 Profile before adding more world content

Milestone 24 reduced material churn, but the project now has three
runtime-built districts, many imported character clips, and ambient
NPCs. Add a cheap profiling pass with documented budgets before any
fourth district, deeper crowd simulation, or battle minigame.

## 3.5 Keep procedural visuals deterministic

Procedural rival graffiti should be stable by `graffitiId` plus crew
seed, not random per render. Saves and screenshots must remain stable,
and smoke tests must be able to assert shape/color choices without
image comparison fragility.

---

# 4. v3 Milestones

Continue v2 numbering. Each milestone should be a separate PR unless a
review finds it is too small to justify the overhead.

## Milestone 27: Playtest Instrumentation & Balance Baseline

Purpose: learn how the current demo actually plays before changing the
numbers.

Deliverables:

* Optional playthrough metrics ledger, enabled by a simple flag/env var.
* A scripted or smoke-driven baseline path that records the main
  progression beats from new alias through Rooftop Row claim.
* Balance snapshot output covering paint costs, mission rewards, heat
  gains, cleanup pressure, gallery payouts, train payouts, district
  decay, and perk/stat multipliers.
* README notes for running a playtest capture.
* CHANGELOG entry.

Review focus:

* Metrics are passive unless explicitly enabled.
* No save schema bump unless metrics are persisted in regular saves.
* Smoke coverage proves the recorder does not alter progression.

## Milestone 28: Balance Pass 1 - Main Path

Purpose: tune the demo against one target playthrough instead of
milestone-by-milestone gut feel.

Deliverables:

* Target run definition: expected completion window, expected caught
  count, expected paint purchases, expected rank at each district, and
  acceptable grind budget.
* Tuned paint costs, cash rewards, heat gains, patrol pressure,
  territory decay, gallery payouts, train pass-through payouts, and
  Rooftop Row risk values.
* Smoke invariants that prevent obvious soft locks and starvation.
* A before/after balance note in CHANGELOG.

Review focus:

* Tune data first; code only when the balancing model cannot express
  the needed behavior.
* Watch for accidental rank inflation from stacking gallery, train,
  crowd, and district decay/payout loops.
* Verify that Stealth, Style, and Hustle still feel distinct.

## Milestone 29: Procedural Rival Graffiti Variety

Purpose: make rival territory visually read as crews, not repeated
placeholder text.

Deliverables:

* Deterministic procedural layouts for rival tags, throw-ups, stencils,
  and roller/blockbuster fallbacks using crew palette, alias/tag,
  simple stroke blocks, drips, offsets, and layout noise.
* Stable seed based on graffiti id and crew id.
* Blackbook/history display remains lightweight; do not store rendered
  image blobs for rivals.
* Smoke coverage for deterministic variant generation and history
  round-trips.

Review focus:

* Procedural output must be readable from gameplay camera distance.
* Player freehand image persistence must remain untouched.
* Rival surface rules from Milestone 16 must still apply.

## Milestone 30: Rooftop Traversal Polish

Purpose: keep Rooftop Row dangerous but legible.

Deliverables:

* Clearer climb/descent prompts and first-entry return-route hint.
* Visible ledge/edge warning or wind tell for high-risk rooftop work.
* A small stumble/slip feedback beat for long rooftop pieces if it
  improves readability.
* Optional vault animation trigger only if there is a real traversal
  event for it.
* Camera and guard behavior verification on elevated routes.

Review focus:

* Hazards should communicate before punishing.
* Avoid turning Rooftop Row into a tutorial wall of text.
* Controller and keyboard prompts both remain accurate.

## Milestone 31: Performance & Runtime Budget Pass

Purpose: know the cost of the current city before adding another major
feature.

Deliverables:

* A local profiling command or debug mode that records node counts,
  spawned wall/prop/NPC counts, material cache size, rough frame timing
  where available, and import/fallback status for character visuals.
* Documented desktop target budgets for the prototype.
* Low-risk fixes for obvious runtime waste found during profiling.
* Smoke coverage for budget helpers where practical.

Review focus:

* Profiling code should be removable or dormant in normal play.
* Do not start a broad renderer rewrite without a measured bottleneck.
* Preserve the runtime-built-scene architecture.

## Milestone 32: Battle Prototype Paper Cut

Purpose: decide whether Plan.md §20 battles belong in this prototype
before sinking implementation time.

Deliverables:

* A short paper prototype document for dance or rap battle:
  input pattern, scoring, fail state, reward, expected duration, and
  why it improves the graffiti loop.
* One tiny in-game prototype only if the paper version has a clear
  60-second interaction that beats another paint/territory objective.
* If built, add smoke coverage for entry, scoring, reward, and failure.

Review focus:

* Be ruthless. A battle that feels like disconnected filler should stay
  out of v3.
* No rhythm-game framework or complex combat unless the paper cut earns
  it.

## Milestone 33: Playtest Feedback Pass

Purpose: convert outside observations into fixes without widening scope.

Deliverables:

* A playtest findings note: top confusion points, pacing issues,
  repeated failure points, and moments testers liked.
* Small fixes only: prompts, objective text, map/blackbook clarity,
  minor data tuning, missing feedback sounds/toasts, and soft-lock
  protections.
* Updated smoke tests for every fixed regression or confusion point
  that can be automated.

Review focus:

* Link each change to a finding.
* Avoid adding new systems as a reaction to one tester's confusion.
* Preserve the main-path balance target from Milestone 28 unless the
  evidence says it is wrong.

## Milestone 34: v3 Demo Candidate

Purpose: freeze a candidate build for repeated playtesting.

Deliverables:

* 3 clean headless smoke runs.
* 1 clean windowed boot.
* README updated with current playtest instructions.
* CHANGELOG release section for v3 candidate.
* Known issues list with severity and next action.
* Tag candidate after user merge.

Review focus:

* No feature creep.
* Verify the install/run path on a fresh checkout if possible.
* Known issues are honest and specific.

---

# 5. PR and Code Review Process

v3 should be worked as small PRs with explicit review notes. The goal
is not ceremony; it is keeping a growing prototype understandable.

## Branch naming

Use:

* `feature/milestone-27-playtest-instrumentation`
* `feature/milestone-28-balance-pass`
* `feature/milestone-29-rival-graffiti-variety`
* `feature/milestone-30-rooftop-traversal-polish`
* `feature/milestone-31-performance-budget`
* `docs/plan-v3`

## PR description template

```
## Summary
- What changed
- Why this milestone needed it

## Testing
- [ ] Smoke run 1
- [ ] Smoke run 2
- [ ] Smoke run 3
- [ ] Windowed boot

## Review Notes
- Risky files or systems
- Data/schema changes
- Save migration notes
- Follow-up intentionally left out
```

## Review checklist

Every PR review should cover:

* Gameplay: does the change improve the target player experience?
* Data: are new behaviors expressed in JSON where the architecture
  expects content to be data-driven?
* Signals: do paint and world events flow through existing managers?
* Save/load: does a schema change bump and migrate `SAVE_VERSION`?
* UI/input: do modals follow the registry and slot-key convention?
* Smoke coverage: does the test cover the feature and its failure mode?
* Regression risk: which existing loop could this accidentally break?
* Scope: is any unrelated cleanup sneaking into the milestone?

## Multi-angle review pattern

For implementation PRs, do a short review from these angles before
merge:

1. Player experience review - clarity, pacing, feedback, friction.
2. Architecture review - data flow, manager ownership, signals, saves.
3. Test review - smoke coverage, determinism, soft-lock coverage.
4. Content review - data consistency, naming, copy, world placement.
5. Performance review - node/material churn, import fallback, runtime
   cost.

Document findings in the PR. Fix blocking issues in the same branch.
Non-blocking items become a clearly named follow-up.

---

# 6. v3 Success Criteria

The v3 candidate is successful if:

* A new tester can reach Rooftop Row claim without developer guidance.
* The run produces metrics for the main progression beats.
* Paint/cash/heat pressure feels tight but not starving on the target
  path.
* At least one tester describes their stat/perk/gallery choice as
  meaningful.
* Rival territory is visually more distinct than repeated labels.
* Rooftop Row feels dangerous for understandable reasons.
* The repo has a documented known-issues list instead of mystery bugs.

---

# 7. Do Not Build Yet

Carry forward the v1/v2 restraint:

* Full city
* Multiplayer
* Complex combat
* Procedural world generation
* Advanced layered-editor painting
* Full faction diplomacy
* Large quest trees
* Character creator
* Vehicles
* Online sharing

Also defer these until after the v3 candidate unless a playtest finding
proves they are blocking:

* Fourth district
* Deep crowd simulation
* Full battle system
* Large animation state-machine rewrite
* Asset-heavy art replacement pass

---

# 8. Immediate Next PR

After this docs PR lands, start Milestone 27:

1. Create `feature/milestone-27-playtest-instrumentation`.
2. Add the optional metrics ledger and balance snapshot helper.
3. Extend smoke coverage without changing progression numbers.
4. Run 3 smoke passes and 1 windowed boot.
5. Open the PR with baseline metrics pasted into the description.

