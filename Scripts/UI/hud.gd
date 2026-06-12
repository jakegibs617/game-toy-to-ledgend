class_name Hud
extends CanvasLayer
## Prototype HUD: rank / reputation / paint / selected graffiti type
## (top-left), interaction prompt and feedback messages (bottom), the
## Tab crew menu (Milestone 5), and the M district map (Milestone 6).

const ACCENT := Color("#ffd23f")
const LOW_PAINT := Color("#ff6b6b")
## Number-key actions reused by every modal (shop slots, dialogue
## choices, blackbook pages) in display order — one list so the modals
## can't drift.
const MODAL_SLOT_ACTIONS := ["graffiti_tag", "graffiti_throwup", "graffiti_piece", "shop_delivery"]
## Preloaded like MissionManager's zone scripts: the global class cache
## isn't rebuilt on fresh headless runs, so class_name lookups can fail.
const BlackbookPanelScript := preload("res://Scripts/UI/blackbook_panel.gd")
const FreehandPanelScript := preload("res://Scripts/UI/freehand_panel.gd")
const UiKit := preload("res://Scripts/UI/ui_kit.gd")
const HEAT_COLORS := {
	"Cold": Color.WHITE,
	"Low": Color("#ffd23f"),
	"Watched": Color("#ff9f43"),
	"Hot": Color("#ff6b6b"),
	"Blazing": Color("#e0301e"),
}

