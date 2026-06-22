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
                "aim_at", "goto_wall", "goto_actor", "goto_objective", "paint_objective",
                "stop", "paint", "interact", "freehand", "rest", "wait",
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

    if _objective_actor_nearby(obs) and "interact" in legal:
        return {"reason": "interact with objective actor", "action": "interact"}

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
    def __init__(self, host: str, model: str, use_vision: bool, notes_path: str = ""):
        self.host = host.rstrip("/")
        self.model = model
        self.use_vision = use_vision
        self.notes_path = notes_path
        self._turn = 0
        with open(CHEATSHEET, "r", encoding="utf-8") as f:
            self.system = f.read()

    def __call__(self, obs: dict) -> dict:
        self._turn += 1
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
            "If paint_objective is in legal_actions and the objective requires painting a specific "
            "wall, prefer paint_objective — it handles navigation, can selection, and painting in "
            "one stateful macro. "
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
        # Retry up to 3 times on timeout; qwen3:14b can be slow under memory pressure.
        _last_exc: Exception | None = None
        for _attempt in range(3):
            try:
                resp = _post(self.host + "/api/chat", payload, timeout=300.0)
                break
            except (TimeoutError, OSError) as exc:
                _last_exc = exc
                print(f"      !! Ollama timeout (attempt {_attempt+1}/3); retrying...",
                      flush=True)
                time.sleep(5)
        else:
            raise RuntimeError("Ollama failed after 3 attempts") from _last_exc
        content = resp.get("message", {}).get("content", "{}")
        try:
            action = _parse_action_content(content)
        except json.JSONDecodeError:
            _record_parse_failure(self.notes_path, self._turn, obs, content)
            repaired = _try_repair_json(self.host, self.model, content)
            if repaired:
                try:
                    action = _parse_action_content(repaired)
                except json.JSONDecodeError:
                    return _fallback_action(obs, "unparseable model output (repair failed)")
            else:
                return _fallback_action(obs, "unparseable model output")
        if not isinstance(action, dict) or "action" not in action:
            return _fallback_action(obs, "no action field")
        legal = obs.get("legal_actions") or []
        if legal and action.get("action") not in legal:
            return _fallback_action(obs, f"model chose unavailable {action.get('action')}")
        if action.get("action") == "goto_wall" and _focused_wall_ready_to_paint(obs):
            return _fallback_action(obs, "focused wall is ready to paint")
        if action.get("action") == "interact" and _focused_wall_ready_to_paint(obs):
            return _fallback_action(obs, "focused wall is ready to paint")
        if (action.get("action") in ("goto_actor", "goto_objective")
                and _objective_actor_nearby(obs)
                and "interact" in legal):
            return _fallback_action(obs, "objective actor already in interact range")
        if _is_noop_action(obs, action):
            return _fallback_action(obs, f"model chose no-op {action.get('action')}")
        invalid = _invalid_nav_params(obs, action)
        if invalid:
            return _fallback_action(obs, invalid)
        return action


# --- main loop --------------------------------------------------------------

def summarize(obs: dict) -> str:
    dist = obs.get("objective_distance", -1.0)
    dist_str = f" d={dist:.0f}m" if dist >= 0 else ""
    nav = obs.get("nav") or {}
    stuck = int(nav.get("stuck_frames", 0))
    nav_dist = nav.get("dist", -1.0)
    stuck_str = f" stuck={stuck}" if stuck > 10 else ""
    nav_dist_str = f" nav_d={nav_dist:.0f}m" if nav_dist >= 0 else ""
    return (f"rep={obs.get('reputation')} paint={obs.get('paint')} "
            f"heat={obs.get('heat')} can={obs.get('selected_can')} "
            f"focus={obs.get('focused_wall') or '-'}{dist_str}{nav_dist_str}{stuck_str} "
            f"obj={(obs.get('objective') or '')[:40]!r}")


def _fallback_action(obs: dict, reason: str) -> dict:
    action = _compute_fallback(obs, reason)
    action["_harness_fallback"] = True
    return action


