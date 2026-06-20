# Agent pilot

Drives _Toy to Legend_ through the in-game agent server so a local Ollama model
(or a rule-based baseline) plays it. See `docs/OLLAMA_AGENT_PLAN.md` for the full
design and `docs/AGENT_CHEATSHEET.md` for the model's system prompt.

## 1. Launch the game with the agent server

Run **windowed** (multimodal needs a renderer for screenshots):

```sh
AGENT=1 /Applications/Godot.app/Contents/MacOS/Godot --path .
```

It prints `AGENT: listening on http://127.0.0.1:8088`.

## 2. Run the pilot

No third-party Python deps — uses only the standard library.

```sh
# Rule-based baseline (no model needed) — proves the loop, plays the first tag:
python3 agent/pilot.py --goal "safehouse"

# Local Ollama model decides each turn (multimodal: state + screenshot):
ollama serve                 # in another terminal, if not already running
ollama pull qwen2.5vl        # any vision model; or llama3.2-vision
python3 agent/pilot.py --brain ollama --model qwen2.5vl

# Text-only model (no screenshot):
python3 agent/pilot.py --brain ollama --model llama3.2 --no-vision
```

## How it works

Each turn: `GET /observe` → a JSON player-view (cans, paint/cash/rep/heat,
objective, HUD prompt, focused wall, nearby walls, nav state) plus a screenshot
path → the brain picks one action → `POST /act`. Actions are macro-intents
(`goto_wall`, `aim_at`, `paint`, `select_can`, …) that the server executes by
**synthesizing real input**, so the agent plays through the same chain a human
keypress takes.

## Watching it play

When the game runs with `AGENT=1`, a cyan overlay appears in the top-right
(`Scripts/UI/agent_overlay.gd`). It mirrors what the pilot perceives each turn —
rep/cash/paint/heat, selected can, focused wall, objective, HUD prompt — plus the
action it chose with the model's stated reason, and a rolling log of recent
turns. That's the point of running windowed: you can watch *why* the agent acts,
not just that it's running. It costs nothing outside `AGENT=1`.

## Recommendation loop

The Ollama brain is also prompted as a playtester. When it notices friction,
confusion, delight, missing feedback, or a likely improvement, it may include a
structured recommendation with its action. The pilot appends those notes to:

```text
agent/playtest_recommendations.jsonl
```

Each row includes the turn, objective, district, chosen action, note,
recommendation, category, and priority. Treat these as triage input: useful
ideas to review, not automatic work orders.

## Flags

| Flag | Default | Meaning |
|---|---|---|
| `--brain` | `heuristic` | `heuristic` or `ollama` |
| `--server` | `http://127.0.0.1:8088` | agent server URL |
| `--ollama` | `http://localhost:11434` | Ollama API URL |
| `--model` | `qwen2.5vl` | Ollama model |
| `--no-vision` | off | text-only (skip the screenshot) |
| `--max-turns` | 60 | stop after N turns |
| `--delay` | 0.4 | seconds between turns (let the world advance) |
| `--goal` | "" | stop when the objective text contains this substring |
| `--notes` | `agent/playtest_recommendations.jsonl` | JSONL file for playtest recommendations |
