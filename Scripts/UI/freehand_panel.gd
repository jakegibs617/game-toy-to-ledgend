extends PanelContainer
## Freehand spray painting canvas (GDD §10 "Later Advanced
## System", first Could-Have from section 36). Opened by Hud when the
## player presses F at a paintable wall: hold LMB to spray, C cycles
## the fill color, Enter/E commits the piece, Esc bails.
##
## The painting model (image, coverage grid, colors used) lives apart
## from the UI nodes so the headless smoke test can begin()/spray_at()/
## result() on a panel that never entered the scene tree.

signal committed(image: Image, colors_used: int, coverage: float)
signal cancelled

const UiKit := preload("res://Scripts/UI/ui_kit.gd")

## Pixels per meter of wall face; canvas resolution follows wall size.
const PIXELS_PER_METER := 96
const MAX_CANVAS := Vector2i(720, 440)
const SPRAY_RADIUS := 14.0
## Coverage is tracked on a coarse grid — a cell counts once the spray
## center passes through it, which is plenty for a style score.
const COVERAGE_CELLS := Vector2i(16, 12)

var image: Image = null

var _wall_name := ""
var _colors_used: Dictionary = {}  # hex -> true, only colors actually sprayed
var _covered: Dictionary = {}      # cell index -> true
var _spraying := false
var _rng := RandomNumberGenerator.new()

var _canvas: TextureRect = null
var _texture: ImageTexture = null
var _title_label: Label
var _footer_label: Label
var _dirty := false

func _ready() -> void:
	UiKit.apply_panel_style(self, Color("#ff4f79"), 0.92, 12.0, 8.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title_label = UiKit.make_label(box, 20, Color("#ff4f79"))
	_canvas = TextureRect.new()
	_canvas.stretch_mode = TextureRect.STRETCH_KEEP
	box.add_child(_canvas)
	_footer_label = UiKit.make_label(box, 15, Color(1, 1, 1, 0.8))
	_refresh_ui()

## Starts a fresh piece sized to `wall`'s face. Safe off-tree.
func begin(wall: PaintableWall) -> void:
	var size: Array = wall.def.get("size", [4, 3, 0.3])
	begin_canvas(wall.display_name(), Vector2(float(size[0]), float(size[1])))

## Starts a fresh canvas of `size_meters` with no wall behind it — the
## gallery commission path (Milestone 21). Safe off-tree.
func begin_canvas(title: String, size_meters: Vector2) -> void:
	var px := Vector2i(
		clampi(int(size_meters.x * PIXELS_PER_METER), 64, MAX_CANVAS.x),
		clampi(int(size_meters.y * PIXELS_PER_METER), 64, MAX_CANVAS.y))
	image = Image.create(px.x, px.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_wall_name = title
	_colors_used.clear()
	_covered.clear()
	_spraying = false
	_rng.seed = hash(_wall_name)
	if _canvas != null:
		_texture = ImageTexture.create_from_image(image)
		_canvas.texture = _texture
		_canvas.custom_minimum_size = Vector2(px)
		_refresh_ui()

## One spray stamp at `pos` in image pixels: speckled edge, solid
## center after repeated passes — the spray-can look without brushes.
func spray_at(pos: Vector2) -> void:
	if image == null:
		return
	var color := Color(GameState.current_fill_color())
	_colors_used[GameState.current_fill_color()] = true
	var r := int(SPRAY_RADIUS)
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var dist := Vector2(dx, dy).length()
			if dist > SPRAY_RADIUS:
				continue
			var x := int(pos.x) + dx
			var y := int(pos.y) + dy
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var falloff := 1.0 - dist / SPRAY_RADIUS
			if _rng.randf() < falloff * 0.55:
				var base := image.get_pixel(x, y)
				image.set_pixel(x, y, base.blend(Color(color, 0.85)))
	var cell := Vector2i(
		clampi(int(pos.x / image.get_width() * COVERAGE_CELLS.x), 0, COVERAGE_CELLS.x - 1),
		clampi(int(pos.y / image.get_height() * COVERAGE_CELLS.y), 0, COVERAGE_CELLS.y - 1))
	_covered[cell.y * COVERAGE_CELLS.x + cell.x] = true
	_dirty = true

## What the writer made: the image plus the style-score ingredients.
func result() -> Dictionary:
	return {
		"image": image,
		"colors_used": maxi(_colors_used.size(), 1),
		"coverage": float(_covered.size()) / float(COVERAGE_CELLS.x * COVERAGE_CELLS.y),
	}

## Routes modal input from Hud. Returns true when consumed.
func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed("toggle_mouse"):
		_spraying = false
		cancelled.emit()
		return true
	if event.is_action_pressed("interact") or \
			(event is InputEventKey and event.pressed and event.keycode == KEY_ENTER):
		_spraying = false
		var r := result()
		committed.emit(r["image"], int(r["colors_used"]), float(r["coverage"]))
		return true
	if event.is_action_pressed("cycle_color"):
		GameState.cycle_fill_color()
		_refresh_ui()
		return true
	# Swallow the key that opened the canvas — otherwise it falls through
	# to Player, re-triggers freehand_requested, and begin() wipes the work.
	if event.is_action_pressed("freehand_paint"):
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_spraying = event.pressed
		if _spraying:
			Sfx.play("spray")
		return true
	return false

func _process(_delta: float) -> void:
	if _spraying and _canvas != null and image != null:
		var local := _canvas.get_global_mouse_position() - _canvas.get_global_rect().position
		# Bound by the image, not the rect: STRETCH_KEEP draws 1:1 at the
		# top-left, and the VBox can stretch the rect wider than the canvas
		# — spraying in that dead zone must not score coverage.
		if Rect2(Vector2.ZERO, Vector2(image.get_width(), image.get_height())).has_point(local):
			spray_at(local)
	if _dirty and _texture != null:
		_texture.update(image)
		_dirty = false

func _refresh_ui() -> void:
	_title_label.text = "FREEHAND PIECE — %s" % _wall_name if _wall_name != "" else "FREEHAND PIECE"
	var color_text := GameState.current_fill_color_name()
	if GameState.colors_unlocked:
		color_text += "  [C] next color"
	_footer_label.text = "Hold LMB: spray   ·   Color: %s   ·   [E/Enter] commit   ·   [Esc] bail" % color_text
	_footer_label.label_settings.font_color = Color(GameState.current_fill_color())
