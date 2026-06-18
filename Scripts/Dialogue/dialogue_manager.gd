extends Node
## RPG-style choice dialogue (Plan.md section 26; "dialogue" from the
## section 36 Should-Have list). Trees live in Data/dialogue.json:
## nodes with speaker/text and numbered choices that branch ("next"),
## run an action ("end" / "open_shop" / "start_delivery"), gate behind
## requirement checks (e.g. minRank — Plan.md section 26 "Dialogue
## Checks"), and pay one-time effects ("once" flags). The HUD renders
## the active node and feeds choices back here. Autoloaded as
## DialogueManager.

signal dialogue_changed
signal dialogue_ended
signal dialogue_event(message: String)

const DIALOGUE_PATH := "res://Data/dialogue.json"
const DataLoader := preload("res://Scripts/Data/data_loader.gd")
## Walking away from the speaker ends the conversation, mirroring the
## supply shop's behavior.
const TALK_CLOSE_DISTANCE := 6.0

var trees: Dictionary = {}
var flags: Dictionary = {}  # "once" rewards already paid, persisted
var _tree_id := ""
var _node_id := ""
var _anchor: Node3D = null

func _ready() -> void:
	var parsed: Variant = DataLoader.load_json(DIALOGUE_PATH, "DialogueManager")
	if parsed is Dictionary:
		trees = parsed
		for tree_id in trees:
			var tree: Variant = trees[tree_id]
			if not DataLoader.require_fields(tree, ["start", "nodes"],
					"DialogueManager: tree \"%s\"" % String(tree_id)):
				continue
			if not (tree["nodes"] is Dictionary):
				DataLoader.report("DialogueManager: nodes of \"%s\" must be an object" % String(tree_id))
				continue
			for node_id in tree["nodes"]:
				DataLoader.require_fields(tree["nodes"][node_id], ["speaker", "text"],
					"DialogueManager: node \"%s/%s\"" % [String(tree_id), String(node_id)])

func _physics_process(_delta: float) -> void:
	if _anchor == null:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(_anchor) \
			or player.global_position.distance_to(_anchor.global_position) > TALK_CLOSE_DISTANCE:
		end_dialogue()

func is_active() -> bool:
	return _tree_id != ""

## Opens a dialogue tree. `anchor` is the speaker's node (used for the
## walk-away check and as the shop anchor for "open_shop" choices);
## null skips the distance check, which the smoke test relies on.
func start(tree_id: String, anchor: Node3D = null) -> bool:
	var tree: Dictionary = trees.get(tree_id, {})
	if tree.is_empty():
		return false
	SupplyManager.close_shop()
	_tree_id = tree_id
	_anchor = anchor
	_enter_node(String(tree["start"]))
	return true

func end_dialogue() -> void:
	if not is_active():
		return
	_tree_id = ""
	_node_id = ""
	_anchor = null
	dialogue_ended.emit()

func current_node() -> Dictionary:
	if not is_active():
		return {}
	return trees[_tree_id]["nodes"].get(_node_id, {})

## Choices of the current node annotated with their lock state, in the
## same order choose() indexes them.
func visible_choices() -> Array:
	var result: Array = []
	for choice in current_node().get("choices", []):
		result.append({
			"text": String(choice["text"]),
			"locked": _is_locked(choice),
			"lockedText": String(choice.get("lockedText", "(not yet)")),
		})
	return result

## Picks choice `index` on the current node. Locked or out-of-range
## choices refuse and return false.
func choose(index: int) -> bool:
	var choices: Array = current_node().get("choices", [])
	if index < 0 or index >= choices.size():
		return false
	var choice: Dictionary = choices[index]
	if _is_locked(choice):
		dialogue_event.emit(String(choice.get("lockedText", "(not yet)")))
		return false
	match String(choice.get("action", "")):
		"end":
			end_dialogue()
		"open_shop":
			var anchor := _anchor
			end_dialogue()
			if anchor != null:
				SupplyManager.toggle_shop(anchor)
		"start_delivery":
			end_dialogue()
			SupplyManager.start_delivery()
		"start_gallery":
			end_dialogue()
			GalleryManager.start_commission()
		_:
			# A choice with neither action nor next is a data mistake —
			# end cleanly instead of silently looping the same node.
			if choice.has("next"):
				_enter_node(String(choice["next"]))
			else:
				push_error("DialogueManager: choice \"%s\" in %s/%s has no next or action"
					% [String(choice["text"]), _tree_id, _node_id])
				end_dialogue()
	return true

func save_state() -> Dictionary:
	return {"flags": flags.duplicate(true)}

func load_state(data: Dictionary) -> void:
	flags = data.get("flags", {}).duplicate(true)
	end_dialogue()  # the loaded world may not match the conversation

func _enter_node(node_id: String) -> void:
	_node_id = node_id
	var node := current_node()
	# "once" nodes pay their effects on the first visit only — Prime's
	# lesson is a lesson, not a faucet.
	var once := String(node.get("once", ""))
	if node.has("effects") and (once == "" or not flags.get(once, false)):
		_apply_effects(node["effects"])
		if once != "":
			flags[once] = true
	dialogue_changed.emit()

## Plan.md section 26 "Dialogue Checks": requirements a choice can gate
## behind. minRank compares ladder positions via GameState.rank_index.
func _is_locked(choice: Dictionary) -> bool:
	var req: Dictionary = choice.get("requires", {})
	if req.has("minRank") and GameState.rank_index(GameState.rank) \
			< GameState.rank_index(String(req["minRank"])):
		return true
	if req.has("recruited") and String(CrewManager.members.get(
			String(req["recruited"]), {}).get("stage", "")) != "recruited":
		return true
	return false

func _apply_effects(effects: Dictionary) -> void:
	# A mentor can teach a new graffiti type (Indigo's wheatpaste lesson,
	# Product_reqs.md) — same unlock the mission rewards use, paid once.
	for type in effects.get("unlockTypes", []):
		GameState.unlock_type(String(type))
	if effects.has("rep"):
		GameState.add_reputation(int(effects["rep"]))
	if effects.has("cash"):
		GameState.add_cash(int(effects["cash"]))
	if effects.has("paint"):
		GameState.add_paint(int(effects["paint"]))
	if effects.has("message"):
		dialogue_event.emit(String(effects["message"]))
