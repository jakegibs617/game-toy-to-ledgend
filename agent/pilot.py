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
import re
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
                "aim_at", "goto_wall", "goto_actor", "goto_objective",
                "stop", "paint", "freehand", "rest", "wait",
            ],
        },
        "slot": {"type": "integer"},
        "wallId": {"type": "string"},
        "actorId": {"type": "string"},
        "targetType": {"type": "string", "enum": ["wall", "actor"]},
        "targetWallId": {"type": "string"},
        "targetActorId": {"type": "string"},
        "dir": {"type": "string", "enum": ["forward", "back", "left", "right"]},
        "seconds": {"type": "number"},
        "dx": {"type": "number"},
        "dy": {"type": "number"},
        "playtest_note": {"type": "string"},
        "recommendation": {"type": "string"},
        "recommendation_category": {
            "type": "string",
            "enum": ["navigation", "objective", "feedback", "controls", "content", "balance", "ui", "performance", "other"],
        },
        "recommendation_priority": {
            "type": "string",
            "enum": ["low", "medium", "high"],
        },
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

    def observe(self, want_shot: bool = True) -> dict:
        url = self.base + "/observe" + ("" if want_shot else "?shot=0")
        return _get(url)

    def act(self, action: dict) -> dict:
        return _post(self.base + "/act", action)


# --- brains -----------------------------------------------------------------

