class_name MissionActor
extends StaticBody3D
## A non-recruitable mission NPC (e.g. Lupe the supply contact), built
## at runtime from the "actors" block of Data/missions.json. Same
## placeholder look as Npc; E reports to MissionManager, falling back
## to an idle line when no objective wants this actor.

var data: Dictionary = {}

func setup(actor_data: Dictionary) -> void:
	data = actor_data
	name = String(data["actorId"])
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
	label.text = String(data.get("name", "?"))
	label.font_size = 64
	label.outline_size = 12
	label.pixel_size = 0.004
	label.position = Vector3(0, 2.1, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func prompt_text() -> String:
	if data.get("shop", false):
		return "[E] %s (%s) — talk / shop" % [
			String(data.get("name", "?")), String(data.get("roleLabel", ""))]
	return "[E] Talk to %s (%s)" % [
		String(data.get("name", "?")), String(data.get("roleLabel", ""))]

func interact() -> void:
	if MissionManager.notify_actor(String(data["actorId"])):
		return
	# Outside mission beats: a dialogue tree if the actor has one
	# (Milestone 12), else the shop catalog (Milestone 11), else an
	# idle line.
	var dialogue_id := String(data.get("dialogueId", ""))
	if dialogue_id != "" and DialogueManager.start(dialogue_id, self):
		return
	if data.get("shop", false):
		SupplyManager.toggle_shop(self)
		return
	var idle := String(data.get("dialogue", {}).get("idle", ""))
	if idle != "":
		MissionManager.mission_event.emit(idle)