def _compute_fallback(obs: dict, reason: str) -> dict:
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
    # Use paint_objective macro when available (Fix 1).
    if "paint_objective" in legal and obs.get("objective_required_can"):
        return {"reason": reason + "; use paint_objective macro", "action": "paint_objective"}
    if _objective_actor_nearby(obs) and "interact" in legal:
        return {"reason": reason + "; interact with objective actor", "action": "interact"}
    slot = _required_slot_for_objective(obs)
    if slot and "select_can" in legal:
        slot_to_can = {1: "tag", 2: "throwup", 3: "piece", 4: "stencil", 5: "roller", 6: "mural"}
        if obs.get("selected_can") != slot_to_can.get(slot):
            return {"reason": reason + "; select objective can", "action": "select_can", "slot": slot}
    if focused and not str(states.get(focused, "")).startswith("player_") and "paint" in legal:
        return {"reason": reason + "; paint focused wall", "action": "paint"}
    if "interact" in legal and "[E]" in prompt and "Paint" not in prompt \
            and not obs.get("objective_target"):
        return {"reason": reason + "; interact with focused object", "action": "interact"}
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
    if "goto_wall" in legal:
        return {"reason": reason + "; ask server for nearest unowned wall", "action": "goto_wall"}
    if "move" in legal:
        return {"reason": reason + "; explore", "action": "move", "dir": "forward", "seconds": 0.5}
    return {"reason": reason + "; wait", "action": "wait"}


def _opening_hint(obs: dict) -> str:
    if not obs.get("alias_chosen", True):
        return "Choose paint to confirm the alias modal."
    legal = obs.get("legal_actions") or []
    if _objective_actor_nearby(obs) and "interact" in legal:
        target = obs.get("objective_target") or {}
        aid = target.get("actorId", "the objective actor")
        return f"{aid} is already close enough; choose interact now."
    if "paint_objective" in legal and obs.get("objective_required_can"):
        req = obs.get("objective_required_can", "")
        return (f"paint_objective is available — it selects the {req} can, navigates to "
                f"the wall, and paints it automatically. Choose paint_objective now.")
    objective = (obs.get("objective") or "").lower()
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
        tgt = obs["objective_target"]
        ttype = tgt.get("type", "")
        if ttype == "actor":
            aid = tgt.get("actorId", "")
            return (f"Use goto_objective with targetType=actor and targetActorId={aid} "
                    f"to reach the objective. Do NOT use goto_wall here.")
        if ttype == "wall":
            wid = tgt.get("wallId", "")
            return (f"Use goto_objective with targetType=wall and targetWallId={wid} "
                    f"to reach the objective. Do NOT use goto_wall here.")
        return "Choose goto_objective to follow the current objective target."
    if "safehouse" in objective and "goto_actor" in legal:
        actors = obs.get("nearby_actors") or []
        if any(a.get("actorId") == "safehouse" for a in actors):
            return "Choose goto_actor with actorId safehouse."
    return ""


def _is_paint_objective_running(obs: dict) -> bool:
    """True if the server-side paint_objective macro is already running for the current wall."""
    nav = obs.get("nav") or {}
    obj_target = obs.get("objective_target") or {}
    target_wall = obj_target.get("wallId") if obj_target.get("type") == "wall" else ""
    # Server considers it running if goto_target or aim_target is set to the objective wall.
    return bool(target_wall and (
        nav.get("goto_target") == target_wall or nav.get("aim_target") == target_wall
    ))


def _objective_actor_nearby(obs: dict, max_dist: float = 3.5) -> bool:
    target = obs.get("objective_target") or {}
    if target.get("type") != "actor":
        return False
    actor_id = target.get("actorId")
    if not actor_id:
        return False
    for actor in obs.get("nearby_actors") or []:
        if actor.get("actorId") == actor_id and float(actor.get("distance", 999.0)) <= max_dist:
            return True
    return False


def _focused_wall_ready_to_paint(obs: dict) -> bool:
    focused = obs.get("focused_wall") or ""
    if not focused or "paint" not in (obs.get("legal_actions") or []):
        return False
    prompt = obs.get("prompt") or ""
    states = {w["wallId"]: w.get("state") for w in (obs.get("nearby_walls") or [])}
    return not str(states.get(focused, "")).startswith("player_")


def _invalid_nav_params(obs: dict, action: dict) -> str:
    """Return a non-empty reason string if a nav action is missing a required ID."""
    chosen = action.get("action", "")
    wall_id = action.get("wallId") or ""
    actor_id = action.get("actorId") or ""
    walls_by_id = {w["wallId"] for w in (obs.get("nearby_walls") or [])}
    actors_by_id = {a["actorId"] for a in (obs.get("nearby_actors") or [])}
    if chosen in ("goto_wall", "aim_at"):
        if not wall_id and chosen == "aim_at":
            return f"{chosen} with no wallId"
        if wall_id not in walls_by_id:
            if chosen == "goto_wall" and not wall_id:
                return ""
            return f"{chosen} wallId {wall_id!r} not in nearby_walls"
    if chosen == "goto_actor":
        if not actor_id:
            return "goto_actor with no actorId"
        if actor_id not in actors_by_id:
            return f"goto_actor actorId {actor_id!r} not in nearby_actors"
    return ""


