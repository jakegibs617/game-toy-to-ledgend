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
  - `qwen3.5:latest`
  - `mistral:7b`
- No vision model is installed yet. Current runs use text-only mode:

```powershell
python agent\pilot.py --brain ollama --model qwen3.5 --no-vision --max-turns 20 --delay 0.5
```

## How To Launch

Start the game window with the agent server:

```powershell
$env:AGENT = "1"
Start-Process -FilePath "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64.exe" -ArgumentList "--path","." -WorkingDirectory "C:\Users\jakeg\OneDrive\Desktop\game-toy-to-ledgend"
```

Then run the pilot:

```powershell
python agent\pilot.py --brain ollama --model qwen3.5 --no-vision --max-turns 20 --delay 0.5 --notes agent\playtest_recommendations.jsonl
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

- `Scripts/UI/agent_overlay.gd`
  - Shows what the agent sees and does.
  - Displays latest action, reason, recent turn log, and latest recommendation
    when the model emits one.

- `agent/pilot.py`
  - Has heuristic and Ollama brains.
  - Uses `docs/AGENT_CHEATSHEET.md` as the Ollama system prompt.
  - Handles `goto_objective`.
  - Falls back to useful deterministic actions when model JSON is malformed.
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

Issues found:

- `qwen3.5` frequently emits malformed/non-JSON output despite structured
  schema instructions.
- Fallback now recovers from malformed output by using objective targets,
  selecting required cans, painting focused walls, or waiting while navigation is
  already active.
- `goto_objective` originally reset navigation every malformed turn; fixed by
  treating repeated navigation actions as no-ops while nav is active.
- For `reach_wall`, objective target now prefers the spawned `reach_<wall>` zone
  actor instead of only the wall.
- Wall navigation now switches into aim mode after arriving within stop
  distance.
- Agent steering now re-captures mouse before injecting mouse motion.

Current remaining problem:

- The agent can still stall around paint-specific objectives. It may reach the
  target wall area and select the correct can but not reliably focus the wall and
  press `paint`.

## Recommended Next Fixes

1. Add a dedicated `paint_objective` macro.
   - Resolve `objective_target`.
   - Select required can if needed.
   - Move toward the target.
   - Aim at the target wall.
   - Press `paint` once focused and prompt says paint.
   - This should be server-side stateful, not model-dependent.

2. Add observe fields for paint objectives:
   - `objective_required_can`
   - `objective_can_slot`
   - `objective_ready_to_interact`
   - `objective_distance`

3. Improve malformed output handling:
   - When Ollama output is invalid, log a compact parse-failure row.
   - Optionally retry once with a terse “return only JSON” repair prompt.
   - If repair fails, use deterministic fallback.

4. Add recommendation scaffolding independent of model compliance:
   - If the pilot detects repeated fallback, repeated same objective, or no
     distance change, write an automatic harness recommendation.
   - This would have captured the navigation/focus issues even when the model
     did not emit `recommendation`.

5. Install and test a vision model later:

```powershell
ollama pull llama3.2-vision
python agent\pilot.py --brain ollama --model llama3.2-vision --max-turns 20
```

Vision is not required for the harness fixes above, but it may improve
playtester-style observations.

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
- `docs/PLATFORM_READINESS.md` was added to document Windows/Mac platform setup.
- `README.md` was updated with Windows run/smoke commands.
- `agent/playtest_recommendations.jsonl` may not exist yet if the model has not
  emitted recommendations.
