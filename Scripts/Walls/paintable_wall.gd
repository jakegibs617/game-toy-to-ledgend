class_name PaintableWall
extends StaticBody3D
## A paintable surface, built at runtime from a wall definition in
## Data/walls.json. Placeholder graffiti is rendered as a Label3D
## (plus a backdrop quad for pieces) until real decal art exists.

var def: Dictionary = {}

const RivalGraffitiStyle := preload("res://Scripts/Walls/rival_graffiti_style.gd")
const GraffitiFonts := preload("res://Scripts/Walls/graffiti_font_library.gd")
## Seconds between each letter spraying on during an animated paint.
const LETTER_REVEAL_DELAY := 0.11

var _graffiti_anchor: Node3D
var _reveal_tween: Tween

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
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	for child in _graffiti_anchor.get_children():
		child.queue_free()

## Milestone 8 art pass: each graffiti gets a deterministic tilt; bigger
## work (throw-ups/pieces/etc.) gets filled panels behind bare lettering,
## all unshaded so the work pops in the dusk lighting. No paint drips
## (Product_reqs.md). When `animate` is set on a fresh player paint, the
## letters spray on one at a time instead of appearing all at once.
func show_graffiti(graffiti: Dictionary, animate := false) -> void:
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
	var type := String(graffiti.get("type", "tag"))
	var label := Label3D.new()
	var full_text := String(graffiti.get("alias", "???"))
	label.text = full_text
	label.modulate = fill
	label.outline_modulate = outline
	# Only render a font that is capable for this graffiti type
	# (Product_reqs.md): a marker hand never letters a throw-up/piece/etc.
	GraffitiFonts.apply_to_label(label,
		GraffitiFonts.resolve_for_families(
			String(graffiti.get("fontStyle", GraffitiFonts.default_style_id())),
			_font_families_for_type(type)))
	# Every type is bare lettering now — just the sized fill + outline, no
	# rectangular background panel behind the letters (Product_reqs.md).
	match type:
		"tag":
			label.font_size = 96
			label.outline_size = 18
			label.pixel_size = 0.004
		"throwup":
			label.font_size = 160
			label.outline_size = 48
			label.pixel_size = 0.006
		"piece":
			label.font_size = 220
			label.outline_size = 64
			label.pixel_size = 0.008
		"stencil":
			# Crisp single-pass cut: thin outline (Milestone 16).
			label.font_size = 110
			label.outline_size = 10
			label.pixel_size = 0.004
		"roller":
			# Blockbuster strip the full width of the parapet.
			label.font_size = 250
			label.outline_size = 78
			label.pixel_size = 0.009
		"mural":
			label.font_size = 230
			label.outline_size = 60
			label.pixel_size = 0.009
		"sticker":
			# A slap: small printed label on a paper backing (Product_reqs.md).
			# The fill color is the paper stock; the outline color is the ink,
			# so the name reads dark-on-paper instead of vanishing into it.
			_add_paper_backing(holder, _panel_size(0.34, 0.2), fill)
			label.modulate = outline
			label.outline_modulate = fill
			label.font_size = 60
			label.outline_size = 12
			label.pixel_size = 0.0032
		"wheatpaste":
			# A pasted poster: bigger paper panel behind the lettering.
			_add_paper_backing(holder, _panel_size(0.6, 0.74), fill)
			label.modulate = outline
			label.outline_modulate = fill
			label.font_size = 150
			label.outline_size = 34
			label.pixel_size = 0.006
	# Bespoke style behaviors (Product_reqs.md): glass scratch hands draw
	# as a faint greyscale scratch, and acid hands run vertical down a tall
	# glass panel. The plan is shared with the smoke test (GraffitiFonts).
	# Paper work (stickers/wheatpaste) is printed, not scratched onto glass,
	# so it keeps its own paper-on-ink look and ignores the scratch plan.
	if not bool(WallManager.styles.get(type, {}).get("paper", false)):
		_apply_style_render_plan(holder, label,
			String(graffiti.get("fontStyle", GraffitiFonts.default_style_id())), fill, outline)
	holder.add_child(label)
	if animate:
		_reveal_label_letters(label, full_text)

## Applies the font style's render plan to a freshly built player label:
## desaturate + fade the one-color scratch hand, and rotate the holder
## upright for a vertical (acid) orientation. Leaves normal tags untouched.
func _apply_style_render_plan(holder: Node3D, label: Label3D, font_style: String,
		fill: Color, outline: Color) -> void:
	var plan := GraffitiFonts.render_plan(font_style, _is_portrait())
	if bool(plan["greyscale"]):
		var op := float(plan["opacity"])
		var grey := _greyscale(fill, op)
		label.modulate = grey
		label.outline_modulate = _greyscale(outline, op).darkened(0.4)
	if String(plan["orientation"]) == "vertical":
		holder.rotation_degrees.z += 90.0

## A wall is portrait when its painted face is taller than it is wide —
## acid hands run vertically down those (storefront glass panels).
func _is_portrait() -> bool:
	var size: Array = def.get("size", [4, 3, 0.3])
	return float(size[1]) > float(size[0])

## Luminance-matched grey at the given alpha (scratch hands are one color).
func _greyscale(color: Color, alpha: float) -> Color:
	var lum := color.get_luminance()
	return Color(lum, lum, lum, alpha)

## The font families this graffiti type is allowed to render with, read
## from the style def in graffiti_styles.json (empty = no restriction).
func _font_families_for_type(type: String) -> Array:
	var style: Dictionary = WallManager.styles.get(type, {})
	return style.get("fontFamilies", [])

