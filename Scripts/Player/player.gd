class_name Player
extends CharacterBody3D
## Third-person player controller. Builds its own capsule, camera rig,
## and interaction raycast at runtime so no .tscn wiring is needed.

signal focus_changed(node: Node3D)
signal painted(result: Dictionary)

const WALK_SPEED := 4.0
const RUN_SPEED := 7.5
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025
const INTERACT_RANGE := 3.5
const CAMERA_DISTANCE := 3.5

var _pivot: Node3D
var _camera: Camera3D
var _ray: RayCast3D
var _focused: Node3D = null
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	name = "Player"
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	col.shape = capsule
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	var mesh := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.height = 1.8
	capsule_mesh.radius = 0.35
	mesh.mesh = capsule_mesh
	mesh.position = Vector3(0, 0.9, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#3aa0c8")
	mesh.material_override = mat
	add_child(mesh)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 1.6, 0)
	add_child(_pivot)
	var arm := SpringArm3D.new()
	arm.spring_length = CAMERA_DISTANCE
	arm.position = Vector3(0.4, 0.2, 0)
	arm.add_excluded_object(get_rid())
	_pivot.add_child(arm)
	_camera = Camera3D.new()
	_camera.current = true
	arm.add_child(_camera)

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -(INTERACT_RANGE + CAMERA_DISTANCE))
	_ray.add_exception(self)
	_camera.add_child(_ray)

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_pivot.rotation.x = clampf(
			_pivot.rotation.x - event.relative.y * MOUSE_SENSITIVITY,
			deg_to_rad(-70.0), deg_to_rad(35.0))
	elif event.is_action_pressed("toggle_mouse"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("graffiti_tag"):
		GameState.select_graffiti_type("tag")
	elif event.is_action_pressed("graffiti_throwup"):
		GameState.select_graffiti_type("throwup")
	elif event.is_action_pressed("graffiti_piece"):
		GameState.select_graffiti_type("piece")
	elif event.is_action_pressed("cycle_color"):
		GameState.cycle_fill_color()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed := RUN_SPEED if Input.is_action_pressed("run") else WALK_SPEED
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
	move_and_slide()
	_update_focus()

func _update_focus() -> void:
	var focus: Node3D = null
	var collider: Object = _ray.get_collider()
	if collider != null and (
			collider is PaintableWall or collider is Npc or collider is PickupItem or collider.has_method("prompt_text")):
		if global_position.distance_to(_ray.get_collision_point()) <= INTERACT_RANGE + 1.5:
			focus = collider
	if focus != _focused:
		_focused = focus
		focus_changed.emit(focus)

func _try_interact() -> void:
	if _focused == null:
		return
	if _focused is PaintableWall:
		painted.emit(WallManager.paint_wall(
			_focused, GameState.selected_graffiti_type))
	elif _focused.has_method("interact"):
		_focused.interact()
