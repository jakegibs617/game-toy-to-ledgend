class_name MapPanel
extends PanelContainer
## City map (Plan.md section 24, Milestone 6; multi-district since
## Milestone 18). Toggled with M from the HUD. Draws every paintable
## wall top-down — line length is wall width, thickness is visibility,
## color is current owner — plus crew NPC locations and the player.
## The footer shows each district's influence from TerritoryManager.

const UiKit := preload("res://Scripts/UI/ui_kit.gd")
const MAP_SIZE := Vector2(640, 380)
const WORLD_MARGIN := 10.0
const BG_COLOR := Color(0.07, 0.07, 0.1, 0.95)
const PLAYER_COLOR := Color("#7be05a")
const BLANK_COLOR := Color("#6a6a72")
const CROSS_OUT_COLOR := Color("#e0301e")
const BUFFED_COLOR := Color("#c4bcab")
const GUARD_COLOR := Color("#ff9f43")

var _player: Node3D
var _canvas: Control
var _legend: Label
var _world_min := Vector2(-30.0, -25.0)
var _world_max := Vector2(30.0, 35.0)

func _ready() -> void:
	visible = false
	_fit_world_bounds()
	var box := VBoxContainer.new()
	add_child(box)
	var title := UiKit.make_label(box, 24)
	title.text = "THE CITY   —   [M] close"
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

## The map covers every wall in every district (Milestone 18), with a
## margin so edge walls don't sit on the border.
func _fit_world_bounds() -> void:
	if WallManager.wall_defs.is_empty():
		return
	var first: Array = WallManager.wall_defs[0]["position"]
	_world_min = Vector2(first[0], first[2])
	_world_max = _world_min
	for def in WallManager.wall_defs:
		var pos: Array = def["position"]
		_world_min = _world_min.min(Vector2(pos[0], pos[2]))
		_world_max = _world_max.max(Vector2(pos[0], pos[2]))
	_world_min -= Vector2(WORLD_MARGIN, WORLD_MARGIN)
	_world_max += Vector2(WORLD_MARGIN, WORLD_MARGIN)

func bind_player(player: Node3D) -> void:
	_player = player

func _process(_delta: float) -> void:
	if visible:
		_canvas.queue_redraw()  # follow the player marker

func _refresh_legend() -> void:
	var lines: PackedStringArray = []
	for district_id in TerritoryManager.districts:
		lines.append("%s:  %s" % [
			String(TerritoryManager.districts[district_id].get("name", district_id)),
			TerritoryManager.summary_text(String(district_id))])
	_legend.text = "\n".join(lines)

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
	return (world_xz - _world_min) / (_world_max - _world_min) * _canvas.size

func _scale() -> float:
	return _canvas.size.x / (_world_max.x - _world_min.x)
