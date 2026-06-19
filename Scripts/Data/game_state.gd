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
signal alias_changed(new_alias: String)
signal graffiti_type_changed(new_type: String)
signal fill_color_changed(color_name: String)
signal tag_font_style_changed(style_id: String)
## Milestone 18: which block the writer is standing in. Travel points
## set it; HeatManager, PatrolManager, and the HUD read it.
signal district_changed(district_id: String)
## World-object outcomes that want a HUD toast (climbs, future trains)
## without each one needing its own manager.
signal player_event(message: String)
signal crew_board_requested
## A bench asks the HUD to open the blackbook in style-practice mode; the
## HUD fires sit_practice_ended when that book closes so the player stands.
signal sit_practice_requested
signal sit_practice_ended
## A rep-gated nightclub asks the HUD to open the dance-floor modal once the
## bouncer has waved the writer in (Product_reqs "dance / club / DJ invite").
signal nightclub_requested(club: Dictionary)
signal rival_duel_record_changed(wins: int, losses: int, streak: int)

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
const GraffitiFonts := preload("res://Scripts/Walls/graffiti_font_library.gd")
const FONT_PRACTICE_TOY_RESPONSE_CUT := 0.04
const FONT_PRACTICE_RESPONSE_FLOOR := 0.8

const FILL_COLORS := [
	{"name": "White", "hex": "#f2f2f2"},
	{"name": "Chrome", "hex": "#c9d4df"},
	{"name": "Hot Pink", "hex": "#ff4f79"},
	{"name": "Gold", "hex": "#ffd23f"},
	{"name": "Aqua", "hex": "#46d9c7"},
]

var alias := "NOVA"
var alias_chosen := false
var reputation := 0
var crew_rep := 0
var rank := "Toy"
var paint := 20
var cash := 25
var selected_graffiti_type := "tag"
var unlocked_types := {"tag": true}
var selected_tag_font_style_id := "ff_comma_trial"
var unlocked_tag_font_styles := {"ff_comma_trial": true}
var tag_font_practice_counts: Dictionary = {}
var colors_unlocked := false
var fill_color_index := 0
var extra_fill_colors: Array = []  # rare colors bought from the shop
var current_district_id := "district_mill_yard"
## Best dance hype reached per nightclub (clubId -> 0..100), so the club
## remembers a writer's signature set across sessions.
var nightlife_best: Dictionary = {}
## Rival wall duels are lightweight contested-wall callouts: a rival marks
## your spot, and answering that exact wall with fresh paint records a win.
var rival_duel_wins := 0
var rival_duel_losses := 0
var rival_duel_streak := 0

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
		"selected_tag_font_style_id": selected_tag_font_style_id,
		"unlocked_tag_font_styles": unlocked_tag_font_styles.duplicate(true),
		"tag_font_practice_counts": tag_font_practice_counts.duplicate(true),
		"colors_unlocked": colors_unlocked,
		"fill_color_index": fill_color_index,
		"extra_fill_colors": extra_fill_colors.duplicate(true),
		"current_district_id": current_district_id,
		"nightlife_best": nightlife_best.duplicate(true),
		"rival_duel_wins": rival_duel_wins,
		"rival_duel_losses": rival_duel_losses,
		"rival_duel_streak": rival_duel_streak,
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
	selected_tag_font_style_id = String(data.get("selected_tag_font_style_id", selected_tag_font_style_id))
	unlocked_tag_font_styles = data.get("unlocked_tag_font_styles", unlocked_tag_font_styles).duplicate(true)
	_normalize_unlocked_tag_font_styles()
	tag_font_practice_counts = data.get("tag_font_practice_counts", tag_font_practice_counts).duplicate(true)
	if not is_tag_font_style_unlocked(selected_tag_font_style_id):
		selected_tag_font_style_id = GraffitiFonts.default_style_id()
	colors_unlocked = bool(data.get("colors_unlocked", colors_unlocked))
	extra_fill_colors = data.get("extra_fill_colors", extra_fill_colors).duplicate(true)
	fill_color_index = clampi(int(data.get("fill_color_index", fill_color_index)), 0, fill_palette().size() - 1)
	# Silent on purpose: district_changed listeners (chain triggers,
	# patrol respawns) must not react against half-restored state.
	# SaveManager re-announces the district once the full load is done.
	current_district_id = String(data.get("current_district_id", current_district_id))
	nightlife_best = data.get("nightlife_best", nightlife_best).duplicate(true)
	rival_duel_wins = int(data.get("rival_duel_wins", rival_duel_wins))
	rival_duel_losses = int(data.get("rival_duel_losses", rival_duel_losses))
	rival_duel_streak = int(data.get("rival_duel_streak", rival_duel_streak))
	reputation_changed.emit(reputation, 0)
	crew_rep_changed.emit(crew_rep, 0)
	if rank != old_rank:  # otherwise every quick-load announces "RANK UP"
		rank_changed.emit(rank)
	paint_changed.emit(paint)
	cash_changed.emit(cash)
	graffiti_type_changed.emit(selected_graffiti_type)
	tag_font_style_changed.emit(selected_tag_font_style_id)
	fill_color_changed.emit(current_fill_color_name())
	alias_changed.emit(alias)
	rival_duel_record_changed.emit(rival_duel_wins, rival_duel_losses, rival_duel_streak)

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

