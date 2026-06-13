class_name PaintableWall
extends StaticBody3D
## A paintable surface, built at runtime from a wall definition in
## Data/walls.json. Placeholder graffiti is rendered as a Label3D
## (plus a backdrop quad for pieces) until real decal art exists.

var def: Dictionary = {}

const RivalGraffitiStyle := preload("res://Scripts/Walls/rival_graffiti_style.gd")

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
	mesh.material_override = _surface_material()
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
	_add_surface_details(box_size)

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
	if String(graffiti.get("creatorId", "player")) != "player":
		_show_rival_graffiti(holder, graffiti, fill, outline)
		return
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
		"stencil":
			# Crisp single-pass cut: thin outline, no drips (Milestone 16).
			label.font_size = 110
			label.outline_size = 10
			label.pixel_size = 0.004
			drip_spread = 0.0
			_add_panel(holder, _panel_size(0.4, 0.3), outline.lightened(0.08), -0.01)
		"roller":
			# Blockbuster strip the full width of the parapet.
			label.font_size = 250
			label.outline_size = 78
			label.pixel_size = 0.009
			letter_bottom = 0.5
			drip_spread = 2.2
			_add_panel(holder, _panel_size(0.97, 0.6), outline.darkened(0.2), -0.012)
		"mural":
			# Layered color field — the closest placeholder art gets to a
			# full production (Milestone 16).
			label.font_size = 230
			label.outline_size = 60
			label.pixel_size = 0.009
			letter_bottom = 0.9
			drip_spread = 1.4
			_add_panel(holder, _panel_size(0.94, 0.88), fill.darkened(0.6), -0.021)
			_add_panel(holder, _panel_size(0.9, 0.8), Color("#1f3a5f"), -0.018)
			_add_panel(holder, _panel_size(0.6, 0.5), fill.lightened(0.15).darkened(0.1), -0.015)
	holder.add_child(label)
	if drip_spread > 0.0:
		_add_drips(holder, rng, fill, letter_bottom, drip_spread)

func _show_rival_graffiti(holder: Node3D, graffiti: Dictionary, fill: Color, outline: Color) -> void:
	var variant := RivalGraffitiStyle.variant_for(graffiti)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(variant["seed"])
	holder.rotation_degrees.z = float(variant["slant"])
	holder.position.x = float(variant["xOffset"]) * _panel_size(1.0, 1.0).x
	holder.position.y = float(variant["yOffset"]) * _panel_size(1.0, 1.0).y
	var type := String(graffiti.get("type", "tag"))
	var alias := String(graffiti.get("alias", "???"))
	match type:
		"tag":
			_add_rival_label(holder, alias, fill, outline, 108, 20, 0.0045, Vector3.ZERO)
			_add_rival_stripes(holder, rng, variant, fill, outline, 0.45)
			_add_drips(holder, rng, fill, 0.22, 0.65)
		"stencil":
			_add_panel(holder, _panel_size(0.48, 0.34), outline.lightened(0.05), -0.016)
			_add_rival_cut_marks(holder, rng, variant, fill)
			_add_rival_label(holder, alias, fill, outline.darkened(0.3), 118, 8, 0.004, Vector3(0, 0, 0.006))
		"throwup":
			_add_panel(holder, _panel_size(0.62, 0.46), outline.darkened(0.25), -0.02)
			_add_panel(holder, _panel_size(0.54, 0.38), fill.darkened(0.25), -0.015)
			_add_rival_stripes(holder, rng, variant, fill.lightened(0.08), outline, 0.72)
			_add_rival_label(holder, alias, fill, outline, 168, 52, 0.006, Vector3(0, 0, 0.01))
			_add_rival_chips(holder, rng, variant, outline)
			_add_drips(holder, rng, fill, 0.55, 1.2)
		"piece":
			_add_panel(holder, _panel_size(0.88, 0.78), outline.darkened(0.35), -0.024)
			_add_panel(holder, _panel_size(0.8, 0.68), fill.darkened(0.45), -0.018)
			_add_rival_stripes(holder, rng, variant, fill.lightened(0.18), outline, 0.95)
			_add_rival_label(holder, alias, fill, outline, 214, 66, 0.008, Vector3(0, 0, 0.012))
			_add_rival_chips(holder, rng, variant, fill.lightened(0.2))
			_add_drips(holder, rng, fill, 0.78, 1.55)
		"roller":
			_add_panel(holder, _panel_size(0.98, 0.58), outline.darkened(0.22), -0.02)
			_add_rival_stripes(holder, rng, variant, fill, outline, 1.1)
			_add_rival_label(holder, alias, fill, outline, 252, 80, 0.009, Vector3(0, 0, 0.012))
			_add_drips(holder, rng, fill, 0.52, 2.1)
		"mural":
			_add_panel(holder, _panel_size(0.94, 0.88), outline.darkened(0.35), -0.026)
			_add_panel(holder, _panel_size(0.86, 0.76), fill.darkened(0.5), -0.02)
			_add_panel(holder, _panel_size(0.58, 0.45), fill.lightened(0.12), -0.015)
			_add_rival_stripes(holder, rng, variant, fill.lightened(0.16), outline, 1.0)
			_add_rival_label(holder, alias, fill, outline, 226, 62, 0.009, Vector3(0, 0, 0.014))
			_add_rival_chips(holder, rng, variant, outline.lightened(0.15))
			_add_drips(holder, rng, fill, 0.86, 1.4)
		_:
			_add_rival_label(holder, alias, fill, outline, 120, 24, 0.005, Vector3.ZERO)