def heuristic_brain(obs: dict) -> dict:
    """A tiny rule-based player: dismiss the alias modal, walk to the nearest
    paintable wall, tag it, then idle. No model required."""
    if not obs.get("alias_chosen", True):
        return {"reason": "start game", "action": "paint"}  # E confirms the alias

    walls = obs.get("nearby_walls") or []
    states = {w["wallId"]: w.get("state") for w in walls}

    focused = obs.get("focused_wall") or ""
    prompt = obs.get("prompt") or ""
    # Only tag a wall we don't already own — otherwise we'd repaint it forever.
    fresh_focus = focused and not str(states.get(focused, "")).startswith("player_")
    if fresh_focus and "Paint" in prompt:
        if obs.get("selected_can") != "tag":
            return {"reason": "use the tag can", "action": "select_can", "slot": 1}
        return {"reason": f"tag {focused}", "action": "paint"}

    nav = obs.get("nav") or {}
    if nav.get("goto_target") or nav.get("goto_actor"):
        return {"reason": "walking to target", "action": "wait"}

    target = obs.get("objective_target") or {}
    if target and "goto_objective" in (obs.get("legal_actions") or []):
        return _goto_objective_action(target, "follow the objective marker")

    objective = (obs.get("objective") or "").lower()
    actors = obs.get("nearby_actors") or []
    if "safehouse" in objective:
        safehouse = next((a for a in actors if a.get("actorId") == "safehouse"), None)
        if safehouse:
            return {"reason": "return to the safehouse", "action": "goto_actor",
                    "actorId": "safehouse"}

    blank = next((w for w in walls if w.get("state") == "blank"), None)
    target = blank or next(
        (w for w in walls if not str(w.get("state")).startswith("player_")), None)
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
        hint = _opening_hint(obs)
        user = (
            "Current observation (JSON):\n" + json.dumps(view, indent=2) +
            ("\n\nCurrent tactical hint: " + hint if hint else "") +
            "\n\nChoose exactly one action from legal_actions to progress the current objective. "
            "Play as a curious completionist: when the objective allows a choice, prefer actions "
            "that reveal new places, characters, mechanics, cans, tools, menus, or reactions over "
            "repeating an already proven action. "
            "Also act as a playtester. If this turn reveals friction, confusion, delight, missing "
            "feedback, or an opportunity to make the game better, include playtest_note and a concise "
            "recommendation with recommendation_category and recommendation_priority. Leave those "
            "fields empty when there is nothing useful to recommend. "
            "Do not choose rest unless rest is listed in legal_actions. "
            "If objective_target is present, prefer goto_objective unless you are already focused "
            "on the required interaction. "
            "If the objective says to return to the safehouse but no safehouse action is available, "
            "choose goto_actor with actorId safehouse when available. "
            "Avoid no-op actions, such as selecting the can that is already selected. "
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
            action = _parse_action_content(content)
        except json.JSONDecodeError:
            return _fallback_action(obs, "unparseable model output")
        if not isinstance(action, dict) or "action" not in action:
            return _fallback_action(obs, "no action field")
        legal = obs.get("legal_actions") or []
        if legal and action.get("action") not in legal:
            return _fallback_action(obs, f"model chose unavailable {action.get('action')}")
        if _is_noop_action(obs, action):
            return _fallback_action(obs, f"model chose no-op {action.get('action')}")
        return action


# --- main loop --------------------------------------------------------------

def summarize(obs: dict) -> str:
    return (f"rep={obs.get('reputation')} paint={obs.get('paint')} "
            f"heat={obs.get('heat')} can={obs.get('selected_can')} "
            f"focus={obs.get('focused_wall') or '-'} "
            f"obj={(obs.get('objective') or '')[:40]!r}")


def _fallback_action(obs: dict, reason: str) -> dict:
    if not obs.get("alias_chosen", True):
        return {"reason": reason + "; confirm alias", "action": "paint"}
    nav = obs.get("nav") or {}
    if nav.get("goto_target") or nav.get("goto_actor") or nav.get("aim_target"):
        return {"reason": reason + "; navigation already active", "action": "wait"}
    walls = obs.get("nearby_walls") or []
    focused = obs.get("focused_wall") or ""
    states = {w["wallId"]: w.get("state") for w in walls}
    prompt = obs.get("prompt") or ""
    legal = obs.get("legal_actions") or []
    slot = _required_slot_for_objective(obs)
    if slot and "select_can" in legal:
        slot_to_can = {1: "tag", 2: "throwup", 3: "piece", 4: "stencil", 5: "roller", 6: "mural"}
        if obs.get("selected_can") != slot_to_can.get(slot):
            return {"reason": reason + "; select objective can", "action": "select_can", "slot": slot}
    if focused and not str(states.get(focused, "")).startswith("player_") and "paint" in legal and "Paint" in prompt:
        return {"reason": reason + "; paint focused wall", "action": "paint"}
    if obs.get("objective_target") and "goto_objective" in legal:
        return _goto_objective_action(obs.get("objective_target") or {},
                                      reason + "; go to objective target")
    objective = (obs.get("objective") or "").lower()
    actors = obs.get("nearby_actors") or []
    if "safehouse" in objective and "goto_actor" in legal:
        if any(a.get("actorId") == "safehouse" for a in actors):
            return {"reason": reason + "; go to safehouse", "action": "goto_actor",
                    "actorId": "safehouse"}
    target = next((w for w in walls if not str(w.get("state")).startswith("player_")), None)
    if target and "goto_wall" in legal:
        return {"reason": reason + "; go to unowned wall", "action": "goto_wall", "wallId": target["wallId"]}
    if "move" in legal:
        return {"reason": reason + "; explore", "action": "move", "dir": "forward", "seconds": 0.5}
    return {"reason": reason + "; wait", "action": "wait"}


def _opening_hint(obs: dict) -> str:
    if not obs.get("alias_chosen", True):
        return "Choose paint to confirm the alias modal."
    objective = (obs.get("objective") or "").lower()
    legal = obs.get("legal_actions") or []
    prompt = obs.get("prompt") or ""
    focused = obs.get("focused_wall") or ""
    walls = obs.get("nearby_walls") or []
    if "first tag" in objective:
        if focused and "paint" in legal and "Paint" in prompt:
            return "The wall is focused and paint is legal; choose paint."
        target = next((w for w in walls if not str(w.get("state")).startswith("player_")), None)
        if target and "goto_wall" in legal:
            return f"Choose goto_wall with wallId {target['wallId']}."
    if obs.get("objective_target") and "goto_objective" in legal:
        return "Choose goto_objective to follow the current objective target."
    if "safehouse" in objective and "goto_actor" in legal:
        actors = obs.get("nearby_actors") or []
        if any(a.get("actorId") == "safehouse" for a in actors):
            return "Choose goto_actor with actorId safehouse."
    return ""


def _is_noop_action(obs: dict, action: dict) -> bool:
    nav = obs.get("nav") or {}
    chosen = action.get("action")
    if chosen == "goto_wall":
        return bool(nav.get("goto_target")) and nav.get("goto_target") == action.get("wallId")
    if chosen == "goto_actor":
        return bool(nav.get("goto_actor")) and nav.get("goto_actor") == action.get("actorId")
    if chosen == "aim_at":
        return bool(nav.get("aim_target")) and nav.get("aim_target") == action.get("wallId")
    if chosen == "goto_objective":
        target = _action_objective_target(obs, action)
        if target.get("type") == "wall":
            return bool(nav.get("goto_target")) and nav.get("goto_target") == target.get("wallId")
        if target.get("type") == "actor":
            return bool(nav.get("goto_actor")) and nav.get("goto_actor") == target.get("actorId")
        return False
    if chosen != "select_can":
        return False
    slot = int(action.get("slot", 1))
    selected = obs.get("selected_can")
    slot_to_can = {
        1: "tag",
        2: "throwup",
        3: "piece",
        4: "stencil",
        5: "roller",
        6: "mural",
    }
    return slot_to_can.get(slot) == selected


def _required_slot_for_objective(obs: dict) -> int:
    objective = (obs.get("objective") or "").lower()
    if re.search(r"\bthrow[- ]?up\b", objective):
        return 2
    if re.search(r"\bpiece\b", objective):
        return 3
    if re.search(r"\bstencil\b", objective):
        return 4
    if re.search(r"\broller\b", objective):
        return 5
    if re.search(r"\bmural\b", objective):
        return 6
    if re.search(r"\btag\b", objective):
        return 1
    return 0


def _parse_action_content(content: str) -> dict:
    text = content.strip()
    if text.startswith("```"):
        lines = text.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines).strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        if start != -1:
            obj, _ = json.JSONDecoder().raw_decode(text[start:])
            return obj
        raise