var _rank_label: Label
var _rep_label: Label
var _paint_label: Label
var _cash_label: Label
var _heat_label: Label
var _type_label: Label
var _shop_panel: PanelContainer
var _shop_label: Label
var _dialogue_panel: PanelContainer
var _dialogue_speaker_label: Label
var _dialogue_label: Label
var _mission_panel: PanelContainer
var _mission_title_label: Label
var _mission_objective_label: Label
var _prompt_panel: PanelContainer
var _prompt_label: Label
var _message_label: Label
var _message_timer: Timer
var _blackbook  # BlackbookPanelScript instance (untyped: see preload note)
var _freehand  # FreehandPanelScript instance (untyped: see preload note)
var _map_panel: MapPanel
var _freehand_wall: PaintableWall = null
var _focused: Node3D = null
var _rank_index := 0
## The modal registry (Plan_v2.md §3.1): one entry per modal, in input
## priority order. The first open modal owns input; opening any modal
## closes the rest, so two can never fight over the number keys.
var _modals: Array[Dictionary] = []

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var left := VBoxContainer.new()
	left.position = Vector2(16, 16)
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)

	var stats_panel := UiKit.make_panel(Color("#46d9c7"))
	left.add_child(stats_panel)
	var stats := VBoxContainer.new()
	stats_panel.add_child(stats)
	_rank_label = UiKit.make_label(stats, 22, ACCENT)
	_rep_label = UiKit.make_label(stats, 18)
	_paint_label = UiKit.make_label(stats, 18)
	_cash_label = UiKit.make_label(stats, 18)
	_heat_label = UiKit.make_label(stats, 18)
	_type_label = UiKit.make_label(stats, 18)

	_mission_panel = UiKit.make_panel(ACCENT)
	left.add_child(_mission_panel)
	var mission_box := VBoxContainer.new()
	_mission_panel.add_child(mission_box)
	_mission_title_label = UiKit.make_label(mission_box, 18, ACCENT)
	_mission_objective_label = UiKit.make_label(mission_box, 16)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -150.0
	bottom.offset_bottom = -30.0
	bottom.add_theme_constant_override("separation", 8)
	root.add_child(bottom)
	_message_label = UiKit.make_label(bottom, 22)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var prompt_center := CenterContainer.new()
	prompt_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(prompt_center)
	_prompt_panel = UiKit.make_panel(Color("#3aa0c8"))
	_prompt_panel.visible = false
	prompt_center.add_child(_prompt_panel)
	_prompt_label = UiKit.make_label(_prompt_panel, 17)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var hint := UiKit.make_label(root, 13, Color(1, 1, 1, 0.55))
	hint.text = "WASD move · Shift run · Space jump · E interact · 1/2/3 can · C color · F freehand · Tab blackbook · M map · F5 save · F9 load"
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_message_timer = Timer.new()
	_message_timer.one_shot = true
	_message_timer.wait_time = 2.5
	_message_timer.timeout.connect(func() -> void: _message_label.text = "")
	add_child(_message_timer)

	_blackbook = BlackbookPanelScript.new()
	_blackbook.set_anchors_preset(Control.PRESET_CENTER)
	_blackbook.visible = false
	root.add_child(_blackbook)

	_freehand = FreehandPanelScript.new()
	_freehand.set_anchors_preset(Control.PRESET_CENTER)
	_freehand.visible = false
	_freehand.committed.connect(_on_freehand_committed)
	_freehand.cancelled.connect(_close_freehand)
	root.add_child(_freehand)

	_shop_panel = UiKit.make_panel(Color("#e0a030"))
	_shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	_shop_panel.visible = false
	root.add_child(_shop_panel)
	var shop_box := VBoxContainer.new()
	shop_box.custom_minimum_size = Vector2(560, 0)
	_shop_panel.add_child(shop_box)
	var shop_title := UiKit.make_label(shop_box, 24, Color("#e0a030"))
	shop_title.text = "LUPE'S SUPPLIES   —   [E] close"
	_shop_label = UiKit.make_label(shop_box, 17)

	_dialogue_panel = UiKit.make_panel(Color("#8a9a5b"))
	_dialogue_panel.set_anchors_preset(Control.PRESET_CENTER)
	_dialogue_panel.visible = false
	root.add_child(_dialogue_panel)
	var dialogue_box := VBoxContainer.new()
	dialogue_box.custom_minimum_size = Vector2(620, 0)
	_dialogue_panel.add_child(dialogue_box)
	_dialogue_speaker_label = UiKit.make_label(dialogue_box, 24, Color("#8a9a5b"))
	_dialogue_label = UiKit.make_label(dialogue_box, 17)
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_map_panel = MapPanel.new()
	_map_panel.set_anchors_preset(Control.PRESET_CENTER)
	root.add_child(_map_panel)

	_register_modals()

	GameState.reputation_changed.connect(_on_rep_changed)
	GameState.rank_changed.connect(_on_rank_changed)
	GameState.paint_changed.connect(_on_paint_changed)
	GameState.cash_changed.connect(_on_cash_changed)
	SupplyManager.shop_toggled.connect(_on_shop_toggled)
	SupplyManager.supply_event.connect(_on_supply_event)
	DialogueManager.dialogue_changed.connect(_on_dialogue_changed)
	DialogueManager.dialogue_ended.connect(func() -> void: _dialogue_panel.visible = false)
	DialogueManager.dialogue_event.connect(func(message: String) -> void:
		_show_message(message, 4.0))
	GameState.graffiti_type_changed.connect(_on_type_changed)
	GameState.fill_color_changed.connect(func(_name: String) -> void:
		_on_type_changed(GameState.selected_graffiti_type))
	RivalManager.rival_event.connect(_on_rival_event)
	HeatManager.heat_changed.connect(_on_heat_changed)
	HeatManager.heat_level_changed.connect(_on_heat_level_changed)
	HeatManager.cleanup_event.connect(_on_cleanup_event)
	PatrolManager.patrol_event.connect(_on_patrol_event)
	CrewManager.crew_event.connect(_on_crew_event)
	TerritoryManager.district_claimed.connect(_on_district_claimed)
	MissionManager.mission_started.connect(_on_mission_started)
	MissionManager.objective_changed.connect(_on_objective_changed)
	MissionManager.mission_completed.connect(_on_mission_completed)
	MissionManager.chain_completed.connect(_on_chain_completed)
	MissionManager.mission_event.connect(_on_mission_event)
	SaveManager.save_event.connect(_on_save_event)
	CrewManager.crew_changed.connect(func() -> void:
		if _blackbook.visible:
			_blackbook.refresh())
	_rank_index = GameState.rank_index(GameState.rank)
	_refresh_stats()
	_refresh_mission()

func bind_player(player: Player) -> void:
	player.focus_changed.connect(_on_focus_changed)
	player.painted.connect(_on_painted)
	player.freehand_requested.connect(_on_freehand_requested)
	_map_panel.bind_player(player)

## The modal registry (Plan_v2.md §3.1). Each entry: is_open/close
## callables plus an input handler (returns true when consumed); modals
## the HUD opens itself (blackbook, map) also carry an open callable.
## Shop, dialogue, and freehand open through their own flows.
func _register_modals() -> void:
	_modals = [
		{"name": "freehand",
			"is_open": func() -> bool: return _freehand.visible,
			"close": _close_freehand,
			"input": _freehand.handle_input},
		{"name": "dialogue",
			"is_open": DialogueManager.is_active,
			"close": DialogueManager.end_dialogue,
			"input": _handle_dialogue_input},
		{"name": "shop",
			"is_open": SupplyManager.is_shop_open,
			"close": SupplyManager.close_shop,
			"input": _handle_shop_input},
		{"name": "blackbook",
			"is_open": func() -> bool: return _blackbook.visible,
			"close": func() -> void: _blackbook.visible = false,
			"open": _open_blackbook,
			"input": _handle_blackbook_input},
		{"name": "map",
			"is_open": func() -> bool: return _map_panel.visible,
			"close": func() -> void: _map_panel.visible = false,
			"open": func() -> void: _map_panel.visible = true,
			"input": func(_event: InputEvent) -> bool: return false},
	]

