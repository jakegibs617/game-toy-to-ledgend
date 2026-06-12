class_name PatrolGuard
extends CharacterBody3D
## Security patrol NPC (Plan.md sections 12, 18, 25). Walks a fixed
## waypoint route back and forth; when PatrolManager decides a guard
## witnessed the player painting, it gives chase. Catching the player
## hands the incident back to PatrolManager.

enum State {PATROL, CHASE, RETURN}

const IDLE_MODEL_PATH := "res://Assets/Characters/security_bull_idle.glb"
const WALK_MODEL_PATH := "res://Assets/Characters/security_bull_walking.glb"
const RUN_MODEL_PATH := "res://Assets/Characters/security_bull_running.glb"
const ALERT_MODEL_PATH := "res://Assets/Characters/security_bull_alert.glb"
const LOOK_AROUND_MODEL_PATH := "res://Assets/Characters/security_bull_look_around.glb"
const LADDER_CLIMB_MODEL_PATH := "res://Assets/Characters/security_bull_ladder_climb.glb"
const MODEL_SOURCE_HEIGHT := 1.7
const IDLE_ANIMATION_NAME := "Armature|clip0|baselayer"
const WALK_ANIMATION_NAME := "Armature|walking_man|baselayer"
const RUN_ANIMATION_NAME := "Armature|running|baselayer"
const ALERT_ANIMATION_NAME := "Armature|Alert|baselayer"
const LOOK_AROUND_ANIMATION_NAME := "Armature|Look_Around_Dumbfounded|baselayer"
const LADDER_CLIMB_ANIMATION_NAME := "Armature|Fast_Ladder_Climb|baselayer"
const AnimatedModelSet := preload("res://Scripts/Characters/animated_model_set.gd")

var state := State.PATROL

var _route_speed := 2.2
var _chase_speed := 6.2
var _spot_range := 9.0
var _catch_radius := 1.7
var _give_up_range := 18.0
var _give_up_seconds := 9.0
var _waypoints: Array[Vector3] = []
var _wp_index := 0
var _wp_dir := 1  # routes are walked ping-pong, not looped
var _target: Node3D = null
var _chase_time := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _visual_models: Dictionary = {}
var _visual_animation_players: Dictionary = {}
var _visual_animation_names: Dictionary = {}
var _active_visual_state := ""
var _action_visual_state := ""
var _action_visual_time_left := 0.0

func setup(route: Dictionary, config: Dictionary) -> void:
	name = "PatrolGuard_%s" % String(route.get("routeId", "route"))
	_route_speed = float(route.get("speed", _route_speed))
	_chase_speed = float(config.get("chaseSpeed", _chase_speed))
	_spot_range = float(config.get("spotRange", _spot_range))
	_catch_radius = float(config.get("catchRadius", _catch_radius))
	_give_up_range = float(config.get("giveUpRange", _give_up_range))
	_give_up_seconds = float(config.get("giveUpSeconds", _give_up_seconds))
	for wp in route.get("waypoints", []):
		_waypoints.append(Vector3(wp[0], wp[1], wp[2]))
	if not _waypoints.is_empty():
		position = _waypoints[0]
	_build_body()

func is_chasing() -> bool:
	return state == State.CHASE

func start_chase(target: Node3D) -> void:
	_target = target
	_chase_time = 0.0
	state = State.CHASE
	play_context_animation("alert", 0.8)

func end_chase() -> void:
	if state == State.CHASE:
		state = State.RETURN
		play_context_animation("look_around", 1.2)

## True if the target is in range, inside the forward vision cone, and
## not blocked by level geometry. The player's Stealth stat shrinks
## the effective range (Milestone 17).
func can_see(target: CollisionObject3D) -> bool:
	var to := target.global_position - global_position
	if to.length() > _spot_range * StatsManager.spot_range_multiplier():
		return false
	if (-global_transform.basis.z).dot(to.normalized()) < 0.25:
		return false
	return _clear_line_to(target)

## A long paint job (mural exposure, Milestone 16): the writer stood
## at the wall so long that any guard close enough with a clear line
## of sight clocks them — distance scaled by `range_mult`, no facing
## cone (the guard turned around at some point).
func noticed_during(target: CollisionObject3D, range_mult: float) -> bool:
	var to := target.global_position - global_position
	if to.length() > _spot_range * range_mult * StatsManager.spot_range_multiplier():
		return false
	return _clear_line_to(target)

