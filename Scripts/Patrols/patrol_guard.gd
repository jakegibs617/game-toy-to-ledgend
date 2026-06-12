class_name PatrolGuard
extends CharacterBody3D
## Security patrol NPC (Plan.md sections 12, 18, 25). Walks a fixed
## waypoint route back and forth; when PatrolManager decides a guard
## witnessed the player painting, it gives chase. Catching the player
## hands the incident back to PatrolManager. Placeholder body: navy
## capsule with a flashlight showing its facing.

enum State {PATROL, CHASE, RETURN}

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

func end_chase() -> void:
	if state == State.CHASE:
		state = State.RETURN

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
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.34
	mesh.mesh = capsule
	mesh.position = Vector3(0, 0.9, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#27324f")
	mesh.material_override = mat
	add_child(mesh)

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
