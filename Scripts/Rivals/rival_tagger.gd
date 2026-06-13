class_name RivalTagger
extends CharacterBody3D
## A rival crew member who physically runs up to a wall, sprays it, and
## flees — the visible body for a RivalManager retaliation
## (Product_reqs.md). district.gd spawns one on the manager's behalf so
## the player SEES the TOY get put up instead of paint appearing
## instantly. The actual wall mutation runs through the on_arrive
## callback (RivalManager.respond) the moment the tagger reaches the
## wall, so WallManager's signal flow is unchanged; this is just its
## body. Rival crews wear the Hooded Fox Warrior model (Product_reqs.md),
## falling back to a colored capsule like AmbientNpc when the GLBs are
## missing; either way the crew color rides on the spray can and name tag.

const MODEL_SOURCE_HEIGHT := 1.7
const IDLE_MODEL_PATH := "res://Assets/Characters/hooded_fox_warrior_idle.glb"
const WALK_MODEL_PATH := "res://Assets/Characters/hooded_fox_warrior_walking.glb"
const RUN_MODEL_PATH := "res://Assets/Characters/hooded_fox_warrior_running.glb"
const RUN_FAST_MODEL_PATH := "res://Assets/Characters/hooded_fox_warrior_run_fast.glb"
const IDLE_ANIMATION_NAME := "Armature|Idle_02|baselayer"
const WALK_ANIMATION_NAME := "Armature|walking_man|baselayer"
const RUN_ANIMATION_NAME := "Armature|running|baselayer"
const RUN_FAST_ANIMATION_NAME := "Armature|RunFast|baselayer"
const AnimatedModelSet := preload("res://Scripts/Characters/animated_model_set.gd")

const RUN_SPEED := 5.5
const ARRIVE_DIST := 0.6
const APPROACH_OFFSET := 2.0   # where it stops, in front of the wall face
const SIDE_OFFSET := 7.0       # how far to the side it runs in from / flees to
const TAG_DURATION := 1.3      # seconds spent spraying before the paint lands
## If the tagger can't reach the wall in this long (blocked by geometry,
## an elevated wall it can't path to, etc.) the paint is applied anyway
## and the body removed — a stuck animation must never swallow the
## retaliation the way an instant response never would.
const MAX_APPROACH_TIME := 8.0
const MAX_RETREAT_TIME := 6.0

enum State { APPROACH, TAG, RETREAT }

var _state: State = State.APPROACH
var _target := Vector3.ZERO       # spray spot in front of the wall
var _wall_pos := Vector3.ZERO     # wall center, on the ground plane
var _retreat_point := Vector3.ZERO
var _on_arrive := Callable()
var _arrived_fired := false
var _tag_timer := 0.0
var _state_time := 0.0            # seconds spent in the current state
var _crew_color := Color("#d94f6c")
var _arm: Node3D
var _puff: MeshInstance3D
var _visual_models: Dictionary = {}
var _visual_animation_players: Dictionary = {}
var _visual_animation_names: Dictionary = {}
var _active_visual_state := ""

## wall: the PaintableWall (any Node3D); crew: the rival crew def;
## on_arrive: applies the actual graffiti when the tagger reaches the wall.
func begin(wall: Node3D, crew: Dictionary, on_arrive: Callable) -> void:
	_on_arrive = on_arrive
	_crew_color = Color(String(crew.get("fillColor", "#d94f6c")))
	# Graffiti renders on the wall's local +Z face (see PaintableWall),
	# so that axis is the front the tagger walks up to.
	var front := wall.global_transform.basis.z
	front.y = 0.0
	front = front.normalized() if front.length() > 0.01 else Vector3.FORWARD
	_wall_pos = wall.global_position
	_wall_pos.y = 0.0
	_target = _wall_pos + front * APPROACH_OFFSET
	var side := Vector3(front.z, 0.0, -front.x)
	_retreat_point = _target + side * SIDE_OFFSET
	global_position = _retreat_point  # run in from the side
	_build_body(String(crew.get("tag", "?")))

func _physics_process(delta: float) -> void:
	_state_time += delta
	match _state:
		State.APPROACH:
			# Stuck on geometry or an unreachable (e.g. elevated) wall:
			# put the paint up where it stands and bail, so the response
			# is never silently dropped.
			if _state_time >= MAX_APPROACH_TIME:
				_fire_arrival()
				queue_free()
				return
			if _move_toward(_target):
				_enter_state(State.TAG)
				_tag_timer = TAG_DURATION
				_face(_wall_pos)
				if _arm != null:
					_arm.rotation_degrees = Vector3(-70, 0, 0)
				if _puff != null:
					_puff.visible = true
		State.TAG:
			velocity = Vector3.ZERO
			move_and_slide()
			_tag_timer -= delta
			if _puff != null:
				_puff.scale = Vector3.ONE * (1.0 + 0.4 * sin(_tag_timer * 30.0))
			# The paint lands only when the rival finishes the spray beat:
			# the writer watches them run up, stand in front, and tag before
			# TOY appears — never before the body is there (Product_reqs.md).
			if _tag_timer <= 0.0:
				_fire_arrival()
				if _puff != null:
					_puff.visible = false
				if _arm != null:
					_arm.rotation_degrees = Vector3.ZERO
				_enter_state(State.RETREAT)
		State.RETREAT:
			# Don't linger forever if the exit is blocked.
			if _move_toward(_retreat_point) or _state_time >= MAX_RETREAT_TIME:
				queue_free()
				return
	# Run while moving, settle into idle for the spray beat (the floating
	# can/puff sell the actual tag in both the animated and capsule bodies).
	_update_visual_animation()