func choose_alias(raw_alias: String) -> void:
	var chosen := raw_alias.strip_edges().to_upper()
	if chosen == "":
		chosen = "NOVA"
	alias = chosen.substr(0, 12)
	alias_chosen = true
	alias_changed.emit(alias)
	MissionManager.notify_alias_chosen()

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

func cycle_graffiti_type(step: int) -> void:
	var order: Array = WallManager.styles.keys()
	if order.is_empty():
		return
	var current := maxi(order.find(selected_graffiti_type), 0)
	for offset in range(1, order.size() + 1):
		var index := wrapi(current + step * offset, 0, order.size())
		if is_type_unlocked(String(order[index])):
			select_graffiti_type(String(order[index]))
			return

func unlock_type(type: String) -> void:
	unlocked_types[type] = true
	graffiti_type_changed.emit(selected_graffiti_type)

func is_type_unlocked(type: String) -> bool:
	return bool(unlocked_types.get(type, false))

func selected_tag_font_style() -> String:
	selected_tag_font_style_id = GraffitiFonts.resolve_style_id(selected_tag_font_style_id)
	if not is_tag_font_style_unlocked(selected_tag_font_style_id):
		selected_tag_font_style_id = GraffitiFonts.default_style_id()
	return selected_tag_font_style_id

func select_tag_font_style(style_id: String) -> void:
	style_id = GraffitiFonts.resolve_style_id(style_id)
	if not is_tag_font_style_unlocked(style_id):
		return
	selected_tag_font_style_id = style_id
	tag_font_style_changed.emit(style_id)

func unlock_tag_font_style(style_id: String) -> void:
	style_id = GraffitiFonts.resolve_style_id(style_id)
	if not GraffitiFonts.is_valid_style(style_id):
		return
	unlocked_tag_font_styles[style_id] = true
	tag_font_style_changed.emit(selected_tag_font_style_id)

func is_tag_font_style_unlocked(style_id: String) -> bool:
	style_id = GraffitiFonts.resolve_style_id(style_id)
	return bool(unlocked_tag_font_styles.get(style_id, false)) \
		and GraffitiFonts.is_valid_style(style_id)

func _normalize_unlocked_tag_font_styles() -> void:
	var normalized := {}
	for style_id in unlocked_tag_font_styles:
		var resolved := GraffitiFonts.resolve_style_id(String(style_id))
		if GraffitiFonts.is_valid_style(resolved) and bool(unlocked_tag_font_styles[style_id]):
			normalized[resolved] = true
	normalized[GraffitiFonts.default_style_id()] = true
	unlocked_tag_font_styles = normalized

func practice_tag_font_style(style_id: String) -> Dictionary:
	style_id = GraffitiFonts.resolve_style_id(style_id)
	var style := GraffitiFonts.style_def(style_id)
	if style.is_empty():
		return {"ok": false, "reason": "Unknown tag style."}
	var required_level := int(style.get("level", 0))
	if StatsManager.level("style") < required_level:
		return {"ok": false, "reason": "%s needs Style level %d." % [
			GraffitiFonts.style_label(style_id), required_level]}
	var count := practice_count_for_tag_font_style(style_id) + 1
	var required := int(style.get("practiceRequired", 5))
	tag_font_practice_counts[style_id] = count
	if count >= required:
		unlock_tag_font_style(style_id)
	return {"ok": true, "count": count, "required": required,
		"unlocked": is_tag_font_style_unlocked(style_id)}

