extends Node3D
## Graybox prototype district (Plan.md "First Agent Task"): ground,
## placeholder buildings, lighting, JSON-driven paintable walls,
## player, and HUD. Set SMOKE_TEST=1 to run a headless self-check.

const PLAYER_SPAWN := Vector3(0, 0.5, 4)

func _ready() -> void:
	_build_environment()
	_add_box(Vector3(0, -0.25, 0), Vector3(80, 0.5, 80), Color("#5c5c60"), "Ground")
	_build_buildings()
	WallManager.spawn_walls(self)
	RivalManager.claim_initial_territory()
	CrewManager.spawn_npcs(self)
	MissionManager.spawn_actors(self)

	var player := Player.new()
	player.position = PLAYER_SPAWN
	add_child(player)
	SaveManager.register_player(player)
	var hud := Hud.new()
	add_child(hud)
	hud.bind_player(player)
	MissionManager.begin_chain()

	if OS.get_environment("SMOKE_TEST") == "1":
		_run_smoke_test.call_deferred()

## Milestone 8 lighting pass: dusk, because the story opens at night
## (Plan.md section 40) — low warm sun, cool fill, fog, glow, and
## street lamps so graffiti pops against the darkening block.
func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-14, -50, 0)
	sun.light_color = Color("#ff9a5c")
	sun.light_energy = 0.45
	sun.shadow_enabled = true
	add_child(sun)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50, 130, 0)
	moon.light_color = Color("#7c8fd9")
	moon.light_energy = 0.25
	add_child(moon)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#0d1330")
	sky_mat.sky_horizon_color = Color("#d96c3f")
	sky_mat.ground_bottom_color = Color("#0a0a12")
	sky_mat.ground_horizon_color = Color("#b85a3c")
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color("#141a2a")
	env.fog_density = 0.008
	env.fog_sky_affect = 0.2
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	for lamp_pos in [
			Vector3(-16, 0, -6.5), Vector3(-2, 0, 6.5),
			Vector3(10, 0, -6.5), Vector3(20, 0, 6.5)]:
		_add_street_lamp(lamp_pos)

func _add_street_lamp(pos: Vector3) -> void:
	var lamp := Node3D.new()
	lamp.position = pos
	add_child(lamp)

	var pole := MeshInstance3D.new()
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.15, 4.2, 0.15)
	pole.mesh = pole_mesh
	pole.position = Vector3(0, 2.1, 0)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color("#2c2c30")
	pole.material_override = pole_mat
	lamp.add_child(pole)

	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.45, 0.18, 0.45)
	head.mesh = head_mesh
	head.position = Vector3(0, 4.25, 0)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color("#ffd9a0")
	head_mat.emission_enabled = true
	head_mat.emission = Color("#ffc46b")
	head_mat.emission_energy_multiplier = 2.0
	head.material_override = head_mat
	lamp.add_child(head)

	var light := OmniLight3D.new()
	light.position = Vector3(0, 4.0, 0)
	light.light_color = Color("#ffc46b")
	light.light_energy = 2.4
	light.omni_range = 14.0
	lamp.add_child(light)

func _build_buildings() -> void:
	# Two building rows with a street between (z -8..8) and north/south alleys.
	_add_box(Vector3(-14, 5, -14), Vector3(18, 10, 12), Color("#7a7066"), "MillWest")
	_add_box(Vector3(12, 6, -14), Vector3(16, 12, 12), Color("#6e6a70"), "MillEast")
	_add_box(Vector3(-14, 4, 14), Vector3(18, 8, 12), Color("#75695e"), "CornerBlock")
	_add_box(Vector3(12, 5, 14), Vector3(16, 10, 12), Color("#7c7368"), "BodegaBlock")

