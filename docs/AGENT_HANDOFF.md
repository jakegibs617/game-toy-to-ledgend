# Agent Playtest Harness — Handoff

Current date: 2026-06-22. Project: Toy to Legend, Godot graffiti RPG.

## Current Phase: Long-Loop Playtest

**Latest continuation (2026-06-22, commits `ace86bd`, `e278892`, `3397405`,
`f16d6ac`, `f59fa65`):** fixes D–H applied this session.  Run 17 (PID 1012)
is live with all fixes.  Watch for objective clearing during the influence
grind (turn 42+).

**Active fixes this session:**
- **Fix D** (`ace86bd`): district filter in `_nearest_unowned_wall()` — prevents cross-district nav (canal_06 at 103m was the old bug).
- **Fix E** (`3397405`): painted walls no longer added to `influence_skip_walls` — only geometry stalls go into skip.
- **Fix F** (`e278892`): `"think": False` in Ollama options — restores ~13s/turn (vs 6min/turn with thinking mode).
- **Fix G** (`f16d6ac`): `influence_skip_walls` cleared on safehouse rest.
- **Fix H** (`f59fa65`): `last_wall_skip_turn = turn` reset on rest — prevents immediate re-skip after clearing (same_obj_streak remains high post-rest, was triggering skip within 1 turn of the new cycle).

**Current status:** run 17 in progress.  Verify in the log:
1. `!! harness: rest — clearing influence_skip_walls` fires when paint=0 at safehouse.
2. No `!! harness: influence wall-skip` line appears within 6 turns of a rest.
3. Objective changes away from "Own the block" → SUCCESS.

**Latest run status (2026-06-22, commit `f59fa65`):** the opening chain now
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
| 42+ | **Own the block — push influence past 50%** | ⚠️ **testing fix** |

Two root-cause blockers from run 9 (`bdmn7kh72`) were diagnosed and fixed
in commit `320a6ef`.  Run 10 verifies the fix.

---

## Current Blocker Analysis (Run 9 / `bdmn7kh72`)

### Blocker A: aim_at infinite loop (turns 56–100, 45 wasted turns)

After painting `wall_mill_02` the player arrived within 3 m of `wall_alley_n_02`.
The close-wall aim redirect fired every turn because `aim_at` never achieved
focus (no `focused_wall` in obs), and the redirect had no failure limit.

```
[056]  -> wait (harness: nav complete)
[057..100]  -> aim_at  (harness: close-wall aim -> 'wall_alley_n_02' (3.0m))
             -- focused_wall never became non-empty; redirect kept firing
```

**Fix (commit `320a6ef`):** track `_aim_redir_count` per wall.  After
`_AIM_REDIR_MAX=4` consecutive aim_at redirects without focus, stop
intercepting for that wall so goto_wall navigates to a different approach angle.
Counter resets when focus is achieved; cleared on objective change.

### Blocker B: territory-neutral wall wasting paint turns

`wall_mill_glass_01` has `territoryNeutral: true` in walls.json — painting it
spends paint but contributes **zero** district influence.  The agent painted it
at turns 52, 107, 113 of run 9 (9 turns lost; 3 paint canister charges wasted).

The influence math: total non-neutral weight = 26.0, total including roof = 31.0,
threshold = 50% = 15.5 weight.  Roof wall (vis=5, y=10.8 m) is unreachable.
Ground-level walls that matter:

| Wall | vis | Key? |
|------|-----|------|
| wall_landmark_01 | 5 | HIGH |
| wall_bodega_01 | 4 | HIGH |
| wall_median_01 | 4 | HIGH |
| wall_mill_01 | 3 | medium |
| wall_loading_01 | 3 | medium |
| wall_corner_01 | 2 | medium |
| wall_mill_02 | 2 | medium |
| wall_alley_n_01 | 1 | low |
| wall_alley_n_02 | 1 | low |
| wall_lot_01 | 1 | low |
| wall_mill_glass_01 | 2 | **NEUTRAL — skip** |

Painting landmark+bodega+median+mill_01 = 17/31 = 54.8% → objective clears.

**Fix (commit `320a6ef`):**
- `agent_server.gd`: `_is_neutral()` helper; `_nearby_walls()` exposes
  `territory_neutral` flag; `_nearest_unowned_wall()` skips neutral walls.
- `pilot.py`: all harness redirects (wall-skip, close-wall-aim, repaint-block,
  bench-interact-block) filter by `territory_neutral` instead of
  `all_painted_walls`.

### Blocker C: stolen walls unreachable by harness (endgame goto_wall loop)

After rivals buffed walls back, `_nearest_unowned_wall()` found them as valid
targets (state no longer starts with `player_`), navigated, but
`all_painted_walls` blocked the close-wall aim redirect from focusing them.
Result: goto_wall → instant nav completion → no redirect → goto_wall loop.

