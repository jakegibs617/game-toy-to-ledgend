# Agent Playtest Harness — Handoff

Current date: 2026-06-21. Project: Toy to Legend, Godot graffiti RPG.

## Current Phase: Long-Loop Playtest

**Latest run status (2026-06-21, commit `2a91941`):** the opening chain now
clears completely in ~41 turns.  Verified in every recent run:

| Turn range | Milestone | Status |
|---|---|---|
| 1–2 | Choose alias / first tag | ✓ stable |
| 3–5 | Return to safehouse | ✓ stable |
| 6–8 | Check first tag / paint throw-up | ✓ stable (`paint_objective`) |
| 9–12 | Visit Lupe, buy supplies, pick colour | ✓ stable |
| 13–21 | Meet Moth / recover blackbook / return | ✓ stable |
| 22–36 | Paint 3 different walls in the Mill Yard | ✓ stable |
| 37 | A crew hit your wall — take it back | ✓ stable |
| 38–41 | Put up a piece with your crew | ✓ stable |
| 42+ | **Own the block — push influence past threshold** | ❌ **current blocker** |

The remaining blocker is the final **"Own the block"** influence grind.
After painting all accessible Mill Yard walls (~5 walls), the agent has no
unowned walls left to navigate to and loops on `goto_wall` until max-turns.

---

## Current Blocker: "Own the block" — no unowned walls left

### Symptoms (run 7 / `bu99ma6c2`, turns 42-93)

```
[042] obj='Own the block...'  rep=464  paint=29
      -> goto_wall (aim_at with no wallId; go to unowned wall)
[043] nav_d=5m  -> wait
[044] rep=432  -> goto_wall   (no nav_d — nothing to navigate to)
...
[093] rep=432  -> goto_wall   (50 turns of this, rep unchanged)
```

- By turn 41 the player has painted: `wall_corner_01`, `wall_median_01`,
  `wall_mill_02`, `wall_mill_glass_01` (plus `wall_median_01` from the
  opening).
- `_nearest_unowned_wall()` appears to return `""` — the server accepts
  goto_wall but starts no navigation.
- The only known remaining unowned wall, `wall_alley_n_02`, was tried in
  earlier runs (nav_d=6m, stuck=23) but the force-stop fired before the
  player could reach it.

### What to inspect next

1. **How many unowned walls remain** after the crew-piece step?
   Run `/observe` at turn 42 and check `nearby_walls` + query
   `WallManager.wall_states` for the full district — if only 1-2 walls
   remain they may not be enough to cross the influence threshold.

2. **What does the influence threshold actually require?**
   Check the mission data (`/Data/missions.json`) for the `min_influence`
   value on the `own_the_block` step.  If it requires >50% and the district
   only has ~6 paintable walls, the math may not work.

3. **Is `wall_alley_n_02` reachable?**
   In run 5 it was tried once (nav_d=6m, stuck=23) then abandoned when the
   force-stop fired.  It may be reachable with a longer approach.  Try
   `goto_wall` with explicit `wallId: "wall_alley_n_02"` and let the nav run
   for >90 frames to allow the side-step to trigger.

4. **Godot crash at turn 93** (ConnectionRefused on /act). Godot closed
   unexpectedly after ~3 hours of runtime.  Likely a memory/stability issue
   with long sessions.

### Fix directions (pick one)

- **Game-level (likely required):** add 3-4 more paintable ground-level walls
  to the Mill district, or lower the `min_influence` threshold so the
  existing ~5 walls are sufficient.

- **Agent-level:** when `_nearest_unowned_wall()` returns `""`, add `rest`
  as the harness fallback instead of `goto_wall` — the safehouse is always
  reachable via `goto_actor safehouse` and resting might trigger a game event
  that advances the objective.

