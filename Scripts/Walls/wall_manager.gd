extends Node
## Loads wall definitions and graffiti styles from /Data, spawns
## PaintableWall nodes, applies graffiti, and tracks every wall's state
## in memory (the in-memory persistence required by Plan.md section 47).
## Autoloaded as WallManager.

signal wall_painted(wall_id: String, graffiti: Dictionary)
signal wall_crossed_out(wall_id: String)
signal wall_buffed(wall_id: String)

const WALLS_PATH := "res://Data/walls.json"
const STYLES_PATH := "res://Data/graffiti_styles.json"
## Plan.md section 15 "Cleanup Retaliation": repainting a wall the city
## buffed pays extra — taking the spot back is part of the fantasy.
const BUFF_RETALIATION_BONUS := 1.25

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
	elif String(wall_states[wall_id].get("state", "")) == "buffed":
		wall.show_buff()
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
	var cost := SupplyManager.paint_cost(style)
	if not GameState.try_spend_paint(cost):
		return {"ok": false, "reason": "Not enough paint."}
	var def := wall.def
	var state: Dictionary = wall_states[def["wallId"]]
	var rep := _reputation_for(style, def)
	if String(state.get("state", "")) == "buffed":
		rep = int(round(rep * BUFF_RETALIATION_BONUS))
	var graffiti := _player_graffiti(def, type, style, rep)
	_commit_player_graffiti(wall, state, graffiti)
	return {"ok": true, "rep": rep, "graffiti": graffiti}

## Freehand spray painting (Plan.md section 10 "Later Advanced System"):
## commits a player-drawn image as a piece. The hand-made work earns a
## style multiplier (Plan.md section 11) from canvas coverage and the
## number of colors used — a lazy scribble pays less than a full burner.
func paint_freehand(wall: PaintableWall, image: Image,
		colors_used: int, coverage: float) -> Dictionary:
	if not GameState.is_type_unlocked("piece"):
		return {"ok": false, "reason": "Freehand work needs the Piece can unlocked."}
	var style: Dictionary = styles.get("piece", {})
	if not GameState.try_spend_paint(SupplyManager.paint_cost(style)):
		return {"ok": false, "reason": "Not enough paint."}
	var def := wall.def
	var state: Dictionary = wall_states[def["wallId"]]
	var style_mult := freehand_style_multiplier(colors_used, coverage)
	var rep := int(round(_reputation_for(style, def) * style_mult))
	if String(state.get("state", "")) == "buffed":
		rep = int(round(rep * BUFF_RETALIATION_BONUS))
	var graffiti := _player_graffiti(def, "piece", style, rep)
	graffiti["freehand"] = true
	graffiti["image"] = Marshalls.raw_to_base64(image.save_png_to_buffer())
	graffiti["styleMultiplier"] = style_mult
	_commit_player_graffiti(wall, state, graffiti)
	return {"ok": true, "rep": rep, "styleMultiplier": style_mult, "graffiti": graffiti}

## Style multiplier for hand-drawn work: filling the wall and mixing
## colors pays up to 2x a stock piece; a few stray dots pay half.
func freehand_style_multiplier(colors_used: int, coverage: float) -> float:
	return clampf(0.5 + coverage * 1.2 + 0.15 * (colors_used - 1), 0.5, 2.0)

func _player_graffiti(def: Dictionary, type: String, style: Dictionary, rep: int) -> Dictionary:
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
	return graffiti

## Walls remember (Plan.md section 9) — but only the metadata. Stored
## freehand images are dropped from history so wall_states (deep-copied
## and JSON-written on every quick_save) doesn't grow by a full PNG
## each time a wall is repainted.
func _archive_current(state: Dictionary) -> void:
	if state["currentGraffiti"] == null:
		return
	var entry: Dictionary = state["currentGraffiti"].duplicate()
	entry.erase("image")
	state["history"].append(entry)

func _commit_player_graffiti(wall: PaintableWall, state: Dictionary, graffiti: Dictionary) -> void:
	_archive_current(state)
	state["currentGraffiti"] = graffiti
	state["ownerCrewId"] = "player"
	state["state"] = "player_" + String(graffiti["type"])
	state.erase("crossOut")
	GameState.add_reputation(int(graffiti["repValue"]))
	wall.show_graffiti(graffiti)
	wall_painted.emit(String(graffiti["wallId"]), graffiti)

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
	_archive_current(state)
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

## City cleanup paints over whatever is on the wall (Plan.md sections
## 18 and 33). The work moves into history — walls remember — and the
## wall shows mismatched gray roller patches until someone repaints.
func buff_wall(wall_id: String) -> bool:
	var state: Dictionary = wall_states.get(wall_id, {})
	if state.is_empty() or state.get("currentGraffiti") == null:
		return false
	state["currentGraffiti"]["isBuffed"] = true
	_archive_current(state)
	state["currentGraffiti"] = null
	state["ownerCrewId"] = "city"
	state["state"] = "buffed"
	state.erase("crossOut")
	if wall_nodes.has(wall_id):
		wall_nodes[wall_id].show_buff()
	wall_buffed.emit(wall_id)
	return true

func save_state() -> Dictionary:
	return {
		"wall_states": wall_states.duplicate(true),
		"next_graffiti_id": _next_graffiti_id,
	}

func load_state(data: Dictionary) -> void:
	if data.has("wall_states"):
		wall_states = data["wall_states"].duplicate(true)
	if data.has("next_graffiti_id"):
		_next_graffiti_id = int(data["next_graffiti_id"])
	_refresh_wall_visuals()

func _refresh_wall_visuals() -> void:
	for wall_id in wall_nodes:
		var wall: PaintableWall = wall_nodes[wall_id]
		var state: Dictionary = wall_states.get(wall_id, {})
		wall.clear_graffiti()
		if String(state.get("state", "")) == "buffed":
			wall.show_buff()
		if state.get("currentGraffiti") != null:
			wall.show_graffiti(state["currentGraffiti"])
		if state.has("crossOut"):
			wall.show_cross_out(state["crossOut"])

## Plan.md section 11: base value scaled by visibility and risk
## multipliers, plus the current heat level — risky painting while the
## city is watching pays more (Plan.md section 12).
func _reputation_for(style: Dictionary, def: Dictionary) -> int:
	var base := float(style.get("baseValue", 10))
	var visibility_mult := 1.0 + 0.2 * float(def.get("visibility", 1))
	var risk_mult := 1.0 + 0.3 * float(def.get("risk", 1))
	return int(round(base * visibility_mult * risk_mult * HeatManager.rep_multiplier()))

func _load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("WallManager: cannot open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("WallManager: invalid JSON in %s" % path)
	return parsed
