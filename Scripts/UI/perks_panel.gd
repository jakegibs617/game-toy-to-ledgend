extends PanelContainer
## Perk chooser (Milestone 17, Plan.md §7): P opens it; rank-ups grant
## the points. One option per tree at a time (max two perks per tree by
## §7), so the choices always fit the number-key slots. Text builds
## purely from StatsManager — the smoke test reads it off-tree.

const UiKit := preload("res://Scripts/UI/ui_kit.gd")

var _title_label: Label
var _content_label: Label

func _ready() -> void:
	UiKit.apply_panel_style(self, Color("#7be05a"), 0.92, 14.0, 8.0, true)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(640, 0)
	add_child(box)
	_title_label = UiKit.make_label(box, 24, Color("#7be05a"))
	_content_label = UiKit.make_label(box, 17)
	refresh()

func refresh() -> void:
	if _title_label == null:
		return
	_title_label.text = "PERKS   —   points: %d   —   [P] close" % StatsManager.perk_points
	_content_label.text = page_text()

## Pure text: stats first (they level by doing), then one pickable
## perk per tree, numbered in slot order.
func page_text() -> String:
	var lines: PackedStringArray = []
	for stat in StatsManager.stat_defs:
		var def: Dictionary = StatsManager.stat_defs[stat]
		lines.append("%s %d/%d  (%d xp) — %s" % [
			String(def.get("label", stat)), StatsManager.level(String(stat)),
			int(def.get("maxLevel", 5)), StatsManager.xp_for(String(stat)),
			String(def.get("desc", ""))])
	lines.append("")
	var options := StatsManager.choosable_perks()
	if options.is_empty():
		lines.append("Every perk is yours. The city knows it.")
	elif StatsManager.perk_points <= 0:
		lines.append("No perk points — rank up to earn the next choice.")
	for i in options.size():
		var perk: Dictionary = options[i]
		lines.append("[%d] %s (%s) — %s" % [
			i + 1, String(perk["name"]), String(perk["tree"]), String(perk["desc"])])
	var owned_names := StatsManager.owned_perk_names()
	if not owned_names.is_empty():
		lines.append("")
		lines.append("Yours: %s" % ", ".join(owned_names))
	return "\n".join(lines)

## Slot i picks the i-th choosable perk. Returns true when consumed.
func choose_slot(index: int) -> bool:
	var options := StatsManager.choosable_perks()
	if index < 0 or index >= options.size():
		return false
	var ok: bool = StatsManager.choose_perk(String(options[index]["perkId"]))
	if not ok:
		Sfx.play("denied")
	refresh()
	return true
