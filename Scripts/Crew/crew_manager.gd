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
const DataLoader := preload("res://Scripts/Data/data_loader.gd")

var members: Dictionary = {}  # memberId -> definition + runtime "stage"
var _parent: Node3D = null
var _pickup_nodes: Dictionary = {}

func _ready() -> void:
	var parsed: Variant = DataLoader.load_json(NPC_PATH, "CrewManager")
	if parsed is Array:
		for m in parsed:
			DataLoader.require_fields(m,
				["memberId", "name", "alias", "role", "position", "color", "dialogue"],
				"CrewManager: member \"%s\"" % String(m.get("memberId", "?")))
			m["stage"] = "not_met"
			members[m["memberId"]] = m

## Spawns NPCs (and any not-yet-recovered mission items) into a scene.
func spawn_npcs(parent: Node3D) -> void:
	_parent = parent
	_pickup_nodes.clear()
	for m in members.values():
		var npc := Npc.new()
		npc.setup(m)
		parent.add_child(npc)
		_sync_pickup_for_member(String(m["memberId"]))

## Talking to an NPC advances their recruitment stage.
func interact(member_id: String) -> void:
	var m: Dictionary = members[member_id]
	var lines: Dictionary = m.get("dialogue", {})
	match String(m["stage"]):
		"not_met":
			m["stage"] = "mission_active"
			stage_changed.emit(member_id, String(m["stage"]))
			_sync_pickup_for_member(member_id)
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
	_sync_pickup_for_member(member_id)
	crew_event.emit("Recovered %s — bring it back to %s." % [
		String(m["item"]["name"]), m["alias"]])
	return true

func _sync_pickup_for_member(member_id: String) -> void:
	if _parent == null or not is_instance_valid(_parent) or not members.has(member_id):
		return
	var m: Dictionary = members[member_id]
	var should_exist := m.has("item") and String(m.get("stage", "")) == "mission_active"
	var existing: PickupItem = _pickup_nodes.get(member_id, null)
	if existing != null and not is_instance_valid(existing):
		_pickup_nodes.erase(member_id)
		existing = null
	if should_exist and existing == null:
		var item := PickupItem.new()
		item.setup(member_id, m["item"])
		_parent.add_child(item)
		_pickup_nodes[member_id] = item
	elif not should_exist and existing != null:
		existing.queue_free()
		_pickup_nodes.erase(member_id)

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

func save_state() -> Dictionary:
	var stages := {}
	for member_id in members:
		stages[member_id] = String(members[member_id].get("stage", "not_met"))
	return {"stages": stages}

func load_state(data: Dictionary) -> void:
	var stages: Dictionary = data.get("stages", {})
	for member_id in stages:
		if members.has(member_id):
			members[member_id]["stage"] = String(stages[member_id])
			stage_changed.emit(String(member_id), String(stages[member_id]))
			_sync_pickup_for_member(String(member_id))
	crew_changed.emit()

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
