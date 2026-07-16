# Toy to Legend — agent instructions

Open-world graffiti RPG prototype in **Godot 4.6**, built almost
entirely in GDScript at runtime (scenes are one-node shells; no .tscn
wiring to edit).

## Read first

* **ROADMAP.md** — the single living plan: vision, the current milestones (M35+), and the PR/review process. **Start here.**
* **docs/ARCHITECTURE.md** — system map, signal flow, data schemas. Read before touching code.
* **docs/design/GDD.md** — the v1 design doc, archived. Cite sections as `GDD §N` in comments, as the codebase does. Historical reference — where it and ROADMAP.md disagree, **ROADMAP.md wins**.
* **Product_reqs.md** — the owner's raw requests; graffiti-culture source of truth.
* **CHANGELOG.md** — what each milestone shipped; add an entry per milestone.

> ROADMAP.md replaced `Plan.md` / `Plan_v2.md` / `Plan_v3.md` / `Plan_v4.md`
> on 2026-07-15. A July 2026 design review found the core verb (painting)
> is a keypress with no skill or failure in it; M35+ rebuild it. Read
> ROADMAP.md §1 before planning any work.

## Commands

```sh
# Run windowed
/Applications/Godot.app/Contents/MacOS/Godot --path .
# Headless smoke test (asserts the full system chain, prints "SMOKE: OK")
SMOKE_TEST=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path .
# Boot check that self-quits
/Applications/Godot.app/Contents/MacOS/Godot --path . --quit-after 300
```

## Dev loop (per milestone)

branch → implement (extend the smoke test in `Scripts/district.gd`
alongside the feature) → 3 clean smoke runs + 1 windowed boot → PR →
multi-angle code review → fixes → comment on PR → **user merges** →
pull main. Update README (controls/systems) and CHANGELOG in the same
PR.

## Hard-won rules

* **Headless class cache:** fresh headless runs don't rebuild the
  global `class_name` cache — new cross-file script references must
  use `preload("res://...")`, not the bare class name (see
  `Hud.BlackbookPanelScript` for the pattern).
* **Paint only through WallManager** (`paint_wall`, `paint_freehand`,
  `apply_rival_graffiti`, `buff_wall`) — the whole game hangs off its
  `wall_painted` signal. Never mutate `wall_states` directly.
* **Everything is data-driven** from `/Data/*.json` (GDD agent
  rule 3). New content = new JSON entries first, code second.
* **Keep modal models testable off-tree:** UI panels separate their
  state/logic from UI nodes so the headless smoke test can drive them
  (see `freehand_panel.gd` `begin`/`spray_at`/`result`).
* **Save schema changes bump `SaveManager.SAVE_VERSION`.** Wall-state
  dicts must stay JSON-serializable.
* `Sfx` self-disables headless and must stay last in autoload order
  (it connects to the other managers' signals).
* Number keys 1–6 (`slot_1..slot_6`) are the shared slot convention
  (`Hud.MODAL_SLOT_ACTIONS`): modals consume them first, the world
  falls back to can selection in style order. Reuse for any new modal.
