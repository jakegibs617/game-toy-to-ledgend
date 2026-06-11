extends Node
## Vertical-slice mission chain (Plan.md sections 15, 16, and 35 —
## Milestone 7). Loads Data/missions.json and runs the five missions as
## a linear chain of sequential objectives. Objectives complete off the
## signals the existing systems already emit (WallManager, CrewManager,
## TerritoryManager, GameState), so missions stay data-driven glue
## rather than bespoke logic. Also owns the mission-only world actors:
## the safehouse zone and Lupe the supply contact. Autoloaded as
## MissionManager.

signal mission_started(mission: Dictionary)
signal objective_changed(mission: Dictionary, objective: Dictionary)
signal mission_completed(mission: Dictionary)
signal chain_completed
signal mission_event(message: String)

const MISSIONS_PATH := "res://Data/missions.json"
const STAGE_ORDER := ["not_met", "mission_active", "item_recovered", "recruited"]
const MissionZoneScene := preload("res://Scripts/Missions/mission_zone.gd")
const MissionActorScene := preload("res://Scripts/Missions/mission_actor.gd")

var actor_defs: Array = []
var missions: Array = []
var mission_index := -1
var objective_index := -1
var remembered: Dictionary = {}  # "@keys" recorded by objectives, e.g. first_tag_wall
var chain_done := false
var _began := false

func _ready() -> void:
	var parsed: Variant = _load_json(MISSIONS_PATH)
	if parsed is Dictionary:
		actor_defs = parsed.get("actors", [])
		missions = parsed.get("missions", [])
	WallManager.wall_painted.connect(_on_wall_painted)
	CrewManager.stage_changed.connect(_on_stage_changed)
	TerritoryManager.district_claimed.connect(_on_district_claimed)
	GameState.fill_color_changed.connect(_on_color_chosen)

## Spawns mission actors (safehouse zone + dressing, Lupe) into a scene.
func spawn_actors(parent: Node3D) -> void:
	for def in actor_defs:
		if String(def.get("kind", "npc")) == "zone":
			var pos: Array = def["position"]
			var size: Array = def["size"]
			var zone := MissionZoneScene.new()
			zone.setup(String(def["actorId"]),
				Vector3(pos[0], pos[1], pos[2]), Vector3(size[0], size[1], size[2]))
			parent.add_child(zone)
			_add_zone_dressing(parent, def)
		else:
			var actor := MissionActorScene.new()
			actor.setup(def)
			parent.add_child(actor)
	# Re-entering a scene while a reach_wall objective is live: the
	# one-shot trigger was lost with the old scene, so respawn it.
	if _active_type() == "reach_wall":
		_spawn_reach_zone(current_objective())

func begin_chain() -> void:
	if _began:
		return
	_began = true
	_start_mission(0)

func current_mission() -> Dictionary:
	if mission_index < 0 or mission_index >= missions.size():
		return {}
	return missions[mission_index]

func current_objective() -> Dictionary:
	var objectives: Array = current_mission().get("objectives", [])
	if chain_done or objective_index < 0 or objective_index >= objectives.size():
		return {}
	return objectives[objective_index]

func save_state() -> Dictionary:
	return {
		"mission_index": mission_index,
		"objective_index": objective_index,
		"remembered": remembered.duplicate(true),
		"chain_done": chain_done,
		"began": _began,
		"painted_objectives": _painted_objective_state(),
	}

func load_state(data: Dictionary) -> void:
	mission_index = int(data.get("mission_index", mission_index))
	objective_index = int(data.get("objective_index", objective_index))
	remembered = data.get("remembered", {}).duplicate(true)
	chain_done = bool(data.get("chain_done", chain_done))
	_began = bool(data.get("began", _began))
	_restore_painted_objectives(data.get("painted_objectives", {}))
	var mission := current_mission()
	var objective := current_objective()
	if not mission.is_empty():
		mission_started.emit(mission)
	if not objective.is_empty():
		objective_changed.emit(mission, objective)
		if String(objective.get("type", "")) == "reach_wall":
			_spawn_reach_zone(objective)
	if chain_done:
		chain_completed.emit()

## Zones and mission NPCs report the player here. Returns true if it
## advanced the active objective, so actors can fall back to idle lines.
func notify_actor(actor_id: String) -> bool:
	var obj := current_objective()
	if _active_type() in ["reach", "talk", "reach_wall"] and _objective_actor_id(obj) == actor_id:
		_complete_objective()
		return true
	return false