func _clear_line_to(target: CollisionObject3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1.5, 0),
		target.global_position + Vector3(0, 1.0, 0),
		0xFFFFFFFF, [get_rid(), target.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _physics_process(delta: float) -> void:
	if _action_visual_time_left > 0.0:
		_action_visual_time_left = maxf(_action_visual_time_left - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	match state:
		State.PATROL:
			_walk_route()
		State.RETURN:
			if _waypoints.is_empty() or _walk_toward(_waypoints[_wp_index], _route_speed * 1.25):
				state = State.PATROL
		State.CHASE:
			_chase(delta)
	_update_visual_animation()
	move_and_slide()

func _walk_route() -> void:
	if _waypoints.size() < 2:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	if _walk_toward(_waypoints[_wp_index], _route_speed):
		var next := _wp_index + _wp_dir
		if next < 0 or next >= _waypoints.size():
			_wp_dir = -_wp_dir
			next = _wp_index + _wp_dir
		_wp_index = next

func _chase(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		state = State.RETURN
		return
	# Security won't climb (Milestone 19): once the writer holds the
	# high ground, the chase is over.
	if _target.global_position.y - global_position.y > 2.5:
		state = State.RETURN
		PatrolManager.guard_gave_up(self)
		return
	_chase_time += delta
	var dist := global_position.distance_to(_target.global_position)
	if dist <= _catch_radius:
		PatrolManager.resolve_catch(self)
	elif dist > _give_up_range or _chase_time > _give_up_seconds:
		state = State.RETURN
		PatrolManager.guard_gave_up(self)
	else:
		_walk_toward(_target.global_position, _chase_speed)

## Steers toward `point` on the ground plane; true when close enough.
func _walk_toward(point: Vector3, speed: float) -> bool:
	var flat := point - global_position
	flat.y = 0.0
	if flat.length() < 0.35:
		velocity.x = 0.0
		velocity.z = 0.0
		return true
	var dir := flat.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	rotation.y = atan2(-dir.x, -dir.z)
	return false

func _build_body() -> void:
	if not _try_build_animated_visual():
		_build_capsule_fallback()

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.8
	shape.radius = 0.34
	col.shape = shape
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	var label := Label3D.new()
	label.text = "SECURITY"
	label.font_size = 52
	label.outline_size = 12
	label.pixel_size = 0.004
	label.position = Vector3(0, 2.15, 0)
	label.modulate = Color("#9fb4e8")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

	var flashlight := SpotLight3D.new()
	flashlight.position = Vector3(0, 1.5, 0)
	flashlight.rotation_degrees = Vector3(-12, 0, 0)
	flashlight.light_color = Color("#e8f0ff")
	flashlight.light_energy = 1.6
	flashlight.spot_range = _spot_range
	flashlight.spot_angle = 28.0
	add_child(flashlight)

func _try_build_animated_visual() -> bool:
	if not ResourceLoader.exists(WALK_MODEL_PATH) and not ResourceLoader.exists(RUN_MODEL_PATH):
		return false
	var container := Node3D.new()
	container.name = "SecurityBullModel"
	_apply_visual_transform(container)
	var built := false
	built = _add_animated_model(
		container, IDLE_MODEL_PATH, "idle", IDLE_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, WALK_MODEL_PATH, "walk", WALK_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, RUN_MODEL_PATH, "run", RUN_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, ALERT_MODEL_PATH, "alert", ALERT_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, LOOK_AROUND_MODEL_PATH, "look_around", LOOK_AROUND_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, LADDER_CLIMB_MODEL_PATH, "climb", LADDER_CLIMB_ANIMATION_NAME) or built
	if not built:
		return false
	add_child(container)
	_set_visual_state("idle")
	return true

func _add_animated_model(container: Node3D, path: String,
		visual_state: String, preferred_animation: String) -> bool:
	return AnimatedModelSet.add_animated_model(container, path, visual_state,
		preferred_animation, _visual_models, _visual_animation_players,
		_visual_animation_names)

func _apply_visual_transform(model: Node3D) -> void:
	var s := 1.8 / MODEL_SOURCE_HEIGHT
	model.scale = Vector3.ONE * s
	model.position = Vector3.ZERO
	model.rotation.y = PI

func _update_visual_animation() -> void:
	if _visual_animation_players.is_empty():
		return
	if _action_visual_time_left > 0.0 and _visual_models.has(_action_visual_state):
		_set_visual_state(_action_visual_state)
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 0.1:
		_set_visual_state("idle")
	elif state == State.CHASE and _visual_models.has("run"):
		_set_visual_state("run")
	else:
		_set_visual_state("walk")

func _set_visual_state(visual_state: String) -> void:
	var target := visual_state
	if target == "idle":
		target = "idle" if _visual_models.has("idle") else ("walk" if _visual_models.has("walk") else "run")
	if not _visual_models.has(target):
		return
	if _active_visual_state != target:
		for key in _visual_models:
			_visual_models[key].visible = String(key) == target
		_active_visual_state = target
	var player: AnimationPlayer = _visual_animation_players[target]
	var animation: StringName = _visual_animation_names[target]
	if visual_state == "idle":
		if player.is_playing():
			player.pause()
		player.seek(0.0, true)
		return
	player.speed_scale = 1.0
	if not player.is_playing() or String(player.current_animation) != String(animation):
		player.play(animation)

func play_context_animation(visual_state: String, duration := 0.75) -> void:
	if not _visual_models.has(visual_state):
		return
	_action_visual_state = visual_state
	_action_visual_time_left = duration
	_set_visual_state(visual_state)

func _build_capsule_fallback() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "CapsuleFallback"
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.34
	mesh.mesh = capsule
	mesh.position = Vector3(0, 0.9, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#27324f")
	mesh.material_override = mat
	add_child(mesh)
