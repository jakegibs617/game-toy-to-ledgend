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
const DataLoader := preload("res://Scripts/Data/data_loader.gd")
const GraffitiFonts := preload("res://Scripts/Walls/graffiti_font_library.gd")
## Plan.md section 15 "Cleanup Retaliation": repainting a wall the city
## buffed pays extra — taking the spot back is part of the fantasy.
const BUFF_RETALIATION_BONUS := 1.25
## Walls remember (Plan.md section 9) — but not forever. History is
## deep-copied on every quick_save, so it stays bounded (Plan_v2.md §3.5).
const MAX_WALL_HISTORY := 20
## Crew-backed work (requiresCrew styles — murals) builds standing with
## your own people: the counterweight the gallery trade (Milestone 21)
## spends.
const CREW_WORK_CREW_REP := 2

var wall_defs: Array = []
var styles: Dictionary = {}
var wall_states: Dictionary = {}  # wall_id -> state dictionary
var wall_nodes: Dictionary = {}   # wall_id -> PaintableWall node
var _next_graffiti_id := 1

func _ready() -> void:
	var parsed_walls: Variant = DataLoader.load_json(WALLS_PATH, "WallManager")
	wall_defs = parsed_walls if parsed_walls is Array else []
	for def in wall_defs:
		DataLoader.require_fields(def,
			["wallId", "name", "districtId", "position", "rotationY", "size",
			"visibility", "risk", "color"],
			"WallManager: wall \"%s\"" % String(def.get("wallId", "?")))
	var parsed_styles: Variant = DataLoader.load_json(STYLES_PATH, "WallManager")
	styles = parsed_styles if parsed_styles is Dictionary else {}
	for type in styles:
		DataLoader.require_fields(styles[type],
			["label", "baseValue", "paintCost", "heatValue", "fillColor", "outlineColor"],
			"WallManager: style \"%s\"" % String(type))
		if styles[type] is Dictionary:
			# Styles know their own key so consumers holding only the
			# dict (rep multipliers, typed perks) can identify the type.
			styles[type]["type"] = type
	GraffitiFonts.style_ids()  # include tag-font catalog in startup validation

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
	var start := _begin_player_paint(wall, type)
	if not start["ok"]:
		return start
	var graffiti := _player_graffiti(wall.def, type, start["style"], start["rep"])
	_commit_player_graffiti(wall, start["state"], graffiti)
	return {"ok": true, "rep": start["rep"], "graffiti": graffiti}

## Freehand spray painting (Plan.md section 10 "Later Advanced System"):
## commits a player-drawn image as a piece. The hand-made work earns a
## style multiplier (Plan.md section 11) from canvas coverage and the
## number of colors used — a lazy scribble pays less than a full burner.
func paint_freehand(wall: PaintableWall, image: Image,
		colors_used: int, coverage: float) -> Dictionary:
	var style_mult := freehand_style_multiplier(colors_used, coverage)
	var start := _begin_player_paint(wall, "piece", style_mult,
		"Freehand work needs the Piece can unlocked.")
	if not start["ok"]:
		return start
	var graffiti := _player_graffiti(wall.def, "piece", start["style"], start["rep"])
	graffiti["freehand"] = true
	graffiti["image"] = Marshalls.raw_to_base64(image.save_png_to_buffer())
	graffiti["styleMultiplier"] = style_mult
	_commit_player_graffiti(wall, start["state"], graffiti)
	return {"ok": true, "rep": start["rep"], "styleMultiplier": style_mult, "graffiti": graffiti}

## Crew assist path (Milestone 22): recruited fillers can throw quick
## crew-backed throw-ups onto held territory. It still routes through
## WallManager and emits wall_painted so territory updates, but the
## creator is the member, not "player", so heat/XP/missions don't treat
## passive fill-ins as direct player paints.
func apply_crew_graffiti(wall_id: String, member: Dictionary, type := "throwup") -> Dictionary:
	if not wall_states.has(wall_id) or not wall_nodes.has(wall_id):
		return {"ok": false, "reason": "Unknown wall."}
	var style: Dictionary = styles.get(type, {})
	if style.is_empty():
		return {"ok": false, "reason": "Unknown graffiti type."}
	var graffiti := {
		"graffitiId": "graffiti_%03d" % _next_graffiti_id,
		"creatorId": String(member.get("memberId", "crew")),
		"crewId": "player_crew",
		"wallId": wall_id,
		"type": type,
		"alias": String(member.get("alias", GameState.alias)),
		"fillColor": member.get("color", style.get("fillColor", "#ffffff")),
		"outlineColor": style.get("outlineColor", "#000000"),
		"fontStyle": GameState.selected_tag_font_style(),
		"repValue": 0,
		"isCrossedOut": false,
		"isBuffed": false,
	}
	_next_graffiti_id += 1
	var state: Dictionary = wall_states[wall_id]
	_archive_current(state)
	state["currentGraffiti"] = graffiti
	state["ownerCrewId"] = "player"
	state["state"] = "player_" + type
	state.erase("crossOut")
	wall_nodes[wall_id].show_graffiti(graffiti)
	wall_painted.emit(wall_id, graffiti)
	return {"ok": true, "graffiti": graffiti}

