class_name Hud
extends CanvasLayer
## Prototype HUD: rank / reputation / paint / selected graffiti type
## (top-left), interaction prompt and feedback messages (bottom), the
## Tab crew menu (Milestone 5), and the M district map (Milestone 6).

var _rank_label: Label
var _rep_label: Label
var _paint_label: Label
var _type_label: Label
var _mission_title_label: Label
var _mission_objective_label: Label
var _prompt_label: Label
var _message_label: Label
var _message_timer: Timer
var _crew_panel: PanelContainer
var _crew_label: Label
var _map_panel: MapPanel
var _focused: Node3D = null

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var stats := VBoxContainer.new()
	stats.position = Vector2(16, 16)
	root.add_child(stats)
	_rank_label = _make_label(stats, 22)
	_rep_label = _make_label(stats, 18)
	_paint_label = _make_label(stats, 18)
	_type_label = _make_label(stats, 18)
	_mission_title_label = _make_label(stats, 18)
	_mission_objective_label = _make_label(stats, 16)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -130.0
	bottom.offset_bottom = -30.0
	root.add_child(bottom)
	_message_label = _make_label(bottom, 22)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label = _make_label(bottom, 18)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_message_timer = Timer.new()
	_message_timer.one_shot = true
	_message_timer.wait_time = 2.5
	_message_timer.timeout.connect(func() -> void: _message_label.text = "")
	add_child(_message_timer)

	_crew_panel = PanelContainer.new()
	_crew_panel.set_anchors_preset(Control.PRESET_CENTER)
	_crew_panel.visible = false
	root.add_child(_crew_panel)
	var crew_box := VBoxContainer.new()
	crew_box.custom_minimum_size = Vector2(560, 0)
	_crew_panel.add_child(crew_box)
	var crew_title := _make_label(crew_box, 24)
	crew_title.text = "CREW   —   [Tab] close"
	_crew_label = _make_label(crew_box, 17)

	_map_panel = MapPanel.new()
	_map_panel.set_anchors_preset(Control.PRESET_CENTER)
	root.add_child(_map_panel)

	GameState.reputation_changed.connect(_on_rep_changed)
	GameState.rank_changed.connect(_on_rank_changed)
	GameState.paint_changed.connect(_on_paint_changed)
	GameState.graffiti_type_changed.connect(_on_type_changed)
	GameState.fill_color_changed.connect(func(_name: String) -> void:
		_on_type_changed(GameState.selected_graffiti_type))
	RivalManager.rival_event.connect(_on_rival_event)
	CrewManager.crew_event.connect(_on_crew_event)
	TerritoryManager.district_claimed.connect(_on_district_claimed)
	MissionManager.mission_started.connect(_on_mission_started)
	MissionManager.objective_changed.connect(_on_objective_changed)
	MissionManager.mission_completed.connect(_on_mission_completed)
	MissionManager.chain_completed.connect(_on_chain_completed)
	MissionManager.mission_event.connect(_on_mission_event)
	SaveManager.save_event.connect(_on_save_event)
	CrewManager.crew_changed.connect(func() -> void: _refresh_crew_menu())
	_refresh_stats()
	_refresh_mission()

func bind_player(player: Player) -> void:
	player.focus_changed.connect(_on_focus_changed)
	player.painted.connect(_on_painted)
	_map_panel.bind_player(player)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("crew_menu"):
		_crew_panel.visible = not _crew_panel.visible
		if _crew_panel.visible:
			_map_panel.visible = false
			_refresh_crew_menu()
	elif event.is_action_pressed("map"):
		_map_panel.visible = not _map_panel.visible
		if _map_panel.visible:
			_crew_panel.visible = false
	elif event.is_action_pressed("quick_save"):
		SaveManager.quick_save()
	elif event.is_action_pressed("quick_load"):
		if SaveManager.quick_load():
			_refresh_stats()
			_refresh_mission()
			_refresh_prompt()
			_refresh_crew_menu()
			_map_panel.queue_redraw()

func _refresh_stats() -> void:
	_rank_label.text = "Rank: %s" % GameState.rank
	_rep_label.text = "Rep: %d" % GameState.reputation
	_paint_label.text = "Paint: %d" % GameState.paint
	_on_type_changed(GameState.selected_graffiti_type)

func _on_rep_changed(new_rep: int, _gained: int) -> void:
	_rep_label.text = "Rep: %d" % new_rep

func _on_rank_changed(new_rank: String) -> void:
	_rank_label.text = "Rank: %s" % new_rank
	_show_message("RANK UP — you are now \"%s\"" % new_rank)

func _on_paint_changed(new_paint: int) -> void:
	_paint_label.text = "Paint: %d" % new_paint

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

func _on_painted(result: Dictionary) -> void:
	if result.get("ok", false):
		_show_message("Painted!  +%d rep" % int(result["rep"]))
	else:
		_show_message(String(result.get("reason", "Can't paint here.")))
	_refresh_prompt()

func _refresh_prompt() -> void:
	if _focused == null:
		_prompt_label.text = ""
		return
	if _focused is PaintableWall:
		var def: Dictionary = _focused.def
		var state: Dictionary = WallManager.wall_states.get(def["wallId"], {})
		var owner_id: String = state.get("ownerCrewId", "none")
		var style: Dictionary = WallManager.styles.get(GameState.selected_graffiti_type, {})
		_prompt_label.text = "%s  |  Owner: %s  |  Risk %d  |  Visibility %d\n[E] Paint %s (%d paint)   [1] Tag  [2] Throw-up  [3] Piece" % [
			_focused.display_name(), owner_id,
			int(def.get("risk", 1)), int(def.get("visibility", 1)),
			style.get("label", "?"), int(style.get("paintCost", 1)),
		]
	elif _focused.has_method("prompt_text"):
		_prompt_label.text = _focused.prompt_text()

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
	if _crew_panel.visible:
		_refresh_crew_menu()

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
	if MissionManager.chain_done:
		_mission_title_label.text = "Mission: Prototype Complete"
		_mission_objective_label.text = "Mill Yard knows your name."
	elif mission.is_empty() or objective.is_empty():
		_mission_title_label.text = ""
		_mission_objective_label.text = ""
	else:
		_mission_title_label.text = "Mission: %s" % String(mission.get("title", ""))
		_mission_objective_label.text = String(objective.get("text", ""))

func _refresh_crew_menu() -> void:
	var lines: PackedStringArray = []
	for m in CrewManager.members.values():
		lines.append("%s (%s) — %s\n      %s" % [
			String(m["alias"]), String(m["name"]),
			String(m.get("roleLabel", m["role"])),
			CrewManager.status_text(m)])
	_crew_label.text = "\n".join(lines) if not lines.is_empty() else "No writers met yet."

func _show_message(text: String, duration := 2.5) -> void:
	_message_label.text = text
	_message_timer.start(duration)

func _make_label(parent: Control, font_size: int) -> Label:
	var label := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = font_size
	settings.outline_size = 6
	settings.outline_color = Color(0, 0, 0, 0.85)
	label.label_settings = settings
	parent.add_child(label)
	return label
