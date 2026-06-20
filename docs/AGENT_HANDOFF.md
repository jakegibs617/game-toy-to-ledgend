# Agent Playtest Harness Handoff

Current date: 2026-06-20. Project: Toy to Legend, Godot graffiti RPG.

## Current Goal

Build a useful local agent playtest loop:

1. Run the game windowed with `AGENT=1`.
2. Let a local Ollama model play through real input via the Godot agent server.
3. Watch the game and overlay as the agent explores.
4. Capture model recommendations for game improvements.
5. Use only the useful recommendations as triage input for future build work.

The agent should act like a curious open-world game enthusiast and
completionist. It should try to see systems, characters, options, districts, and
mechanics, but 80% coverage is an acceptable playtest win. It is also asked to
notice friction, confusion, delight, missing feedback, and build opportunities.

## Current Environment

- Windows machine.
- Godot Engine 4.7 stable installed through `winget`.
- Local Ollama is available.
- Local models currently observed:
  - `qwen3:14b` (default)
  - `qwen3.5:latest`
  - `mistral:7b`
- No vision model is installed yet. Current runs use text-only mode:

```powershell
python agent\pilot.py --brain ollama --model qwen3:14b --no-vision --max-turns 20 --delay 0.5
```

## How To Launch

Start the game window with the agent server:

```powershell
$env:AGENT = "1"
Start-Process -FilePath "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64.exe" -ArgumentList "--path","." -WorkingDirectory "C:\Users\jakeg\OneDrive\Desktop\game-toy-to-ledgend"
```

Then run the pilot:

```powershell
python agent\pilot.py --brain ollama --model qwen3:14b --no-vision --max-turns 20 --delay 0.5 --notes agent\playtest_recommendations.jsonl
```

Stop stale processes before relaunching after code changes:

```powershell
Get-Process | Where-Object { $_.ProcessName -like "Godot_v4.7-stable_win64*" } | Stop-Process -Force
Get-Process | Where-Object { $_.ProcessName -like "python*" } | Stop-Process -Force
```

## What Exists Now

- `Scripts/Debug/agent_server.gd`
  - Runs a localhost HTTP server on `127.0.0.1:8088`.
  - `GET /observe` returns player state, objective, prompt, focused wall,
    nearby walls, nearby actors, nav state, legal actions, and optional
    screenshot path.
  - `GET /observe?shot=0` skips screenshots for text-only models.
  - `POST /act` executes macro-actions through real Godot input, not by mutating
    managers directly.
  - Current actions include `goto_wall`, `goto_actor`, `goto_objective`,
    `aim_at`, `paint`, `select_can`, `move`, `look`, `rest`, and `wait`.
  - `objective_target` is now exposed. It resolves mission objectives to exact
    actors or walls, including remembered mission refs such as the first tag
    wall.
  - Autonomous nav captures the mouse only while `aim_at`/`goto_*` is active,
    then restores the previous mouse mode when nav becomes idle. This prevents
    the agent from fighting modal/UI mouse state.
  - `goto_objective` can carry an explicit `targetType` plus `targetWallId` or
    `targetActorId`, so the pilot can act on the target it observed instead of
    always re-resolving the current mission target at execution time.

- `Scripts/UI/agent_overlay.gd`
  - Shows what the agent sees and does.
  - Displays latest action, reason, recent turn log, and latest recommendation
    when the model emits one.

- `agent/pilot.py`
  - Has heuristic and Ollama brains.
  - Uses `docs/AGENT_CHEATSHEET.md` as the Ollama system prompt.
  - Handles `goto_objective`.
  - Falls back to useful deterministic actions when model JSON is malformed.
  - Treats repeated nav commands as no-ops only when the target is the same,
    so the model can still course-correct to a different wall or actor.
  - Writes model recommendations to `agent/playtest_recommendations.jsonl`.

- `docs/AGENT_CHEATSHEET.md`
  - Defines the agent as a curious completionist playtester.
  - Instructs the model to emit optional structured recommendations:
    `playtest_note`, `recommendation`, `recommendation_category`,
    `recommendation_priority`.

## Latest Run Results

The agent loop was tried repeatedly with `qwen3.5` text-only.

Progress achieved:

- Confirmed writer alias.
- Went to a wall.
- Painted the first tag.
- Returned to the safehouse with `goto_objective`.
- Advanced to `Go check on your first tag`.
- After adding `objective_target`, reached the remembered first-tag objective in
  at least one run.
