extends Node
## Milestone 8 save/load. Persists the vertical slice's meaningful
## runtime state to disk: player position, progression, walls, crew,
## territory, and mission progress.

signal save_event(message: String)

const SAVE_PATH := "user://toy_to_legend_save.json"
## Bump whenever any section's shape changes (CLAUDE.md rule), and add
## the matching step to _migrate so mid-demo saves keep loading.
## v2 (Milestone 17): adds the "stats" section (xp, perk points, perks).
## v3 (Milestone 18): per-district heat dict; mission chains (chain
## index/flags, painted-objective keys gain a chain prefix).
## v4 (Milestone 20): painted train-car service state.
## v5 (Milestone 21): gallery sales log; "game" section gains crew_rep.
const SAVE_VERSION := 5

var _player: Player

func register_player(player: Player) -> void:
	_player = player

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func quick_save() -> bool:
	var data := {
		"version": SAVE_VERSION,
		"player": _player_state(),
		"game": GameState.save_state(),
		"walls": WallManager.save_state(),
		"crew": CrewManager.save_state(),
		"territory": TerritoryManager.save_state(),
		"heat": HeatManager.save_state(),
		"supplies": SupplyManager.save_state(),
		"dialogue": DialogueManager.save_state(),
		"missions": MissionManager.save_state(),
		"stats": StatsManager.save_state(),
		"trains": TrainManager.save_state(),
		"gallery": GalleryManager.save_state(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		save_event.emit("Save failed: couldn't write %s" % SAVE_PATH)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	save_event.emit("Saved prototype state. [F9] load")
	return true

func quick_load() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		save_event.emit("No save found yet. [F5] save")
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		save_event.emit("Load failed: save file is invalid.")
		return false
	var data: Dictionary = parsed
	if int(data.get("version", 0)) > SAVE_VERSION:
		save_event.emit("Load failed: save is from a newer prototype.")
		return false
	data = _migrate(data)
	var district_before := GameState.current_district_id
	GameState.load_state(data.get("game", {}))
	WallManager.load_state(data.get("walls", {}))
	CrewManager.load_state(data.get("crew", {}))
	TerritoryManager.load_state(data.get("territory", {}))
	HeatManager.load_state(data.get("heat", {}))
	SupplyManager.load_state(data.get("supplies", {}))
	DialogueManager.load_state(data.get("dialogue", {}))
	MissionManager.load_state(data.get("missions", {}))
	StatsManager.load_state(data.get("stats", {}))
	TrainManager.load_state(data.get("trains", {}))
	GalleryManager.load_state(data.get("gallery", {}))
	_apply_player_state(data.get("player", {}))
	# Every manager is restored — now it's safe for district listeners
	# (chain triggers, patrol respawns, HUD) to react to where we are.
	if GameState.current_district_id != district_before:
		GameState.district_changed.emit(GameState.current_district_id)
	save_event.emit("Loaded prototype state.")
	return true

## Upgrades an older save to the current schema, one version step at a
## time (Plan_v2.md §3.7). When SAVE_VERSION bumps to N, add an
## `if version < N:` block here that reshapes the N-1 sections.
func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 1))
	if version < 2:
		# v1 predates progression: fresh stats, no perks. The writer
		# keeps their rep/rank; the new systems start clean.
		data["stats"] = {}
		version = 2
	if version < 3:
		# v2's single heat value belonged to the only district there
		# was; the mission state was chain 0 of what is now a chain
		# list, so painted keys "mi:oi" gain the chain prefix "0:".
		var old_heat: Dictionary = data.get("heat", {})
		data["heat"] = {
			"by_district": {"district_mill_yard": float(old_heat.get("heat", 0.0))},
			"ticks_until_cleanup": int(old_heat.get("ticks_until_cleanup", 0)),
		}
		var missions: Dictionary = data.get("missions", {})
		missions["chain_index"] = 0
		missions["chain_flags"] = [{
			"started": bool(missions.get("began", false)),
			"done": bool(missions.get("chain_done", false)),
		}]
		var painted: Dictionary = missions.get("painted_objectives", {})
		var rekeyed := {}
		for key in painted:
			rekeyed["0:%s" % String(key)] = painted[key]
		missions["painted_objectives"] = rekeyed
		data["missions"] = missions
		version = 3
	if version < 4:
		data["trains"] = {}
		version = 4
	if version < 5:
		# v4 predates the gallery and the public/crew rep split: no
		# sales yet, and the writer's crew standing starts neutral.
		data["gallery"] = {}
		if data.has("game"):
			data["game"]["crew_rep"] = int(data["game"].get("crew_rep", 0))
		version = 5
	data["version"] = version
	return data

func _player_state() -> Dictionary:
	if _player == null:
		return {}
	return {
		"position": [_player.global_position.x, _player.global_position.y, _player.global_position.z],
		"rotation_y": _player.rotation.y,
	}

func _apply_player_state(data: Dictionary) -> void:
	if _player == null or data.is_empty():
		return
	var pos: Array = data.get("position", [])
	if pos.size() == 3:
		_player.global_position = Vector3(pos[0], pos[1], pos[2])
	_player.rotation.y = float(data.get("rotation_y", _player.rotation.y))
	_player.velocity = Vector3.ZERO
