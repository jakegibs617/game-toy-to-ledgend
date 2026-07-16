class_name BlackbookPanel
extends PanelContainer
## The blackbook (GDD §23, Milestone 13): the writer's
## journal on Tab. Four pages cycled with the number keys — Writer
## (alias/rank/wallet/heat/territory/mission notes), Styles (unlocked
## graffiti types and the fill palette), Crew (recruitment status —
## previously the standalone crew menu), and The City (known rival
## crews and your presence on the walls). Page text is built from the
## autoload managers only, so the smoke test can read pages without a
## scene.

const UiKit := preload("res://Scripts/UI/ui_kit.gd")
const GraffitiFonts := preload("res://Scripts/Walls/graffiti_font_library.gd")

var page := 0
## Set by the HUD when the book is opened from a bench (Product_reqs.md):
## the Styles page lists practiceable tag styles and the number keys
## sketch them instead of flipping pages.
var practice_mode := false
var _title_label: Label
var _content_label: Label
# A white "sketch page" that shows the writer's tag drawn in the style
# currently being practiced (Product_reqs.md). Only visible in practice mode.
var _sketch_card: PanelContainer
var _sketch_label: Label
var _preview_style := ""

## Up to MODAL_SLOT_ACTIONS' worth of tag styles still worth practicing
## (not the toy default, not already unlocked), in catalog order. The
## index is the slot the player presses to sketch one.
func practiceable_style_ids() -> Array:
	var ids: Array = []
	for style_id in GraffitiFonts.style_ids():
		var id := String(style_id)
		var def: Dictionary = GraffitiFonts.style_def(id)
		if bool(def.get("toyStyle", false)) or GameState.is_tag_font_style_unlocked(id):
			continue
		ids.append(id)
		if ids.size() >= 6:
			break
	return ids

## Sketch the style in practice slot `slot` once. Returns the
## GameState.practice result (ok/reason/count/required/unlocked).
func sketch(slot: int) -> Dictionary:
	var ids := practiceable_style_ids()
	if slot < 0 or slot >= ids.size():
		return {"ok": false, "reason": "No style to sketch in that slot."}
	# Show this style on the sketch page even if the practice just unlocked
	# it (and it drops out of the practiceable list).
	_preview_style = String(ids[slot])
	var result := GameState.practice_tag_font_style(_preview_style)
	refresh()
	return result

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
	# Wrap long lines (e.g. the full tag-style list) so the page keeps the
	# box's width instead of ballooning it and shoving centered content
	# (the sketch card) off-screen.
	_content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_label.custom_minimum_size = Vector2(640, 0)
	_sketch_card = PanelContainer.new()
	_sketch_card.visible = false
	var page_style := StyleBoxFlat.new()
	page_style.bg_color = Color.WHITE
	page_style.set_content_margin_all(14.0)
	page_style.set_corner_radius_all(6)
	_sketch_card.add_theme_stylebox_override("panel", page_style)
	_sketch_label = Label.new()
	_sketch_label.custom_minimum_size = Vector2(0, 150)
	_sketch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sketch_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sketch_label.add_theme_font_size_override("font_size", 72)
	_sketch_label.add_theme_color_override("font_color", Color("#1a1a1a"))
	_sketch_card.add_child(_sketch_label)
	box.add_child(_sketch_card)
	# Sit the sketch page right under the title so it stays on screen even
	# when the Styles text runs long (the panel is centered and can overflow).
	box.move_child(_sketch_card, 1)
	refresh()

func set_page(index: int) -> void:
	if index < 0 or index >= _page_defs().size():
		return
	page = index
	refresh()

func refresh() -> void:
	if _title_label == null or _content_label == null:
		return  # built off-tree (smoke test) — page_text() is the read path
	var defs := _page_defs()
	var tabs: PackedStringArray = []
	for i in defs.size():
		var title: String = defs[i]["title"]
		tabs.append("[%d] %s" % [i + 1, title] if i != page else "[%d] >%s<" % [i + 1, title])
	_title_label.text = "BLACKBOOK   %s   —   [Tab] close" % "   ".join(tabs)
	_content_label.text = page_text(page)
	_update_sketch_card()