- Advanced to the throw-up objective:
  `Paint a throw-up over it - press 2, then E`.
- Selected the throw-up can via fallback.

Issues found and addressed:

- `qwen3.5` frequently emits malformed/non-JSON output despite structured
  schema instructions.
- Fallback now recovers from malformed output by using objective targets,
  selecting required cans, painting focused walls, or waiting while navigation is
  already active.
- `goto_objective` originally reset navigation every malformed turn; fixed by
  treating same-target navigation actions as no-ops while nav is active, while
  still allowing course corrections to different targets.
- For `reach_wall`, objective target now prefers the spawned `reach_<wall>` zone
  actor instead of only the wall.
- Wall navigation now switches into aim mode after arriving within stop
  distance.
- Actor navigation now keeps steering until the actor is both close and roughly
  centered, instead of stopping while still looking away.
- Agent steering now captures mouse at nav start and restores it when idle,
  rather than re-capturing every `_look()` call.
- `goto_actor` is only exposed as a general legal action when actors are nearby;
  objective navigation can still target mission actors outside the nearby list.
- Recommendation logging now warns and continues if the notes file cannot be
  created or written.

Current remaining problems:

- **Reach-zone navigation blocked by geometry** (most impactful): the forward-walk nav
  system (`_pursue_actor_goto`) can navigate around zero obstacles. When the reach zone
  for "Go check on your first tag" is 16m+ away and the direct path is blocked by walls
  or other geometry, the player walks 1-2m and then stops, indefinitely. Reproduced with
  BOTH the heuristic brain and Ollama — this is a server-side nav limitation, not a model
  issue. Proper pathfinding (NavMesh + waypoints, or explicit waypoint routing through the
  district layout) would fix this.

- **Actor proximity blocked by counter geometry**: after the reach zone is entered and the
  throwup is painted, `goto_objective` to Lupe stalls when the player is 2m from Lupe but
  geometry blocks the final step. Fixed `GOTO_ACTOR_STOP_DIST` from 1.6m → 2.5m (wider
  stop so the player stops before hitting the counter), and added `interact` action for
  E-key NPC prompts. But this fix cannot be verified until the reach-zone nav is fixed too.

- **`goto_wall` without wallId**: model (especially mistral:7b) frequently emits
  `goto_wall` without a `wallId`; fallback recovers, but wastes turns.

- **mistral:7b instruction following**: does not reliably choose `goto_objective` over
  `goto_wall`. Use `qwen3:14b` (slower, ~30s/turn) or add explicit nav override logic
  in pilot.py for when `objective_target` is present and same_obj_streak is high.

## What Was Shipped in the Current Session (2026-06-20, continued)

5. **`paint_objective` Phase 3b yaw-based fix — CONFIRMED WORKING** (`Scripts/Debug/agent_server.gd`):
   - Root cause of the original stall: `direct_space_state.intersect_ray()` called
     from `_process` reflects the PREVIOUS physics step's geometry — same stale-frame
     lag as `RayCast3D`. Phase 3b was guarded by `_camera_sees_wall()` which always
     returned false for this reason.
   - Fix: replaced the physics raycast guard with a rotation-based check —
     `absf(wrapf(desired_yaw - _player.rotation.y, -PI, PI)) <= AIM_DONE_RAD * 4.0`
     (12°). After aim exits, `_player.rotation.y` is immediately current (mouse
     events processed synchronously), so this fires correctly in the same frame aim
     completes.
   - Force-sets `_player._focused = wall_node`, emits `focus_changed`, then presses
     interact. Bypasses the physics focus lag entirely.
   - **Verified**: rep 26 → 141 in one turn (throwup painted), mission advanced to
     next objective. Previously stalled at focus=- for 30+ turns.
   - **Note**: the headless smoke test does NOT catch parse errors in agent_server.gd
     because (a) `SMOKE_TEST=1` disables the agent server, and (b) the headless runner
     uses cached `.gdc` bytecode from a prior compile. Always launch windowed after
     editing agent_server.gd to confirm the script parses.