## The HUD intro panel reports the chosen alias here.
func notify_alias_chosen() -> void:
	if _active_type() == "choose_alias":
		_complete_objective()

func _start_mission(index: int) -> void:
	mission_index = index
	objective_index = -1
	var mission: Dictionary = missions[index]
	mission_started.emit(mission)
	mission_event.emit("NEW MISSION — %s" % String(mission["title"]))
	_apply_effects(mission.get("onStart", {}))
	_advance_objective()

func _advance_objective() -> void:
	objective_index += 1
	var mission := current_mission()
	var objectives: Array = mission.get("objectives", [])
	if objective_index >= objectives.size():
		_complete_mission()
		return
	var obj: Dictionary = objectives[objective_index]
	objective_changed.emit(mission, obj)
	_setup_objective(obj)

## Scripted moments and already-satisfied checks when an objective
## becomes active (e.g. Moth recruited before her mission started).
func _setup_objective(obj: Dictionary) -> void:
	match String(obj.get("type", "")):
		"choose_alias":
			if GameState.alias_chosen:
				_complete_objective()
		"paint":
			obj["_painted"] = []
		"reach_wall":
			_spawn_reach_zone(obj)
		"defend":
			_script_defend(obj)
		"stage":
			var member: Dictionary = CrewManager.members.get(String(obj.get("memberId", "")), {})
			var have := STAGE_ORDER.find(String(member.get("stage", "not_met")))
			if have >= STAGE_ORDER.find(String(obj.get("stage", ""))):
				_complete_objective()
		"claim_district":
			if TerritoryManager.is_claimed(String(obj.get("districtId", ""))):
				_complete_objective()

func _complete_objective() -> void:
	_apply_effects(current_objective().get("onComplete", {}))
	_advance_objective()

func _complete_mission() -> void:
	var mission := current_mission()
	_apply_effects(mission.get("onComplete", {}))
	mission_completed.emit(mission)
	mission_event.emit("MISSION COMPLETE — %s" % String(mission["title"]))
	if mission_index + 1 < missions.size():
		_start_mission(mission_index + 1)
	else:
		chain_done = true
		chain_completed.emit()

## Mission/objective reward and scripted-event blocks from missions.json.
func _apply_effects(effects: Dictionary) -> void:
	if effects.is_empty():
		return
	for type in effects.get("unlockTypes", []):
		GameState.unlock_type(String(type))
	if effects.get("unlockColors", false):
		GameState.unlock_colors()
	if effects.has("paint"):
		GameState.add_paint(int(effects["paint"]))
	if effects.has("cash"):
		GameState.add_cash(int(effects["cash"]))
	if effects.has("rep"):
		GameState.add_reputation(int(effects["rep"]))
	if effects.has("minRep") and GameState.reputation < int(effects["minRep"]):
		GameState.add_reputation(int(effects["minRep"]) - GameState.reputation)
	if effects.has("crossOut"):
		var co: Dictionary = effects["crossOut"]
		var wall_id := _resolve_wall(String(co.get("wall", "")))
		var crew: Dictionary = RivalManager.crews.get(String(co.get("crewId", "buff_kings")), {})
		if wall_id != "" and not crew.is_empty():
			WallManager.cross_out_wall(wall_id, crew, String(co.get("text", "TOY")))
	if effects.has("message"):
		mission_event.emit(String(effects["message"]))

## The Mission 5 "defend your wall" beat: a rival deterministically hits
## the player's latest wall, and the objective completes on the repaint.
func _script_defend(obj: Dictionary) -> void:
	var target := String(remembered.get("last_player_wall", ""))
	if target == "" or String(WallManager.wall_states.get(target, {}).get("ownerCrewId", "")) != "player":
		for wall_id in WallManager.wall_states:
			if String(WallManager.wall_states[wall_id]["ownerCrewId"]) == "player":
				target = wall_id
				break
	if target == "":
		return
	remembered["defend_wall"] = target
	var crew_id := String(obj.get("crewId", "buff_kings"))
	for crew in RivalManager.crews.values():
		if target in crew.get("territory", []):
			crew_id = String(crew["crewId"])
			break
	RivalManager.respond(target, crew_id)

