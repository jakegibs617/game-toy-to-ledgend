class_name RivalTagger
extends CharacterBody3D
## A rival crew member who physically runs up to a wall, sprays it, and
## flees — the visible body for a RivalManager retaliation
## (Product_reqs.md). district.gd spawns one on the manager's behalf so
## the player SEES the TOY get put up instead of paint appearing
## instantly. The actual wall mutation runs through the on_arrive
## callback (RivalManager.respond) the moment the tagger reaches the
## wall, so WallManager's signal flow is unchanged; this is just its
## body. Built in code with a capsule fallback like AmbientNpc — rival
## crews carry colors, not character GLBs.

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
			# Put the paint up halfway through the spray beat.
			if _tag_timer <= TAG_DURATION * 0.5:
				_fire_arrival()
			if _tag_timer <= 0.0:
				if _puff != null:
					_puff.visible = false
				if _arm != null:
					_arm.rotation_degrees = Vector3.ZERO
				_enter_state(State.RETREAT)
		State.RETREAT:
			# Don't linger forever if the exit is blocked.
			if _move_toward(_retreat_point) or _state_time >= MAX_RETREAT_TIME:
				queue_free()

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

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.7
	shape.radius = 0.3
	col.shape = shape
	col.position = Vector3(0, 0.85, 0)
	add_child(col)

	var label := Label3D.new()
	label.text = tag_text.to_upper()
	label.font_size = 40
	label.outline_size = 10
	label.pixel_size = 0.003
	label.modulate = _crew_color.lightened(0.4)
	label.position = Vector3(0, 2.15, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
