# Ollama Agent Play Plan

Plan for letting a **local Ollama model pilot _Toy to Legend_** — observe the
game the way a player does, decide an action, and have that action replayed
through the game's real input chain. Sibling doc to `ROADMAP.md`; follows the
same PR/review/smoke-test process.

## Goal

A runtime bridge where a local Ollama model is the player. The game exposes a
player's-eye view (text state + a screenshot), the model picks one action, and
the action is executed by **synthesizing real input** — so the model plays
roughly the way a human would, not by mutating managers directly.

## Purpose: a watchable agent playtester

The near-term reason to build this is **testing the game as we keep building it**.
The agent becomes an automated playtester you can *watch*:

- Runs **windowed** so you can see it move, aim, and tag in real time.
- An on-screen **agent overlay** shows what the model perceived and which action
  it chose each turn, so a watcher can tell *why* it did something.
- As new features land, the agent exercises them through real input (complements
  the smoke test, which checks systems but never touches the input layer).

So this harness is both "let a model play" and "a living regression test you can
sit and watch."

## Phases at a glance

1. **Now** — watchable single-agent playtester (this document).
2. **Later** — agents *inside* the game: model-driven NPCs/crew/rivals acting as
   live characters while a human plays alongside them. See
   [Future phase](#future-phase-agents-inside-the-game).

## Locked design decisions

| Decision | Choice | Why |
|---|---|---|
| Where the agent loop lives | **External Python pilot** | Godot stays a thin server; all LLM orchestration, schema validation, retries, model-swapping, logging live in Python. |
| How the model perceives | **Multimodal** (text state + screenshot each turn) | Richest context; most human-like. Requires a vision model + windowed run. |
| Action faithfulness | **Semantic macro-actions** | Model issues intents; harness executes via real synthesized input. Decisions are the model's; aiming/pathing is assisted. Achievable for small local models. |

## Core constraint: turn-based stepping

A local model takes hundreds of ms to several seconds per decision, so real-time
60 fps play is infeasible. The loop is **stepped**:

```
pause/slow game → snapshot observation → ask model → apply action → advance a
fixed slice of frames → repeat
```

Everything below assumes this cadence, not real-time control.

## Architecture

```
┌─ Godot (windowed, AGENT=1) ──────────────┐         ┌─ Python agent/pilot.py ─┐      ┌─ Ollama ─┐
│  agent_server.gd (localhost socket)      │         │  loop:                  │      │ vision   │
│   • observe → { state JSON, screenshot } │ ◄─────► │   GET observe           │ ───► │  model   │
│   • act     → synth real input           │  HTTP   │   build prompt + image  │      │ (/api/   │
│  (turn-based: pause → snapshot → step)   │         │   call model (schema)   │      │  chat)   │
└──────────────────────────────────────────┘         │   POST act + log        │      └──────────┘
                                                      └─────────────────────────┘
```

### Why these seams work (grounding in the existing code)

- All input is registered at runtime in `Scripts/Data/game_state.gd`
  (`_setup_input_actions`) and is injectable via `Input.parse_input_event` /
  `Input.action_press`/`action_release`.
- Two input pathways, both reachable by injected events: movement polling in
  `Scripts/Player/player.gd` `_physics_process`, and discrete actions in
  `_unhandled_input`.
- The player's observable world is HUD text — `Hud._prompt_label.text`
  (`[E] Paint …`) plus message toasts — which is exactly the decision signal a
  human reads.
- Painting needs the player near a wall **and** the camera ray focused on it
  (`_focused`); camera turns come from `InputEventMouseMotion` while the mouse is
  captured. Macro-actions wrap this so the model never has to micro-steer.
- Env-gated instrumentation precedent: `Scripts/Debug/playtest_metrics.gd`
  (`PLAYTEST_METRICS=1`, self-disables under `SMOKE_TEST`). The agent server
  mirrors that pattern.

## What needs to be built

### 1. Player cheat-sheet (read-only) — `docs/AGENT_CHEATSHEET.md`
Distil controls → goals + the new-player mission loop from `README.md`,
`FEATURES.md`, and the `enter_district` chain in `Data/missions.json`. Becomes
the model's system prompt and seeds the action list.

### 2. Godot agent server — `Scripts/Debug/agent_server.gd`
- New autoload (or `district.gd`-spawned node), gated by `AGENT=1`,
  **self-disabling under `SMOKE_TEST`** (same guard as `playtest_metrics.gd`).
- Opens a localhost endpoint (HTTP via `TCPServer`, or `StreamPeerTCP`) with two
  verbs:
  - `observe` → JSON player-view + screenshot path/base64:
    - alias, selected can/type, fill color, cap
    - paint, cash, rep, heat (current district)
    - current mission objective text
    - nearby walls: `wallId`, distance, bearing, `paintable?`, the
      `[E] Paint …` prompt string
    - nearby threats: patrol guards, heat level
    - `legal_actions`: the macro-actions valid right now
  - `act` → one action object; executes by synthesizing real input.
- Turn-based stepping: on `observe`, optionally pause; on `act`, apply input then
  advance N physics frames before returning.
- Screenshot: `get_viewport().get_texture().get_image().save_png(...)` (requires
  **windowed** run — headless has no renderer).

### 2b. Watchable agent overlay — `Scripts/UI/agent_overlay.gd`
On-screen panel (only when `AGENT=1`) so a human can watch *and understand* the
agent: last perceived state summary, the action it chose, and a short rolling log
of recent turns. Built in code like the rest of the HUD; reuses `ui_kit.gd`
builders. This is what makes the playtester "watchable," not just "running."

### 3. Action layer (macro-actions) — part of `agent_server.gd`
Each intent is a composition of synthesized input through the real chain:

| Action | Executes |
|---|---|
| `select_can(n)` | `slot_<n>` key |
| `cycle_color` / `cycle_cap` | `C` / `K` |
| `goto_wall(id)` | drive `move_*` toward the wall's position |
| `aim_at(id)` | feed `InputEventMouseMotion` until `_focused` == wall |
| `paint` | `interact` (`E`) once `_focused` is paintable |
| `freehand(id)` | `freehand_paint` (`F`) |
| `rest` | `safehouse_rest` (`R`) |
| `flee` | move away from nearest threat |
| `wait` | advance frames, no input |

Assert each action via an extension to the smoke test (`Scripts/district.gd`),
per project convention.

### 4. Python pilot — `agent/pilot.py` (+ `agent/requirements.txt`)
- Ollama client against `localhost:11434` `/api/chat`, **structured outputs** so
  the model must return a valid action object (JSON schema).
- Multimodal: include the screenshot (base64) in the `images` field each turn.
- Loop: `GET observe` → build prompt (cheat-sheet system + current observation)
  → call model → validate action against schema → `POST act` → log.
- Logging: write a screenshot + decision timeline as proof of play.
- Config: model name, server URL, max turns, step size — swap models easily.

### 5. Iterate
Trim observation for compactness, tune the action set and prompt until the model
reliably: chooses a can → navigates to a wall → tags it → reacts to heat.

## Prerequisites

- `ollama serve` running (not running by default on this machine).
- A vision model pulled: `ollama pull qwen2.5vl` (or `llama3.2-vision`).
  No models are currently pulled.
- Game launched **windowed** with `AGENT=1` (multimodal needs a renderer):
  `AGENT=1 /Applications/Godot.app/Contents/MacOS/Godot --path .`

## Build order

1. Cheat-sheet (`docs/AGENT_CHEATSHEET.md`).
2. `agent_server.gd` with `observe`/`act`; verify with a scripted Python client
   (no model).
3. Macro-action layer + smoke-test assertions.
4. `agent/pilot.py`; start server, pull vision model, run first-session loop.
5. Iterate on observation/action/prompt.

## Future phase: agents inside the game

A later, separate phase — **not built now**, but the harness above is the
foundation for it. Instead of one model driving the player, multiple models drive
**in-game characters** (recruitable crew, rival taggers, ambient locals) as live
actors while a **human** plays alongside them.

What carries over, and what changes:

- **Reuse:** the observe/decide/act loop, the Ollama pilot, structured-output
  actions, and the macro-action vocabulary.
- **Changes:**
  - Each agent gets a **scoped observation** (what that NPC can perceive) and an
    **NPC-appropriate action set** (move/tag/cross-out/banter/recruit), not the
    full player action list.
  - Actors drive existing NPC controllers (`Npc`, `RivalTagger`, `AmbientNpc`)
    rather than synthesizing player input — they call the same public manager
    paths those actors already use (e.g. `apply_rival_graffiti`,
    `apply_crew_graffiti`).
  - The loop runs **per-agent and concurrently** with live human play, so the
    stepping model must become budgeted/async (one slow local model can't block
    the human's frame) — likely a small fixed agent count, throttled decisions,
    or a queue.
  - Dialogue/banter agents may want a text-only fast model; taggers may stay
    multimodal.

Open questions to resolve when we get there: how many concurrent agents a local
machine can sustain, decision cadence per agent, and whether to share one Ollama
model across actors or run several.

## Out of scope (for now)

- Real-time (non-stepped) control of the player agent.
- Agents inside the game — deferred to the future phase above.
- Cloud/hosted models — local Ollama only.
- Training/fine-tuning — prompt-only piloting.