func _add_box(pos: Vector3, size: Vector3, color: Color, box_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = pos
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	return body

## Headless verification of the core loop: paint a wall, check state,
## reputation, and paint supply, then exercise the Milestone 4 rival
## reaction (initial territory claim, retaliation queue, "TOY"
## cross-out) and quit.
func _run_smoke_test() -> void:
	print("SMOKE: walls spawned = %d" % WallManager.wall_nodes.size())
	assert(WallManager.wall_nodes.size() == WallManager.wall_defs.size())
	var first_id: String = WallManager.wall_defs[0]["wallId"]
	# Milestone 4: wall_mill_01 is Buff Kings territory, claimed at startup.
	var state: Dictionary = WallManager.wall_states[first_id]
	assert(state["ownerCrewId"] == "buff_kings")
	assert(state["state"] == "rival_throwup")
	var wall: PaintableWall = WallManager.wall_nodes[first_id]
	var paint_before: int = GameState.paint
	var result: Dictionary = WallManager.paint_wall(wall, "tag")
	print("SMOKE: paint result = %s" % str(result))
	assert(result["ok"])
	assert(state["state"] == "player_tag")
	assert(state["ownerCrewId"] == "player")
	assert(state["history"].size() == 1)  # the rival claim we painted over
	assert(GameState.paint == paint_before - 1)
	assert(GameState.reputation == int(result["rep"]))
	print("SMOKE: rep=%d rank=%s paint=%d" % [GameState.reputation, GameState.rank, GameState.paint])

	# Painting in crew territory must queue a retaliation.
	assert(RivalManager._pending.size() == 1)
	assert(RivalManager._pending[0]["crewId"] == "buff_kings")
	var events: Array = []
	RivalManager.rival_event.connect(func(msg: String, wid: String) -> void:
		events.append([msg, wid]))
	RivalManager.respond(first_id, "buff_kings")
	assert(state["state"] == "crossed_out")
	assert(state["currentGraffiti"]["isCrossedOut"])
	assert(state["crossOut"]["text"] == "TOY")
	assert(events.size() == 1 and events[0][1] == first_id)
	print("SMOKE: rival event = %s" % events[0][0])

	# Milestone 7: drive the first two mission beats through the same
	# objective notifications the world actors/zones use.
	assert(MissionManager.current_mission()["missionId"] == "m1_first_mark")
	assert(MissionManager.current_objective()["type"] == "reach")
	assert(MissionManager.notify_actor("safehouse"))
	assert(MissionManager.current_mission()["missionId"] == "m2_dont_be_a_toy")
	assert(GameState.is_type_unlocked("throwup"))
	assert(MissionManager.notify_actor("reach_%s" % first_id))

	# The player can paint back over the cross-out and reclaim the wall.
	result = WallManager.paint_wall(wall, "throwup")
	assert(result["ok"])
	assert(state["state"] == "player_throwup")
	assert(not state.has("crossOut"))
	assert(state["history"].size() == 2)
	assert(MissionManager.current_mission()["missionId"] == "m3_get_supplies")
	assert(MissionManager.notify_actor("lupe"))
	assert(GameState.is_type_unlocked("piece"))
	assert(GameState.colors_unlocked)
	GameState.cycle_fill_color()
	assert(MissionManager.current_mission()["missionId"] == "m4_find_a_lookout")

	# Milestone 5: recruit Mina "Moth" (Plan.md section 14) and check
	# her lookout bonus dampens rival responses.
	assert(CrewManager.members.has("npc_mina_moth"))
	var mina: Dictionary = CrewManager.members["npc_mina_moth"]
	assert(mina["stage"] == "not_met")
	var chance_before := RivalManager.response_chance("wall_mill_02", "buff_kings")
	CrewManager.interact("npc_mina_moth")
	assert(mina["stage"] == "mission_active")
	assert(CrewManager.collect_item("npc_mina_moth"))
	assert(mina["stage"] == "item_recovered")
	CrewManager.interact("npc_mina_moth")
	assert(mina["stage"] == "recruited")
	assert(CrewManager.has_role("lookout"))
	var chance_after := RivalManager.response_chance("wall_mill_02", "buff_kings")
	assert(chance_after < chance_before)
	print("SMOKE: lookout bonus %.2f -> %.2f" % [chance_before, chance_after])

	# The recruited lookout warns when a new retaliation is queued.
	var events_before := events.size()
	result = WallManager.paint_wall(WallManager.wall_nodes["wall_mill_02"], "tag")
	assert(result["ok"])
	assert(RivalManager._pending.size() == 2)
	assert(events.size() == events_before + 1)
	print("SMOKE: lookout warning = %s" % events[-1][0])

	# Milestone 6: district influence reflects wall ownership, and
	# painting enough key walls claims the block once for a rep bonus.
	var district_id := "district_mill_yard"
	assert(not TerritoryManager.is_claimed(district_id))
	var shares: Dictionary = TerritoryManager.influence(district_id)
	print("SMOKE: influence before claim = %s" % str(shares))
	assert(shares.get("player", 0.0) > 0.0)        # mill walls reclaimed above
	assert(shares.get("buff_kings", 0.0) > 0.0)    # they still hold the landmark
	assert(shares.get("player", 0.0) < 0.5)
	var claims: Array = []
	TerritoryManager.district_claimed.connect(
		func(did: String, _d: Dictionary) -> void: claims.append(did))
	var rep_before: int = GameState.reputation
	for wall_id in ["wall_landmark_01", "wall_bodega_01", "wall_median_01"]:
		result = WallManager.paint_wall(WallManager.wall_nodes[wall_id], "tag")
		assert(result["ok"])
	shares = TerritoryManager.influence(district_id)
	assert(shares["player"] >= 0.5)
	assert(TerritoryManager.is_claimed(district_id))
	assert(claims == [district_id])  # threshold reward fires exactly once
	assert(GameState.reputation > rep_before + 150)  # paints + 150 claim bonus
	print("SMOKE: district claimed, influence = %s" % str(shares))
	print("SMOKE: %s" % TerritoryManager.summary_text(district_id))
	if MissionManager.current_objective().get("type", "") == "defend":
		var defend_wall := String(MissionManager.remembered.get("defend_wall", ""))
		assert(defend_wall != "")
		result = WallManager.paint_wall(WallManager.wall_nodes[defend_wall], "tag")
		assert(result["ok"])
	if MissionManager.current_objective().get("type", "") == "paint":
		result = WallManager.paint_wall(WallManager.wall_nodes["wall_landmark_01"], "piece")
		assert(result["ok"])
	assert(MissionManager.chain_done)
	print("SMOKE: mission chain complete")

	# Heat system (Plan.md section 12): all that painting built heat,
	# which raises the rep payout for further risky work.
	assert(HeatManager.heat > 0.0)
	assert(HeatManager.rep_multiplier() > 1.0)
	print("SMOKE: heat=%.1f (%s)" % [HeatManager.heat, HeatManager.level_name()])
	var cleanup_walls: Array = []
	HeatManager.cleanup_event.connect(func(_msg: String, wid: String) -> void:
		cleanup_walls.append(wid))
	var buff_id := "wall_lot_01"
	result = WallManager.paint_wall(WallManager.wall_nodes[buff_id], "tag")
	assert(result["ok"])
	var buff_state: Dictionary = WallManager.wall_states[buff_id]
	var history_before: int = buff_state["history"].size()
	assert(HeatManager.force_cleanup(buff_id))
	assert(buff_state["state"] == "buffed")
	assert(buff_state["ownerCrewId"] == "city")
	assert(buff_state["currentGraffiti"] == null)
	assert(buff_state["history"].size() == history_before + 1)
	assert(buff_state["history"][-1]["isBuffed"])
	assert(cleanup_walls == [buff_id])
	assert(TerritoryManager.influence(district_id).has("city"))
	# Cleanup retaliation (Plan.md section 15): repainting a buffed wall
	# pays a bonus over the plain value.
	var plain_rep: int = WallManager._reputation_for(
		WallManager.styles["tag"], WallManager.wall_def(buff_id))
	result = WallManager.paint_wall(WallManager.wall_nodes[buff_id], "tag")
	assert(result["ok"])
	assert(int(result["rep"]) == int(round(plain_rep * WallManager.BUFF_RETALIATION_BONUS)))
	assert(buff_state["state"] == "player_tag" and buff_state["ownerCrewId"] == "player")
	# Laying low: heat decays on the simulation tick.
	var heat_before_tick: float = HeatManager.heat
	HeatManager._on_tick()
	assert(HeatManager.heat < heat_before_tick)
	print("SMOKE: buff + retaliation bonus OK, heat decays %.1f -> %.1f" % [
		heat_before_tick, HeatManager.heat])

	# Milestone 8: save to disk, mutate important runtime state, then
	# load and prove the saved wall/progression/player state comes back.
	var player := get_node("Player") as Player
	var saved_rep := GameState.reputation
	var saved_paint := GameState.paint
	var saved_rank := GameState.rank
	var saved_wall_state: Dictionary = WallManager.wall_states[first_id].duplicate(true)
	var saved_position := player.global_position
	var saved_heat: float = HeatManager.heat
	assert(SaveManager.quick_save())
	GameState.reputation = 1
	GameState.paint = 1
	GameState.rank = "Toy"
	HeatManager.heat = 0.0
	player.global_position = Vector3(22, 0.5, 22)
	WallManager.apply_rival_graffiti(first_id, RivalManager.crews["ghost_line"], "tag")
	assert(WallManager.wall_states[first_id]["ownerCrewId"] == "ghost_line")
	assert(SaveManager.quick_load())
	assert(GameState.reputation == saved_rep)
	assert(GameState.paint == saved_paint)
	assert(GameState.rank == saved_rank)
	assert(is_equal_approx(HeatManager.heat, saved_heat))
	assert(player.global_position == saved_position)
	assert(WallManager.wall_states[first_id]["ownerCrewId"] == saved_wall_state["ownerCrewId"])
	assert(WallManager.wall_states[first_id]["state"] == saved_wall_state["state"])
	assert(WallManager.wall_states[first_id]["currentGraffiti"]["graffitiId"] == saved_wall_state["currentGraffiti"]["graffitiId"])
	print("SMOKE: save/load restored wall, player, and progression state")
	print("SMOKE: OK")
	get_tree().quit()
