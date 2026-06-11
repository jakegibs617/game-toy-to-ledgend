extends Node
## Loads wall definitions and graffiti styles from /Data, spawns
## PaintableWall nodes, applies graffiti, and tracks every wall's state
## in memory (the in-memory persistence required by Plan.md section 47).
## Autoloaded as WallManager.

signal wall_painted(wall_id: String, graffiti: Dictionary)
signal wall_crossed_out(wall_id: String)

const WALLS_PATH := "res://Data/walls.json"
const STYLES_PATH := "res://Data/graffiti_styles.json"

var wall_defs: Array = []
var styles: Dictionary = {}
var wall_states: Dictionary = {}  # wall_id -> state dictionary
var wall_nodes: Dictionary = {}   # wall_id -> PaintableWall node
var _next_graffiti_id := 1

func _ready() -> void:
	wall_defs = _load_json(WALLS_PATH)
	styles = _load_json(STYLES_PATH)

func spawn_walls(parent: Node3D) -> void:
	wall_nodes.clear()
	for def in wall_defs:
		spawn_wall(def, parent)

func spawn_wall(def: Dictionary, parent: Node3D) -> PaintableWall:
	var wall := PaintableWall.new()
	wall.setup(def)
	parent.add_child(wall)
	var wall_id: String = def["wallId"]
	wall_nodes[wall_id] = wall
	if not wall_states.has(wall_id):
		wall_states[wall_id] = {
			"ownerCrewId": def.get("ownerCrewId", "none"),
			"state": "blank",
			"currentGraffiti": null,
			"history": [],
		}
	elif wall_states[wall_id]["currentGraffiti"] != null:
		# Re-entering a scene: restore the remembered graffiti visually.
		wall.show_graffiti(wall_states[wall_id]["currentGraffiti"])
		if wall_states[wall_id].has("crossOut"):
			wall.show_cross_out(wall_states[wall_id]["crossOut"])
	return wall

func wall_def(wall_id: String) -> Dictionary:
	for def in wall_defs:
		if String(def["wallId"]) == wall_id:
			return def
	return {}

## Attempts to paint `type` graffiti on `wall` as the player.
## Returns {ok, rep, graffiti} on success or {ok: false, reason} on failure.
func paint_wall(wall: PaintableWall, type: String) -> Dictionary:
	if not GameState.is_type_unlocked(type):
		var label: String = styles.get(type, {}).get("label", type)
		return {"ok": false, "reason": "%s is not unlocked yet." % label}
	var style: Dictionary = styles.get(type, {})
	if style.is_empty():
		return {"ok": false, "reason": "Unknown graffiti type."}
	var cost := int(style.get("paintCost", 1))
	if not GameState.try_spend_paint(cost):
		return {"ok": false, "reason": "Not enough paint."}
	var def := wall.def
	var rep := _reputation_for(style, def)
	var graffiti := {
		"graffitiId": "graffiti_%03d" % _next_graffiti_id,
		"creatorId": "player",
		"crewId": "player_crew",
		"wallId": def["wallId"],
		"type": type,
		"alias": GameState.alias,
		"fillColor": GameState.current_fill_color() if GameState.colors_unlocked else style.get("fillColor", "#ffffff"),
		"outlineColor": style.get("outlineColor", "#000000"),
		"repValue": rep,
		"isCrossedOut": false,
		"isBuffed": false,
	}
	_next_graffiti_id += 1
	var state: Dictionary = wall_states[def["wallId"]]
	if state["currentGraffiti"] != null:
		state["history"].append(state["currentGraffiti"])
	state["currentGraffiti"] = graffiti
	state["ownerCrewId"] = "player"
	state["state"] = "player_" + type
	state.erase("crossOut")
	GameState.add_reputation(rep)
	wall.show_graffiti(graffiti)
	wall_painted.emit(def["wallId"], graffiti)
	return {"ok": true, "rep": rep, "graffiti": graffiti}

## A rival crew paints over whatever is on the wall (Plan.md section 13
## "cover weak graffiti" / initial territory claims).
func apply_rival_graffiti(wall_id: String, crew: Dictionary, type: String) -> Dictionary:
	var style: Dictionary = styles.get(type, {})
	var graffiti := {
		"graffitiId": "graffiti_%03d" % _next_graffiti_id,
		"creatorId": String(crew["crewId"]),
		"crewId": String(crew["crewId"]),
		"wallId": wall_id,
		"type": type,
		"alias": String(crew.get("tag", "???")),
		"fillColor": crew.get("fillColor", style.get("fillColor", "#ffffff")),
		"outlineColor": crew.get("outlineColor", style.get("outlineColor", "#000000")),
		"repValue": 0,
		"isCrossedOut": false,
		"isBuffed": false,
	}
	_next_graffiti_id += 1
	var state: Dictionary = wall_states[wall_id]
	if state["currentGraffiti"] != null:
		state["history"].append(state["currentGraffiti"])
	state["currentGraffiti"] = graffiti
	state["ownerCrewId"] = String(crew["crewId"])
	state["state"] = "rival_" + type
	state.erase("crossOut")
	if wall_nodes.has(wall_id):
		wall_nodes[wall_id].show_graffiti(graffiti)
	wall_painted.emit(wall_id, graffiti)
	return graffiti

## A rival crew defaces the current graffiti without covering it
## (Plan.md section 13 "TOY" mechanic). The graffiti stays visible but
## crossed out; the wall keeps its owner so the insult stings.
func cross_out_wall(wall_id: String, crew: Dictionary, text := "TOY") -> void:
	var state: Dictionary = wall_states[wall_id]
	if state["currentGraffiti"] != null:
		state["currentGraffiti"]["isCrossedOut"] = true
	state["state"] = "crossed_out"
	state["crossOut"] = {
		"by": String(crew["crewId"]),
		"text": text,
		"color": String(crew.get("crossOutColor", "#e0301e")),
	}
	if wall_nodes.has(wall_id):
		wall_nodes[wall_id].show_cross_out(state["crossOut"])
	wall_crossed_out.emit(wall_id)

## Plan.md section 11: base value scaled by visibility and risk multipliers.
func _reputation_for(style: Dictionary, def: Dictionary) -> int:
	var base := float(style.get("baseValue", 10))
	var visibility_mult := 1.0 + 0.2 * float(def.get("visibility", 1))
	var risk_mult := 1.0 + 0.3 * float(def.get("risk", 1))
	return int(round(base * visibility_mult * risk_mult))

func _load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("WallManager: cannot open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("WallManager: invalid JSON in %s" % path)
	return parsed