func practice_count_for_tag_font_style(style_id: String) -> int:
	style_id = GraffitiFonts.resolve_style_id(style_id)
	return int(tag_font_practice_counts.get(style_id, 0))

func toy_response_multiplier(style_id: String) -> float:
	style_id = GraffitiFonts.resolve_style_id(style_id)
	var style := GraffitiFonts.style_def(style_id)
	if bool(style.get("toyStyle", false)):
		return 1.0
	var required := maxi(int(style.get("practiceRequired", 5)), 1)
	var practice := mini(practice_count_for_tag_font_style(style_id), required)
	return maxf(1.0 - FONT_PRACTICE_TOY_RESPONSE_CUT * practice, FONT_PRACTICE_RESPONSE_FLOOR)

func gear_suspicion_multiplier() -> float:
	var carried_cans := 0
	for type in unlocked_types:
		if is_type_unlocked(String(type)):
			carried_cans += 1
	var multiplier := 1.0 + maxf(carried_cans - 1, 0) * 0.03
	if is_type_unlocked("stencil"):
		multiplier += 0.08
	# A wheatpaste bucket and roll of posters is bulky to lug (Product_reqs.md);
	# stickers are flat, so they only count toward the can tally above.
	if is_type_unlocked("wheatpaste"):
		multiplier += float(WallManager.styles.get("wheatpaste", {}).get("gearSuspicion", 0.0))
	var font_style := GraffitiFonts.style_def(selected_tag_font_style())
	multiplier += float(font_style.get("gearSuspicion", 0.0))
	return multiplier

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

## True once the writer's current rank is at least `min_rank` — the
## rep-based invite check shared by gated content (nightclub bouncer).
## An unknown `min_rank` reads as "no gate" (index 0).
func rank_meets(min_rank: String) -> bool:
	return rank_index(rank) >= rank_index(min_rank)

## Records a dance set if it beats the writer's stored best for that club,
## returning true when a new personal best was set.
func note_nightlife_best(club_id: String, hype_pct: int) -> bool:
	if hype_pct <= int(nightlife_best.get(club_id, 0)):
		return false
	nightlife_best[club_id] = hype_pct
	return true

func note_rival_duel_win() -> void:
	rival_duel_wins += 1
	rival_duel_streak += 1
	rival_duel_record_changed.emit(rival_duel_wins, rival_duel_losses, rival_duel_streak)

func note_rival_duel_loss() -> void:
	rival_duel_losses += 1
	rival_duel_streak = 0
	rival_duel_record_changed.emit(rival_duel_wins, rival_duel_losses, rival_duel_streak)

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
	_add_joy_axis_action("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis_action("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis_action("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis_action("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_button_action("run", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button_action("jump", JOY_BUTTON_A)
	_add_joy_button_action("interact", JOY_BUTTON_X)
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
	_add_key_action("can_prev", KEY_BRACKETLEFT)
	_add_key_action("can_next", KEY_BRACKETRIGHT)
	_add_joy_button_action("cycle_color", JOY_BUTTON_Y)
	_add_joy_button_action("freehand_paint", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button_action("perks", JOY_BUTTON_DPAD_UP)
	_add_joy_button_action("crew_menu", JOY_BUTTON_BACK)
	_add_joy_button_action("map", JOY_BUTTON_DPAD_DOWN)
	_add_joy_button_action("toggle_mouse", JOY_BUTTON_START)
	_add_joy_button_action("can_prev", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button_action("can_next", JOY_BUTTON_DPAD_RIGHT)

func _add_key_action(action: String, keycode: Key) -> void:
	if InputMap.has_action(action):
		pass
	else:
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

func _add_joy_button_action(action: String, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

func _add_joy_axis_action(action: String, axis: JoyAxis, axis_value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = axis_value
	InputMap.action_add_event(action, ev)
