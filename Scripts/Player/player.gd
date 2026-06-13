class_name Player
extends CharacterBody3D
## Third-person player controller. Builds its own capsule, camera rig,
## and interaction raycast at runtime so no .tscn wiring is needed.

signal focus_changed(node: Node3D)
signal painted(result: Dictionary)
signal freehand_requested(wall: PaintableWall)

const WALK_MODEL_PATH := "res://Assets/Characters/neon_rooster_walking.glb"
const RUN_MODEL_PATH := "res://Assets/Characters/neon_rooster_running.glb"
const IDLE_MODEL_PATH := "res://Assets/Characters/neon_rooster_character_output.glb"
const WALK_BACK_MODEL_PATH := "res://Assets/Characters/neon_rooster_walk_backward.glb"
const RUN_FAST_MODEL_PATH := "res://Assets/Characters/neon_rooster_run_fast.glb"
const JUMP_MODEL_PATH := "res://Assets/Characters/neon_rooster_jump.glb"
const CLIMB_MODEL_PATH := "res://Assets/Characters/neon_rooster_ladder_climb.glb"
const CLIMB_FINISH_MODEL_PATH := "res://Assets/Characters/neon_rooster_ladder_climb_finish.glb"
const VAULT_MODEL_PATH := "res://Assets/Characters/neon_rooster_vault.glb"
const STATIC_MODEL_PATH := "res://Assets/Characters/neon_rooster.glb"
const ANIMATED_MODEL_SOURCE_HEIGHT := 1.7  # animated GLBs have feet at local y=0
const STATIC_MODEL_SOURCE_HEIGHT := 1.913  # static fallback GLB is origin-centered
const IDLE_ANIMATION_NAME := "Armature|clip0|baselayer"
# Extra idle clips (Product_reqs.md): the rooster picks one at random each
# time it settles from movement and holds that stance for the whole idle —
# the pose only changes the next time idle re-activates, not while standing
# still. Keyed visual-state -> (GLB path, clip name). Missing imports just
# shrink the pool.
const IDLE_VARIANTS := {
	"idle_4": ["res://Assets/Characters/neon_rooster_idle_4.glb", "Armature|Idle_4|baselayer"],
	"idle_6": ["res://Assets/Characters/neon_rooster_idle_6.glb", "Armature|Idle_6|baselayer"],
	"idle_11": ["res://Assets/Characters/neon_rooster_idle_11.glb", "Armature|Idle_11|baselayer"],
}
const WALK_ANIMATION_NAME := "Armature|walking_man|baselayer"
const WALK_BACK_ANIMATION_NAME := "Armature|Walk_Backward_inplace|baselayer"
const RUN_ANIMATION_NAME := "Armature|running|baselayer"
const RUN_FAST_ANIMATION_NAME := "Armature|RunFast|baselayer"
const JUMP_ANIMATION_NAME := "Armature|Regular_Jump|baselayer"
const CLIMB_ANIMATION_NAME := "Armature|Fast_Ladder_Climb|baselayer"
const CLIMB_FINISH_ANIMATION_NAME := "Armature|Ladder_Climb_Finish|baselayer"
# The ladder-climb clip is authored gripping a rail off to one side, so the
# body reads as floating to the right of our rung mesh. Shift just the climb
# model left (and a touch toward the wall) so the hands land on the ladder
# (Product_reqs ladder feature). Local to the PI-rotated model container, so
# +x is screen-left while climbing.
const CLIMB_VISUAL_OFFSET := Vector3(0.45, 0.0, -0.1)
const VAULT_ANIMATION_NAME := "Armature|Parkour_Vault_2|baselayer"
const AnimatedModelSet := preload("res://Scripts/Characters/animated_model_set.gd")

const WALK_SPEED := 4.0
const RUN_SPEED := 7.5
const CLIMB_SPEED := 3.2
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025
const JOY_LOOK_SENSITIVITY := 2.4
const JOY_LOOK_DEADZONE := 0.18
const INTERACT_RANGE := 3.5
const CAMERA_DISTANCE := 3.5

