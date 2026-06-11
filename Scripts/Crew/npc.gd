class_name Npc
extends StaticBody3D
## A recruitable NPC, built at runtime from Data/npc_data.json.
## Placeholder body: colored capsule with a floating alias label.
## The player's interaction ray focuses it; E talks via CrewManager.

var data: Dictionary = {}

func setup(npc_data: Dictionary) -> void:
	data = npc_data
	name = String(data["memberId"])
	var pos: Array = data.get("position", [0, 0, 0])
	position = Vector3(pos[0], pos[1], pos[2])

	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.7
	capsule.radius = 0.32
	mesh.mesh = capsule
	mesh.position = Vector3(0, 0.85, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(String(data.get("color", "#cccccc")))
	mesh.material_override = mat
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.7
	shape.radius = 0.32
	col.shape = shape
	col.position = Vector3(0, 0.85, 0)
	add_child(col)

	var label := Label3D.new()
	label.text = String(data.get("alias", "?"))
	label.font_size = 64
	label.outline_size = 12
	label.pixel_size = 0.004
	label.position = Vector3(0, 2.1, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func prompt_text() -> String:
	return "[E] Talk to %s (%s)" % [
		String(data.get("alias", "?")),
		String(data.get("roleLabel", data.get("role", "")))]

func interact() -> void:
	# Once recruited, members with a dialogue tree chat through it
	# (Milestone 12); recruitment stages stay with CrewManager.
	var dialogue_id := String(data.get("dialogueId", ""))
	if String(data.get("stage", "")) == "recruited" and dialogue_id != "" \
			and DialogueManager.start(dialogue_id, self):
		return
	CrewManager.interact(String(data["memberId"]))
