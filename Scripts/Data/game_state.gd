extends Node
## Global player state: alias, reputation, rank, and paint supply.
## Autoloaded as GameState. Also registers the prototype input map at
## runtime so project.godot stays minimal (see Plan.md section 37).

signal reputation_changed(new_rep: int, gained: int)
## Milestone 21 (§11 public/crew split, minimal form): standing with
## your own people. Crew-backed work raises it; gallery sales spend it.
signal crew_rep_changed(new_crew_rep: int, change: int)
signal rank_changed(new_rank: String)
signal paint_changed(new_paint: int)
signal cash_changed(new_cash: int)
signal graffiti_type_changed(new_type: String)
signal fill_color_changed(color_name: String)
## Milestone 18: which block the writer is standing in. Travel points
## set it; HeatManager, PatrolManager, and the HUD read it.
signal district_changed(district_id: String)
## World-object outcomes that want a HUD toast (climbs, future trains)
## without each one needing its own manager.
signal player_event(message: String)

const RANKS := [
	{"name": "Toy", "min_rep": 0},
	{"name": "Rookie", "min_rep": 50},
	{"name": "Up", "min_rep": 150},
	{"name": "Known", "min_rep": 400},
	{"name": "Block King", "min_rep": 800},
]

## Number-key slots registered as slot_1..slot_N (Milestone 16). The
## single source for everyone who loops them (player can selection,
## Hud.MODAL_SLOT_ACTIONS length).
const SLOT_COUNT := 6

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
var crew_rep := 0
var rank := "Toy"
var paint := 20
var cash := 25
var selected_graffiti_type := "tag"
var unlocked_types := {"tag": true}
var colors_unlocked := false
var fill_color_index := 0
var extra_fill_colors: Array = []  # rare colors bought from the shop
var current_district_id := "district_mill_yard"

func _ready() -> void:
	_setup_input_actions()

func save_state() -> Dictionary:
	return {
		"alias": alias,
		"alias_chosen": alias_chosen,
		"reputation": reputation,
		"crew_rep": crew_rep,
		"rank": rank,
		"paint": paint,
		"cash": cash,
		"selected_graffiti_type": selected_graffiti_type,
		"unlocked_types": unlocked_types.duplicate(true),
		"colors_unlocked": colors_unlocked,
		"fill_color_index": fill_color_index,
		"extra_fill_colors": extra_fill_colors.duplicate(true),
		"current_district_id": current_district_id,
	}

func load_state(data: Dictionary) -> void:
	var old_rank := rank
	alias = String(data.get("alias", alias))
	alias_chosen = bool(data.get("alias_chosen", alias_chosen))
	reputation = int(data.get("reputation", reputation))
	crew_rep = int(data.get("crew_rep", crew_rep))
	rank = String(data.get("rank", _rank_for(reputation)))
	paint = int(data.get("paint", paint))
	cash = int(data.get("cash", cash))
	selected_graffiti_type = String(data.get("selected_graffiti_type", selected_graffiti_type))
	unlocked_types = data.get("unlocked_types", unlocked_types).duplicate(true)
	colors_unlocked = bool(data.get("colors_unlocked", colors_unlocked))
	extra_fill_colors = data.get("extra_fill_colors", extra_fill_colors).duplicate(true)
	fill_color_index = clampi(int(data.get("fill_color_index", fill_color_index)), 0, fill_palette().size() - 1)
	# Silent on purpose: district_changed listeners (chain triggers,
	# patrol respawns) must not react against half-restored state.
	# SaveManager re-announces the district once the full load is done.
	current_district_id = String(data.get("current_district_id", current_district_id))
	reputation_changed.emit(reputation, 0)
	crew_rep_changed.emit(crew_rep, 0)
	if rank != old_rank:  # otherwise every quick-load announces "RANK UP"
		rank_changed.emit(rank)
	paint_changed.emit(paint)
	cash_changed.emit(cash)
	graffiti_type_changed.emit(selected_graffiti_type)
	fill_color_changed.emit(current_fill_color_name())

func add_reputation(amount: int) -> void:
	reputation += amount
	reputation_changed.emit(reputation, amount)
	var new_rank := _rank_for(reputation)
	if new_rank != rank:
		rank = new_rank
		rank_changed.emit(rank)

## Crew standing moves separately from public rep (§11 split): murals
## and recruits build it, selling canvases to the gallery spends it.
## It can go negative — the street remembers who cashed out.
func add_crew_rep(amount: int) -> void:
	if amount == 0:
		return
	crew_rep += amount
	crew_rep_changed.emit(crew_rep, amount)

func try_spend_paint(cost: int) -> bool:
	if paint < cost:
		return false
	paint -= cost
	paint_changed.emit(paint)
	return true

func add_paint(amount: int) -> void:
	paint += amount
	paint_changed.emit(paint)

func try_spend_cash(cost: int) -> bool:
	if cash < cost:
		return false
	cash -= cost
	cash_changed.emit(cash)
	return true

func add_cash(amount: int) -> void:
	cash += amount
	cash_changed.emit(cash)

func select_graffiti_type(type: String) -> void:
	if not is_type_unlocked(type):
		return
	selected_graffiti_type = type
	graffiti_type_changed.emit(type)

## Number key i selects the i-th graffiti style in canonical (JSON)
## order — the same order the wall prompt and blackbook list them.
func select_type_slot(index: int) -> void:
	var order: Array = WallManager.styles.keys()
	if index >= 0 and index < order.size():
		select_graffiti_type(String(order[index]))

func unlock_type(type: String) -> void:
	unlocked_types[type] = true
	graffiti_type_changed.emit(selected_graffiti_type)

func is_type_unlocked(type: String) -> bool:
	return bool(unlocked_types.get(type, false))

func set_district(district_id: String) -> void:
	if district_id == current_district_id or district_id == "":
		return
	current_district_id = district_id
	district_changed.emit(district_id)

func unlock_colors() -> void:
	colors_unlocked = true
	fill_color_changed.emit(current_fill_color_name())

func cycle_fill_color() -> void:
	if not colors_unlocked:
		return
	fill_color_index = (fill_color_index + 1) % fill_palette().size()
	fill_color_changed.emit(current_fill_color_name())

## Base palette plus any rare colors bought from the supply shop.
func fill_palette() -> Array:
	return FILL_COLORS + extra_fill_colors

## A rare color from the supply shop (Plan.md section 21) joins the
## palette and is selected immediately — you just paid for it.
func add_fill_color(color_name: String, hex: String) -> void:
	extra_fill_colors.append({"name": color_name, "hex": hex})
	fill_color_index = fill_palette().size() - 1
	fill_color_changed.emit(current_fill_color_name())

func current_fill_color() -> String:
	return String(fill_palette()[fill_color_index]["hex"])

func current_fill_color_name() -> String:
	return String(fill_palette()[fill_color_index]["name"])

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
	# Generic number-key slots (Milestone 16): in the world they select
	# cans by style order; in a modal they pick that modal's slots
	# (shop rows, dialogue choices, blackbook pages).
	for i in SLOT_COUNT:
		_add_key_action("slot_%d" % (i + 1), (KEY_1 + i) as Key)
	_add_key_action("cycle_color", KEY_C)
	_add_key_action("freehand_paint", KEY_F)
	_add_key_action("perks", KEY_P)
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
