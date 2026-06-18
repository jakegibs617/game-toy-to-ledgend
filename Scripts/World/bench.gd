extends StaticBody3D
## A street bench the writer can sit on to sketch tag styles in the
## blackbook (Product_reqs.md). Same interactable protocol as
## TravelPoint/ClimbZone (group "interactable", prompt_text + interact):
## interacting seats the player and opens the blackbook in practice mode.
## Styles can only be practiced while seated — you sketch in your book on
## a bench, not mid-stride.

const SEAT_HEIGHT := 0.48

var _label := ""

func setup(def: Dictionary) -> void:
	_label = String(def.get("label", "BENCH")).replace("\n", " ")
	name = String(def.get("benchId", "bench"))
	var pos: Array = def.get("position", [0, 0, 0])
	position = Vector3(pos[0], pos[1], pos[2])
	rotation_degrees = Vector3(0, float(def.get("rotationY", 0.0)), 0)
	add_to_group("interactable")

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#6b4a2f")
	wood.roughness = 0.9
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color("#3a3d42")
	frame.metallic = 0.4
	frame.roughness = 0.5

	# Seat slab, backrest, and two end frames.
	_add_part(Vector3(0, SEAT_HEIGHT, 0), Vector3(1.8, 0.1, 0.5), wood)
	_add_part(Vector3(0, SEAT_HEIGHT + 0.45, -0.2), Vector3(1.8, 0.4, 0.08), wood)
	_add_part(Vector3(-0.8, SEAT_HEIGHT * 0.5, 0), Vector3(0.1, SEAT_HEIGHT, 0.5), frame)
	_add_part(Vector3(0.8, SEAT_HEIGHT * 0.5, 0), Vector3(0.1, SEAT_HEIGHT, 0.5), frame)

	# Collision: a single seat-height box so the player can't walk through.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, SEAT_HEIGHT + 0.1, 0.5)
	col.shape = shape
	col.position = Vector3(0, (SEAT_HEIGHT + 0.1) * 0.5, 0)
	add_child(col)

	var sign_label := Label3D.new()
	sign_label.text = String(def.get("label", "BENCH"))
	sign_label.font_size = 32
	sign_label.outline_size = 8
	sign_label.pixel_size = 0.004
	sign_label.position = Vector3(0, SEAT_HEIGHT + 1.0, 0)
	sign_label.modulate = Color("#d8c39c")
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(sign_label)

func _add_part(local_pos: Vector3, part_size: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = part_size
	mesh.mesh = box
	mesh.position = local_pos
	mesh.material_override = material
	add_child(mesh)

func prompt_text() -> String:
	return "%s\n[E] Sit & sketch styles" % _label

## Player raycast interaction (same protocol as TravelPoint/Npc).
func interact() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("begin_sit"):
		# The seat faces +z local (the street); the player's forward is -z,
		# so look 180° off the bench yaw to face out at the street.
		player.begin_sit(_seat_position(), global_rotation.y + PI)
	# The player asks the HUD to open the practice blackbook once the sit
	# animation settles (it also flips to first person then).

## World-space anchor for the seated player's origin. The sit clip is
## floor-rooted (origin at the feet/ground), so we park the player at the
## bench's ground center and let the animation seat the body on the slab.
func _seat_position() -> Vector3:
	return global_position