var _pivot: Node3D
var _camera: Camera3D
var _ray: RayCast3D
var _focused: Node3D = null
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _visual_models: Dictionary = {}
var _visual_animation_players: Dictionary = {}
var _visual_animation_names: Dictionary = {}
var _active_visual_state := ""
var _action_visual_state := ""
var _action_visual_time_left := 0.0
var _idle_states: Array[String] = []  # built idle variants, picked from on settle
var _idle_choice := ""                # the idle currently being shown
var _idle_rng := RandomNumberGenerator.new()
# Interactive ladder climb (Product_reqs ladder feature). While active the
# player rides the entry→exit line by hand instead of free movement.
var _climb_active := false
var _climb_entry := Vector3.ZERO
var _climb_exit := Vector3.ZERO
var _climb_zone: Node = null
var _climb_t := 0.0

func _ready() -> void:
	name = "Player"
	add_to_group("player")  # managers (e.g. SupplyManager) look us up here
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	col.shape = capsule
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	_build_visual()

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

## Kronako Iconz rooster model, scaled to the 1.8 m capsule. The
## animated action GLBs are preferred; the static GLB and old debug
## capsule are fallbacks when imports are unavailable.
func _build_visual() -> void:
	if _try_build_animated_visual():
		return
	if _try_build_static_visual(STATIC_MODEL_PATH):
		return
	var mesh := MeshInstance3D.new()
	mesh.name = "CapsuleFallback"
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.height = 1.8
	capsule_mesh.radius = 0.35
	mesh.mesh = capsule_mesh
	mesh.position = Vector3(0, 0.9, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#3aa0c8")
	mesh.material_override = mat
	add_child(mesh)

func _try_build_animated_visual() -> bool:
	if not ResourceLoader.exists(WALK_MODEL_PATH) and not ResourceLoader.exists(RUN_MODEL_PATH):
		return false
	var container := Node3D.new()
	container.name = "CharacterModel"
	_apply_animated_visual_transform(container)
	var built := false
	built = _add_animated_model(
		container, IDLE_MODEL_PATH, "idle", IDLE_ANIMATION_NAME) or built
	_idle_rng.randomize()
	for variant in IDLE_VARIANTS:
		var spec: Array = IDLE_VARIANTS[variant]
		if _add_animated_model(container, String(spec[0]), variant, String(spec[1])):
			_idle_states.append(variant)
			# Loop each idle so it never freezes between random swaps.
			var ap: AnimationPlayer = _visual_animation_players[variant]
			var clip := ap.get_animation(_visual_animation_names[variant])
			if clip != null:
				clip.loop_mode = Animation.LOOP_LINEAR
	built = _add_animated_model(
		container, WALK_MODEL_PATH, "walk", WALK_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, WALK_BACK_MODEL_PATH, "walk_back", WALK_BACK_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, RUN_MODEL_PATH, "run", RUN_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, RUN_FAST_MODEL_PATH, "run_fast", RUN_FAST_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, JUMP_MODEL_PATH, "jump", JUMP_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, CLIMB_MODEL_PATH, "climb", CLIMB_ANIMATION_NAME) or built
	if _visual_models.has("climb"):
		_visual_models["climb"].position += CLIMB_VISUAL_OFFSET
	built = _add_animated_model(
		container, CLIMB_FINISH_MODEL_PATH, "climb_finish",
		CLIMB_FINISH_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, VAULT_MODEL_PATH, "vault", VAULT_ANIMATION_NAME) or built
	if not built:
		return false
	add_child(container)
	_set_visual_state("idle")
	return true

func _add_animated_model(container: Node3D, path: String,
		state: String, preferred_animation: String) -> bool:
	return AnimatedModelSet.add_animated_model(container, path, state,
		preferred_animation, _visual_models, _visual_animation_players,
		_visual_animation_names)

func _try_build_static_visual(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var packed: PackedScene = load(path)
	if packed == null:
		return false
	var model := packed.instantiate()
	model.name = "CharacterModel"
	_apply_static_visual_transform(model)
	add_child(model)
	return true

func _apply_animated_visual_transform(model: Node3D) -> void:
	var s := 1.8 / ANIMATED_MODEL_SOURCE_HEIGHT
	model.scale = Vector3.ONE * s
	model.position = Vector3.ZERO
	model.rotation.y = PI  # glTF forward is +Z; Godot's is -Z

func _apply_static_visual_transform(model: Node3D) -> void:
	var s := 1.8 / STATIC_MODEL_SOURCE_HEIGHT
	model.scale = Vector3.ONE * s
	model.position = Vector3(0, STATIC_MODEL_SOURCE_HEIGHT * 0.5 * s, 0)
	model.rotation.y = PI  # glTF forward is +Z; Godot's is -Z

func _update_visual_animation(delta: float, is_moving: bool, is_running: bool) -> void:
	if _visual_animation_players.is_empty():
		return
	if _action_visual_time_left > 0.0 and _visual_models.has(_action_visual_state):
		_set_visual_state(_action_visual_state)
		return
	if not is_on_floor() and _visual_models.has("jump"):
		_set_visual_state("jump")
		return
	if is_moving:
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if input_dir.y > 0.35 and _visual_models.has("walk_back") and not is_running:
			_set_visual_state("walk_back")
		elif is_running:
			_set_visual_state("run_fast" if _visual_models.has("run_fast") else "run")
		else:
			_set_visual_state("walk")
	else:
		_set_idle_state()

## Plays an idle clip, picking a fresh random variant only when the player
## has just settled from movement and holding it for the whole idle stretch
## (Product_reqs.md: the stance stays put until idle re-activates). With no
## extra idle variants imported this falls back to the single legacy idle.
func _set_idle_state() -> void:
	if _idle_states.is_empty():
		_set_visual_state("idle")
		return
	if not _idle_states.has(_active_visual_state):  # just arrived from movement → pick one
		_idle_choice = _next_idle()
	_set_visual_state(_idle_choice)

## A random idle, always different from the current one when there is a
## choice, so each swap is visibly a new animation.
func _next_idle() -> String:
	if _idle_states.size() == 1:
		return _idle_states[0]
	var pick := _idle_choice
	while pick == _idle_choice:
		pick = _idle_states[_idle_rng.randi_range(0, _idle_states.size() - 1)]
	return pick

func _set_visual_state(state: String) -> void:
	var target := state
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
	player.speed_scale = 0.65 if state.begins_with("idle") else 1.0
	if not player.is_playing() or String(player.current_animation) != String(animation):
		player.play(animation)

func play_context_animation(state: String, duration := 0.75) -> void:
	if not _visual_models.has(state):
		return
	_action_visual_state = state
	_action_visual_time_left = duration
	_set_visual_state(state)

## Attach to a ladder for a controllable, reversible climb (Product_reqs
## ladder feature). Forward drives up the entry→exit line, back drives
## down; reaching the exit summits, dropping back to the entry steps off
## at the foot, and jump detaches mid-ladder. ClimbZone rolls the slip
## before calling, so the ride itself is safe.
func begin_climb(entry: Vector3, exit: Vector3, zone: Node) -> void:
	_climb_active = true
	_climb_entry = entry
	_climb_exit = exit
	_climb_zone = zone
	_climb_t = 0.0
	velocity = Vector3.ZERO
	global_position = entry
	_action_visual_state = ""
	_action_visual_time_left = 0.0
	_update_climb_visual(0.0)

func _process_climb(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		_end_climb()  # hop off; gravity takes over from here
		return
	var axis := Input.get_axis("move_back", "move_forward")
	_advance_climb(axis, delta)
	if _climb_active:
		_update_climb_visual(axis)

## Moves along the ladder by `axis` (+1 up, -1 down). Public/deterministic
## so the smoke test can drive the climb without polling input.
func _advance_climb(axis: float, delta: float) -> void:
	if not _climb_active:
		return
	var length := _climb_entry.distance_to(_climb_exit)
	if length < 0.001:
		_summit_climb()
		return
	_climb_t = clampf(_climb_t + axis * CLIMB_SPEED / length * delta, 0.0, 1.0)
	global_position = _climb_entry.lerp(_climb_exit, _climb_t)
	velocity = Vector3.ZERO
	if _climb_t >= 1.0:
		_summit_climb()
	elif _climb_t <= 0.0 and axis < 0.0:
		_end_climb()  # stepped back down to the foot — no summit

func _summit_climb() -> void:
	var zone := _climb_zone
	_end_climb()
	if zone != null and is_instance_valid(zone) and zone.has_method("complete_climb"):
		zone.complete_climb()
	# Pull up and over the ledge as the climb tops out (Product_reqs ladder
	# feature). Optional clip — skipped silently if the GLB isn't imported.
	if _visual_models.has("climb_finish"):
		var ap: AnimationPlayer = _visual_animation_players["climb_finish"]
		var clip := ap.get_animation(_visual_animation_names["climb_finish"])
		play_context_animation("climb_finish", clip.length if clip != null else 1.0)

func _end_climb() -> void:
	if not _climb_active:
		return
	_climb_active = false
	_climb_zone = null
	if _visual_animation_players.has("climb"):
		_visual_animation_players["climb"].speed_scale = 1.0
	_action_visual_state = ""
	_action_visual_time_left = 0.0

func _update_climb_visual(axis: float) -> void:
	if not _visual_models.has("climb"):
		return
	_set_visual_state("climb")
	# Drive the clip by direction: climbing up plays it forward, reversing
	# plays it backward, holding still pauses on the current rung.
	_visual_animation_players["climb"].speed_scale = axis

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
	elif _climb_active:
		# On the ladder, world actions are suppressed; only look and the
		# mouse toggle above stay live. Up/down and detach are polled in
		# _process_climb.
		return
	elif event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("freehand_paint"):
		if _focused is PaintableWall:
			freehand_requested.emit(_focused)
	elif event.is_action_pressed("cycle_color"):
		GameState.cycle_fill_color()
	elif event.is_action_pressed("can_prev"):
		GameState.cycle_graffiti_type(-1)
	elif event.is_action_pressed("can_next"):
		GameState.cycle_graffiti_type(1)
	else:
		# Number keys select cans by style order (modals consume these
		# first via Hud, so this only fires with the world in focus).
		for i in GameState.SLOT_COUNT:
			if event.is_action_pressed("slot_%d" % (i + 1)):
				GameState.select_type_slot(i)
				return

func _physics_process(delta: float) -> void:
	if _action_visual_time_left > 0.0:
		_action_visual_time_left = maxf(_action_visual_time_left - delta, 0.0)
	_apply_controller_look(delta)
	if _climb_active:
		_process_climb(delta)
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var is_running := Input.is_action_pressed("run")
	var speed := RUN_SPEED if is_running else WALK_SPEED
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
	_update_visual_animation(delta, direction != Vector3.ZERO, is_running)
	move_and_slide()
	_update_focus()

func _apply_controller_look(delta: float) -> void:
	var look := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if look.length() < JOY_LOOK_DEADZONE:
		return
	rotate_y(-look.x * JOY_LOOK_SENSITIVITY * delta)
	_pivot.rotation.x = clampf(
		_pivot.rotation.x - look.y * JOY_LOOK_SENSITIVITY * delta,
		deg_to_rad(-70.0), deg_to_rad(35.0))

func _update_focus() -> void:
	var focus: Node3D = null
	var collider: Object = _ray.get_collider()
	if collider != null and (
			collider is PaintableWall or collider is Npc or collider is PickupItem or collider.has_method("prompt_text")):
		if global_position.distance_to(_ray.get_collision_point()) <= INTERACT_RANGE + 1.5:
			focus = collider
	if focus == null:
		focus = _nearest_interactable()
	if focus != _focused:
		_focused = focus
		focus_changed.emit(focus)

func _nearest_interactable() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	var max_dist_sq := pow(INTERACT_RANGE, 2.0)
	for node in get_tree().get_nodes_in_group("interactable"):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var dist := global_position.distance_squared_to(node.global_position)
		if dist <= max_dist_sq and dist < best_dist and _has_line_of_sight(node):
			best_dist = dist
			best = node
	return best

func _has_line_of_sight(node: Node3D) -> bool:
	var exclude: Array[RID] = [get_rid()]
	if node is CollisionObject3D:
		exclude.append((node as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1.0, 0),
		node.global_position + Vector3(0, 0.6, 0),
		0xFFFFFFFF, exclude)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _try_interact() -> void:
	if _focused == null:
		return
	if _focused is PaintableWall:
		painted.emit(WallManager.paint_wall(
			_focused, GameState.selected_graffiti_type))
	elif _focused.has_method("interact"):
		_focused.interact()