## The shared head of every player paint path (Plan_v2.md §3.4): unlock
## check, paint spend, and the rep payout including the buff-retaliation
## bonus. A perk that discounts paint or boosts retaliation pay (Plan.md
## section 7) now has exactly one place to hook.
## Returns {ok: false, reason} or {ok: true, style, state, rep}.
func _begin_player_paint(wall: PaintableWall, type: String,
		style_mult := 1.0, unlock_reason := "") -> Dictionary:
	var style: Dictionary = styles.get(type, {})
	if style.is_empty():
		return {"ok": false, "reason": "Unknown graffiti type."}
	if not GameState.is_type_unlocked(type):
		var reason := unlock_reason if unlock_reason != "" \
			else "%s is not unlocked yet." % String(style.get("label", type))
		return {"ok": false, "reason": reason}
	var block := paint_block_reason(type, wall.def)
	if block != "":
		return {"ok": false, "reason": block}
	if not GameState.try_spend_paint(SupplyManager.paint_cost(style)):
		return {"ok": false, "reason": "Not enough paint."}
	var state: Dictionary = wall_states[wall.def["wallId"]]
	var rep := int(round(_reputation_for(style, wall.def) * style_mult))
	if String(state.get("state", "")) == "buffed":
		rep = int(round(rep * BUFF_RETALIATION_BONUS))
	return {"ok": true, "style": style, "state": state, "rep": rep}

## Style multiplier for hand-drawn work: filling the wall and mixing
## colors pays up to 2x a stock piece; a few stray dots pay half.
func freehand_style_multiplier(colors_used: int, coverage: float) -> float:
	return clampf(0.5 + coverage * 1.2 + 0.15 * (colors_used - 1), 0.5, 2.0)

## Surface rules (Plan.md §8/§9, Milestone 16): a style with a
## "surfaces" list only goes on those surface types — rollers need a
## rooftop parapet. Applies to everyone, rivals included.
func surface_block_reason(type: String, def: Dictionary) -> String:
	var style: Dictionary = styles.get(type, {})
	var surfaces: Array = style.get("surfaces", [])
	var surface := String(def.get("surfaceType", "plain"))
	if not surfaces.is_empty() and surface not in surfaces:
		return "%s work needs a %s surface — this is %s." % [
			String(style.get("label", type)), "/".join(PackedStringArray(surfaces)), surface]
	return ""

## Player-side paint rules beyond the unlock: surface fit, plus crew
## presence for murals (§8 — somebody holds the ladder and watches the
## street; the filler role specializes this in Milestone 22).
func paint_block_reason(type: String, def: Dictionary) -> String:
	var block := surface_block_reason(type, def)
	if block != "":
		return block
	var style: Dictionary = styles.get(type, {})
	if style.get("requiresCrew", false) and not CrewManager.any_recruited():
		return "A %s needs crew watching your back." % String(style.get("label", type)).to_lower()
	return ""

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
		"fontStyle": GameState.selected_tag_font_style(),
		"repValue": rep,
		"isCrossedOut": false,
		"isBuffed": false,
	}
	_next_graffiti_id += 1
	return graffiti

## Walls remember (Plan.md section 9) — but only the metadata. Stored
## freehand images are dropped from history so wall_states (deep-copied
## and JSON-written on every quick_save) doesn't grow by a full PNG
## each time a wall is repainted, and the array itself is capped at
## MAX_WALL_HISTORY entries, oldest first (Plan_v2.md §3.5).
func _archive_current(state: Dictionary) -> void:
	if state["currentGraffiti"] == null:
		return
	var entry: Dictionary = state["currentGraffiti"].duplicate()
	entry.erase("image")
	var history: Array = state["history"]
	history.append(entry)
	while history.size() > MAX_WALL_HISTORY:
		history.pop_front()

func _commit_player_graffiti(wall: PaintableWall, state: Dictionary, graffiti: Dictionary) -> void:
	_archive_current(state)
	state["currentGraffiti"] = graffiti
	state["ownerCrewId"] = "player"
	state["state"] = "player_" + String(graffiti["type"])
	state.erase("crossOut")
	GameState.add_reputation(int(graffiti["repValue"]))
	if styles.get(String(graffiti["type"]), {}).get("requiresCrew", false):
		GameState.add_crew_rep(CREW_WORK_CREW_REP)
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
		"fontStyle": GraffitiFonts.default_style_id(),
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
## multipliers, the current heat level — risky painting while the city
## is watching pays more (Plan.md section 12) — and the writer's Style
## stat + perks (Milestone 17, Plan.md section 6).
func _reputation_for(style: Dictionary, def: Dictionary) -> int:
	var base := float(style.get("baseValue", 10))
	var visibility_mult := 1.0 + 0.2 * float(def.get("visibility", 1))
	var risk_mult := 1.0 + 0.3 * float(def.get("risk", 1))
	return int(round(base * visibility_mult * risk_mult
		* HeatManager.rep_multiplier(String(def.get("districtId", "")))
		* StatsManager.rep_multiplier(String(style.get("type", "")))))
