class_name AmbientNpc
extends CharacterBody3D
## Lightweight ambient pedestrian (Milestone 25): walks a small
## waypoint loop, pauses to look at nearby fresh player work, and
## scatters when heat spikes. Data-driven from Data/ambient_npcs.json.

const AnimatedModelSet := preload("res://Scripts/Characters/animated_model_set.gd")

var data: Dictionary = {}
var _waypoints: Array[Vector3] = []
var _wp_index := 0
var _speed := 1.6
var _scatter_speed := 4.2
var _target_wall_id := ""
var _visual_models: Dictionary = {}
var _visual_animation_players: Dictionary = {}
var _visual_animation_names: Dictionary = {}
var _active_visual_state := ""
var _base_color := Color("#cccccc")
static var _crowd_paid_walls: Dictionary = {}

func setup(def: Dictionary) -> void:
	data = def
	name = String(def.get("npcId", "ambient_npc"))
	_speed = float(def.get("speed", _speed))
	_base_color = Color(String(def.get("color", "#cccccc")))
	for p in def.get("waypoints", []):
		_waypoints.append(Vector3(p[0], p[1], p[2]))
	if not _waypoints.is_empty():
		position = _waypoints[0]
	_build_body()
	WallManager.wall_painted.connect(_on_wall_painted)
	HeatManager.heat_level_changed.connect(func(level: String, rising: bool) -> void:
		var in_this_district := GameState.current_district_id == String(data.get("districtId", ""))
		if rising and in_this_district and level in ["Hot", "Blazing"]:
			_scatter())

func _physics_process(_delta: float) -> void:
	var target: Variant = _current_target()
	if target == null:
		velocity = Vector3.ZERO
		_set_visual_state("idle")
	else:
		_walk_toward(target)
	move_and_slide()

func _current_target() -> Variant:
	if _target_wall_id != "" and WallManager.wall_nodes.has(_target_wall_id):
		return WallManager.wall_nodes[_target_wall_id].global_position
	if _waypoints.is_empty():
		return null
	return _waypoints[_wp_index]

func _walk_toward(point: Vector3) -> void:
	var flat := point - global_position
	flat.y = 0.0
	if flat.length() < 0.45:
		velocity = Vector3.ZERO
		_set_visual_state("idle")
		if _target_wall_id != "":
			_pay_crowd_rep(_target_wall_id)
			_target_wall_id = ""
		elif not _waypoints.is_empty():
			_wp_index = (_wp_index + 1) % _waypoints.size()
		return
	var dir := flat.normalized()
	velocity.x = dir.x * _speed
	velocity.z = dir.z * _speed
	rotation.y = atan2(-dir.x, -dir.z)
	_set_visual_state("walk")

func crowd_target_wall_id() -> String:
	return _target_wall_id

func walking_speed() -> float:
	return _speed

func _scatter() -> void:
	_target_wall_id = ""
	if _waypoints.is_empty():
		return
	_wp_index = (_wp_index + maxi(_waypoints.size() / 2, 1)) % _waypoints.size()
	_speed = _scatter_speed

func _on_wall_painted(wall_id: String, graffiti: Dictionary) -> void:
	if String(graffiti.get("creatorId", "")) != "player":
		return
	if _crowd_paid_walls.has(wall_id):
		return
	var wall: Node3D = WallManager.wall_nodes.get(wall_id, null)
	if wall != null and global_position.distance_to(wall.global_position) <= float(data.get("reactRange", 24.0)):
		_target_wall_id = wall_id

func _pay_crowd_rep(wall_id: String) -> void:
	if _crowd_paid_walls.has(wall_id):
		return
	_crowd_paid_walls[wall_id] = true
	GameState.add_reputation(1)
	GameState.player_event.emit("%s stops to check the fresh paint. (+1 rep)" %
		String(data.get("label", "Someone")))

func _build_body() -> void:
	if not _try_build_visual():
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.height = 1.7
		capsule.radius = 0.28
		mesh.mesh = capsule
		mesh.position = Vector3(0, 0.85, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _base_color
		mesh.material_override = mat
		add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.7
	shape.radius = 0.28
	col.shape = shape
	col.position = Vector3(0, 0.85, 0)
	add_child(col)
	var label := Label3D.new()
	label.text = String(data.get("label", "LOCAL"))
	label.font_size = 38
	label.outline_size = 8
	label.pixel_size = 0.003
	label.position = Vector3(0, 2.05, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _try_build_visual() -> bool:
	var visuals: Dictionary = data.get("visuals", {})
	if visuals.is_empty():
		return false
	var root := AnimatedModelSet.build_from_manifest(self, visuals,
		_visual_models, _visual_animation_players, _visual_animation_names)
	if root == null:
		return false
	_set_visual_state(String(visuals.get("initialState", "idle")))
	return true

func _set_visual_state(state: String) -> void:
	if _visual_animation_players.is_empty():
		return
	var target := state if _visual_models.has(state) else String(_visual_models.keys()[0])
	if _active_visual_state != target:
		for key in _visual_models:
			_visual_models[key].visible = String(key) == target
		_active_visual_state = target
	var player: AnimationPlayer = _visual_animation_players[target]
	var animation: StringName = _visual_animation_names[target]
	if target == "idle":
		player.speed_scale = 0.5
	else:
		player.speed_scale = 1.0
	if not player.is_playing() or String(player.current_animation) != String(animation):
		player.play(animation)