def _is_noop_action(obs: dict, action: dict) -> bool:
    nav = obs.get("nav") or {}
    chosen = action.get("action")
    if chosen == "goto_wall":
        wall_id = (action.get("wallId") or "").strip()
        current_target = (nav.get("goto_target") or "").strip()
        # No wallId while nav is already running → server restarts to same nearest wall → noop.
        if not wall_id and current_target:
            return True
        return bool(current_target) and current_target == wall_id
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
    if chosen == "paint_objective":
        return _is_paint_objective_running(obs)
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


def _try_repair_json(host: str, model: str, bad_content: str) -> str:
    """Ask the model to return just the JSON, given its malformed output. Returns '' on failure."""
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": 'Return only valid JSON with an "action" field. No explanation.'},
            {"role": "user", "content": f"Fix this malformed JSON:\n{bad_content[:400]}"},
        ],
        "format": {"type": "object", "properties": {"action": {"type": "string"}}, "required": ["action"]},
        "stream": False,
        "options": {"temperature": 0.0},
    }
    try:
        resp = _post(host + "/api/chat", payload, timeout=30.0)
        return resp.get("message", {}).get("content", "")
    except Exception:
        return ""


def _record_parse_failure(path: str, turn: int, obs: dict, raw: str) -> None:
    if not path:
        return
    entry = {
        "turn": turn,
        "time": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "type": "parse_failure",
        "objective": obs.get("objective", ""),
        "raw_excerpt": raw[:200],
    }
    try:
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError as e:
        print(f"Warning: could not record parse failure to {path}: {e}", file=sys.stderr)


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
        brain = OllamaBrain(args.ollama, args.model, not args.no_vision, notes_path=args.notes)
    else:
        brain = heuristic_brain

    try:
        game.observe(want_shot=False)
    except (urllib.error.URLError, OSError) as e:
        print(f"Cannot reach the game at {args.server}: {e}\n"
              f"Launch it with AGENT=1 first.", file=sys.stderr)
        return 2

    # Stall tracking for automatic harness recommendations.
    fallback_streak = 0
    same_obj_streak = 0
    rejected_streak = 0
    prev_objective = ""
    last_auto_rec_turn = -99  # ensures first eligible stall can fire immediately
    last_forced_stop_turn = -99
    influence_skip_walls: set = set()  # walls to avoid during influence-grind stalls
    all_painted_walls: set = set()    # every wall ever painted this session; never cleared
    last_wall_skip_turn: int = -99
    _aim_redir_count: dict = {}  # wall_id -> consecutive aim-redirects without focus; reset on focus
    _AIM_REDIR_MAX: int = 4

    for turn in range(1, args.max_turns + 1):
        obs = game.observe(want_shot)
        # Reset aim-redirect counter for any wall now in focus (aim succeeded).
        _focused_now = obs.get("focused_wall") or ""
        if _focused_now:
            _aim_redir_count.pop(_focused_now, None)
        action = brain(obs)

        # Safety valve: if same objective for 20+ turns AND nav is stuck
        # (server already tried side-steps but can't make progress), force
        # a stop so the model can choose a different approach next turn.
        nav = obs.get("nav") or {}
        nav_active = bool(nav.get("goto_target") or nav.get("goto_actor"))
        nav_stuck = int(nav.get("stuck_frames", 0)) >= 60
        nav_stuck_light = int(nav.get("stuck_frames", 0)) >= 30  # softer threshold

        if "fill color" in (obs.get("objective") or "").lower() \
                and action.get("action") != "cycle_color" \
                and "cycle_color" in (obs.get("legal_actions") or []):
            action = {
                "reason": "harness: choose-color objective requires cycle_color",
                "action": "cycle_color",
                "_harness_fallback": True,
            }

        # Let active server navigation finish. Raw move/look or fresh nav actions
        # cancel/restart the controller and can strand the agent just outside
        # focus range while the objective itself has not changed.
        if nav_active and action.get("action") in (
                "move", "look", "aim_at", "goto_wall", "goto_actor",
                "goto_objective", "stop"):
            action = {
                "reason": f"model chose {action.get('action')} during active nav; wait",
                "action": "wait",
                "_harness_fallback": True,
            }
        if nav_active and action.get("action") == "interact" and not _objective_actor_nearby(obs):
            action = {
                "reason": "model chose non-objective interact during active nav; wait",
                "action": "wait",
                "_harness_fallback": True,
            }

        # Wall-skip for free-roam paint stalls: when stuck navigating to a wall and
        # there is no specific objective target (any unowned wall works), blacklist
        # the stuck wall and steer to a different nearby unowned wall instead.
        # Covers both "Own the block" influence grind and "Paint X walls" objectives.
        # Uses a soft stuck threshold (>=30) because the counter oscillates when
        # side-steps keep firing without making net progress.
        _goto_wall_active = bool(nav.get("goto_target")) and not nav.get("goto_actor")
        _has_specific_target = bool(obs.get("objective_target"))
        if (_goto_wall_active and not _has_specific_target
                and nav_active and (nav_stuck_light or same_obj_streak >= 12)
                and same_obj_streak >= 10
                and turn - last_wall_skip_turn >= 6):
            _stuck_wall = (nav.get("goto_target") or "").strip()
            if _stuck_wall:
                influence_skip_walls.add(_stuck_wall)
            _walls_near = obs.get("nearby_walls") or []
            _alt_wall = next(
                (w["wallId"] for w in _walls_near
                 if w["wallId"] not in influence_skip_walls
                 and not w.get("territory_neutral", False)
                 and not str(w.get("state", "")).startswith("player_")),
                None
            )
            if _alt_wall:
                action = {
                    "reason": f"harness: wall {_stuck_wall!r} blocked; trying {_alt_wall!r}",
                    "action": "goto_wall",
                    "wallId": _alt_wall,
                    "_harness_fallback": True,
                }
                last_wall_skip_turn = turn
                print(
                    f"      !! harness: influence wall-skip -> {_alt_wall!r} "
                    f"(skip: {sorted(influence_skip_walls)})",
                    flush=True,
                )

        # Close-wall aim: when model calls goto_wall during free-roam but the
        # player is already within 4 m of an unowned wall and the camera is not
        # on it, nav completes instantly (within GOTO_STOP_DIST=3 m) leaving
        # focus=-.  Redirect to aim_at so the model can paint next turn.
        # After _AIM_REDIR_MAX consecutive failures for the same wall without achieving
        # focus, stop redirecting so the model can navigate to a better angle.
        if (not _has_specific_target and action.get("action") == "goto_wall"
                and not obs.get("focused_wall") and not nav_active):
            _walls_near = obs.get("nearby_walls") or []
            _close_unowned = [
                w for w in _walls_near
                if not str(w.get("state", "")).startswith("player_")
                and not w.get("territory_neutral", False)
                and float(w.get("distance", 99.0)) <= 4.0
                and _aim_redir_count.get(w["wallId"], 0) < _AIM_REDIR_MAX
            ]
            if _close_unowned:
                _aim_w = min(_close_unowned, key=lambda w: float(w.get("distance", 99.0)))
                _cnt = _aim_redir_count.get(_aim_w["wallId"], 0) + 1
                _aim_redir_count[_aim_w["wallId"]] = _cnt
                action = {
                    "reason": (f"harness: already {_aim_w['distance']}m from unowned "
                               f"{_aim_w['wallId']!r}; aiming instead of re-navigating"),
                    "action": "aim_at",
                    "wallId": _aim_w["wallId"],
                    "_harness_fallback": True,
                }
                print(f"      !! harness: close-wall aim -> {_aim_w['wallId']!r} "
                      f"({_aim_w['distance']}m) [{_cnt}/{_AIM_REDIR_MAX}]", flush=True)

        # When paint is empty during a free-roam objective, navigate to the
        # safehouse and rest to refill.  With 0 paint no wall can be painted;
        # this is the only recovery path available mid-objective.
        if (not _has_specific_target and int(obs.get("paint", 1)) == 0
                and same_obj_streak >= 3):
            _actors = obs.get("nearby_actors") or []
            _at_safehouse = any(a.get("actorId") == "safehouse" for a in _actors)
            if _at_safehouse and "rest" in (obs.get("legal_actions") or []):
                action = {
                    "reason": "harness: paint=0 and at safehouse; resting to refill",
                    "action": "rest",
                    "_harness_fallback": True,
                }
                print("      !! harness: paint=0; resting at safehouse", flush=True)
            elif action.get("action") not in ("goto_actor", "rest"):
                action = {
                    "reason": "harness: paint=0; navigate to safehouse to rest",
                    "action": "goto_actor",
                    "actorId": "safehouse",
                    "_harness_fallback": True,
                }
                print("      !! harness: paint=0; heading to safehouse", flush=True)

        # If the model keeps nudging around a player-owned focused wall during a
        # free-roam paint objective, ask the server to pick the nearest valid
        # unowned wall globally. Nearby_walls can contain only the owned wall,
        # so choosing from the local list would strand the agent in place.
        if (not _has_specific_target and not nav_active and same_obj_streak >= 6
                and action.get("action") in ("move", "look", "wait", "interact")):
            _fw = obs.get("focused_wall") or ""
            _fw_state = next(
                (str(w.get("state", "")) for w in (obs.get("nearby_walls") or [])
                 if w["wallId"] == _fw),
                "",
            )
            if _fw and _fw_state.startswith("player_") and "goto_wall" in (obs.get("legal_actions") or []):
                action = {
                    "reason": f"harness: {_fw!r} already owned; find another wall",
                    "action": "goto_wall",
                    "_harness_fallback": True,
                }
                print(f"      !! harness: owned-wall roam redirect from {_fw!r}", flush=True)

        if (not _has_specific_target and not nav_active and same_obj_streak >= 6
                and not obs.get("focused_wall")
                and action.get("action") in ("move", "look", "wait")
                and "goto_wall" in (obs.get("legal_actions") or [])):
            action = {
                "reason": "harness: free-roam paint stall; find another wall",
                "action": "goto_wall",
                "_harness_fallback": True,
            }
            print("      !! harness: free-roam goto_wall redirect", flush=True)

        if (not _has_specific_target and not nav_active
                and "own the block" in (obs.get("objective") or "").lower()
                and action.get("action") == "interact"
                and not _objective_actor_nearby(obs)
                and "goto_wall" in (obs.get("legal_actions") or [])):
            action = {
                "reason": "harness: influence objective; skip non-objective interact",
                "action": "goto_wall",
                "_harness_fallback": True,
            }
            print("      !! harness: influence interact blocked", flush=True)

        # Block repainting already-owned walls and neutral walls during free-roam
        # paint objectives. The model sometimes revisits player-owned walls, or
        # paints glass/neutral walls that spend paint but add no influence.
        # Redirect to the nearest non-neutral unowned alt or ask the server to
        # pick one globally.
        if not _has_specific_target and action.get("action") == "paint":
            _fw = obs.get("focused_wall") or ""
            if _fw:
                _fw_wall = next(
                    (w for w in (obs.get("nearby_walls") or []) if w["wallId"] == _fw),
                    {},
                )
                _fw_state = str(_fw_wall.get("state", ""))
                _fw_neutral = bool(_fw_wall.get("territory_neutral", False))
                _influence_objective = "own the block" in (obs.get("objective") or "").lower()
                if _fw_state.startswith("player_") or (_fw_neutral and _influence_objective):
                    _walls_near = obs.get("nearby_walls") or []
                    _alt = next(
                        (w["wallId"] for w in _walls_near
                         if w["wallId"] not in influence_skip_walls
                         and not w.get("territory_neutral", False)
                         and not str(w.get("state", "")).startswith("player_")),
                        None,
                    )
                    action = (
                        {"reason": f"harness: {_fw!r} already owned; goto {_alt!r}",
                         "action": "goto_wall", "wallId": _alt, "_harness_fallback": True}
                        if _alt else
                        {"reason": f"harness: {_fw!r} already owned; no alt — stop",
                         "action": "goto_wall", "_harness_fallback": True}
                    )
                    print(f"      !! harness: paint blocked on {_fw!r} "
                          f"(state={_fw_state!r} neutral={_fw_neutral})", flush=True)

        # Track painted walls so neither the wall-skip nor the repaint-block
        # targets them again. influence_skip_walls is cleared on objective change;
        # all_painted_walls persists for the whole session and covers walls painted
        # in earlier objectives (e.g. wall_mill_glass_01 painted during "Put up a piece"
        # should stay off-limits when "Own the block" begins).
        if action.get("action") == "paint":
            _fw = obs.get("focused_wall") or ""
            if _fw:
                if not _has_specific_target:
                    influence_skip_walls.add(_fw)
                all_painted_walls.add(_fw)

        # Block secondary-object interact (bench, decoration) during free-roam
        # objectives when the model is clearly stalled. If there is no objective
        # actor nearby and same_obj is high, a non-paint interact is wasted time.
        # Redirect to the nearest unowned wall, or stop to let the model rethink.
        if (not _has_specific_target and action.get("action") == "interact"
                and same_obj_streak >= 15 and not _objective_actor_nearby(obs)):
            _walls_near = obs.get("nearby_walls") or []
            _alt = next(
                (w["wallId"] for w in _walls_near
                 if w["wallId"] not in influence_skip_walls
                 and not w.get("territory_neutral", False)
                 and not str(w.get("state", "")).startswith("player_")),
                None,
            )
            action = (
                {"reason": f"harness: bench-interact blocked; goto unowned {_alt!r}",
                 "action": "goto_wall", "wallId": _alt, "_harness_fallback": True}
                if _alt else
                {"reason": "harness: bench-interact blocked; no unowned wall visible",
                 "action": "stop", "_harness_fallback": True}
            )
            print(f"      !! harness: bench-interact blocked "
                  f"(same_obj={same_obj_streak})", flush=True)

        if (same_obj_streak >= 20 and nav_active and nav_stuck
                and turn - last_forced_stop_turn >= 8):
            action = {"reason": "harness: nav blocked too long — stopping to retry",
                      "action": "stop", "_harness_fallback": True}
            last_forced_stop_turn = turn
            print(f"      !! harness: forced stop (same_obj={same_obj_streak} "
                  f"stuck_frames={nav.get('stuck_frames')})", flush=True)

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

        # Update stall counters.
        obj_text = obs.get("objective") or ""
        is_fallback = bool(action.get("_harness_fallback"))
        is_rejected = not result.get("ok", True)
        if obj_text == prev_objective:
            same_obj_streak += 1
        else:
            same_obj_streak = 0
            prev_objective = obj_text
            fallback_streak = 0
            rejected_streak = 0
            influence_skip_walls.clear()
            _aim_redir_count.clear()
        fallback_streak = fallback_streak + 1 if is_fallback else 0
        rejected_streak = rejected_streak + 1 if is_rejected else 0

        # Emit an auto-recommendation when stalled, with a per-stall cooldown.
        _AUTO_REC_FALLBACK = 3
        _AUTO_REC_SAME_OBJ = 6
        _AUTO_REC_REJECTED = 3
        _AUTO_REC_COOLDOWN = 5
        stalled = (fallback_streak >= _AUTO_REC_FALLBACK
                   or same_obj_streak >= _AUTO_REC_SAME_OBJ
                   or rejected_streak >= _AUTO_REC_REJECTED)
        if stalled and turn - last_auto_rec_turn >= _AUTO_REC_COOLDOWN:
            _record_auto_recommendation(args.notes, turn, obs, fallback_streak, same_obj_streak)
            print(f"      !! auto-rec: stall detected (fallback={fallback_streak} "
                  f"same_obj={same_obj_streak} rejected={rejected_streak})", flush=True)
            last_auto_rec_turn = turn

        if args.goal and args.goal.lower() in (obs.get("objective") or "").lower():
            print(f"Reached goal objective: {obs.get('objective')!r}", flush=True)
            return 0
        time.sleep(args.delay)

    print("Max turns reached.", flush=True)
    return 0