func _open_blackbook() -> void:
	_blackbook.visible = true
	_blackbook.refresh()

## Closes every open modal except `except` — the one call every
## opener routes through, so two modals can never stay open together.
func close_modals(except := "") -> void:
	for modal in _modals:
		if String(modal["name"]) != except and modal["is_open"].call():
			modal["close"].call()

func open_modal(name: String) -> void:
	close_modals(name)
	var modal := _find_modal(name)
	if modal.has("open") and not modal["is_open"].call():
		modal["open"].call()

func _toggle_modal(name: String) -> void:
	var modal := _find_modal(name)
	if modal.is_empty():
		return
	if modal["is_open"].call():
		modal["close"].call()
	else:
		open_modal(name)

func _find_modal(name: String) -> Dictionary:
	for modal in _modals:
		if String(modal["name"]) == name:
			return modal
	return {}

## The first open modal in priority order, or {} when the world has input.
func _active_modal() -> Dictionary:
	for modal in _modals:
		if modal["is_open"].call():
			return modal
	return {}

func _unhandled_input(event: InputEvent) -> void:
	# While a modal is open the number keys answer/buy/flip pages
	# instead of switching cans, so the open modal sees (and consumes)
	# events before the player controller does.
	var active := _active_modal()
	if not active.is_empty() and active["input"].call(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("crew_menu"):
		_toggle_modal("blackbook")
	elif event.is_action_pressed("map"):
		_toggle_modal("map")
	elif event.is_action_pressed("quick_save"):
		SaveManager.quick_save()
	elif event.is_action_pressed("quick_load"):
		if SaveManager.quick_load():
			_refresh_stats()
			_refresh_mission()
			_refresh_prompt()
			if _blackbook.visible:
				_blackbook.refresh()
			_map_panel.queue_redraw()

func _refresh_stats() -> void:
	_rank_label.text = "Rank: %s" % GameState.rank
	_rep_label.text = "Rep: %d" % GameState.reputation
	_paint_label.text = "Paint: %d" % GameState.paint
	_cash_label.text = "Cash: $%d" % GameState.cash
	_on_heat_changed(HeatManager.heat, 0.0)
	_on_type_changed(GameState.selected_graffiti_type)

## Keyboard conversation (Milestone 12): number keys pick choices,
## E/Esc walks away. Returns true when the event was consumed.
func _handle_dialogue_input(event: InputEvent) -> bool:
	if event.is_action_pressed("interact") or event.is_action_pressed("toggle_mouse"):
		DialogueManager.end_dialogue()
		return true
	for i in MODAL_SLOT_ACTIONS.size():
		if event.is_action_pressed(MODAL_SLOT_ACTIONS[i]):
			if not DialogueManager.choose(i):
				Sfx.play("denied")
			return true
	return false

func _on_dialogue_changed() -> void:
	var node: Dictionary = DialogueManager.current_node()
	if node.is_empty():
		_dialogue_panel.visible = false
		return
	close_modals("dialogue")
	_dialogue_panel.visible = true
	_dialogue_speaker_label.text = "%s   —   [E] walk away" % String(node.get("speaker", "?"))
	var lines: PackedStringArray = [String(node.get("text", "")), ""]
	var choices: Array = DialogueManager.visible_choices()
	for i in choices.size():
		var choice: Dictionary = choices[i]
		if choice["locked"]:
			lines.append("[%d] %s  %s" % [i + 1, String(choice["text"]), String(choice["lockedText"])])
		else:
			lines.append("[%d] %s" % [i + 1, String(choice["text"])])
	_dialogue_label.text = "\n".join(lines)

## Keyboard shopping (Milestone 11): 1-3 buy catalog slots, 4 takes a
## delivery run, E/Esc puts the cans away. Returns true when consumed.
func _handle_shop_input(event: InputEvent) -> bool:
	if event.is_action_pressed("interact") or event.is_action_pressed("toggle_mouse"):
		SupplyManager.close_shop()
		return true
	# Slot i is catalog item i; the row after the catalog is the delivery
	# run — the same order _refresh_shop renders, so display and input
	# can't drift apart if the catalog grows.
	for i in MODAL_SLOT_ACTIONS.size():
		if event.is_action_pressed(MODAL_SLOT_ACTIONS[i]):
			if i < SupplyManager.catalog.size():
				var result: Dictionary = SupplyManager.buy(
					String(SupplyManager.catalog[i]["itemId"]))
				if not result.get("ok", false):
					Sfx.play("denied")
					_show_message(String(result.get("reason", "")))
			elif i == SupplyManager.catalog.size():
				SupplyManager.start_delivery()
			_refresh_shop()
			return true
	return false

func _refresh_shop() -> void:
	var lines: PackedStringArray = []
	lines.append("Cash: $%d" % GameState.cash)
	for i in SupplyManager.catalog.size():
		var item: Dictionary = SupplyManager.catalog[i]
		var status := ""
		if not item.get("repeatable", false) and SupplyManager.is_owned(String(item["itemId"])):
			status = "   [OWNED]"
		lines.append("[%d] %s — $%d (%s)%s" % [
			i + 1, String(item["name"]), int(item.get("price", 0)),
			String(item.get("desc", "")), status])
	if not SupplyManager.delivery.is_empty():
		var status := "   [PACKAGE OUT — make the drop]" if SupplyManager.delivery_active else ""
		lines.append("[%d] %s — earn $%d (draws heat)%s" % [
			SupplyManager.catalog.size() + 1,
			String(SupplyManager.delivery.get("name", "Delivery Run")),
			int(SupplyManager.delivery.get("cash", 0)), status])
	_shop_label.text = "\n".join(lines)

func _on_cash_changed(new_cash: int) -> void:
	_cash_label.text = "Cash: $%d" % new_cash
	if _shop_panel.visible:
		_refresh_shop()

func _on_shop_toggled(open: bool) -> void:
	_shop_panel.visible = open
	if open:
		close_modals("shop")
		_refresh_shop()

func _on_supply_event(message: String) -> void:
	_show_message(message, 4.0)
	if _shop_panel.visible:
		_refresh_shop()

func _on_rep_changed(new_rep: int, _gained: int) -> void:
	_rep_label.text = "Rep: %d" % new_rep

func _on_rank_changed(new_rank: String) -> void:
	_rank_label.text = "Rank: %s" % new_rank
	var idx := GameState.rank_index(new_rank)
	if idx >= _rank_index:
		_show_message("RANK UP — you are now \"%s\"" % new_rank)
	else:
		_show_message("RANK LOST — you're back down to \"%s\"" % new_rank)
	_rank_index = idx

func _on_paint_changed(new_paint: int) -> void:
	_paint_label.text = "Paint: %d%s" % [new_paint, "  — LOW" if new_paint < 5 else ""]
	_paint_label.label_settings.font_color = LOW_PAINT if new_paint < 5 else Color.WHITE

func _on_type_changed(type: String) -> void:
	var label: String = WallManager.styles.get(type, {}).get("label", type)
	var color_text := ""
	if GameState.colors_unlocked:
		color_text = " | Color: %s [C]" % GameState.current_fill_color_name()
	_type_label.text = "Can: %s%s" % [label, color_text]
	_refresh_prompt()

func _on_focus_changed(node: Node3D) -> void:
	_focused = node
	_refresh_prompt()

## Milestone 14: F at a wall opens the freehand canvas. The paint check
## here is a courtesy — the real spend happens at commit.
func _on_freehand_requested(wall: PaintableWall) -> void:
	if not GameState.is_type_unlocked("piece"):
		Sfx.play("denied")
		_show_message("Freehand work needs the Piece can unlocked.")
		return
	if GameState.paint < SupplyManager.paint_cost(WallManager.styles.get("piece", {})):
		Sfx.play("denied")
		_show_message("Not enough paint.")
		return
	close_modals("freehand")
	_freehand.begin(wall)
	_freehand.visible = true
	_freehand_wall = wall
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_freehand_committed(image: Image, colors_used: int, coverage: float) -> void:
	var wall := _freehand_wall
	_close_freehand()
	if wall == null:
		return
	var result: Dictionary = WallManager.paint_freehand(wall, image, colors_used, coverage)
	if result.get("ok", false):
		_show_message("Painted!  +%d rep (style x%.1f)" % [
			int(result["rep"]), float(result["styleMultiplier"])], 4.0)
	else:
		Sfx.play("denied")
		_show_message(String(result.get("reason", "Can't paint here.")))
	_refresh_prompt()

func _close_freehand() -> void:
	_freehand.visible = false
	_freehand_wall = null
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_painted(result: Dictionary) -> void:
	if result.get("ok", false):
		_show_message("Painted!  +%d rep" % int(result["rep"]))
	else:
		Sfx.play("denied")
		_show_message(String(result.get("reason", "Can't paint here.")))
	_refresh_prompt()

func _refresh_prompt() -> void:
	if _focused == null:
		_prompt_label.text = ""
		_prompt_panel.visible = false
		return
	_prompt_panel.visible = true
	if _focused is PaintableWall:
		var def: Dictionary = _focused.def
		var state: Dictionary = WallManager.wall_states.get(def["wallId"], {})
		var owner_id: String = state.get("ownerCrewId", "none")
		var style: Dictionary = WallManager.styles.get(GameState.selected_graffiti_type, {})
		var freehand_hint := "  [F] Freehand" if GameState.is_type_unlocked("piece") else ""
		_prompt_label.text = "%s  |  Owner: %s  |  Risk %d  |  Visibility %d\n[E] Paint %s (%d paint)   [1] Tag  [2] Throw-up  [3] Piece%s" % [
			_focused.display_name(), owner_id,
			int(def.get("risk", 1)), int(def.get("visibility", 1)),
			style.get("label", "?"), SupplyManager.paint_cost(style),
			freehand_hint,
		]
	elif _focused.has_method("prompt_text"):
		_prompt_label.text = _focused.prompt_text()

func _on_heat_changed(new_heat: float, _gained: float) -> void:
	var level := HeatManager.level_name()
	_heat_label.text = "Heat: %s (%d)" % [level, roundi(new_heat)]
	_heat_label.label_settings.font_color = HEAT_COLORS.get(level, Color.WHITE)

func _on_heat_level_changed(level: String, rising: bool) -> void:
	if rising:
		_show_message("HEAT RISING — the block is %s now. Risky spots pay more." % level.to_upper(), 4.0)
	else:
		_show_message("Cooling off — heat is down to %s." % level, 3.0)

## City cleanup just erased somebody's work (Plan.md section 33).
func _on_cleanup_event(message: String, _wall_id: String) -> void:
	_show_message(message, 5.0)
	_refresh_prompt()

## Security activity: lookout warnings, sightings, chases (Plan.md
## section 25).
func _on_patrol_event(message: String) -> void:
	_show_message(message, 4.0)

## Rival notifications linger longer — they matter (Plan.md section 13).
func _on_rival_event(message: String, _wall_id: String) -> void:
	_show_message(message, 5.0)
	_refresh_prompt()

## Claiming a block is the Milestone 6 payoff — make it land.
func _on_district_claimed(_district_id: String, district: Dictionary) -> void:
	_show_message("BLOCK CLAIMED — %s is yours!  +%d rep" % [
		String(district.get("name", "The district")),
		int(district.get("claimRepBonus", 0))], 6.0)

func _on_crew_event(message: String) -> void:
	_show_message(message, 4.0)
	if _blackbook.visible:
		_blackbook.refresh()

func _on_mission_started(_mission: Dictionary) -> void:
	_refresh_mission()

func _on_objective_changed(_mission: Dictionary, _objective: Dictionary) -> void:
	_refresh_mission()

func _on_mission_completed(_mission: Dictionary) -> void:
	_refresh_mission()

func _on_chain_completed() -> void:
	_refresh_mission()
	_show_message("PROTOTYPE COMPLETE — you are Known in the Mill Yard.", 7.0)

func _on_mission_event(message: String) -> void:
	_show_message(message, 5.0)

func _on_save_event(message: String) -> void:
	_show_message(message, 3.5)

func _refresh_mission() -> void:
	var mission := MissionManager.current_mission()
	var objective := MissionManager.current_objective()
	_mission_panel.visible = true
	if MissionManager.chain_done:
		_mission_title_label.text = "Mission: Prototype Complete"
		_mission_objective_label.text = "Mill Yard knows your name."
	elif mission.is_empty() or objective.is_empty():
		_mission_panel.visible = false
		_mission_title_label.text = ""
		_mission_objective_label.text = ""
	else:
		_mission_title_label.text = "Mission: %s" % String(mission.get("title", ""))
		_mission_objective_label.text = String(objective.get("text", ""))

## Blackbook reading mode (Milestone 13): number keys flip pages,
## Esc closes; Tab falls through to the toggle branch below.
func _handle_blackbook_input(event: InputEvent) -> bool:
	if event.is_action_pressed("toggle_mouse"):
		_blackbook.visible = false
		return true
	for i in MODAL_SLOT_ACTIONS.size():
		if event.is_action_pressed(MODAL_SLOT_ACTIONS[i]):
			_blackbook.set_page(i)
			return true
	return false

func _show_message(text: String, duration := 2.5) -> void:
	_message_label.text = text
	_message_timer.start(duration)
