extends Node
## Crew recruitment (Plan.md section 14, Milestone 5). Loads
## Data/npc_data.json, spawns recruitable NPCs, and runs each member's
## recruitment as a small stage machine:
##   not_met -> mission_active -> item_recovered -> recruited
## Recruited members grant passive role bonuses (the lookout makes
## rivals back off more often — see RivalManager). Autoloaded as
## CrewManager.

signal crew_event(message: String)
signal crew_changed
signal stage_changed(member_id: String, stage: String)

const NPC_PATH := "res://Data/npc_data.json"

var members: Dictionary = {}  # memberId -> definition + runtime "stage"

func _ready() -> void:
	var parsed: Variant = _load_json(NPC_PATH)
	if parsed is Array:
		for m in parsed:
			m["stage"] = "not_met"
			members[m["memberId"]] = m

## Spawns NPCs (and any not-yet-recovered mission items) into a scene.
func spawn_npcs(parent: Node3D) -> void:
	for m in members.values():
		var npc := Npc.new()
		npc.setup(m)
		parent.add_child(npc)
		if m.has("item") and m["stage"] in ["not_met", "mission_active"]:
			var item := PickupItem.new()
			item.setup(String(m["memberId"]), m["item"])
			parent.add_child(item)

## Talking to an NPC advances their recruitment stage.
func interact(member_id: String) -> void:
	var m: Dictionary = members[member_id]
	var lines: Dictionary = m.get("dialogue", {})
	match String(m["stage"]):
		"not_met":
			m["stage"] = "mission_active"
			stage_changed.emit(member_id, String(m["stage"]))
			crew_event.emit("%s: \"%s\"" % [m["alias"], lines.get("meet", "...")])
		"mission_active":
			crew_event.emit("%s: \"%s\"" % [m["alias"], lines.get("active", "...")])
		"item_recovered":
			m["stage"] = "recruited"
			stage_changed.emit(member_id, String(m["stage"]))
			crew_event.emit("%s joined your crew — %s! %s" % [
				m["alias"], String(m.get("roleLabel", m["role"])),
				String(m.get("bonusDescription", ""))])
			crew_changed.emit()
		"recruited":
			crew_event.emit("%s: \"%s\"" % [m["alias"], lines.get("recruited", "...")])

## Returns true if the item was collected (mission must be active).
func collect_item(member_id: String) -> bool:
	var m: Dictionary = members[member_id]
	if String(m["stage"]) != "mission_active":
		crew_event.emit("A worn blackbook. Someone must be missing it.")
		return false
	m["stage"] = "item_recovered"
	stage_changed.emit(member_id, String(m["stage"]))
	crew_event.emit("Recovered %s — bring it back to %s." % [
		String(m["item"]["name"]), m["alias"]])
	return true

func first_with_role(role: String) -> Dictionary:
	for m in members.values():
		if String(m["stage"]) == "recruited" and String(m["role"]) == role:
			return m
	return {}

func has_role(role: String) -> bool:
	return not first_with_role(role).is_empty()

func any_recruited() -> bool:
	for m in members.values():
		if String(m["stage"]) == "recruited":
			return true
	return false

## One status line per member for the crew menu.
func status_text(m: Dictionary) -> String:
	match String(m["stage"]):
		"not_met":
			return String(m.get("hint", "Somewhere in the district."))
		"mission_active":
			return String(m.get("missionDescription", "Help them out."))
		"item_recovered":
			return "Return %s to them." % String(m.get("item", {}).get("name", "the item"))
		"recruited":
			return "Recruited — %s" % String(m.get("bonusDescription", ""))
	return ""

func _load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CrewManager: cannot open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("CrewManager: invalid JSON in %s" % path)
	return parsed