def _record_auto_recommendation(path: str, turn: int, obs: dict,
                                fallback_streak: int, same_obj_streak: int) -> None:
    obj = obs.get("objective") or ""
    dist = obs.get("objective_distance", -1.0)
    dist_str = f"{dist:.1f}" if dist >= 0 else "unknown"
    note = (f"Harness detected stall: fallback_streak={fallback_streak} "
            f"same_obj_streak={same_obj_streak} dist={dist_str}")
    priority = "high" if fallback_streak >= 5 or same_obj_streak >= 8 else "medium"
    entry = {
        "turn": turn,
        "time": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "type": "auto_recommendation",
        "objective": obj,
        "district": obs.get("district", ""),
        "focused_wall": obs.get("focused_wall", ""),
        "action": "",
        "reason": note,
        "playtest_note": note,
        "recommendation": (
            f"Agent stalled on {obj!r} for {same_obj_streak} turns "
            f"(fallback {fallback_streak} times, dist={dist_str}). "
            "Consider: clearer progress signal, paint_objective macro if this is a paint task, "
            "or smaller navigation steps."
        ),
        "category": "objective",
        "priority": priority,
        "result_ok": True,
    }
    try:
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError as e:
        print(f"Warning: could not record auto-recommendation to {path}: {e}", file=sys.stderr)


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
    p.add_argument("--model", default="qwen3:14b", help="Ollama model name")
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
