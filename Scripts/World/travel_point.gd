extends StaticBody3D
## Travel point between districts (Milestone 18, Plan_v2.md §4): a
## footbridge gate the player interacts with (E) to cross to the other
## block. Teleports the player to the target district's arrival spot
## and updates GameState.current_district_id — which is what flips
## heat display, patrol presence, and chain triggers over.

var _to_district_id := ""
var _label := ""

func setup(def: Dictionary, to_district_id: String) -> void:
	_to_district_id = to_district_id
	_label = String(def.get("label", "FOOTBRIDGE")).replace("\n", " ")
	name = "TravelPoint_%s" % to_district_id
	var pos: Array = def.get("position", [0, 0, 0])
	position = Vector3(pos[0], pos[1], pos[2])

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 2.4, 0.5)
	mesh.mesh = box
	mesh.position = Vector3(0, 1.2, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#2e4f4f")
	mat.emission_enabled = true
	mat.emission = Color("#46d9c7")
	mat.emission_energy_multiplier = 0.7
	mesh.material_override = mat
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.6, 2.4, 0.5)
	col.shape = shape
	col.position = Vector3(0, 1.2, 0)
	add_child(col)

	var sign_label := Label3D.new()
	sign_label.text = String(def.get("label", "FOOTBRIDGE"))
	sign_label.font_size = 44
	sign_label.outline_size = 10
	sign_label.pixel_size = 0.005
	sign_label.position = Vector3(0, 2.9, 0)
	sign_label.modulate = Color("#46d9c7")
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(sign_label)

func prompt_text() -> String:
	var district: Dictionary = TerritoryManager.districts.get(_to_district_id, {})
	return "%s\n[E] Cross to %s" % [_label, String(district.get("name", _to_district_id))]

## Player raycast interaction (same protocol as Npc/PickupItem).
func interact() -> void:
	var district: Dictionary = TerritoryManager.districts.get(_to_district_id, {})
	if district.is_empty():
		push_error("TravelPoint: unknown destination district \"%s\"" % _to_district_id)
		return
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player != null:
		var arrival: Array = district.get("arrival", [0, 0.5, 0])
		player.global_position = Vector3(arrival[0], arrival[1], arrival[2])
		if player is CharacterBody3D:
			player.velocity = Vector3.ZERO
	GameState.set_district(_to_district_id)
