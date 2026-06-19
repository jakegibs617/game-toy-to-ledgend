# Agent play harness — handoff

Continue the agent play harness for Toy to Legend (Godot 4.6 graffiti RPG).

## Context — what already exists

A localhost bridge that lets an external pilot (a local Ollama model, or a
rule-based baseline) play the game through synthesized real input. Design doc:
`docs/OLLAMA_AGENT_PLAN.md`. Model system-prompt: `docs/AGENT_CHEATSHEET.md`.

- **`Scripts/Debug/agent_server.gd`** — HTTP server on 127.0.0.1:8088, gated by
  `AGENT=1`, self-disables under `SMOKE_TEST`. `GET /observe` → player-view JSON
  (cans, paint/cash/rep/heat, objective, HUD prompt, focused_wall, nearby_walls,
  nav state) + screenshot path; `GET /observe?shot=0` skips the screenshot.
  `POST /act` runs macro-actions (`select_can`, `cycle_color`/`cap`, `move`/
  `look`, `aim_at`, `goto_wall`, `stop`, `paint`, `freehand`, `rest`, `wait`) by
  feeding `InputEventAction` / mouse-motion / movement holds through the real
  input chain. `_act` is a thin logging wrapper over `_act_impl`. Wired into
  `Scripts/district.gd` boot.
- **`Scripts/UI/agent_overlay.gd`** — watchable on-screen overlay (PR #65, branch
  `agent-watch-overlay`, **awaiting user merge** as of this handoff). Cyan
  top-right panel, created only under `AGENT=1` by `agent_server.gd`. Shows last
  perceived state (rep/cash/paint/heat, can, focused wall, objective, HUD
  prompt), the chosen action + the pilot's `reason` (green ok / red rejected),
  and a rolling 8-turn log. Pushed via `_overlay.set_state()` on each `/observe`
  and `_overlay.log_action()` on each `/act`.
- **`agent/pilot.py`** — stdlib-only loop with two brains: `heuristic` (default,
  baseline) and `ollama` (multimodal, structured-output). `agent/README.md` has
  run instructions.

**Verified:** the heuristic pilot autonomously plays the opening objective
(dismiss alias → goto wall → tag), tags multiple distinct walls without
repainting (rep 0→58 over two walls), the overlay updates live each turn and
stays clear of the HUD, and smoke stays `SMOKE: OK` ×3.

## Next — open items

1. **Actually drive the Ollama brain** (the main remaining item): `ollama serve`
   + `ollama pull qwen2.5vl` (or `llama3.2-vision`), launch the game windowed
   with `AGENT=1`, then
   `python3 agent/pilot.py --brain ollama --model qwen2.5vl`. Tune the
   observation/action/prompt (`docs/AGENT_CHEATSHEET.md` is the system prompt)
   until a small local model reliably tags a wall and reacts to heat. Use the
   agent overlay to *watch* the tuning. (Ollama installed at
   `/opt/homebrew/bin/ollama`, v0.21.0; as of last check the server was not
   running and no models were pulled — the vision model is a multi-GB download.)
2. **Later phase (not now):** agents *inside* the game — model-driven
   NPCs/rivals/crew acting while a human plays. See the "Future phase" section in
   `docs/OLLAMA_AGENT_PLAN.md`.

## Gotchas

- If PR #65 isn't merged yet, work off branch `agent-watch-overlay` (or pull main
  once merged). Direct push to main is blocked — branch → PR → review → user
  merges.
- Run **windowed** for screenshots:
  `AGENT=1 /Applications/Godot.app/Contents/MacOS/Godot --path .` — server prints
  "AGENT: listening on http://127.0.0.1:8088". Headless has no renderer (empty
  screenshots).
- To kill instances use `pkill -9 -f "Godot.app/Contents/MacOS/Godot --path"` — a
  pattern matching the project NAME won't match (cmd line is `Godot --path .`),
  so stale instances pile up and keep serving port 8088 with old code. Always
  kill before relaunching after a code change.
- New game opens on the alias modal (`alias_chosen=false`); the first pilot
  action is a `paint` (=interact) to dismiss it.
- Cross-file script refs in new files must use `preload("res://...")` not bare
  `class_name` (headless class-cache rule, `CLAUDE.md`). `agent_overlay.gd` has
  no committed `.uid` yet — the editor will generate one; preload-by-path doesn't
  need it.
- Smoke before PR: `SMOKE_TEST=1 godot --headless --path .` (run 3x, expect
  `SMOKE: OK`). Update `CHANGELOG.md` (and `agent/README.md` if behavior changes)
  in the same PR.
- Pre-existing dirty files (`FEATURES.md`, `Plan_v3.md`, untracked `Plan_v4.md`,
  `agent/__pycache__`) are from a separate Codex loop — leave them out of harness
  PRs.
