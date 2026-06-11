extends Node
## Milestone 8 save/load. Persists the vertical slice's meaningful
## runtime state to disk: player position, progression, walls, crew,
## territory, and mission progress.

signal save_event(message: String)

const SAVE_PATH := "user://toy_to_legend_save.json"
const SAVE_VERSION := 1

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
	GameState.load_state(data.get("game", {}))
	WallManager.load_state(data.get("walls", {}))
	CrewManager.load_state(data.get("crew", {}))
	TerritoryManager.load_state(data.get("territory", {}))
	HeatManager.load_state(data.get("heat", {}))
	SupplyManager.load_state(data.get("supplies", {}))
	DialogueManager.load_state(data.get("dialogue", {}))
	MissionManager.load_state(data.get("missions", {}))
	_apply_player_state(data.get("player", {}))
	save_event.emit("Loaded prototype state.")
	return true

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
