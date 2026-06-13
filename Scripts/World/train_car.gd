extends StaticBody3D
## Runtime-built train car interaction target for Milestone 20.

var def: Dictionary = {}
var _body_mesh: MeshInstance3D
var _graffiti_label: Label3D
var _phase_label: Label3D

const GraffitiFonts := preload("res://Scripts/Walls/graffiti_font_library.gd")

func setup(train_def: Dictionary) -> void:
	def = train_def.duplicate(true)
	name = "TrainCar_%s" % String(def.get("trainId", ""))
	var pos: Array = def.get("yardPosition", [0, 0, 0])
	position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	rotation.y = float(def.get("rotationY", 0.0))
	var size := _size()

	_body_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	_body_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#303844")
	mat.metallic = 0.25
	mat.roughness = 0.55
	_body_mesh.material_override = mat
	add_child(_body_mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	add_child(col)

	_graffiti_label = Label3D.new()
	_graffiti_label.position = Vector3(0, 0.25, -size.z * 0.51)
	_graffiti_label.pixel_size = 0.018
	_graffiti_label.font_size = 92
	_graffiti_label.outline_size = 14
	_graffiti_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_graffiti_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_graffiti_label)

	_phase_label = Label3D.new()
	_phase_label.position = Vector3(0, size.y * 0.72, 0)
	_phase_label.pixel_size = 0.014
	_phase_label.font_size = 38
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_phase_label)
	refresh_from_state()

func interact() -> void:
	var result: Dictionary = TrainManager.paint_train(String(def.get("trainId", "")))
	if not result.get("ok", false):
		GameState.player_event.emit(String(result.get("reason", "Can't paint this train.")))

func prompt_text() -> String:
	var train_id := String(def.get("trainId", ""))
	var state := TrainManager.state_for(train_id)
	var phase := String(state.get("phase", "stopped"))
	var ticks := int(state.get("ticksLeft", 0))
	if state.get("currentGraffiti") != null:
		var graffiti: Dictionary = state["currentGraffiti"]
		return "%s  |  %s  |  passes %d\nYour %s car is in service." % [
			String(def.get("label", train_id)), phase.to_upper(),
			int(graffiti.get("passes", 0)), String(graffiti.get("alias", GameState.alias))]
	if phase != "stopped":
		return "%s  |  DEPARTED  |  back in %d ticks\nTrain's moving. Wait for the next stop." % [
			String(def.get("label", train_id)), ticks]
	return "%s  |  STOPPED  |  leaves in %d ticks\n[E] Paint train side (%d paint)  high heat" % [
		String(def.get("label", train_id)), ticks, int(def.get("paintCost", 8))]

func refresh_from_state() -> void:
	if def.is_empty() or _graffiti_label == null:
		return
	var train_id := String(def.get("trainId", ""))
	var state := TrainManager.state_for(train_id)
	var phase := String(state.get("phase", "stopped"))
	visible = phase == "stopped"
	_phase_label.text = "STOPPED" if phase == "stopped" else "IN SERVICE"
	var graffiti: Variant = state.get("currentGraffiti")
	if graffiti == null:
		_graffiti_label.text = String(def.get("label", train_id)).to_upper()
		_graffiti_label.modulate = Color("#c8d0d8")
		_graffiti_label.outline_modulate = Color("#101018")
	else:
		var g := graffiti as Dictionary
		_graffiti_label.text = String(g.get("alias", GameState.alias)).to_upper()
		_graffiti_label.modulate = Color(String(g.get("fillColor", "#ffd23f")))
		_graffiti_label.outline_modulate = Color(String(g.get("outlineColor", "#101018")))
		GraffitiFonts.apply_to_label(_graffiti_label, String(g.get("fontStyle", GraffitiFonts.default_style_id())))

func _size() -> Vector3:
	var size: Array = def.get("size", [7.5, 2.2, 2.4])
	return Vector3(float(size[0]), float(size[1]), float(size[2]))
