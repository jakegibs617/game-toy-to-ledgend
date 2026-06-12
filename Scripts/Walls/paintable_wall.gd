class_name PaintableWall
extends StaticBody3D
## A paintable surface, built at runtime from a wall definition in
## Data/walls.json. Placeholder graffiti is rendered as a Label3D
## (plus a backdrop quad for pieces) until real decal art exists.

var def: Dictionary = {}

var _graffiti_anchor: Node3D

func setup(wall_def: Dictionary) -> void:
	def = wall_def
	name = String(def["wallId"])
	var pos: Array = def.get("position", [0, 0, 0])
	position = Vector3(pos[0], pos[1], pos[2])
	rotation_degrees = Vector3(0, float(def.get("rotationY", 0.0)), 0)
	var size: Array = def.get("size", [4, 3, 0.3])
	var box_size := Vector3(size[0], size[1], size[2])

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(String(def.get("color", "#9a8f84")))
	mesh.material_override = mat
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	add_child(col)

	# Graffiti hangs just off the wall's front (+Z) face to avoid z-fighting.
	_graffiti_anchor = Node3D.new()
	_graffiti_anchor.position = Vector3(0, 0, box_size.z / 2.0 + 0.03)
	add_child(_graffiti_anchor)

func display_name() -> String:
	return String(def.get("name", def.get("wallId", "Wall")))

func clear_graffiti() -> void:
	for child in _graffiti_anchor.get_children():
		child.queue_free()

## Milestone 8 art pass: each graffiti gets a deterministic tilt, paint
## drips under the letters, and (for throw-ups/pieces) filled panels —
## all unshaded so the work pops in the dusk lighting.
func show_graffiti(graffiti: Dictionary) -> void:
	clear_graffiti()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(graffiti.get("graffitiId", "")) + String(graffiti.get("alias", "")))
	var holder := Node3D.new()
	holder.rotation_degrees = Vector3(0, 0, rng.randf_range(-3.5, 3.5))
	_graffiti_anchor.add_child(holder)

	# Freehand work (Milestone 14) is the player's actual sprayed image;
	# falls through to the placeholder rendering if the image is bad.
	if graffiti.get("freehand", false) and _show_freehand(holder, graffiti):
		return

	var fill := Color(String(graffiti.get("fillColor", "#ffffff")))
	var outline := Color(String(graffiti.get("outlineColor", "#000000")))
	var label := Label3D.new()
	label.text = String(graffiti.get("alias", "???"))
	label.modulate = fill
	label.outline_modulate = outline
	var letter_bottom := 0.25
	var drip_spread := 0.8
	match String(graffiti.get("type", "tag")):
		"tag":
			label.font_size = 96
			label.outline_size = 18
			label.pixel_size = 0.004
		"throwup":
			label.font_size = 160
			label.outline_size = 48
			label.pixel_size = 0.006
			letter_bottom = 0.5
			drip_spread = 1.2
			_add_panel(holder, _panel_size(0.55, 0.42), outline.darkened(0.35), -0.012)
		"piece":
			label.font_size = 220
			label.outline_size = 64
			label.pixel_size = 0.008
			letter_bottom = 0.85
			drip_spread = 1.6
			_add_panel(holder, _panel_size(0.9, 0.84), fill.darkened(0.55), -0.018)
			_add_panel(holder, _panel_size(0.85, 0.78), Color("#26233a"), -0.015)
	holder.add_child(label)
	_add_drips(holder, rng, fill, letter_bottom, drip_spread)

## Slaps a cross-out (e.g. "TOY") at an angle over the current graffiti,
## with a strike bar through the work. Cleared when show_graffiti repaints.
func show_cross_out(cross: Dictionary) -> void:
	var holder := Node3D.new()
	holder.rotation_degrees = Vector3(0, 0, -14)
	_graffiti_anchor.add_child(holder)
	var color := Color(String(cross.get("color", "#e0301e")))

	var label := Label3D.new()
	label.text = String(cross.get("text", "TOY"))
	label.modulate = color
	label.outline_modulate = Color("#1a1a1a")
	label.font_size = 150
	label.outline_size = 28
	label.pixel_size = 0.006
	label.position = Vector3(0, 0, 0.03)
	holder.add_child(label)

	var wall_width := float(def.get("size", [4, 3, 0.3])[0])
	var bar := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(minf(2.6, wall_width * 0.6), 0.09)
	bar.mesh = quad
	bar.position = Vector3(0, -0.04, 0.025)
	bar.material_override = _flat_material(color)
	holder.add_child(bar)

## City cleanup buffed this wall: mismatched roller patches in
## off-tones of the wall color where the work used to be (Plan.md
## section 27 "buff marks"). Cleared when show_graffiti repaints.
func show_buff() -> void:
	clear_graffiti()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(def.get("wallId", "")) + "_buff")
	var size: Array = def.get("size", [4, 3, 0.3])
	var base := Color(String(def.get("color", "#9a8f84")))
	for i in 3:
		var patch := base.lightened(rng.randf_range(0.08, 0.2)) if i % 2 == 0 \
			else base.darkened(rng.randf_range(0.1, 0.22))
		var holder := Node3D.new()
		holder.rotation_degrees = Vector3(0, 0, rng.randf_range(-2.5, 2.5))
		holder.position = Vector3(
			rng.randf_range(-0.15, 0.15) * float(size[0]),
			rng.randf_range(-0.12, 0.12) * float(size[1]),
			0.002 * i)
		_graffiti_anchor.add_child(holder)
		_add_panel(holder, Vector2(
			float(size[0]) * rng.randf_range(0.45, 0.68),
			float(size[1]) * rng.randf_range(0.35, 0.55)), patch, 0.0)

## The player's sprayed PNG (stored base64 in the wall state so it
## survives save/load) on a quad sized to the wall face. Returns false
## on a bad image so show_graffiti can fall back to placeholder art.
func _show_freehand(parent: Node3D, graffiti: Dictionary) -> bool:
	var image := Image.new()
	var bytes := Marshalls.base64_to_raw(String(graffiti.get("image", "")))
	if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK:
		return false
	var quad := QuadMesh.new()
	quad.size = _panel_size(0.92, 0.85)
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(image)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	parent.add_child(mesh)
	return true

## Filled quad behind the letters (throw-up halo / piece background).
func _add_panel(parent: Node3D, panel_size: Vector2, color: Color, z_offset: float) -> void:
	var quad := QuadMesh.new()
	quad.size = panel_size
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.position = Vector3(0, 0, z_offset)
	mesh.material_override = _flat_material(color)
	parent.add_child(mesh)

## Thin paint runs hanging below the letters.
func _add_drips(parent: Node3D, rng: RandomNumberGenerator, color: Color,
		letter_bottom: float, spread: float) -> void:
	var wall_width := float(def.get("size", [4, 3, 0.3])[0])
	spread = minf(spread, wall_width * 0.35)
	for i in rng.randi_range(2, 4):
		var length := rng.randf_range(0.15, 0.45)
		var quad := QuadMesh.new()
		quad.size = Vector2(0.045, length)
		var mesh := MeshInstance3D.new()
		mesh.mesh = quad
		mesh.material_override = _flat_material(color)
		mesh.position = Vector3(
			rng.randf_range(-spread, spread),
			-(letter_bottom + length / 2.0) + rng.randf_range(0.0, 0.1),
			0.005)
		parent.add_child(mesh)

func _panel_size(width_frac: float, height_frac: float) -> Vector2:
	var size: Array = def.get("size", [4, 3, 0.3])
	return Vector2(float(size[0]) * width_frac, float(size[1]) * height_frac)

func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
