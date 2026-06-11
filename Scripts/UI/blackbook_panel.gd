class_name BlackbookPanel
extends PanelContainer
## The blackbook (Plan.md section 23, Milestone 13): the writer's
## journal on Tab. Four pages cycled with the number keys — Writer
## (alias/rank/wallet/heat/territory/mission notes), Styles (unlocked
## graffiti types and the fill palette), Crew (recruitment status —
## previously the standalone crew menu), and The City (known rival
## crews and your presence on the walls). Page text is built from the
## autoload managers only, so the smoke test can read pages without a
## scene.

const PAGES := ["Writer", "Styles", "Crew", "The City"]

var page := 0
var _title_label: Label
var _content_label: Label

func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.09, 0.92)
	style.set_corner_radius_all(6)
	style.border_color = Color("#b48ee0")
	style.border_width_left = 3
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", style)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(640, 0)
	add_child(box)
	_title_label = _make_label(box, 24, Color("#b48ee0"))
	_content_label = _make_label(box, 17)
	refresh()

func set_page(index: int) -> void:
	if index < 0 or index >= PAGES.size():
		return
	page = index
	refresh()

func refresh() -> void:
	var tabs: PackedStringArray = []
	for i in PAGES.size():
		tabs.append("[%d] %s" % [i + 1, PAGES[i]] if i != page else "[%d] >%s<" % [i + 1, PAGES[i]])
	_title_label.text = "BLACKBOOK   %s   —   [Tab] close" % "   ".join(tabs)
	_content_label.text = page_text(page)

## Pure text for a page — reads only the autoload managers.
func page_text(index: int) -> String:
	match index:
		0: return _writer_text()
		1: return _styles_text()
		2: return _crew_text()
		3: return _city_text()
	return ""

func _writer_text() -> String:
	var lines: PackedStringArray = []
	lines.append("Alias: %s" % GameState.alias)
	lines.append("Rank: %s   (Rep %d)" % [GameState.rank, GameState.reputation])
	lines.append("Cash: $%d   ·   Paint: %d" % [GameState.cash, GameState.paint])
	lines.append("Heat: %s (%d)" % [HeatManager.level_name(), roundi(HeatManager.heat)])
	lines.append("")
	for district_id in TerritoryManager.districts:
		var district: Dictionary = TerritoryManager.districts[district_id]
		lines.append("%s — %s" % [String(district.get("name", district_id)),
			TerritoryManager.summary_text(String(district_id))])
	lines.append("")
	if MissionManager.chain_done:
		lines.append("Notes: the Mill Yard knows your name. Canal Side is next.")
	else:
		var mission := MissionManager.current_mission()
		var objective := MissionManager.current_objective()
		if mission.is_empty():
			lines.append("Notes: find your first wall.")
		else:
			lines.append("Notes: %s — %s" % [String(mission.get("title", "")),
				String(objective.get("text", "in progress"))])
	return "\n".join(lines)

func _styles_text() -> String:
	var lines: PackedStringArray = []
	for type in WallManager.styles:
		var style: Dictionary = WallManager.styles[type]
		if GameState.is_type_unlocked(String(type)):
			lines.append("%s — %d paint · base %d rep" % [String(style.get("label", type)),
				SupplyManager.paint_cost(style), int(style.get("baseValue", 0))])
		else:
			lines.append("%s — locked" % String(style.get("label", type)))
	lines.append("")
	if GameState.colors_unlocked:
		var names: PackedStringArray = []
		var palette := GameState.fill_palette()
		for i in palette.size():
			var color_name := String(palette[i]["name"])
			names.append("> %s <" % color_name if i == GameState.fill_color_index else color_name)
		lines.append("Fill colors [C]: %s" % ", ".join(names))
	else:
		lines.append("Fill colors: locked — see Lupe about real paint.")
	return "\n".join(lines)

func _crew_text() -> String:
	var lines: PackedStringArray = []
	for m in CrewManager.members.values():
		lines.append("%s (%s) — %s\n      %s" % [
			String(m["alias"]), String(m["name"]),
			String(m.get("roleLabel", m["role"])),
			CrewManager.status_text(m)])
	return "\n".join(lines) if not lines.is_empty() else "No writers met yet."

func _city_text() -> String:
	var lines: PackedStringArray = []
	for crew in RivalManager.crews.values():
		lines.append("%s (%s) — led by %s" % [String(crew.get("name", "?")),
			String(crew.get("tag", "?")), String(crew.get("leaderAlias", "?"))])
		lines.append("      aggression %d · attitude %d · holds %d walls" % [
			int(crew.get("aggression", 0)), int(crew.get("relationshipToPlayer", 0)),
			_walls_owned_by(String(crew["crewId"]))])
	lines.append("")
	lines.append("Your name is on %d of %d walls; the city buffed %d." % [
		_walls_owned_by("player"), WallManager.wall_defs.size(), _walls_owned_by("city")])
	return "\n".join(lines)

func _walls_owned_by(owner: String) -> int:
	var count := 0
	for wall_id in WallManager.wall_states:
		if String(WallManager.wall_states[wall_id].get("ownerCrewId", "")) == owner:
			count += 1
	return count

func _make_label(parent: Control, font_size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = font_size
	settings.font_color = color
	settings.outline_size = 6
	settings.outline_color = Color(0, 0, 0, 0.85)
	label.label_settings = settings
	parent.add_child(label)
	return label
