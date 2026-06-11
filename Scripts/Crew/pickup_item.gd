class_name PickupItem
extends StaticBody3D
## A mission pickup (e.g. Moth's blackbook), built at runtime from the
## "item" block of an entry in Data/npc_data.json. Collecting it
## advances that member's recruitment; only possible once their
## mission is active.

var member_id := ""
var item: Dictionary = {}

func setup(owner_member_id: String, item_data: Dictionary) -> void:
	member_id = owner_member_id
	item = item_data
	name = "pickup_%s" % member_id
	var pos: Array = item.get("position", [0, 0.5, 0])
	position = Vector3(pos[0], pos[1], pos[2])

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.12, 0.65)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(String(item.get("color", "#3b2f4a")))
	mesh.material_override = mat
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 0.5, 0.85)
	col.shape = shape
	add_child(col)

	var label := Label3D.new()
	label.text = String(item.get("name", "Item"))
	label.font_size = 40
	label.outline_size = 10
	label.pixel_size = 0.003
	label.position = Vector3(0, 0.7, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func prompt_text() -> String:
	return "[E] Pick up %s" % String(item.get("name", "item"))

func interact() -> void:
	if CrewManager.collect_item(member_id):
		queue_free()
