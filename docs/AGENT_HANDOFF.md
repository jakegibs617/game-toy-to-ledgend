# Agent Playtest Harness — Handoff

Current date: 2026-06-21. Project: Toy to Legend, Godot graffiti RPG.

## Current Phase: Long-Loop Playtest

The harness is built. The goal now is to run it continuously, watch where
the agent stalls, fix what blocks it, and rerun — until the agent can
reliably reach **80% coverage** of the game's opening content in a single
unassisted run.

**What 80% coverage looks like** (milestone chain `mill_intro`):

| # | Milestone | Agent action required |
|---|---|---|
| 1 | Confirm writer alias | `paint` on the alias modal |
| 2 | Walk to a wall and tag it | `goto_wall` → `aim_at` / `paint_objective` |
| 3 | Return to the safehouse | `goto_objective` / `goto_actor safehouse` |
| 4 | Go check on your first tag (reach zone) | `goto_objective` — navigates to the remembered wall zone |
| 5 | Paint a throw-up over it | `paint_objective` — selects can 2, navigates, paints |
| 6 | Visit Lupe by the bodega | `goto_objective` → `interact` |
| 7 | Buy supplies from Lupe | `interact` inside the shop modal |
| 8 | Find a lookout | `goto_actor` for the lookout character |
| 9 | Claim the block | paint enough walls to push district influence |

Steps 1–6 are the primary validation target. Steps 7–9 are reach goals.

Outside the mission chain, 80% also means the agent has:
- tried `rest` at the safehouse at least once
- seen `heat` rise and respond to it
- explored the nearby street rather than waiting in one spot

---

## The Run-Fix Cycle

1. **Launch the game** with `AGENT=1` (see Launch Commands below).
2. **Run the pilot** — watch stdout for stalls (`same_obj`, `stuck`, `!! harness`).
3. **Identify the blocker** — look at the turn log and `nav.stuck_frames` /
   `objective_distance` in the observe output to understand _why_ the agent stopped
   making progress.
4. **Fix it** — almost all fixes go in one of three files:
   - `Scripts/Debug/agent_server.gd` — nav logic, legal actions, observe fields
   - `agent/pilot.py` — brain fallback, opening hint, force-stop valve
   - `docs/AGENT_CHEATSHEET.md` — system prompt the model reads every turn
5. **Verify** — always launch windowed after editing `agent_server.gd` (smoke test
   does not catch parse errors there; see note below). Python syntax: `python -m py_compile agent\pilot.py`.
6. **Commit** — one commit per fix, descriptive message. Then rerun from step 1.

---

## Launch Commands

Kill stale processes first:

```powershell
Get-Process | Where-Object { $_.ProcessName -like "Godot_v4.7-stable_win64*" } | Stop-Process -Force
Get-Process | Where-Object { $_.ProcessName -like "python*" } | Stop-Process -Force
```

Start the game (use the console build so stderr is capturable):

```powershell
$env:AGENT = "1"
$godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64_console.exe"
Start-Process -FilePath $godot -ArgumentList "--path","." `
    -WorkingDirectory "C:\Users\jakeg\OneDrive\Desktop\game-toy-to-ledgend" `
    -RedirectStandardError "C:\Users\jakeg\AppData\Local\Temp\godot_agent_err.txt" `
    -RedirectStandardOutput "C:\Users\jakeg\AppData\Local\Temp\godot_agent_out.txt" `
    -NoNewWindow
```

Wait ~15 s for port 8088 to be LISTENING, then run the pilot:

```powershell
python agent\pilot.py --brain ollama --model qwen3:14b --no-vision --max-turns 60 --delay 0.5 --notes agent\playtest_recommendations.jsonl
```

Check for Godot parse errors after launch:

```powershell
Get-Content "C:\Users\jakeg\AppData\Local\Temp\godot_agent_err.txt" | Select-String "ERROR|Parse"
```

---

## Installed Models

| Model | Speed | Instruction following | Notes |
|---|---|---|---|
| `qwen3:14b` | ~30 s/turn | Good | **Default for playtest runs** |
| `mistral:7b` | ~5 s/turn | Poor — ignores `goto_objective` | Use only for nav smoke tests |
| `qwen3.5:latest` | ~15 s/turn | OK | Alternative if qwen3:14b too slow |

No vision model is installed. Text-only (`--no-vision`) is the default.

---

## What the Harness Can Do (current server capabilities)

**`GET /observe`** returns:

- Player state: alias, paint, cash, rep, rank, heat, district, selected can
- Objective: text, `objective_target` (resolved wall/actor), `objective_distance`,
  `objective_required_can`, `objective_can_slot`, `objective_ready_to_interact`
- HUD: prompt text, focused wall id
- World: `nearby_walls` (id, dist, bearing, state), `nearby_actors` (id, dist, bearing, prompt)
- Nav: `aim_target`, `goto_target`, `goto_actor`, `moving`, `dist`, `stuck_frames`
- `legal_actions`: the actions the server will accept this turn

**`POST /act`** macro-actions:

| Action | What it does |
|---|---|
| `paint_objective` | One-shot: selects can, navigates, aims, presses E on objective wall |
| `goto_objective` | Navigate to mission target; accepts explicit `targetType`/`targetWallId`/`targetActorId` |
| `goto_wall(wallId)` | Navigate to a wall; if wallId missing or unknown, picks nearest unowned wall |
| `goto_actor(actorId)` | Navigate to an actor; stops early when non-paint `[E]` prompt appears |
| `aim_at(wallId)` | Turn camera toward a wall |
| `interact` | Press E for NPC/pickup/shop prompts (not paint, not rest) |
| `paint` | Press E to paint focused wall |
| `select_can(slot)` | Choose can 1–6 |
| `move(dir, seconds)` | Walk briefly in one direction |
| `look(dx, dy)` | Nudge camera |
| `rest` | Press R at safehouse |
| `stop` | Cancel all nav |
| `wait` | Do nothing |

**Navigation safety features:**

- Stuck-detection: after 90 frames (~1.5 s) with < 0.3 m progress, fires a 0.5 s
  side-step (alternating L/R). Handles geometry corners and NPCs blocking the path.
- Pilot force-stop: if `same_obj_streak >= 20` AND `nav.stuck_frames >= 60`, the
  pilot overrides the model with `stop` (once per 8 turns) so the model can retry.
- Actor nav stops immediately when a non-paint `[E]` prompt appears (player is already
  in interact range — no need to press into counter geometry).

---

## Known Remaining Blockers

These are the issues most likely to prevent 80% coverage. Fix them in order.

### 1. Complex geometry navigation (highest risk)

The stuck-detection side-step handles single-blocker cases well, but a tight
corridor or a U-shaped obstacle can produce a loop of same-side steps. The pilot's
force-stop after 20 turns helps but is a last resort.

**Symptoms in the turn log:**
```
nav_d=16m stuck=87  (side-step fires)
nav_d=15m stuck=91  (side-step fires again)
same_obj=20 → !! harness: forced stop
```

**Fix directions (pick one):**
- **Unstick with run**: hold shift during the side-step to break through tight spots.
  Add `Input.action_press("run")` before `_move(side, ...)` in `_update_stuck()`.
- **Waypoints**: hardcode 2–3 intermediate waypoints through the district geometry
  in the mission data or agent_server.gd, steering to each in sequence.
- **NavigationAgent3D**: add Godot's built-in nav agent to the player scene and steer
  toward its `get_next_path_position()` output in `_pursue_goto`.

### 2. Lupe shop interaction (unverified)

The `interact` action and prompt-aware actor stop should work for talking to Lupe.
Unverified because the geometry blocker (above) has prevented reaching the Lupe stage
in a full run.

**What to look for when testing:**
- After throwup painted, `goto_objective` targets `lupe` actor.
- Player should stop when `[E] Talk to Lupe` appears in the HUD prompt.
- Model should then choose `interact`.
- If the shop modal opens, model should choose `interact` again per item or
  use `select_can` if the shop uses slot keys.

**If the shop modal stalls:** inspect what legal_actions are exposed inside the
modal and add any missing actions to `_legal_actions()` in agent_server.gd.

### 3. Post-shop objectives (unexplored)

Steps 8–9 (find lookout, claim block) have never been reached by the agent.
No known blockers, but they will likely surface new stalls once Lupe is cleared.

---

## Diagnosing a Stall

When `same_obj_streak` is rising and nothing is progressing, check these in order:

1. **Is nav active?** `nav.goto_target` or `nav.goto_actor` non-empty → server is
   driving the player. Check `nav.dist` — is it decreasing? If not, stuck-detection
   should fire. If it never fires, check whether `_goto_moving` is true.

2. **Is the model choosing wait?** The pilot returns `wait` whenever nav is active.
   If nav never finishes, the model waits forever. Force-stop fires at 20 turns.

3. **Is the model choosing the wrong action?** Look at the `-> action (reason)` line.
   If it's choosing `goto_wall` instead of `goto_objective` when `objective_target` is
   set, the `_opening_hint` should have caught it. Check the hint wording in pilot.py.

4. **Is the server rejecting the action?** Look for `!! rejected:` lines. Then look
   at `_act_impl` in agent_server.gd and `_legal_actions()` to see why.

5. **Is the HUD prompt missing?** If `prompt` is empty the model can't see what E
   does. Check `_hud_prompt()` — it reads `_hud._prompt_label.text`. If the HUD
   structure changed, update this.

---

## Verification Commands

Python syntax:

```powershell
python -m py_compile agent\pilot.py
```

Godot smoke (**does NOT verify `agent_server.gd` — always launch windowed too**):

```powershell
$env:SMOKE_TEST = "1"
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64_console.exe" --headless --path .
```

Smoke test false-positive note: `SMOKE_TEST=1` calls `set_process(false)` in
agent_server.gd's `_ready()`, so parse errors there are never triggered. The headless
runner may also use cached `.gdc` bytecode. Always verify agent_server.gd edits by
launching windowed and checking the captured stderr for `ERROR` or `Parse`.

---

## Repo Notes

- All agent harness code lives on `main` (merged from branch `agent-playtest-loop`).
- `agent/playtest_recommendations.jsonl` is gitignored; accumulates across runs.
- Godot 4.7 import churn (`Assets/**/*.import`, `**/*.gd.uid`) — do not commit
  these unless specifically needed; they conflict with any Mac/Godot-4.6 build.
- `docs/AGENT_CHEATSHEET.md` is the Ollama system prompt — changes there take
  effect immediately on the next pilot run (no rebuild needed).