func _update_visual_animation() -> void:
	if _visual_animation_players.is_empty():
		return
	_set_visual_state("idle" if _state == State.TAG else "run")

## Applies the actual graffiti exactly once, however we got to the wall.
func _fire_arrival() -> void:
	if _arrived_fired:
		return
	_arrived_fired = true
	if _on_arrive.is_valid():
		_on_arrive.call()

func _enter_state(next: State) -> void:
	_state = next
	_state_time = 0.0

## Moves flat toward point, facing the heading; true once within reach.
func _move_toward(point: Vector3) -> bool:
	var flat := point - global_position
	flat.y = 0.0
	if flat.length() <= ARRIVE_DIST:
		velocity = Vector3.ZERO
		move_and_slide()
		return true
	var dir := flat.normalized()
	velocity.x = dir.x * RUN_SPEED
	velocity.z = dir.z * RUN_SPEED
	_face(global_position + dir)
	move_and_slide()
	return false

func _face(point: Vector3) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length() > 0.01:
		rotation.y = atan2(-to.x, -to.z)

func _build_body(tag_text: String) -> void:
	if not _try_build_animated_visual():
		_build_capsule_body()
	_build_spray_fx()
	_build_collision()
	_build_label(tag_text)

## The Hooded Fox Warrior crew model (Product_reqs.md). Runs in on the
## RUN clip and stands on IDLE for the spray beat; returns false when the
## GLBs aren't imported so the caller drops to the capsule fallback.
func _try_build_animated_visual() -> bool:
	if not ResourceLoader.exists(RUN_MODEL_PATH) and not ResourceLoader.exists(IDLE_MODEL_PATH):
		return false
	var container := Node3D.new()
	container.name = "HoodedFoxModel"
	var s := 1.8 / MODEL_SOURCE_HEIGHT
	container.scale = Vector3.ONE * s
	container.rotation.y = PI  # glTF forward is +Z; Godot's is -Z
	var built := false
	for spec in [
			[IDLE_MODEL_PATH, "idle", IDLE_ANIMATION_NAME],
			[WALK_MODEL_PATH, "walk", WALK_ANIMATION_NAME],
			[RUN_MODEL_PATH, "run", RUN_ANIMATION_NAME],
			[RUN_FAST_MODEL_PATH, "run_fast", RUN_FAST_ANIMATION_NAME]]:
		if AnimatedModelSet.add_animated_model(container, String(spec[0]),
				String(spec[1]), String(spec[2]), _visual_models,
				_visual_animation_players, _visual_animation_names):
			built = true
			# Loop each clip so a short run-up or spray beat never freezes.
			var ap: AnimationPlayer = _visual_animation_players[spec[1]]
			var clip := ap.get_animation(_visual_animation_names[spec[1]])
			if clip != null:
				clip.loop_mode = Animation.LOOP_LINEAR
	if not built:
		container.queue_free()
		return false
	add_child(container)
	_set_visual_state("run")
	return true

func _set_visual_state(visual_state: String) -> void:
	var target := visual_state
	if not _visual_models.has(target):
		target = "run" if _visual_models.has("run") else (
			"walk" if _visual_models.has("walk") else "idle")
	if not _visual_models.has(target):
		return
	if _active_visual_state != target:
		for key in _visual_models:
			_visual_models[key].visible = String(key) == target
		_active_visual_state = target
	var ap: AnimationPlayer = _visual_animation_players[target]
	var anim: StringName = _visual_animation_names[target]
	if not ap.is_playing() or String(ap.current_animation) != String(anim):
		ap.play(anim)

func _build_capsule_body() -> void:
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.7
	capsule.radius = 0.3
	mesh.mesh = capsule
	mesh.position = Vector3(0, 0.85, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _crew_color
	mesh.material_override = mat
	add_child(mesh)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.34
	head.mesh = head_mesh
	head.position = Vector3(0, 1.8, 0)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color("#33272b")
	head.material_override = head_mat
	add_child(head)

func _build_spray_fx() -> void:
	# Spray-can arm — raises while tagging.
	_arm = Node3D.new()
	_arm.position = Vector3(0.32, 1.25, 0.0)
	add_child(_arm)
	var can := MeshInstance3D.new()
	var can_mesh := CylinderMesh.new()
	can_mesh.top_radius = 0.06
	can_mesh.bottom_radius = 0.06
	can_mesh.height = 0.26
	can.mesh = can_mesh
	can.position = Vector3(0.0, 0.0, 0.24)
	can.rotation_degrees = Vector3(90, 0, 0)
	var can_mat := StandardMaterial3D.new()
	can_mat.albedo_color = _crew_color.lightened(0.3)
	can.material_override = can_mat
	_arm.add_child(can)

	# Spray puff — flashes during the tag beat.
	_puff = MeshInstance3D.new()
	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = 0.13
	puff_mesh.height = 0.26
	_puff.mesh = puff_mesh
	_puff.position = Vector3(0.32, 1.25, 0.5)
	var puff_mat := StandardMaterial3D.new()
	puff_mat.albedo_color = _crew_color.lightened(0.5)
	puff_mat.emission_enabled = true
	puff_mat.emission = _crew_color.lightened(0.4)
	puff_mat.emission_energy_multiplier = 2.0
	_puff.material_override = puff_mat
	_puff.visible = false
	add_child(_puff)

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.7
	shape.radius = 0.3
	col.shape = shape
	col.position = Vector3(0, 0.85, 0)
	add_child(col)

func _build_label(tag_text: String) -> void:
	var label := Label3D.new()
	label.text = tag_text.to_upper()
	label.font_size = 40
	label.outline_size = 10
	label.pixel_size = 0.003
	label.modulate = _crew_color.lightened(0.4)
	label.position = Vector3(0, 2.15, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