def _goto_objective_action(target: dict, reason: str) -> dict:
    action = {"reason": reason, "action": "goto_objective"}
    if target.get("type") == "wall" and target.get("wallId"):
        action.update({"targetType": "wall", "targetWallId": target["wallId"]})
    elif target.get("type") == "actor" and target.get("actorId"):
        action.update({"targetType": "actor", "targetActorId": target["actorId"]})
    return action


def _action_objective_target(obs: dict, action: dict) -> dict:
    target_type = action.get("targetType")
    if target_type == "wall" and action.get("targetWallId"):
        return {"type": "wall", "wallId": action.get("targetWallId")}
    if target_type == "actor" and action.get("targetActorId"):
        return {"type": "actor", "actorId": action.get("targetActorId")}
    return obs.get("objective_target") or {}


def run(args) -> int:
    game = Game(args.server)
    want_shot = args.brain == "ollama" and not args.no_vision
    if args.brain == "ollama":
        brain = OllamaBrain(args.ollama, args.model, not args.no_vision)
    else:
        brain = heuristic_brain

    try:
        game.observe(want_shot=False)
    except (urllib.error.URLError, OSError) as e:
        print(f"Cannot reach the game at {args.server}: {e}\n"
              f"Launch it with AGENT=1 first.", file=sys.stderr)
        return 2

    for turn in range(1, args.max_turns + 1):
        obs = game.observe(want_shot)
        action = brain(obs)
        reason = action.get("reason", "")
        print(f"[{turn:03d}] {summarize(obs)}", flush=True)
        print(f"      -> {action.get('action')} {('('+reason+')') if reason else ''}", flush=True)
        result = game.act(action)
        _record_recommendation(args.notes, turn, obs, action, result)
        if not result.get("ok"):
            print(f"      !! rejected: {result.get('error')}", flush=True)
        if action.get("recommendation"):
            print(f"      ?? rec[{action.get('recommendation_category', 'other')}]: "
                  f"{action.get('recommendation')}", flush=True)
        if args.goal and args.goal.lower() in (obs.get("objective") or "").lower():
            print(f"Reached goal objective: {obs.get('objective')!r}", flush=True)
            return 0
        time.sleep(args.delay)

    print("Max turns reached.", flush=True)
    return 0


def _record_recommendation(path: str, turn: int, obs: dict, action: dict, result: dict) -> None:
    note = str(action.get("playtest_note", "") or "").strip()
    recommendation = str(action.get("recommendation", "") or "").strip()
    if not note and not recommendation:
        return
    entry = {
        "turn": turn,
        "time": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "objective": obs.get("objective", ""),
        "district": obs.get("district", ""),
        "focused_wall": obs.get("focused_wall", ""),
        "action": action.get("action", ""),
        "reason": action.get("reason", ""),
        "playtest_note": note,
        "recommendation": recommendation,
        "category": action.get("recommendation_category", "other") or "other",
        "priority": action.get("recommendation_priority", "medium") or "medium",
        "result_ok": bool(result.get("ok", True)),
    }
    try:
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError as e:
        print(f"Warning: could not record recommendation to {path}: {e}", file=sys.stderr)


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
    p.add_argument("--notes", default=os.path.join(HERE, "playtest_recommendations.jsonl"),
                   help="JSONL file for model playtest notes/recommendations")
    return run(p.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
