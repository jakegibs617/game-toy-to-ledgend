# v3 Performance & Runtime Budgets

Milestone 31 measures what the current city costs before any fourth
district, deeper crowd simulation, or battle minigame is added. The goal
is a cheap, repeatable profiling readout and a set of documented desktop
budgets — not a renderer rewrite.

## Running a profile

The runtime budget is dormant in normal play. Enable it two ways:

```sh
# Print the budget once, after the world finishes building (windowed):
RUNTIME_BUDGET=1 /Applications/Godot.app/Contents/MacOS/Godot --path .

# The headless smoke test always prints it (SMOKE: runtime budget — ...):
SMOKE_TEST=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path .
```

`RUNTIME_BUDGET=1` runs deferred after spawns and the HUD settle, so it
captures the fully built district. It logs a single
`RUNTIME_BUDGET: ...` line and changes nothing else.

The snapshot lives on the `PlaytestMetrics` autoload
(`runtime_budget_snapshot(scene_root)` /
`runtime_budget_summary_text(scene_root)`) next to the Milestone 27
playtest ledger and Milestone 28 balance snapshot. Pass the active
district node — it owns the street/building material cache.

## What it records

| Field | Source | Meaning |
|---|---|---|
| `worldNodeCount` | recursive walk of the district root | total nodes in the built city |
| `meshInstances` | `nodeTypes["MeshInstance3D"]` | mesh nodes (street detail dominates) |
| `walls` | `WallManager.wall_nodes` | spawned paintable walls |
| `trains` | `TrainManager.train_nodes` | spawned train cars |
| `interactables` | `interactable` group | benches, travel gates, climb zones |
| `materialCacheSize` | district `_material_cache` | shared street/building materials (Milestone 24) |
| `nodeTypes` | recursive histogram | node count by engine class |
| `characterVisual` | player `visual_report()` | `animated` / `static` / `capsule` import status + clip count |
| `frame` | `Performance` + `Engine` | fps, process ms, rendered objects, static MB, tree node count (0 on the headless server) |

## Desktop budgets

Soft ceilings for the prototype, defined in
`PlaytestMetrics.RUNTIME_BUDGETS`. They are set to current usage plus a
little headroom so the snapshot flags the next big content addition
instead of silently absorbing it. Exceeding one populates `overBudget`
and the smoke test fails — a deliberate tripwire, not a hard engine
limit.

| Budget | Ceiling | Current (3-district build) |
|---|---|---|
| `worldNodeCount` | 4000 | ~3660 |
| `meshInstances` | 2500 | ~2110 |
| `walls` | 80 | ~24 |
| `materialCacheSize` | 64 | ~43 |

## Findings & follow-ups

* The runtime-built street detail is the dominant mesh source (~2100 of
  ~3660 nodes). This is acceptable for the prototype but is the first
  place to look (mesh instancing / MultiMesh) if a fourth district pushes
  `meshInstances` over budget. No bottleneck is measured today, so per
  ROADMAP.md §7 no renderer change is made now.
* The Milestone 24 material cache keeps street/building materials shared
  (~43 entries); the budget guards against a regression that starts
  minting per-node materials again.
* Character visuals load the full animated rooster set (`animated`) when
  the GLBs import; the report distinguishes the `static` GLB and
  `capsule` fallbacks so a broken import shows up in the profile instead
  of silently degrading.
