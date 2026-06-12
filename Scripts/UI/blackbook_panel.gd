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

const UiKit := preload("res://Scripts/UI/ui_kit.gd")

var page := 0
var _title_label: Label
var _content_label: Label

## Single source of truth for page order: title + text builder pairs.
## Built per call because Callables need the instance.
func _page_defs() -> Array:
	return [
		{"title": "Writer", "build": _writer_text},
		{"title": "Styles", "build": _styles_text},
		{"title": "Crew", "build": _crew_text},
		{"title": "The City", "build": _city_text},
	]

func _ready() -> void:
	UiKit.apply_panel_style(self, Color("#b48ee0"), 0.92, 14.0, 8.0, true)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(640, 0)
	add_child(box)
	_title_label = UiKit.make_label(box, 24, Color("#b48ee0"))
	_content_label = UiKit.make_label(box, 17)
	refresh()

func set_page(index: int) -> void:
	if index < 0 or index >= _page_defs().size():
		return
	page = index
	refresh()

func refresh() -> void:
	var defs := _page_defs()
	var tabs: PackedStringArray = []
	for i in defs.size():
		var title: String = defs[i]["title"]
		tabs.append("[%d] %s" % [i + 1, title] if i != page else "[%d] >%s<" % [i + 1, title])
	_title_label.text = "BLACKBOOK   %s   —   [Tab] close" % "   ".join(tabs)
	_content_label.text = page_text(page)

## Pure text for a page — reads only the autoload managers.
func page_text(index: int) -> String:
	var defs := _page_defs()
	if index < 0 or index >= defs.size():
		return ""
	return defs[index]["build"].call()

func _writer_text() -> String:
	var lines: PackedStringArray = []
	lines.append("Alias: %s" % GameState.alias)
	lines.append("Rank: %s   (Rep %d)" % [GameState.rank, GameState.reputation])
	lines.append("Cash: $%d   ·   Paint: %d" % [GameState.cash, GameState.paint])
	lines.append("Heat: %s (%d)" % [HeatManager.level_name(), roundi(HeatManager.heat)])
	var stat_parts: PackedStringArray = []
	for stat in StatsManager.stat_defs:
		stat_parts.append("%s %d" % [
			String(StatsManager.stat_defs[stat].get("label", stat)),
			StatsManager.level(String(stat))])
	lines.append("%s   ·   Perk points: %d  [P]" % [
		" · ".join(stat_parts), StatsManager.perk_points])
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
			var notes := String(style.get("notes", ""))
			lines.append("%s — %d paint · base %d rep%s" % [String(style.get("label", type)),
				SupplyManager.paint_cost(style), int(style.get("baseValue", 0)),
				" · " + notes if notes != "" else ""])
		else:
			var hint := String(style.get("lockedHint", ""))
			lines.append("%s — locked%s" % [String(style.get("label", type)),
				" (" + hint + ")" if hint != "" else ""])
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
	var held := _walls_by_owner()
	var lines: PackedStringArray = []
	for crew in RivalManager.crews.values():
		lines.append("%s (%s) — led by %s" % [String(crew.get("name", "?")),
			String(crew.get("tag", "?")), String(crew.get("leaderAlias", "?"))])
		lines.append("      aggression %d · attitude %d · holds %d walls" % [
			int(crew.get("aggression", 0)), int(crew.get("relationshipToPlayer", 0)),
			int(held.get(String(crew["crewId"]), 0))])
	lines.append("")
	lines.append("Your name is on %d of %d walls; the city buffed %d." % [
		int(held.get("player", 0)), WallManager.wall_defs.size(), int(held.get("city", 0))])
	return "\n".join(lines)

## owner -> wall count, in one pass over the wall states.
func _walls_by_owner() -> Dictionary:
	var counts := {}
	for wall_id in WallManager.wall_states:
		var owner := String(WallManager.wall_states[wall_id].get("ownerCrewId", ""))
		counts[owner] = int(counts.get(owner, 0)) + 1
	return counts