6. **Actor proximity stall fix + `interact` action** (`Scripts/Debug/agent_server.gd`,
   `agent/pilot.py`, `docs/AGENT_CHEATSHEET.md`):
   - `GOTO_ACTOR_STOP_DIST` widened from 1.6m → 2.5m so the player stops before
     hitting bodega/NPC geometry instead of pressing into a wall forever.
   - New `interact` action added: exposed in `legal_actions` whenever prompt contains
     `[E]` but is not a paint or rest. Presses E on the focused NPC/object. This lets
     the agent talk to Lupe and other characters without needing a dedicated action per
     NPC type.
   - Fallback in `_compute_fallback` prefers `interact` when it is legal and prompt
     has `[E]`.
   - `ACTION_SCHEMA` enum and `AGENT_CHEATSHEET.md` updated to document the action.

## What Was Shipped in the Last Session (2026-06-20)

All four originally-recommended next fixes were implemented:

1. **`paint_objective` macro** (`Scripts/Debug/agent_server.gd`):
   - New action exposed in `legal_actions` whenever the current objective is a
     paint task with a specific wall.
   - Stateful server-side loop: selects the required can, starts `goto_wall`
     navigation, transitions to `aim_at`, then fires `interact` once the wall
     is focused and `[E] Paint` is in the prompt.
   - Cancels cleanly via `_cancel_nav` / `stop` actions.
   - Fallback in `_compute_fallback` also prefers `paint_objective` when it is legal.

2. **Observe fields for paint objectives** (`Scripts/Debug/agent_server.gd`):
   - `objective_required_can` — e.g. `”throwup”`
   - `objective_can_slot` — slot number (1–6), 0 if not applicable
   - `objective_ready_to_interact` — true when focused, correct can active, prompt ready
   - `objective_distance` — metres to the objective target; -1 if none

3. **Malformed output handling** (`agent/pilot.py`):
   - `OllamaBrain` now accepts `notes_path` and tracks a per-instance turn counter.
   - On `JSONDecodeError`, logs a compact `parse_failure` row to the JSONL file,
     then retries once with a zero-temperature repair prompt.
   - If repair also fails, falls through to the deterministic fallback.

4. **Automatic harness recommendations** (`agent/pilot.py`):
   - `run()` tracks `fallback_streak` and `same_obj_streak` across turns.
   - When ≥3 consecutive fallbacks or ≥6 turns on the same objective, a
     `auto_recommendation` entry is written to the notes file (5-turn cooldown
     to avoid spam).
   - Printed to stdout as `!! auto-rec:` so the operator sees it immediately.

Default model updated to `qwen3:14b`.

## Recommended Next Fixes

1. **Obstacle-avoiding navigation** (most impactful — blocks the full mission chain):
   The current forward-walk nav can't route around geometry. Options in increasing
   complexity:
   - **Waypoint routing**: hardcode 2-3 waypoints through the district so the nav
     controller steers to each in sequence before approaching the final target.
   - **NavMesh agent**: add a Godot NavigationAgent3D to the player and steer toward
     its desired velocity instead of directly toward the goal.
   - Short-term workaround: detect when `d` hasn't decreased in 5+ turns and issue a
     `move` side-step to try to unstick the player.

2. Install and test a vision model:

```powershell
ollama pull llama3.2-vision
python agent\pilot.py --brain ollama --model llama3.2-vision --max-turns 20
```

Vision is not required for the harness fixes above, but it may improve
playtester-style observations.

3. Investigate whether `qwen3:14b` reliably picks `paint_objective` from
   `legal_actions` when it is present, or whether the fallback (`_compute_fallback`)
   is carrying most of that load. If fallback_streak stays near 0 during paint
   objectives, the model is cooperating; if it's frequently high, consider tightening
   the system prompt wording or switching to a more instruction-following model.

## Verification Commands

Python syntax:

```powershell
python -m py_compile agent\pilot.py
```

Godot smoke:

```powershell
$env:SMOKE_TEST = "1"
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64_console.exe" --headless --path .
```

Latest checks passed with `SMOKE: OK`.

## Repo Notes

- Godot 4.7 first import changed many tracked `.import` files and created a few
  `.gd.uid` files. Review generated import churn before committing if the repo
  remains targeted at Godot 4.6.
- PR #66 contains the current agent harness work. After merge, continue from
  `main`.
- `docs/PLATFORM_READINESS.md` was added to document Windows/Mac platform setup.
- `README.md` was updated with Windows run/smoke commands.
- `agent/playtest_recommendations.jsonl` may not exist yet if the model has not
  emitted recommendations.