**Fix (commit `320a6ef`):** removed `all_painted_walls` from all harness
redirect filters.  The player-owned state check is the correct guard;
`all_painted_walls` was over-filtering stolen-back walls that need repainting.

---

## Run 10 — What to Watch

Run 10 is the first run with commit `320a6ef` active.  Start it with a **fresh
save** (delete save files first — see below) so the opening chain runs cleanly.

Key signals to watch in the turn log:

1. **aim-redir counter fires**: `!! harness: close-wall aim -> 'wall_alley_n_02' (3.0m) [N/4]`
   — should only go up to `[4/4]` then stop.
2. **Neutral wall skipped**: `wall_mill_glass_01` should NOT appear as target in
   any harness redirect print line.
3. **Unvisited high-value walls targeted**: `wall_landmark_01`, `wall_bodega_01`,
   `wall_bodega_01`, `wall_median_01` should appear as `goto_wall` targets.
4. **Objective cleared**: objective text changes away from `Own the block` — look
   for rep climbing past the point where influence reaches 50%.

---

## Save File Issue

Godot saves progress after objectives complete.  When a pilot run reaches its
max-turns limit without crashing, the save file persists.  The next launch
loads from that save (mid-game state) rather than starting fresh.

**Solution before each new pilot run:**
Delete both save files (or overwrite them with `{}`):
```
C:\Users\jakeg\AppData\Roaming\Godot\app_userdata\Toy to Legend (Prototype)\toy_to_legend_save.json
C:\Users\jakeg\AppData\Roaming\Godot\app_userdata\Toy to Legend (Prototype)\toy_to_legend_save.backup.json
```

If save files don't exist, Godot starts a brand-new game automatically.

---

## The Run-Fix Cycle

1. **Delete save files** (see above) — fresh start required.
2. **Launch the game** with `AGENT=1` (see Launch Commands below).
3. **Run the pilot** — watch stdout for stalls (`same_obj`, `stuck`, `!! harness`).
4. **Identify the blocker** — look at the turn log and `nav.stuck_frames` /
   `objective_distance` in the observe output to understand _why_ the agent stopped
   making progress.
5. **Fix it** — almost all fixes go in one of three files:
   - `Scripts/Debug/agent_server.gd` — nav logic, legal actions, observe fields
   - `agent/pilot.py` — brain fallback, opening hint, force-stop valve
   - `docs/AGENT_CHEATSHEET.md` — system prompt the model reads every turn
6. **Verify** — always launch windowed after editing `agent_server.gd` (smoke test
   does not catch parse errors there; see note below). Python syntax: `python -m py_compile agent\pilot.py`.
7. **Commit** — one commit per fix, descriptive message. Then rerun from step 1.

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
python agent\pilot.py --brain ollama --model qwen3:14b --no-vision --max-turns 150 --delay 0.5 --notes agent\playtest_recommendations.jsonl
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
- World: `nearby_walls` (id, dist, bearing, state, **territory_neutral**), `nearby_actors` (id, dist, bearing, prompt)
- Nav: `aim_target`, `goto_target`, `goto_actor`, `moving`, `dist`, `stuck_frames`
- `legal_actions`: the actions the server will accept this turn

**`POST /act`** macro-actions:

| Action | What it does |
|---|---|
| `paint_objective` | One-shot: selects can, navigates, aims, presses E on objective wall |
| `goto_objective` | Navigate to mission target; accepts explicit `targetType`/`targetWallId`/`targetActorId` |
| `goto_wall(wallId)` | Navigate to a wall; if wallId missing or unknown, picks nearest non-neutral unowned wall |
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
  blacklists the stuck wall and redirects to a different nearby non-neutral unowned wall.
- Pilot aim-redir limit: if `aim_at` redirect fires ≥4 times for the same wall without
  focus achieved, the harness stops intercepting; goto_wall navigates to a new angle.
- Pilot bench-interact block: if `same_obj >= 15` and model calls `interact` with no
  objective actor nearby, redirects to `goto_wall` or `stop`.
- Height filter: walls >5 m above player are excluded from both `nearby_walls` and
  `_nearest_unowned_wall()` so the agent never targets rooftop walls it cannot reach.
- Territory-neutral filter: `territoryNeutral: true` walls (e.g. `wall_mill_glass_01`)
  are excluded from `_nearest_unowned_wall()` and from all harness redirect targets.
- Repaint block: if model tries to paint an already player-owned wall during a free-roam
  objective, the harness redirects to the nearest non-neutral unowned alternative.

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
unowned alternative.  Player-owned state check is the correct guard.

### Resolved: noop goto_wall restart loop

**Commits:** `753abaf`, `8244d9b`

`_is_noop_action()` catches `goto_wall` with no `wallId` while nav is active
(server would restart to the same nearest wall — a no-op).

### Resolved: Lupe shop / Moth / blackbook / 3-wall / rival response / crew piece

