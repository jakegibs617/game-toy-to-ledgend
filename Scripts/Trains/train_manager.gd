extends Node
## Milestone 20 train painting (ROADMAP.md): stopped cars can be
## painted during a short yard window, then earn visibility-over-time
## rep each time they pass through the known districts.

signal train_event(message: String)
signal train_painted(train_id: String, car: Dictionary)
signal train_passed(train_id: String, district_id: String, rep: int)

const TRAINS_PATH := "res://Data/trains.json"
const DataLoader := preload("res://Scripts/Data/data_loader.gd")
const TrainCarScript := preload("res://Scripts/World/train_car.gd")

var train_defs: Array = []
var train_states: Dictionary = {}  # train_id -> runtime/persisted state
var train_nodes: Dictionary = {}   # train_id -> TrainCar node

func _ready() -> void:
	var parsed: Variant = DataLoader.load_json(TRAINS_PATH, "TrainManager")
	train_defs = parsed if parsed is Array else []
	for def in train_defs:
		DataLoader.require_fields(def,
			["trainId", "label", "districtId", "yardPosition", "size",
			"stopTicks", "travelTicks", "paintCost", "paintRep", "passRep",
			"heatValue", "serviceDistricts"],
			"TrainManager: train \"%s\"" % String(def.get("trainId", "?")))
		var train_id := String(def.get("trainId", ""))
		if train_id == "":
			continue
		if not train_states.has(train_id):
			train_states[train_id] = _fresh_state(def)
	var timer := Timer.new()
	timer.wait_time = HeatManager.TICK_SECONDS
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)

func spawn_trains(parent: Node3D) -> void:
	train_nodes.clear()
	for def in train_defs:
		var car = TrainCarScript.new()
		car.setup(def)
		parent.add_child(car)
		train_nodes[String(def["trainId"])] = car
		_refresh_train_visual(String(def["trainId"]))

func state_for(train_id: String) -> Dictionary:
	return train_states.get(train_id, {})

func is_stopped(train_id: String) -> bool:
	return String(state_for(train_id).get("phase", "stopped")) == "stopped"

func can_paint(train_id: String) -> bool:
	var state := state_for(train_id)
	return is_stopped(train_id) and state.get("currentGraffiti") == null

func paint_train(train_id: String) -> Dictionary:
	var def := train_def(train_id)
	var state := state_for(train_id)
	if def.is_empty() or state.is_empty():
		return {"ok": false, "reason": "Unknown train car."}
	if not is_stopped(train_id):
		return {"ok": false, "reason": "Train's moving. Catch the next stop."}
	if state.get("currentGraffiti") != null:
		return {"ok": false, "reason": "This car already has your name in service."}
	var cost := int(def.get("paintCost", 8))
	if not GameState.try_spend_paint(cost):
		return {"ok": false, "reason": "Not enough paint for a train side."}
	var rep := roundi(float(def.get("paintRep", 90))
		* HeatManager.rep_multiplier(String(def.get("districtId", "")))
		* StatsManager.rep_multiplier("train"))
	var graffiti := {
		"graffitiId": "train_%s_%03d" % [train_id, int(state.get("paintCount", 0)) + 1],
		"creatorId": "player",
		"crewId": "player_crew",
		"trainId": train_id,
		"alias": GameState.alias,
		"type": "train",
		"fillColor": GameState.current_fill_color(),
		"outlineColor": "#101018",
		"fontStyle": GameState.selected_tag_font_style(),
		"repValue": rep,
		"passes": 0,
	}
	state["currentGraffiti"] = graffiti
	state["paintCount"] = int(state.get("paintCount", 0)) + 1
	GameState.add_reputation(rep)
	HeatManager.add_heat(float(def.get("heatValue", 22)), String(def.get("districtId", "")))
	StatsManager.add_xp("style", cost)
	train_painted.emit(train_id, graffiti)
	train_event.emit("Train painted: %s is rolling out with %s. +%d rep" % [
		String(def.get("label", train_id)), GameState.alias, rep])
	_refresh_train_visual(train_id)
	return {"ok": true, "rep": rep, "graffiti": graffiti}

func train_def(train_id: String) -> Dictionary:
	for def in train_defs:
		if String(def.get("trainId", "")) == train_id:
			return def
	return {}

func service_log() -> Array:
	var rows: Array = []
	for def in train_defs:
		var train_id := String(def.get("trainId", ""))
		var state := state_for(train_id)
		var graffiti: Variant = state.get("currentGraffiti")
		if graffiti == null:
			continue
		var row: Dictionary = def.duplicate(true)
		row["currentGraffiti"] = (graffiti as Dictionary).duplicate(true)
		row["phase"] = String(state.get("phase", "stopped"))
		row["ticks_left"] = int(state.get("ticksLeft", 0))
		rows.append(row)
	return rows

func save_state() -> Dictionary:
	return {"train_states": train_states.duplicate(true)}

func load_state(data: Dictionary) -> void:
	if data.has("train_states"):
		train_states = data["train_states"].duplicate(true)
	for def in train_defs:
		var train_id := String(def.get("trainId", ""))
		if train_id != "" and not train_states.has(train_id):
			train_states[train_id] = _fresh_state(def)
	for train_id in train_nodes:
		_refresh_train_visual(String(train_id))

func _fresh_state(def: Dictionary) -> Dictionary:
	return {
		"phase": "stopped",
		"ticksLeft": int(def.get("stopTicks", 2)),
		"currentGraffiti": null,
		"paintCount": 0,
	}

func _on_tick() -> void:
	for def in train_defs:
		var train_id := String(def.get("trainId", ""))
		var state := state_for(train_id)
		if state.is_empty():
			continue
		state["ticksLeft"] = int(state.get("ticksLeft", 1)) - 1
		if int(state["ticksLeft"]) > 0:
			continue  # visuals only change on phase/graffiti transitions
		if String(state.get("phase", "stopped")) == "stopped":
			state["phase"] = "passing"
			state["ticksLeft"] = int(def.get("travelTicks", 3))
			_score_passes(def, state)
		else:
			state["phase"] = "stopped"
			state["ticksLeft"] = int(def.get("stopTicks", 2))
		_refresh_train_visual(train_id)

func _score_passes(def: Dictionary, state: Dictionary) -> void:
	var graffiti: Variant = state.get("currentGraffiti")
	if graffiti == null:
		return
	var districts: Array = def.get("serviceDistricts", [])
	var per_pass := int(def.get("passRep", 24))
	for district_id in districts:
		GameState.add_reputation(per_pass)
		(graffiti as Dictionary)["passes"] = int((graffiti as Dictionary).get("passes", 0)) + 1
		train_passed.emit(String(def["trainId"]), String(district_id), per_pass)
		train_event.emit("%s rolled through %s. +%d rep" % [
			String(def.get("label", def["trainId"])),
			String(TerritoryManager.districts.get(String(district_id), {}).get("name", district_id)),
			per_pass])

func _refresh_train_visual(train_id: String) -> void:
	if train_nodes.has(train_id) and train_nodes[train_id].has_method("refresh_from_state"):
		train_nodes[train_id].refresh_from_state()