## Draws the writer's tag on the white sketch page in the font currently
## being practiced. Hidden outside practice mode.
func _update_sketch_card() -> void:
	if _sketch_card == null:
		return
	if not practice_mode:
		_sketch_card.visible = false
		return
	if _preview_style == "" or not GraffitiFonts.is_valid_style(_preview_style):
		var ids := practiceable_style_ids()
		_preview_style = String(ids[0]) if not ids.is_empty() else GraffitiFonts.default_style_id()
	_sketch_card.visible = true
	_sketch_label.text = GameState.alias if GameState.alias != "" else "TAG"
	var font := GraffitiFonts.font_for_style(_preview_style)
	if font != null:
		_sketch_label.add_theme_font_override("font", font)
	else:
		_sketch_label.remove_theme_font_override("font")

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
	lines.append("Crew rep: %d%s" % [GameState.crew_rep,
		"   — the street side-eyes gallery money" if GameState.crew_rep < 0 else ""])
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
		lines.append("Notes: %s" % String(
			MissionManager.current_chain().get("completeMessage", "the city knows your name.")))
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
	lines.append("")
	var font_names: PackedStringArray = []
	for style_id in GraffitiFonts.style_ids():
		var id := String(style_id)
		var def: Dictionary = GraffitiFonts.style_def(id)
		var name := "%s L%d %s" % [
			GraffitiFonts.style_label(id), int(def.get("level", 0)), String(def.get("family", "style"))]
		if GameState.is_tag_font_style_unlocked(id):
			font_names.append("> %s <" % name if GameState.selected_tag_font_style() == id else name)
		else:
			var required := int(def.get("practiceRequired", 5))
			var practiced := GameState.practice_count_for_tag_font_style(id)
			var hint := String(def.get("lockedHint", "locked"))
			font_names.append("%s (%d/%d sketches: %s)" % [name, practiced, required, hint])
	lines.append("Tag styles: %s" % ", ".join(font_names))
	if practice_mode:
		lines.append("")
		var practiceable := practiceable_style_ids()
		if practiceable.is_empty():
			lines.append("Sketching: every style is practiced — nothing left to fill in.")
		else:
			var opts: PackedStringArray = []
			for i in practiceable.size():
				var id := String(practiceable[i])
				var def: Dictionary = GraffitiFonts.style_def(id)
				opts.append("[%d] %s %d/%d" % [i + 1, GraffitiFonts.style_label(id),
					GameState.practice_count_for_tag_font_style(id),
					int(def.get("practiceRequired", 5))])
			lines.append("Sketching on the bench — press a number to fill a page:")
			lines.append("   " + "   ".join(opts))
	return "\n".join(lines)

func _crew_text() -> String:
	var lines: PackedStringArray = []
	if CrewManager.any_recruited():
		lines.append("Crew morale: %s — %d/%d" % [
			CrewManager.morale_text(), CrewManager.team_morale, CrewManager.MAX_MORALE])
		lines.append("")
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
	lines.append("Wall duels: %d won · %d lost · streak %d" % [
		GameState.rival_duel_wins, GameState.rival_duel_losses, GameState.rival_duel_streak])
	if not RivalManager.active_wall_duels.is_empty():
		var callouts: PackedStringArray = []
		for wall_id in RivalManager.active_wall_duels:
			var duel: Dictionary = RivalManager.active_wall_duels[wall_id]
			var left := int(duel.get("ticksLeft", RivalManager.WALL_DUEL_DEADLINE_TICKS))
			callouts.append("%s at %s (%d to answer)" % [
				String(duel.get("crewName", "A rival crew")),
				String(WallManager.wall_def(String(wall_id)).get("name", wall_id)),
				maxi(left, 0)])
		lines.append("Active callout: %s" % "; ".join(callouts))
	var trains := TrainManager.service_log()
	if not trains.is_empty():
		lines.append("")
		lines.append("Train cars in service:")
		for train in trains:
			var graffiti: Dictionary = train["currentGraffiti"]
			lines.append("      %s — %s, passes %d, %s" % [
				String(train.get("label", train.get("trainId", "Train"))),
				String(graffiti.get("alias", "?")),
				int(graffiti.get("passes", 0)),
				String(train.get("phase", "stopped"))])
	if GalleryManager.sales_count() > 0:
		lines.append("")
		lines.append("Gallery sales: %d canvas%s through Vesper — cash in hand, side-eye on the block." % [
			GalleryManager.sales_count(), "" if GalleryManager.sales_count() == 1 else "es"])
	return "\n".join(lines)

## owner -> wall count, in one pass over the wall states.
func _walls_by_owner() -> Dictionary:
	var counts := {}
	for wall_id in WallManager.wall_states:
		var owner := String(WallManager.wall_states[wall_id].get("ownerCrewId", ""))
		counts[owner] = int(counts.get(owner, 0)) + 1
	return counts