- **Navigation improvement:** increase GOTO_STOP_DIST from 3m to 2m so the
  player gets closer before stopping, and hold shift (run) during stuck
  side-steps to punch through tight geometry.

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
python agent\pilot.py --brain ollama --model qwen3:14b --no-vision --max-turns 120 --delay 0.5 --notes agent\playtest_recommendations.jsonl
```

Check for Godot parse errors after launch:

```powershell
Get-Content "C:\Users\jakeg\AppData\Local\Temp\godot_agent_err.txt" | Select-String "ERROR|Parse"
```

---

## Installed Models

| Model | Speed | Instruction following | Notes |
|---|---|---|---|
| `qwen3:14b` | ~30 s/turn (can spike to 5 min) | Good | **Default for playtest runs** |
| `mistral:7b` | ~5 s/turn | Poor — ignores `goto_objective` | Use only for nav smoke tests |
| `qwen3.5:latest` | ~15 s/turn | OK | Alternative if qwen3:14b too slow |

No vision model is installed. Text-only (`--no-vision`) is the default.

The pilot now retries Ollama up to 3× (5 s sleep) before failing, so
transient slow inference no longer crashes a run.

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
| `goto_actor(actorId)` | Navigate to an actor; ignores unrelated `[E]` prompts and stops only for the target actor prompt or close hard-stop |
| `aim_at(wallId)` | Turn camera toward a wall |
| `interact` | Press E for generic prompts, or directly calls the current objective actor/pickup when it is in range |
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
- Pilot wall-skip: if stuck navigating to a wall (stuck_frames >= 30, same_obj >= 10),
  blacklists the stuck wall and redirects to a different nearby unowned wall.
- Pilot bench-interact block: if `same_obj >= 15` and model calls `interact` with no
  objective actor nearby, redirects to `goto_wall` or `stop`.
- Height filter: walls >5 m above player are excluded from both `nearby_walls` and
  `_nearest_unowned_wall()` so the agent never targets rooftop walls it cannot reach.
- Repaint block: if model tries to paint an already player-owned wall during a free-roam
  objective, the harness redirects to the nearest unowned alternative.

**Current actor/pickup interaction caveat:** after `eee936b`, actor nav only
treats a prompt as successful if it matches the target actor/pickup. Objective
actors and pickups can also be interacted with directly when in range, even if
the HUD ray is focused elsewhere.

---

## Resolved Blockers (this session, 2026-06-21)

### Resolved: goto_wall wobble / wall_roof_mill_01 targeting

**Commits:** `20540eb`, `033b0e4`

`_nearest_unowned_wall()` and `_nearby_walls()` both now skip walls more than
5 m above the player.  `wall_roof_mill_01` (y=10.8 m) was the primary cause
of the original Mill Yard stall — it appeared as "nearest" via 3-D Euclidean
distance even though the straight-line nav cannot reach it from the ground.

### Resolved: Model repainting owned walls

**Commits:** `3295fe9`, `7e46274`

Harness now blocks `paint` on player-owned walls and redirects to the nearest
unowned alternative.  All painted walls are tracked in `all_painted_walls` (a
set that never clears), so the wall-skip never navigates back to walls painted
in earlier objectives.

### Resolved: noop goto_wall restart loop

**Commits:** `753abaf`, `8244d9b`

`_is_noop_action()` catches `goto_wall` with no `wallId` while nav is active
(server would restart to the same nearest wall — a no-op).

### Resolved: Lupe shop / Moth / blackbook / 3-wall / rival response / crew piece

Verified clean in run 5 (`bfapeloy0`) and run 7 (`bu99ma6c2`).

---

## Known Remaining Blockers

### 1. "Own the block" — insufficient unowned walls (current blocker)

After painting ~5 accessible Mill Yard walls the district has no reachable
unowned walls remaining.  `_nearest_unowned_wall()` returns `""` and the
model loops on `goto_wall` with no navigation starting.

**Likely root cause:** the influence threshold requires more wall coverage than
the current district geometry provides with ground-level accessible walls.

**Next step:** check `min_influence` in `/Data/missions.json` and count total
paintable ground-level walls in `walls.json` for the mill district.  If the
math doesn't work (walls × influence_per_wall < threshold), this is a game
design fix, not an agent fix.

### 2. Godot long-session crash

Godot crashed after ~3 hours runtime at turn 93 of run 7 (ConnectionRefused
on /act).  Likely memory leak or OS resource exhaustion.  For now: restart
Godot between runs.

### 3. Complex geometry navigation (general risk)

The stuck-detection side-step handles single-blocker cases well, but a tight
corridor or U-shaped obstacle can produce a loop of same-side steps.

**Fix directions (deferred):**
- **Unstick with run**: hold shift during the side-step to break through tight spots.
- **NavigationAgent3D**: add Godot's built-in nav agent to the player scene.

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

5. **Is `goto_wall` firing with no nav starting?** `_nearest_unowned_wall()` returned
   `""` — all accessible walls are player-owned.  Check wall counts and influence
   threshold in the mission data.

6. **Is the HUD prompt missing?** If `prompt` is empty the model can't see what E
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
