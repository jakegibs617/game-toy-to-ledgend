extends Node
## Global player state: alias, reputation, rank, and paint supply.
## Autoloaded as GameState. Also registers the prototype input map at
## runtime so project.godot stays minimal (see Plan.md section 37).

signal reputation_changed(new_rep: int, gained: int)
signal rank_changed(new_rank: String)
signal paint_changed(new_paint: int)
signal graffiti_type_changed(new_type: String)
signal fill_color_changed(color_name: String)

const RANKS := [
	{"name": "Toy", "min_rep": 0},
	{"name": "Rookie", "min_rep": 50},
	{"name": "Up", "min_rep": 150},
	{"name": "Known", "min_rep": 400},
	{"name": "Block King", "min_rep": 800},
]

const FILL_COLORS := [
	{"name": "White", "hex": "#f2f2f2"},
	{"name": "Chrome", "hex": "#c9d4df"},
	{"name": "Hot Pink", "hex": "#ff4f79"},
	{"name": "Gold", "hex": "#ffd23f"},
	{"name": "Aqua", "hex": "#46d9c7"},
]

var alias := "NOVA"
var alias_chosen := true
var reputation := 0
var rank := "Toy"
var paint := 20
var selected_graffiti_type := "tag"
var unlocked_types := {"tag": true}
var colors_unlocked := false
var fill_color_index := 0

func _ready() -> void:
	_setup_input_actions()

func save_state() -> Dictionary:
	return {
		"alias": alias,
		"alias_chosen": alias_chosen,
		"reputation": reputation,
		"rank": rank,
		"paint": paint,
		"selected_graffiti_type": selected_graffiti_type,
		"unlocked_types": unlocked_types.duplicate(true),
		"colors_unlocked": colors_unlocked,
		"fill_color_index": fill_color_index,
	}

func load_state(data: Dictionary) -> void:
	var old_rank := rank
	alias = String(data.get("alias", alias))
	alias_chosen = bool(data.get("alias_chosen", alias_chosen))
	reputation = int(data.get("reputation", reputation))
	rank = String(data.get("rank", _rank_for(reputation)))
	paint = int(data.get("paint", paint))
	selected_graffiti_type = String(data.get("selected_graffiti_type", selected_graffiti_type))
	unlocked_types = data.get("unlocked_types", unlocked_types).duplicate(true)
	colors_unlocked = bool(data.get("colors_unlocked", colors_unlocked))
	fill_color_index = clampi(int(data.get("fill_color_index", fill_color_index)), 0, FILL_COLORS.size() - 1)
	reputation_changed.emit(reputation, 0)
	if rank != old_rank:  # otherwise every quick-load announces "RANK UP"
		rank_changed.emit(rank)
	paint_changed.emit(paint)
	graffiti_type_changed.emit(selected_graffiti_type)
	fill_color_changed.emit(current_fill_color_name())

func add_reputation(amount: int) -> void:
	reputation += amount
	reputation_changed.emit(reputation, amount)
	var new_rank := _rank_for(reputation)
	if new_rank != rank:
		rank = new_rank
		rank_changed.emit(rank)

func try_spend_paint(cost: int) -> bool:
	if paint < cost:
		return false
	paint -= cost
	paint_changed.emit(paint)
	return true

func add_paint(amount: int) -> void:
	paint += amount
	paint_changed.emit(paint)

func select_graffiti_type(type: String) -> void:
	if not is_type_unlocked(type):
		return
	selected_graffiti_type = type
	graffiti_type_changed.emit(type)

func unlock_type(type: String) -> void:
	unlocked_types[type] = true
	graffiti_type_changed.emit(selected_graffiti_type)

func is_type_unlocked(type: String) -> bool:
	return bool(unlocked_types.get(type, false))

func unlock_colors() -> void:
	colors_unlocked = true
	fill_color_changed.emit(current_fill_color_name())

func cycle_fill_color() -> void:
	if not colors_unlocked:
		return
	fill_color_index = (fill_color_index + 1) % FILL_COLORS.size()
	fill_color_changed.emit(current_fill_color_name())

func current_fill_color() -> String:
	return String(FILL_COLORS[fill_color_index]["hex"])

func current_fill_color_name() -> String:
	return String(FILL_COLORS[fill_color_index]["name"])

## Position of a rank in the ladder — lets listeners tell a rank-up
## from a demotion (possible once patrols can dock reputation).
func rank_index(rank_name: String) -> int:
	for i in RANKS.size():
		if String(RANKS[i]["name"]) == rank_name:
			return i
	return 0

func _rank_for(rep: int) -> String:
	var result: String = RANKS[0]["name"]
	for r in RANKS:
		if rep >= int(r["min_rep"]):
			result = r["name"]
	return result

func _setup_input_actions() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("run", KEY_SHIFT)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("interact", KEY_E)
	_add_key_action("graffiti_tag", KEY_1)
	_add_key_action("graffiti_throwup", KEY_2)
	_add_key_action("graffiti_piece", KEY_3)
	_add_key_action("cycle_color", KEY_C)
	_add_key_action("quick_save", KEY_F5)
	_add_key_action("quick_load", KEY_F9)
	_add_key_action("crew_menu", KEY_TAB)
	_add_key_action("map", KEY_M)
	_add_key_action("toggle_mouse", KEY_ESCAPE)

func _add_key_action(action: String, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)