func _on_wall_painted(wall_id: String, graffiti: Dictionary) -> void:
	if String(graffiti.get("creatorId", "")) != "player":
		return
	remembered["last_player_wall"] = wall_id
	var obj := current_objective()
	match _active_type():
		"paint":
			var types: Array = obj.get("graffitiTypes", [])
			if not types.is_empty() and String(graffiti["type"]) not in types:
				return
			var required_wall := _resolve_wall(String(obj.get("wall", "")))
			if required_wall != "" and wall_id != required_wall:
				return
			if obj.get("requireCrew", false) and not CrewManager.any_recruited():
				return
			var painted: Array = obj.get("_painted", [])
			if obj.get("distinctWalls", false) and wall_id in painted:
				return
			painted.append(wall_id)
			obj["_painted"] = painted
			if painted.size() >= int(obj.get("count", 1)):
				if obj.has("remember"):
					remembered[String(obj["remember"])] = wall_id
				_complete_objective()
		"defend":
			if wall_id == String(remembered.get("defend_wall", "")):
				_complete_objective()

func _on_stage_changed(member_id: String, stage: String) -> void:
	var obj := current_objective()
	if _active_type() == "stage" and String(obj.get("memberId", "")) == member_id \
			and String(obj.get("stage", "")) == stage:
		_complete_objective()

func _on_district_claimed(district_id: String, _district: Dictionary) -> void:
	if _active_type() == "claim_district" \
			and String(current_objective().get("districtId", "")) == district_id:
		_complete_objective()

func _on_color_chosen(_color_name: String) -> void:
	if _active_type() == "choose_color":
		_complete_objective()

func _active_type() -> String:
	return String(current_objective().get("type", ""))

func _painted_objective_state() -> Dictionary:
	var state := {}
	for i in range(missions.size()):
		var objectives: Array = missions[i].get("objectives", [])
		for j in range(objectives.size()):
			var obj: Dictionary = objectives[j]
			if obj.has("_painted"):
				state["%d:%d" % [i, j]] = obj["_painted"].duplicate(true)
	return state

func _restore_painted_objectives(state: Dictionary) -> void:
	for key in state:
		var parts := String(key).split(":")
		if parts.size() != 2:
			continue
		var mi := int(parts[0])
		var oi := int(parts[1])
		if mi < 0 or mi >= missions.size():
			continue
		var objectives: Array = missions[mi].get("objectives", [])
		if oi < 0 or oi >= objectives.size():
			continue
		objectives[oi]["_painted"] = state[key].duplicate(true)

func _objective_actor_id(obj: Dictionary) -> String:
	if obj.has("actorId"):
		return String(obj["actorId"])
	if String(obj.get("type", "")) == "reach_wall":
		return "reach_%s" % _resolve_wall(String(obj.get("wall", "")))
	return ""

## "@key" references resolve through walls remembered by earlier objectives.
func _resolve_wall(ref: String) -> String:
	if ref.begins_with("@"):
		return String(remembered.get(ref.substr(1), ""))
	return ref

## One-shot proximity trigger in front of a target wall ("go check on
## your first tag").
func _spawn_reach_zone(obj: Dictionary) -> void:
	var wall_id := _resolve_wall(String(obj.get("wall", "")))
	var def := WallManager.wall_def(wall_id)
	var scene := get_tree().current_scene
	if def.is_empty() or scene == null:
		return
	var pos: Array = def["position"]
	var size: Array = def["size"]
	var zone := MissionZoneScene.new()
	zone.setup("reach_%s" % wall_id,
		Vector3(pos[0], 1.2, pos[2]), Vector3(float(size[0]) + 2.0, 3.0, 5.0), true)
	scene.add_child(zone)

## Visual marker for a zone actor: a door slab and floating label.
func _add_zone_dressing(parent: Node3D, def: Dictionary) -> void:
	var door: Dictionary = def.get("door", {})
	if not door.is_empty():
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		var ds: Array = door["size"]
		box.size = Vector3(ds[0], ds[1], ds[2])
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(String(door.get("color", "#274156")))
		mesh.material_override = mat
		var dp: Array = door["position"]
		mesh.position = Vector3(dp[0], dp[1], dp[2])
		parent.add_child(mesh)
	if def.has("labelText"):
		var label := Label3D.new()
		label.text = String(def["labelText"])
		label.font_size = 48
		label.outline_size = 10
		label.pixel_size = 0.005
		var lp: Array = def.get("door", {}).get("position", def["position"])
		label.position = Vector3(lp[0], float(lp[1]) + 1.6, float(lp[2]) - 0.2)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		parent.add_child(label)

func _load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MissionManager: cannot open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("MissionManager: invalid JSON in %s" % path)
	return parsed