func _show_rival_graffiti(holder: Node3D, graffiti: Dictionary, fill: Color, outline: Color) -> void:
	var variant := RivalGraffitiStyle.variant_for(graffiti)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(variant["seed"])
	holder.rotation_degrees.z = float(variant["slant"])
	holder.position.x = float(variant["xOffset"]) * _panel_size(1.0, 1.0).x
	holder.position.y = float(variant["yOffset"]) * _panel_size(1.0, 1.0).y
	var type := String(graffiti.get("type", "tag"))
	var alias := String(graffiti.get("alias", "???"))
	# Rivals letter with a font capable for the type too (Product_reqs.md).
	var font_style := GraffitiFonts.resolve_for_families(
		String(graffiti.get("fontStyle", GraffitiFonts.default_style_id())),
		_font_families_for_type(type))
	# No solid background panel behind rival work either (Product_reqs.md):
	# crew identity rides on color, slant, stripes/chips/cut-marks and the
	# deterministic Milestone 29 variant, not a rectangle.
	match type:
		"tag":
			_add_rival_label(holder, alias, fill, outline, 108, 20, 0.0045, Vector3.ZERO, font_style)
		"stencil":
			_add_rival_cut_marks(holder, rng, variant, fill)
			_add_rival_label(holder, alias, fill, outline.darkened(0.3), 118, 8, 0.004, Vector3(0, 0, 0.006), font_style)
		"throwup":
			_add_rival_stripes(holder, rng, variant, fill.lightened(0.08), outline, 0.72)
			_add_rival_label(holder, alias, fill, outline, 168, 52, 0.006, Vector3(0, 0, 0.01), font_style)
			_add_rival_chips(holder, rng, variant, outline)
		"piece":
			_add_rival_stripes(holder, rng, variant, fill.lightened(0.18), outline, 0.95)
			_add_rival_label(holder, alias, fill, outline, 214, 66, 0.008, Vector3(0, 0, 0.012), font_style)
			_add_rival_chips(holder, rng, variant, fill.lightened(0.2))
		"roller":
			_add_rival_stripes(holder, rng, variant, fill, outline, 1.1)
			_add_rival_label(holder, alias, fill, outline, 252, 80, 0.009, Vector3(0, 0, 0.012), font_style)
		"mural":
			_add_rival_stripes(holder, rng, variant, fill.lightened(0.16), outline, 1.0)
			_add_rival_label(holder, alias, fill, outline, 226, 62, 0.009, Vector3(0, 0, 0.014), font_style)
			_add_rival_chips(holder, rng, variant, outline.lightened(0.15))
		_:
			_add_rival_label(holder, alias, fill, outline, 120, 24, 0.005, Vector3.ZERO, font_style)

func _add_rival_label(parent: Node3D, text: String, fill: Color, outline: Color,
		font_size: int, outline_size: int, pixel_size: float, pos: Vector3,
		style_id := "") -> void:
	var label := Label3D.new()
	label.text = text
	label.modulate = fill
	label.outline_modulate = outline
	GraffitiFonts.apply_to_label(label,
		style_id if style_id != "" else GraffitiFonts.default_style_id())
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
	GraffitiFonts.apply_to_label(label, GraffitiFonts.default_style_id())
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

## Paper stock behind a slap/poster (Product_reqs.md): unlike sprayed work,
## stickers and wheatpastes are physical paper, so they read as a panel —
## a paper-colored rectangle with a thin torn-looking dark border behind the
## lettering. Sits just off the wall so the ink can layer on top.
func _add_paper_backing(parent: Node3D, panel_size: Vector2, paper: Color) -> void:
	_add_panel_at(parent, Vector3(0, 0, -0.004),
		panel_size * 1.08, paper.darkened(0.55), 0.0)
	_add_panel_at(parent, Vector3(0, 0, -0.003), panel_size, paper, 0.0)

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

## Sprays the lettering on one character at a time (Product_reqs.md).
## Skipped headless — the smoke test sees the finished text immediately.
func _reveal_label_letters(label: Label3D, full_text: String) -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	if full_text.length() <= 1 or DisplayServer.get_name() == "headless":
		return
	label.text = full_text.substr(0, 1)
	_reveal_tween = create_tween()
	for i in range(2, full_text.length() + 1):
		_reveal_tween.tween_interval(LETTER_REVEAL_DELAY)
		_reveal_tween.tween_callback(_set_label_text.bind(label, full_text.substr(0, i)))

func _set_label_text(label: Label3D, text: String) -> void:
	if is_instance_valid(label):
		label.text = text

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
		"glass":
			_add_glass_panes(box_size)
		_:
			_add_concrete_cuts(box_size)

## Storefront glass (Product_reqs.md scratch/acid surface): a couple of
## bright diagonal reflection streaks and a frame divider so the pane
## reads as glass — the only surface scratch/acid hands take to.
func _add_glass_panes(box_size: Vector3) -> void:
	var z := box_size.z / 2.0 + 0.006
	var divider := Color("#cdd6da", 0.5)
	_add_surface_quad(Vector3(0, 0, z), Vector2(0.05, box_size.y * 0.96), divider, 0.0)
	_add_surface_quad(Vector3(0, 0, z), Vector2(box_size.x * 0.96, 0.05), divider, 0.0)
	for i in 2:
		_add_surface_quad(
			Vector3(-box_size.x * 0.18 + i * box_size.x * 0.36, 0, z + 0.001),
			Vector2(0.12, box_size.y * 1.1),
			Color("#ffffff", 0.12),
			22.0)

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
