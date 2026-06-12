class_name MapPanel
extends PanelContainer
## District map (Plan.md section 24, Milestone 6). Toggled with M from
## the HUD. Draws every paintable wall top-down — line length is wall
## width, thickness is visibility, color is current owner — plus crew
## NPC locations and the player. The footer shows district influence
## from TerritoryManager.

const UiKit := preload("res://Scripts/UI/ui_kit.gd")
const MAP_SIZE := Vector2(400, 400)
const WORLD_MIN := Vector2(-30.0, -25.0)  # world x/z box mapped onto the panel
const WORLD_MAX := Vector2(30.0, 35.0)
const BG_COLOR := Color(0.07, 0.07, 0.1, 0.95)
const PLAYER_COLOR := Color("#7be05a")
const BLANK_COLOR := Color("#6a6a72")
const CROSS_OUT_COLOR := Color("#e0301e")
const BUFFED_COLOR := Color("#c4bcab")
const GUARD_COLOR := Color("#ff9f43")

var _player: Node3D
var _canvas: Control
var _legend: Label

func _ready() -> void:
	visible = false
	var box := VBoxContainer.new()
	add_child(box)
	var title := UiKit.make_label(box, 24)
	var district: Dictionary = TerritoryManager.districts.values()[0] \
		if not TerritoryManager.districts.is_empty() else {}
	title.text = "%s   —   [M] close" % String(district.get("name", "DISTRICT")).to_upper()
	_canvas = Control.new()
	_canvas.custom_minimum_size = MAP_SIZE
	_canvas.draw.connect(_draw_map)
	box.add_child(_canvas)
	_legend = UiKit.make_label(box, 16)
	TerritoryManager.territory_changed.connect(
		func(_district_id: String) -> void: _refresh_legend())
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh_legend())

func bind_player(player: Node3D) -> void:
	_player = player

func _process(_delta: float) -> void:
	if visible:
		_canvas.queue_redraw()  # follow the player marker

func _refresh_legend() -> void:
	if TerritoryManager.districts.is_empty():
		return
	_legend.text = TerritoryManager.summary_text(TerritoryManager.districts.keys()[0])

func _draw_map() -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), BG_COLOR)
	for def in WallManager.wall_defs:
		var state: Dictionary = WallManager.wall_states.get(String(def["wallId"]), {})
		var pos: Array = def["position"]
		var center := _to_map(Vector2(pos[0], pos[2]))
		var rot_y := deg_to_rad(float(def.get("rotationY", 0)))
		var dir := Vector2(cos(rot_y), -sin(rot_y))
		var half := float(def["size"][0]) * 0.5 * _scale()
		var thickness := 2.0 + float(def.get("visibility", 1))
		_canvas.draw_line(center - dir * half, center + dir * half, _owner_color(state), thickness)
		if String(state.get("state", "")) == "crossed_out":
			_canvas.draw_line(center + Vector2(-4, -4), center + Vector2(4, 4), CROSS_OUT_COLOR, 2.0)
			_canvas.draw_line(center + Vector2(-4, 4), center + Vector2(4, -4), CROSS_OUT_COLOR, 2.0)
	for m in CrewManager.members.values():
		if m.has("position"):
			var p: Array = m["position"]
			_canvas.draw_circle(_to_map(Vector2(p[0], p[2])), 3.0, Color(String(m.get("color", "#ffffff"))))
	for guard in PatrolManager.guards():
		if is_instance_valid(guard):
			_canvas.draw_circle(_to_map(
				Vector2(guard.global_position.x, guard.global_position.z)), 4.0, GUARD_COLOR)
	if _player != null:
		_canvas.draw_circle(
			_to_map(Vector2(_player.global_position.x, _player.global_position.z)),
			5.0, PLAYER_COLOR)

func _owner_color(state: Dictionary) -> Color:
	var owner := String(state.get("ownerCrewId", "none"))
	if owner == "player":
		return PLAYER_COLOR
	if owner == "city":
		return BUFFED_COLOR
	if owner == "none" or String(state.get("state", "blank")) == "blank":
		return BLANK_COLOR
	return Color(String(RivalManager.crews.get(owner, {}).get("fillColor", "#aaaaaa")))

func _to_map(world_xz: Vector2) -> Vector2:
	return (world_xz - WORLD_MIN) / (WORLD_MAX - WORLD_MIN) * _canvas.size

func _scale() -> float:
	return _canvas.size.x / (WORLD_MAX.x - WORLD_MIN.x)
