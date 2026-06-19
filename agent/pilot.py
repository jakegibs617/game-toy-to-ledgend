#!/usr/bin/env python3
"""Ollama pilot for Toy to Legend — Phase 4 of docs/OLLAMA_AGENT_PLAN.md.

Drives the game through the agent server (Scripts/Debug/agent_server.gd):
GET /observe -> a player's-eye view (+ a screenshot), pick one action, POST
/act. Two "brains":

  --brain heuristic   rule-based, needs no model; proves the loop and is a
                      baseline. (Default.)
  --brain ollama      a local Ollama model decides each turn, multimodal
                      (state JSON + screenshot), structured-output action.

Run the game windowed first:
  AGENT=1 /Applications/Godot.app/Contents/MacOS/Godot --path .
Then:
  python3 agent/pilot.py                       # heuristic
  python3 agent/pilot.py --brain ollama --model qwen2.5vl
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CHEATSHEET = os.path.join(HERE, "..", "docs", "AGENT_CHEATSHEET.md")

# The action vocabulary the server understands. Also the JSON schema handed to
# Ollama so the model is forced to emit a valid action object.
ACTION_SCHEMA = {
    "type": "object",
    "properties": {
        "reason": {"type": "string"},
        "action": {
            "type": "string",
            "enum": [
                "select_can", "cycle_color", "cycle_cap", "look", "move",
                "aim_at", "goto_wall", "stop", "paint", "freehand", "rest",
                "wait",
            ],
        },
        "slot": {"type": "integer"},
        "wallId": {"type": "string"},
        "dir": {"type": "string", "enum": ["forward", "back", "left", "right"]},
        "seconds": {"type": "number"},
        "dx": {"type": "number"},
        "dy": {"type": "number"},
    },
    "required": ["action"],
}


# --- HTTP helpers -----------------------------------------------------------

def _get(url: str, timeout: float = 5.0) -> dict:
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def _post(url: str, payload: dict, timeout: float = 60.0) -> dict:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


class Game:
    """Thin client for the in-game agent server."""

    def __init__(self, base: str):
        self.base = base.rstrip("/")

    def observe(self) -> dict:
        return _get(self.base + "/observe")

    def act(self, action: dict) -> dict:
        return _post(self.base + "/act", action)


# --- brains -----------------------------------------------------------------

def heuristic_brain(obs: dict) -> dict:
    """A tiny rule-based player: dismiss the alias modal, walk to the nearest
    paintable wall, tag it, then idle. No model required."""
    if not obs.get("alias_chosen", True):
        return {"reason": "start game", "action": "paint"}  # E confirms the alias

    focused = obs.get("focused_wall") or ""
    prompt = obs.get("prompt") or ""
    if focused and "Paint" in prompt:
        if obs.get("selected_can") != "tag":
            return {"reason": "use the tag can", "action": "select_can", "slot": 1}
        return {"reason": f"tag {focused}", "action": "paint"}

    nav = obs.get("nav") or {}
    if nav.get("goto_target"):
        return {"reason": "walking to wall", "action": "wait"}

    walls = obs.get("nearby_walls") or []
    blank = next((w for w in walls if w.get("state") == "blank"), None)
    target = blank or (walls[0] if walls else None)
    if target:
        return {"reason": f"head to {target['wallId']}", "action": "goto_wall",
                "wallId": target["wallId"]}
    # Nothing in range: nudge forward to find a wall.
    return {"reason": "explore", "action": "move", "dir": "forward", "seconds": 0.6}


class OllamaBrain:
    def __init__(self, host: str, model: str, use_vision: bool):
        self.host = host.rstrip("/")
        self.model = model
        self.use_vision = use_vision
        with open(CHEATSHEET, "r", encoding="utf-8") as f:
            self.system = f.read()

    def __call__(self, obs: dict) -> dict:
        # Strip the screenshot path out of the text view; pass the image
        # separately so a vision model sees the frame.
        view = {k: v for k, v in obs.items() if k != "screenshot"}
        user = (
            "Current observation (JSON):\n" + json.dumps(view, indent=2) +
            "\n\nChoose exactly one action to progress the current objective. "
            "Respond only as a JSON action object."
        )
        message = {"role": "user", "content": user}

        shot = obs.get("screenshot") or ""
        if self.use_vision and shot and os.path.exists(shot):
            with open(shot, "rb") as f:
                message["images"] = [base64.b64encode(f.read()).decode("ascii")]

        payload = {
            "model": self.model,
            "messages": [{"role": "system", "content": self.system}, message],
            "format": ACTION_SCHEMA,
            "stream": False,
            "options": {"temperature": 0.2},
        }
        resp = _post(self.host + "/api/chat", payload, timeout=180.0)
        content = resp.get("message", {}).get("content", "{}")
        try:
            action = json.loads(content)
        except json.JSONDecodeError:
            return {"reason": "unparseable model output", "action": "wait"}
        if not isinstance(action, dict) or "action" not in action:
            return {"reason": "no action field", "action": "wait"}
        return action


# --- main loop --------------------------------------------------------------

def summarize(obs: dict) -> str:
    return (f"rep={obs.get('reputation')} paint={obs.get('paint')} "
            f"heat={obs.get('heat')} can={obs.get('selected_can')} "
            f"focus={obs.get('focused_wall') or '-'} "
            f"obj={(obs.get('objective') or '')[:40]!r}")


def run(args) -> int:
    game = Game(args.server)
    if args.brain == "ollama":
        brain = OllamaBrain(args.ollama, args.model, not args.no_vision)
    else:
        brain = heuristic_brain

    try:
        game.observe()
    except (urllib.error.URLError, OSError) as e:
        print(f"Cannot reach the game at {args.server}: {e}\n"
              f"Launch it with AGENT=1 first.", file=sys.stderr)
        return 2

    for turn in range(1, args.max_turns + 1):
        obs = game.observe()
        action = brain(obs)
        reason = action.get("reason", "")
        print(f"[{turn:03d}] {summarize(obs)}")
        print(f"      -> {action.get('action')} {('('+reason+')') if reason else ''}")
        result = game.act(action)
        if not result.get("ok"):
            print(f"      !! rejected: {result.get('error')}")
        if args.goal and args.goal.lower() in (obs.get("objective") or "").lower():
            print(f"Reached goal objective: {obs.get('objective')!r}")
            return 0
        time.sleep(args.delay)

    print("Max turns reached.")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="Ollama pilot for Toy to Legend")
    p.add_argument("--server", default="http://127.0.0.1:8088",
                   help="agent server base URL")
    p.add_argument("--brain", choices=["heuristic", "ollama"], default="heuristic")
    p.add_argument("--ollama", default="http://localhost:11434",
                   help="Ollama API base URL")
    p.add_argument("--model", default="qwen2.5vl", help="Ollama model name")
    p.add_argument("--no-vision", action="store_true",
                   help="text-only (skip the screenshot)")
    p.add_argument("--max-turns", type=int, default=60)
    p.add_argument("--delay", type=float, default=0.4,
                   help="seconds to let the world advance between turns")
    p.add_argument("--goal", default="",
                   help="stop when the objective text contains this substring")
    return run(p.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