Verified clean in run 5 (`bfapeloy0`) and run 7 (`bu99ma6c2`).

### Resolved: aim_at infinite loop + territory-neutral wall + stolen-wall blind spot

**Commit:** `320a6ef`

Three interlinked fixes for the "Own the block" phase:

1. `_aim_redir_count` per-wall counter: close-wall aim redirect bails after 4
   consecutive failures without focus achieved.
2. `territory_neutral` flag in `nearby_walls`; `_nearest_unowned_wall()` skips
   neutral walls; harness redirects filter by neutral instead of `all_painted_walls`.
3. Removed `all_painted_walls` from harness redirect filters so stolen-back walls
   can be re-targeted by the harness.

---

## Resolved Blockers (session 2026-06-22, runs 12–17)

### Fix D — Cross-district navigation (`agent_server.gd`, `ace86bd`)

`_nearest_unowned_wall()` (visibility-first) had no district boundary.  After
painting `wall_landmark_01` (Mill Yard), it picked `wall_canal_06` (Canal Side,
vis=5) at 103 m.  Added `districtId != GameState.current_district_id` filter.
Confirmed in run 14 (nav_d=6m at same point).

### Fix E — Painted walls permanently in skip (`pilot.py`, `3397405`)

`influence_skip_walls.add(_fw)` was called on every successful paint, blocking
cleanup-reclaimed high-value walls forever.  Removed that line; `influence_skip_walls`
now only receives geometry-stalled walls from the stuck-nav path.

### Fix F — Thinking mode slow inference (`pilot.py`, `e278892`)

`qwen3:14b` with extended thinking enabled was taking 6+ min/turn.  Added
`"think": False` to Ollama options.  Restores ~13s/turn.

### Fix G — Skip list not cleared on safehouse rest (`pilot.py`, `f16d6ac`)

After cleanup wiped player-owned landmark_01/bodega_01, they remained in
`influence_skip_walls` for the rest of the session.  Added `influence_skip_walls.clear()`
inside the rest harness block.

### Fix H — Skip fires immediately after rest clears it (`pilot.py`, `f59fa65`)

`same_obj_streak` doesn't reset on rest (objective stays the same).  After Fix G
cleared the skip set, the wall-skip trigger (which fires when `same_obj_streak >= 12`)
re-added the first nav target within 1 turn of the new push cycle.  Fix: reset
`last_wall_skip_turn = turn` inside the rest block, enforcing the existing 6-turn
cooldown before any wall can be added to skip.

---

## Known Remaining Blockers

### 1. "Own the block" — two root-cause fixes applied (run 11)

**Run 10 result (2026-06-22):** Stalled at turn 97/150 with `same_obj=56`.
Objective never cleared.  Two root causes identified and fixed in commit
`93097d9`:

**Fix A — visibility-first wall targeting (`Scripts/Debug/agent_server.gd`):**
`_nearest_unowned_wall()` previously picked by nearest Euclidean distance.
`wall_median_01` (vis=4, ~1m from spawn) was always chosen over
`wall_landmark_01` (vis=5, ~18m away).  Changed to sort by highest visibility
first, distance only as tiebreaker.  Agent now targets landmark_01 first,
which contributes 5/31 influence — the single most impactful wall.

**Fix B — proactive can switch (`agent/pilot.py`):**
Existing low-paint switch only fired when model explicitly chose `paint`.
If the model saw `paint=1, can=throwup (cost 3)` it would reason "can't paint,
go rest" and choose `goto_actor`.  New check fires on any non-paint action when
there's a focused unowned wall and `paint >= 1 but < can_cost[selected]`.
Converts action to `select_can slot=1` so the very next turn can paint.

**Run 11 result (2026-06-22):** Killed at turn 25 after discovering Fix A was
incomplete: model sent `goto_wall` with explicit `wallId="wall_corner_01"` at
turn 22, bypassing `_nearest_unowned_wall()`.  Third fix added (commit `47e9f2d`):

**Fix C — wallId strip during influence grind (`agent/pilot.py`):**
When objective is "own the block" and model sends `goto_wall` with an explicit
`wallId` while nav is not active, the harness strips the wallId so the server
always calls `_nearest_unowned_wall()` → picks landmark_01 (vis=5) first.

**Run 12 started (2026-06-22):** All three fixes active.  Watch for:
- `!! harness: influence wallId strip` appearing at turn 42+ → Fix C firing
- `wall_landmark_01` as the nav target when Fix C strips the wallId
- Objective changing away from "Own the block" → SUCCESS

Expected success path: landmark_01 (5) + bodega_01 (4) + median_01 (4) +
loading_01 (3) = 16/31 = 51.6% influence → objective clears around turn 42–60.

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
   `""` — all accessible non-neutral walls are player-owned.  Check wall counts,
   influence threshold, and whether rivals have stolen any walls back.

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