func _add_rival_label(parent: Node3D, text: String, fill: Color, outline: Color,
		font_size: int, outline_size: int, pixel_size: float, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.modulate = fill
	label.outline_modulate = outline
	label.font_size = font_size
	label.outline_size = outline_size
	label.pixel_size = pixel_size
	label.position = pos
	parent.add_child(label)

func _add_rival_stripes(parent: Node3D, rng: RandomNumberGenerator, variant: Dictionary,
		fill: Color, outline: Color, spread: float) -> void:
	var count := int(variant.get("stripeCount", 3))
	var panel := _panel_size(0.9, 0.7)
	for i in count:
		var width := rng.randf_range(panel.x * 0.14, panel.x * 0.28)
		var height := rng.randf_range(0.035, 0.085)
		var x := rng.randf_range(-panel.x * 0.42, panel.x * 0.42)
		var y := rng.randf_range(-spread, spread)
		var color := fill.lightened(0.12) if i % 2 == 0 else outline.lightened(0.08)
		_add_panel_at(parent, Vector3(x, y, -0.008 + i * 0.001),
			Vector2(width, height), color, rng.randf_range(-18.0, 18.0))

func _add_rival_chips(parent: Node3D, rng: RandomNumberGenerator, variant: Dictionary, color: Color) -> void:
	var count := int(variant.get("chipCount", 3))
	var panel := _panel_size(0.82, 0.62)
	for i in count:
		_add_panel_at(parent,
			Vector3(rng.randf_range(-panel.x * 0.5, panel.x * 0.5),
				rng.randf_range(-panel.y * 0.5, panel.y * 0.5), 0.017 + i * 0.001),
			Vector2(rng.randf_range(0.08, 0.22), rng.randf_range(0.025, 0.07)),
			color,
			rng.randf_range(-35.0, 35.0))

func _add_rival_cut_marks(parent: Node3D, rng: RandomNumberGenerator, variant: Dictionary, color: Color) -> void:
	var count := int(variant.get("repeatCount", 2)) + 2
	var panel := _panel_size(0.46, 0.3)
	for i in count:
		_add_panel_at(parent,
			Vector3(rng.randf_range(-panel.x * 0.42, panel.x * 0.42),
				rng.randf_range(-panel.y * 0.35, panel.y * 0.35), 0.004 + i * 0.001),
			Vector2(rng.randf_range(0.08, 0.18), panel.y * 0.08),
			color.darkened(0.15),
			rng.randf_range(-8.0, 8.0))

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
	var mat := _flat_material(Color.WHITE)
	mat.albedo_texture = ImageTexture.create_from_image(image)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	parent.add_child(mesh)
	return true

## Filled quad behind the letters (throw-up halo / piece background).
func _add_panel(parent: Node3D, panel_size: Vector2, color: Color, z_offset: float) -> void:
	_add_panel_at(parent, Vector3(0, 0, z_offset), panel_size, color, 0.0)

func _add_panel_at(parent: Node3D, pos: Vector3, panel_size: Vector2,
		color: Color, rot_degrees: float) -> void:
	var quad := QuadMesh.new()
	quad.size = panel_size
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.position = pos
	mesh.rotation_degrees.z = rot_degrees
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

func _surface_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var base := Color(String(def.get("color", "#9a8f84")))
	mat.albedo_color = base
	mat.roughness = 0.92
	var noise := FastNoiseLite.new()
	noise.seed = hash(String(def.get("wallId", "")))
	noise.frequency = 0.65
	noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.noise = noise
	mat.albedo_texture = texture
	return mat

func _add_surface_details(box_size: Vector3) -> void:
	match String(def.get("surfaceType", "plain")):
		"brick":
			_add_brick_mortar(box_size)
		"concrete", "rooftop":
			_add_concrete_cuts(box_size)
		"stucco":
			_add_stucco_pitting(box_size)
		_:
			_add_concrete_cuts(box_size)

func _add_brick_mortar(box_size: Vector3) -> void:
	var z := box_size.z / 2.0 + 0.006
	var row_h := 0.34
	var mortar := Color("#201d1b", 0.55)
	var rows := maxi(1, int(ceil(box_size.y / row_h)))
	for row in range(rows + 1):
		var y := -box_size.y / 2.0 + row * row_h
		_add_surface_quad(Vector3(0, y, z), Vector2(box_size.x * 0.98, 0.022), mortar, 0.0)
	for row in range(rows):
		var y_center := -box_size.y / 2.0 + row * row_h + row_h * 0.5
		var brick_w := 0.78
		var offset := 0.0 if row % 2 == 0 else brick_w * 0.5
		var start_x := -box_size.x / 2.0 - brick_w + offset
		var count := int(ceil(box_size.x / brick_w)) + 3
		for col in range(count):
			var x := start_x + col * brick_w
			if x < -box_size.x / 2.0 or x > box_size.x / 2.0:
				continue
			_add_surface_quad(Vector3(x, y_center, z + 0.001), Vector2(0.018, row_h * 0.82), mortar, 0.0)
	_add_wall_grime(box_size, z)

func _add_concrete_cuts(box_size: Vector3) -> void:
	var z := box_size.z / 2.0 + 0.006
	var seam := Color("#343230", 0.45)
	var panel_w := minf(2.4, box_size.x * 0.45)
	var x := -box_size.x / 2.0 + panel_w
	while x < box_size.x / 2.0 - 0.2:
		_add_surface_quad(Vector3(x, 0, z), Vector2(0.026, box_size.y * 0.94), seam, 0.0)
		x += panel_w
	var y := -box_size.y / 2.0 + minf(1.45, box_size.y * 0.5)
	while y < box_size.y / 2.0 - 0.2:
		_add_surface_quad(Vector3(0, y, z + 0.001), Vector2(box_size.x * 0.94, 0.024), seam, 0.0)
		y += minf(1.45, box_size.y * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(def.get("wallId", "")) + "_cracks")
	for i in range(4):
		_add_surface_quad(
			Vector3(
				rng.randf_range(-box_size.x * 0.35, box_size.x * 0.35),
				rng.randf_range(-box_size.y * 0.35, box_size.y * 0.35),
				z + 0.002),
			Vector2(rng.randf_range(0.5, 1.2), 0.018),
			Color("#242424", 0.35),
			rng.randf_range(-35.0, 35.0))
	_add_wall_grime(box_size, z)

func _add_stucco_pitting(box_size: Vector3) -> void:
	var z := box_size.z / 2.0 + 0.006
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(def.get("wallId", "")) + "_stucco")
	for i in range(34):
		var c := Color("#ffffff", rng.randf_range(0.08, 0.16)) if i % 2 == 0 \
			else Color("#171717", rng.randf_range(0.08, 0.14))
		_add_surface_quad(
			Vector3(
				rng.randf_range(-box_size.x * 0.47, box_size.x * 0.47),
				rng.randf_range(-box_size.y * 0.43, box_size.y * 0.43),
				z + 0.001),
			Vector2(rng.randf_range(0.06, 0.18), rng.randf_range(0.018, 0.05)),
			c,
			rng.randf_range(0.0, 180.0))
	_add_concrete_cuts(box_size)

func _add_wall_grime(box_size: Vector3, z: float) -> void:
	_add_surface_quad(
		Vector3(0, -box_size.y * 0.42, z + 0.003),
		Vector2(box_size.x * 0.92, box_size.y * 0.12),
		Color("#111111", 0.22),
		0.0)

func _add_surface_quad(pos: Vector3, detail_size: Vector2, color: Color,
		rot_degrees: float) -> void:
	var quad := QuadMesh.new()
	quad.size = detail_size
	var mesh := MeshInstance3D.new()
	mesh.name = "SurfaceDetail"
	mesh.mesh = quad
	mesh.position = pos
	mesh.rotation_degrees.z = rot_degrees
	mesh.material_override = _surface_detail_material(color)
	add_child(mesh)

func _surface_detail_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.98
	return mat
