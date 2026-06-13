extends Node3D
## Graybox prototype district (Plan.md "First Agent Task"): ground,
## placeholder buildings, lighting, JSON-driven paintable walls,
## player, and HUD. Set SMOKE_TEST=1 to run a headless self-check.

const PLAYER_SPAWN := Vector3(0, 0.5, 4)
const CLIMBS_PATH := "res://Data/climbs.json"
const AMBIENT_NPCS_PATH := "res://Data/ambient_npcs.json"
const DataLoader := preload("res://Scripts/Data/data_loader.gd")
const TravelPointScript := preload("res://Scripts/World/travel_point.gd")
const ClimbZoneScript := preload("res://Scripts/World/climb_zone.gd")
const AmbientNpcScript := preload("res://Scripts/World/ambient_npc.gd")

var _material_cache: Dictionary = {}

func _ready() -> void:
	_build_environment()
	_add_box(Vector3(0, -0.25, 0), Vector3(80, 0.5, 80), Color("#303236"),
		"Ground", _street_material(Color("#303236"), 0.95, 0.52))
	_build_buildings()
	_build_canal_side()
	_build_train_yard()
	_build_street_details()
	_spawn_travel_points()
	_spawn_climb_zones()
	WallManager.spawn_walls(self)
	TrainManager.spawn_trains(self)
	RivalManager.claim_initial_territory()
	CrewManager.spawn_npcs(self)
	MissionManager.spawn_actors(self)
	_spawn_ambient_npcs()

	var player := Player.new()
	player.position = PLAYER_SPAWN
	add_child(player)
	SaveManager.register_player(player)
	PatrolManager.spawn_patrols(self, player)
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
	pole.material_override = _solid_material(Color("#2c2c30"))
	lamp.add_child(pole)

	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.45, 0.18, 0.45)
	head.mesh = head_mesh
	head.position = Vector3(0, 4.25, 0)
	var head_mat := _solid_material(Color("#ffd9a0"), true)
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
	_add_box(Vector3(-14, 5, -14), Vector3(18, 10, 12), Color("#7a7066"),
		"MillWest", _wall_material(Color("#7a7066"), 0.42, 0.96))
	_add_box(Vector3(12, 6, -14), Vector3(16, 12, 12), Color("#6e6a70"),
		"MillEast", _wall_material(Color("#6e6a70"), 0.5, 0.96))
	_add_box(Vector3(-14, 4, 14), Vector3(18, 8, 12), Color("#75695e"),
		"CornerBlock", _wall_material(Color("#75695e"), 0.72, 0.94))
	_add_box(Vector3(12, 5, 14), Vector3(16, 10, 12), Color("#7c7368"),
		"BodegaBlock", _wall_material(Color("#7c7368"), 0.78, 0.92))

## Canal Side graybox (Milestone 18, Plan.md §45): a second block east
## across the water — ground, the canal itself, a footbridge walkway,
## and the buildings the canal walls hang on.
func _build_canal_side() -> void:
	_add_box(Vector3(120, -0.25, 0), Vector3(80, 0.5, 80), Color("#35383a"),
		"CanalGround", _street_material(Color("#35383a"), 0.95, 0.45))
	# The water between the blocks; the footbridge crosses it at z=0.
	_add_box(Vector3(60, -0.6, 0), Vector3(40, 0.3, 80), Color("#1d3a4a"), "CanalWater")
	_add_box(Vector3(60, -0.05, 0), Vector3(44, 0.4, 4.0), Color("#4a4f55"), "Footbridge")
	_add_box(Vector3(108, 5, -14), Vector3(20, 10, 12), Color("#6e7a82"),
		"LockHouseBlock", _wall_material(Color("#6e7a82"), 0.45, 0.96))
	_add_box(Vector3(130, 6, -14), Vector3(14, 12, 12), Color("#75808a"),
		"PumpStation", _wall_material(Color("#75808a"), 0.62, 0.95))
	_add_box(Vector3(106, 4, 14), Vector3(16, 8, 12), Color("#8a8f86"),
		"DryDock", _wall_material(Color("#8a8f86"), 0.72, 0.94))
	_add_box(Vector3(124, 7, 14), Vector3(18, 14, 12), Color("#b9b3a4"),
		"GrainSilo", _wall_material(Color("#b9b3a4"), 0.58, 0.97))
	for lamp_pos in [
			Vector3(100, 0, -6.5), Vector3(118, 0, 6.5), Vector3(134, 0, -6.5)]:
		_add_street_lamp(lamp_pos)

## Milestone 20 train yard: an east-edge siding adjacent to Canal Side,
## sized for the first scheduled train car.
func _build_train_yard() -> void:
	_add_box(Vector3(148, -0.15, -3), Vector3(24, 0.3, 8), Color("#3b3d3f"),
		"TrainYardBed", _street_material(Color("#3b3d3f"), 1.0, 0.9))
	_add_box(Vector3(148, 0.05, -4.35), Vector3(24, 0.12, 0.18), Color("#202328"), "TrainRailNorth")
	_add_box(Vector3(148, 0.05, -1.65), Vector3(24, 0.12, 0.18), Color("#202328"), "TrainRailSouth")
	for x in [138.0, 142.0, 146.0, 150.0, 154.0, 158.0]:
		_add_box(Vector3(x, 0.08, -3), Vector3(0.25, 0.12, 5.2), Color("#6b5840"), "TrainTie")

## First outside-street art pass: readable asphalt, sidewalks, gutters,
## lane/crosswalk paint, metal covers, drains, stains, and small litter.
func _build_street_details() -> void:
	for origin_x in [0.0, 120.0]:
		_add_sidewalk_run(origin_x, -7.2, "North")
		_add_sidewalk_run(origin_x, 7.2, "South")
		_add_lane_markings(origin_x)
		_add_crosswalk(origin_x - 23.0, "West")
		_add_crosswalk(origin_x + 22.0, "East")
		_add_manhole(Vector3(origin_x - 7.0, 0.035, -1.6), "Main")
		_add_manhole(Vector3(origin_x + 14.0, 0.035, 2.3), "Side")
		for z in [-6.25, 6.25]:
			for x in [origin_x - 18.0, origin_x + 4.0, origin_x + 26.0]:
				_add_storm_drain(Vector3(x, 0.04, z))
		_add_oil_stain(Vector3(origin_x - 4.0, 0.045, -2.7), Vector2(2.4, 0.9), 18.0)
		_add_oil_stain(Vector3(origin_x + 17.0, 0.045, 3.4), Vector2(1.5, 0.65), -12.0)
		_add_litter_patch(origin_x)
	_add_flat_box(Vector3(60, 0.065, -2.35), Vector3(44, 0.015, 0.08),
		Color("#d8d4bd", 0.55), "BridgeLaneLine")
	for x in [139.5, 143.5, 147.5, 151.5, 155.5]:
		_add_gravel_chip(Vector3(x, 0.02, -5.2))
		_add_gravel_chip(Vector3(x + 1.1, 0.02, -0.8))

func _add_sidewalk_run(origin_x: float, z: float, side_name: String) -> void:
	_add_flat_box(Vector3(origin_x, 0.03, z), Vector3(70.0, 0.08, 1.35),
		Color("#85817a"), "Sidewalk%s_%d" % [side_name, int(origin_x)])
	_add_flat_box(Vector3(origin_x, 0.075, z * 0.91), Vector3(70.0, 0.12, 0.18),
		Color("#b7b0a5"), "Curb%s_%d" % [side_name, int(origin_x)])
	for i in range(11):
		var x := origin_x - 33.0 + i * 6.6
		_add_flat_box(Vector3(x, 0.085, z), Vector3(0.045, 0.01, 1.28),
			Color("#5f5d59", 0.9), "SidewalkJoint")

func _add_lane_markings(origin_x: float) -> void:
	for i in range(7):
		var x := origin_x - 30.0 + i * 9.5
		_add_flat_box(Vector3(x, 0.04, 0.0), Vector3(4.2, 0.012, 0.11),
			Color("#d8d4bd", 0.62), "FadedLaneDash")
	for z in [-5.65, 5.65]:
		_add_flat_box(Vector3(origin_x, 0.038, z), Vector3(66.0, 0.01, 0.08),
			Color("#d3c177", 0.4), "FadedCurbPaint")

func _add_crosswalk(x: float, suffix: String) -> void:
	for i in range(5):
		_add_flat_box(Vector3(x, 0.045, -3.2 + i * 1.6), Vector3(1.15, 0.014, 0.62),
			Color("#e6e1cf", 0.54), "Crosswalk%s" % suffix)

func _add_manhole(pos: Vector3, suffix: String) -> void:
	var cover := MeshInstance3D.new()
	cover.name = "Manhole%s" % suffix
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.52
	mesh.bottom_radius = 0.52
	mesh.height = 0.025
	mesh.radial_segments = 36
	cover.mesh = mesh
	cover.position = pos
	cover.material_override = _solid_material(Color("#202328"), false, 0.65)
	add_child(cover)
	for offset in [-0.22, 0.0, 0.22]:
		_add_flat_box(pos + Vector3(0, 0.018, offset), Vector3(0.72, 0.006, 0.028),
			Color("#4d5359"), "ManholeGroove")

func _add_storm_drain(pos: Vector3) -> void:
	_add_flat_box(pos, Vector3(0.8, 0.025, 0.22), Color("#1b1f24"), "StormDrain")
	for i in range(4):
		_add_flat_box(pos + Vector3(-0.27 + i * 0.18, 0.018, 0),
			Vector3(0.035, 0.006, 0.2), Color("#59606a"), "StormDrainBar")

func _add_oil_stain(pos: Vector3, size: Vector2, rot_degrees: float) -> void:
	var stain := MeshInstance3D.new()
	stain.name = "OilStain"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 0.01
	mesh.radial_segments = 24
	stain.mesh = mesh
	stain.position = pos
	stain.scale = Vector3(size.x, 1.0, size.y)
	stain.rotation_degrees.y = rot_degrees
	stain.material_override = _solid_material(Color(0.03, 0.035, 0.04, 0.48), false, 0.18)
	add_child(stain)

func _add_litter_patch(origin_x: float) -> void:
	var colors := [Color("#d9d2bc"), Color("#4f658a"), Color("#9a4f4b"), Color("#d8c45f")]
	var points := [
		Vector3(origin_x - 19.0, 0.055, 5.2), Vector3(origin_x - 10.0, 0.055, -6.0),
		Vector3(origin_x + 7.5, 0.055, 6.1), Vector3(origin_x + 23.0, 0.055, -5.5),
		Vector3(origin_x + 28.0, 0.055, 2.8)]
	for i in range(points.size()):
		var p: Vector3 = points[i]
		var size := Vector3(0.36 + 0.06 * (i % 2), 0.006, 0.18 + 0.05 * (i % 3))
		var paper := _add_flat_box(p, size, colors[i % colors.size()], "StreetLitter")
		paper.rotation_degrees.y = float(i * 23)

func _add_gravel_chip(pos: Vector3) -> void:
	for i in range(4):
		var chip := _add_flat_box(pos + Vector3(i * 0.18, 0, (i % 2) * 0.22),
			Vector3(0.14, 0.02, 0.09), Color("#68635a"), "GravelChip")
		chip.rotation_degrees.y = float(i * 31)

## Climb routes up the graybox buildings (Milestone 19, Data/climbs.json).
func _spawn_climb_zones() -> void:
	var parsed: Variant = DataLoader.load_json(CLIMBS_PATH, "District")
	if not (parsed is Array):
		return
	for def in parsed:
		if not DataLoader.require_fields(def,
				["climbId", "label", "position", "top", "fallChance", "fallRepPenalty"],
				"District: climb \"%s\"" % String(def.get("climbId", "?"))):
			continue
		var zone := ClimbZoneScript.new()
		zone.setup(def)
		add_child(zone)

## One gate per district that has a travel def (districts.json).
func _spawn_travel_points() -> void:
	for district_id in TerritoryManager.districts:
		var district: Dictionary = TerritoryManager.districts[district_id]
		var travel: Dictionary = district.get("travel", {})
		if travel.is_empty():
			continue
		var point := TravelPointScript.new()
		point.setup(travel, String(travel.get("to", "")))
		add_child(point)

func _spawn_ambient_npcs() -> void:
	var parsed: Variant = DataLoader.load_json(AMBIENT_NPCS_PATH, "District")
	if not (parsed is Array):
		return
	for def in parsed:
		if not DataLoader.require_fields(def, ["npcId", "waypoints"],
				"District: ambient npc \"%s\"" % String(def.get("npcId", "?"))):
			continue
		var npc := AmbientNpcScript.new()
		npc.setup(def)
		add_child(npc)

func _add_box(pos: Vector3, size: Vector3, color: Color, box_name: String,
		material: Material = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = pos
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	if material != null:
		mesh.material_override = material
	else:
		mesh.material_override = _solid_material(color)
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	return body

func _add_flat_box(pos: Vector3, size: Vector3, color: Color, box_name: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = box_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = _solid_material(color, false, 0.88)
	add_child(mesh)
	return mesh

func _street_material(base: Color, roughness: float, noise_frequency: float) -> StandardMaterial3D:
	var key := "street:%s:%.2f:%.2f" % [base.to_html(true), roughness, noise_frequency]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base
	mat.roughness = roughness
	var noise := FastNoiseLite.new()
	noise.seed = 4812
	noise.frequency = noise_frequency
	noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.noise = noise
	mat.albedo_texture = texture
	_material_cache[key] = mat
	return mat

func _wall_material(base: Color, noise_frequency: float, roughness: float) -> StandardMaterial3D:
	var key := "wall:%s:%.2f:%.2f" % [base.to_html(true), noise_frequency, roughness]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base
	mat.roughness = roughness
	var noise := FastNoiseLite.new()
	noise.seed = hash(str(base))
	noise.frequency = noise_frequency
	noise.fractal_octaves = 5
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.noise = noise
	mat.albedo_texture = texture
	_material_cache[key] = mat
	return mat

func _solid_material(color: Color, emission := false, roughness := 0.7) -> StandardMaterial3D:
	var key := "solid:%s:%s:%.2f" % [color.to_html(true), str(emission), roughness]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.0
	_material_cache[key] = mat
	return mat

## Headless self-check, split per system (Plan_v2.md §3.3): each
## _smoke_* function documents the state it assumes and asserts one
## system's behavior. The sequence matters — later sections build on
## the world the earlier ones left behind — but each function is
## readable (and extendable) on its own. Every milestone adds or
## extends a section.
func _run_smoke_test() -> void:
	_smoke_data_validation()
	_smoke_world_hardening()
	_smoke_walls_and_rivals()
	_smoke_missions()
	_smoke_crew()
	_smoke_territory()
	_smoke_heat_and_cleanup()
	_smoke_patrols()
	_smoke_save_load()
	_smoke_supplies()
	_smoke_dialogue()
	_smoke_blackbook()
	_smoke_freehand()
	_smoke_graffiti_types()
	_smoke_progression()
	_smoke_canal_side()
	_smoke_rooftop_climbing()
	_smoke_train_painting()
	_smoke_gallery()
	_smoke_history_cap()
	_smoke_ambient_npc_life()
	_smoke_player_model()
	print("SMOKE: OK")
	get_tree().quit()

func _smoke_player() -> Player:
	return get_node("Player") as Player

func _first_wall_id() -> String:
	return String(WallManager.wall_defs[0]["wallId"])

## Plan_v2.md §3.6: every manager validates its /Data file at autoload
## time; shipped data must produce zero validation errors.
func _smoke_data_validation() -> void:
	assert(DataLoader.error_count == 0)
	assert(not WallManager.wall_defs.is_empty())
	assert(not WallManager.styles.is_empty())
	var has_controller_move := false
	for event in InputMap.action_get_events("move_forward"):
		if event is InputEventJoypadMotion:
			has_controller_move = true
	assert(has_controller_move)
	var has_controller_can_cycle := false
	for event in InputMap.action_get_events("can_next"):
		if event is InputEventJoypadButton:
			has_controller_can_cycle = true
	assert(has_controller_can_cycle)
	print("SMOKE: data validation clean")

func _smoke_world_hardening() -> void:
	assert(_solid_material(Color("#68635a")) == _solid_material(Color("#68635a")))
	assert(get_node_or_null("local_mill_01") != null)
	assert(get_node_or_null("local_canal_01") != null)
	assert(get_node_or_null("local_mill_02") != null)
	assert(get_node_or_null("local_mill_03") != null)
	assert(get_node_or_null("local_canal_02") != null)
	assert(get_node_or_null("local_canal_03") != null)
	var player := _smoke_player()
	var blocker := _add_box(player.global_position + Vector3(0, 0.8, -1.0),
		Vector3(1.0, 1.6, 0.2), Color("#111111"), "SmokeLOSBlock")
	var target := Node3D.new()
	target.name = "SmokeBlockedInteractable"
	target.position = player.global_position + Vector3(0, 0, -2.2)
	add_child(target)
	assert(not player._has_line_of_sight(target))
	remove_child(target)
	target.free()
	remove_child(blocker)
	blocker.free()
	print("SMOKE: world hardening — material cache + interactable LOS")

## Assumes: fresh boot. Paints the first wall (Buff Kings territory,
## claimed at startup), checks state/rep/paint, then exercises the
## Milestone 4 rival reaction: retaliation queue and "TOY" cross-out.
func _smoke_walls_and_rivals() -> void:
	print("SMOKE: walls spawned = %d" % WallManager.wall_nodes.size())
	assert(WallManager.wall_nodes.size() == WallManager.wall_defs.size())
	assert(not GameState.alias_chosen)
	GameState.choose_alias("NOVA")
	assert(GameState.alias_chosen and GameState.alias == "NOVA")
	assert(MissionManager.current_objective()["type"] == "paint")
	var first_id := _first_wall_id()
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

## Assumes: the first wall is crossed out and mission 1 is active.
## Drives the first mission beats (Milestone 7) through the same
## objective notifications the world actors/zones use, repainting the
## crossed-out wall along the way.
func _smoke_missions() -> void:
	var first_id := _first_wall_id()
	var state: Dictionary = WallManager.wall_states[first_id]
	assert(MissionManager.current_mission()["missionId"] == "m1_first_mark")
	assert(MissionManager.current_objective()["type"] == "reach")
	assert(MissionManager.notify_actor("safehouse"))
	assert(MissionManager.current_mission()["missionId"] == "m2_dont_be_a_toy")
	assert(GameState.is_type_unlocked("throwup"))
	assert(MissionManager.notify_actor("reach_%s" % first_id))

	# The player can paint back over the cross-out and reclaim the wall.
	var result: Dictionary = WallManager.paint_wall(WallManager.wall_nodes[first_id], "throwup")
	assert(result["ok"])
	assert(state["state"] == "player_throwup")
	assert(not state.has("crossOut"))
	assert(state["history"].size() == 2)
	assert(MissionManager.current_mission()["missionId"] == "m3_get_supplies")
	var lupe := get_node_or_null("lupe")
	assert(lupe != null)
	var lupe_visuals: Dictionary = MissionManager.actor_defs[1].get("visuals", {})
	if not lupe_visuals.is_empty() \
			and ResourceLoader.exists(String(lupe_visuals["states"]["idle"]["model"])):
		assert(lupe.get_node_or_null("LupeRatModel") != null)
		assert(lupe.get_node_or_null("SupplyCrate") != null)
	assert(MissionManager.notify_actor("lupe"))
	assert(GameState.is_type_unlocked("piece"))
	assert(GameState.colors_unlocked)
	GameState.cycle_fill_color()
	assert(MissionManager.current_mission()["missionId"] == "m4_find_a_lookout")

## Assumes: mission 4 just started and one retaliation (the first
## wall's) is pending. Recruits Mina "Moth" (Milestone 5, Plan.md
## section 14) and checks her lookout bonus dampens rival responses
## and warns when a new retaliation is queued.
func _smoke_crew() -> void:
	assert(CrewManager.members.has("npc_mina_moth"))
	assert(CrewManager.members.has("npc_rico_caps"))
	assert(CrewManager.members.has("npc_jay_metro"))
	var mina: Dictionary = CrewManager.members["npc_mina_moth"]
	assert(mina["stage"] == "not_met")
	var chance_before := RivalManager.response_chance("wall_mill_02", "buff_kings")
	CrewManager.interact("npc_mina_moth")
	assert(mina["stage"] == "mission_active")
	var blackbook := get_node_or_null("pickup_npc_mina_moth")
	assert(blackbook is PickupItem)
	blackbook.interact()
	assert(mina["stage"] == "item_recovered")
	assert(blackbook.is_queued_for_deletion())
	CrewManager.interact("npc_mina_moth")
	assert(mina["stage"] == "recruited")
	assert(CrewManager.has_role("lookout"))
	# Recruiting builds crew standing (§11 split, Milestone 21).
	assert(GameState.crew_rep == CrewManager.RECRUIT_CREW_REP)
	var moth_node := get_node_or_null("npc_mina_moth")
	assert(moth_node != null)
	assert(moth_node.get_node_or_null("CharacterVisual/LookoutRadioPhone") != null)
	assert(moth_node.get_node_or_null("CharacterVisual/LookoutActiveIndicator") != null)
	if ResourceLoader.exists(String(mina["visuals"]["states"]["idle"]["model"])):
		assert(moth_node.get_node_or_null("CharacterVisual/LookoutMeerkatModel") != null)
	var chance_after := RivalManager.response_chance("wall_mill_02", "buff_kings")
	assert(chance_after < chance_before)
	print("SMOKE: lookout bonus %.2f -> %.2f" % [chance_before, chance_after])

	for member_id in ["npc_rico_caps", "npc_jay_metro"]:
		var member: Dictionary = CrewManager.members[member_id]
		CrewManager.interact(member_id)
		assert(member["stage"] == "mission_active")
		var pickup := get_node_or_null("pickup_%s" % member_id)
		assert(pickup is PickupItem)
		pickup.interact()
		assert(member["stage"] == "item_recovered")
		CrewManager.interact(member_id)
		assert(member["stage"] == "recruited")
	assert(CrewManager.has_role("filler"))
	assert(CrewManager.has_role("getaway"))
	assert(GameState.crew_rep == CrewManager.RECRUIT_CREW_REP * 3)
	assert(get_node_or_null("npc_rico_caps/CharacterVisual/RicoCapsModel") != null)
	assert(get_node_or_null("npc_jay_metro/CharacterVisual/JayMetroModel") != null)
	var migrated_v5 := SaveManager._migrate({
		"version": 5,
		"crew": {"stages": {"npc_mina_moth": "recruited"}},
	})
	assert(int(migrated_v5["version"]) == SaveManager.SAVE_VERSION)
	assert(migrated_v5["crew"].has("getaway_used_levels"))
	print("SMOKE: crew depth — Caps and Metro recruited from data")

	# The recruited lookout warns when a new retaliation is queued.
	var events: Array = []
	RivalManager.rival_event.connect(func(msg: String, wid: String) -> void:
		events.append([msg, wid]))
	var result: Dictionary = WallManager.paint_wall(WallManager.wall_nodes["wall_mill_02"], "tag")
	assert(result["ok"])
	assert(RivalManager._pending.size() == 2)
	assert(events.size() == 1)
	print("SMOKE: lookout warning = %s" % events[-1][0])

## Assumes: the player holds the two mill walls; the landmark is still
## Buff Kings'. District influence reflects wall ownership (Milestone
## 6); painting the key walls claims the block once for a rep bonus and
## finishes the mission chain.
func _smoke_territory() -> void:
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
	var result: Dictionary
	for wall_id in ["wall_landmark_01", "wall_bodega_01", "wall_median_01"]:
		result = WallManager.paint_wall(WallManager.wall_nodes[wall_id], "tag")
		assert(result["ok"])
	shares = TerritoryManager.influence(district_id)
	assert(shares["player"] >= 0.5)
	assert(TerritoryManager.is_claimed(district_id))
	assert(claims == [district_id])  # threshold reward fires exactly once
	assert(GameState.reputation > rep_before + 150)  # paints + 150 claim bonus
	var caps_fill_count := 0
	for state in WallManager.wall_states.values():
		var graffiti: Dictionary = {}
		if state.get("currentGraffiti") is Dictionary:
			graffiti = state["currentGraffiti"]
		if String(graffiti.get("creatorId", "")) == "npc_rico_caps":
			caps_fill_count += 1
	assert(caps_fill_count > 0)
	print("SMOKE: district claimed, influence = %s" % str(shares))
	print("SMOKE: %s; Caps filled %d spots" % [
		TerritoryManager.summary_text(district_id), caps_fill_count])
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

## Assumes: the mission chain's painting built heat. Heat raises the
## rep payout (Plan.md section 12); city cleanup buffs a wall into
## history (section 33) and repainting it pays the retaliation bonus
## (section 15); heat decays on the simulation tick.
func _smoke_heat_and_cleanup() -> void:
	var district_id := "district_mill_yard"
	assert(HeatManager.heat > 0.0)
	assert(HeatManager.rep_multiplier() > 1.0)
	print("SMOKE: heat=%.1f (%s)" % [HeatManager.heat, HeatManager.level_name()])
	var cleanup_walls: Array = []
	HeatManager.cleanup_event.connect(func(_msg: String, wid: String) -> void:
		cleanup_walls.append(wid))
	var buff_id := "wall_lot_01"
	var result: Dictionary = WallManager.paint_wall(WallManager.wall_nodes[buff_id], "tag")
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

## Assumes: a recruited lookout and moderate heat. Patrol presence
## follows the heat level (Milestone 10, Plan.md sections 12/18/25):
## lookout callouts, line-of-sight spotting, chases, and the catch.
func _smoke_patrols() -> void:
	var player := _smoke_player()
	assert(PatrolManager.guard_count() ==
		PatrolManager.guards_for_level(HeatManager.level_name()))
	var patrol_events: Array = []
	PatrolManager.patrol_event.connect(func(msg: String) -> void:
		patrol_events.append(msg))
	HeatManager.add_heat(100.0)
	assert(HeatManager.level_name() == "Blazing")
	assert(PatrolManager.guard_count() == 3)
	# A recruited lookout calls out patrols near the paint spot
	# (Plan.md section 14: warns player of cops) when nobody saw it land.
	var guard: PatrolGuard = PatrolManager.guards()[0]
	var has_guard_model := guard.get_node_or_null("SecurityBullModel") != null
	var has_guard_capsule := guard.get_node_or_null("CapsuleFallback") != null
	assert(has_guard_model != has_guard_capsule)
	if ResourceLoader.exists(PatrolGuard.WALK_MODEL_PATH) and ResourceLoader.exists(PatrolGuard.RUN_MODEL_PATH):
		assert(has_guard_model)
		for visual_state in ["idle", "walk", "run", "alert", "look_around", "climb"]:
			assert(guard._visual_animation_players.has(visual_state))
			assert(String(guard._visual_animation_names[visual_state]) != "")
	guard.global_position = player.global_position + Vector3(10, 0, 0)
	var result: Dictionary = WallManager.paint_wall(WallManager.wall_nodes["wall_lot_01"], "tag")
	assert(result["ok"])
	assert(not patrol_events.is_empty() and patrol_events[-1].contains("Moth"))
	print("SMOKE: patrol visual = %s" % ("animated security bull" if has_guard_model else "capsule fallback"))
	print("SMOKE: lookout patrol warning = %s" % patrol_events[-1])

	# Spotted: a guard with line of sight to the painter spikes heat and
	# gives chase (section 25: security reacts to painting).
	HeatManager.settle(50.0)
	assert(PatrolManager.guard_count() == 2)
	guard = PatrolManager.guards()[0]
	guard.global_position = player.global_position + Vector3(3, 0, 0)
	guard.look_at(player.global_position + Vector3.UP, Vector3.UP)
	var spotted_guards: Array = []
	PatrolManager.player_spotted.connect(func(g: PatrolGuard) -> void:
		spotted_guards.append(g))
	var heat_before_spot: float = HeatManager.heat
	result = WallManager.paint_wall(WallManager.wall_nodes["wall_lot_01"], "tag")
	assert(result["ok"])
	assert(spotted_guards == [guard])
	assert(guard.is_chasing())
	assert(HeatManager.heat > heat_before_spot)
	print("SMOKE: spotted by patrol, heat %.1f -> %.1f" % [
		heat_before_spot, HeatManager.heat])

	# Metro's getaway role (Milestone 22): the first catch at a heat
	# level becomes a free escape, then the usual fine applies once that
	# route is spent.
	var caught_guards: Array = []
	PatrolManager.player_caught.connect(func(g: PatrolGuard) -> void:
		caught_guards.append(g))
	var rep_before_catch: int = GameState.reputation
	var paint_before_catch: int = GameState.paint
	PatrolManager.resolve_catch(guard)
	assert(caught_guards.is_empty())
	assert(GameState.reputation == rep_before_catch)
	assert(GameState.paint == paint_before_catch)
	assert(CrewManager._getaway_used_levels.has("Hot"))
	guard.start_chase(player)
	PatrolManager.resolve_catch(guard)
	assert(caught_guards == [guard])
	assert(GameState.reputation == rep_before_catch - mini(25, rep_before_catch))
	assert(GameState.paint == paint_before_catch - mini(3, paint_before_catch))
	assert(HeatManager.heat <= 25.0)
	assert(PatrolManager.guard_count() ==
		PatrolManager.guards_for_level(HeatManager.level_name()))
	print("SMOKE: Metro escape, then caught — rep %d -> %d, paint %d -> %d, heat %.1f, guards %d" % [
		rep_before_catch, GameState.reputation, paint_before_catch,
		GameState.paint, HeatManager.heat, PatrolManager.guard_count()])

## Assumes: a played world (rep, painted walls, recruited crew). Saves
## to disk, mutates important runtime state, then loads and proves the
## saved wall/progression/player state comes back (Milestone 8).
func _smoke_save_load() -> void:
	var player := _smoke_player()
	var first_id := _first_wall_id()
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

## Assumes: the full mission chain paid out exactly $25 starting + $15
## (m1) + $15 (m4) + $50 (m5) = $105 and nothing else spent cash.
## Exercises Lupe's shop, the fat cap discount, rare colors, the
## delivery run, and the supply save/load round trip (Milestone 11).
func _smoke_supplies() -> void:
	assert(GameState.cash == 105)
	var cash_now: int = GameState.cash
	var paint_now: int = GameState.paint
	assert(SupplyManager.buy("paint_pack")["ok"])
	assert(GameState.paint == paint_now + 10)
	assert(GameState.cash == cash_now - 12)
	# The fat cap discounts bigger work but never below 1 paint.
	assert(SupplyManager.paint_cost(WallManager.styles["piece"]) == 6)
	assert(SupplyManager.buy("fat_cap")["ok"])
	assert(SupplyManager.paint_cost(WallManager.styles["piece"]) == 5)
	assert(SupplyManager.paint_cost(WallManager.styles["throwup"]) == 2)
	assert(SupplyManager.paint_cost(WallManager.styles["tag"]) == 1)
	assert(not SupplyManager.buy("fat_cap")["ok"])  # one-time upgrade
	# A rare color joins the palette and gets selected.
	var palette_size: int = GameState.fill_palette().size()
	assert(SupplyManager.buy("burner_chrome")["ok"])
	assert(GameState.fill_palette().size() == palette_size + 1)
	assert(GameState.current_fill_color_name() == "Burner Chrome")
	# Painting actually spends the discounted cost.
	paint_now = GameState.paint
	var result: Dictionary = WallManager.paint_wall(WallManager.wall_nodes["wall_median_01"], "piece")
	assert(result["ok"])
	assert(GameState.paint == paint_now - 5)
	# Broke writers get turned away.
	var stash: int = GameState.cash
	assert(GameState.try_spend_cash(stash))
	assert(not SupplyManager.buy("paint_pack")["ok"])
	GameState.add_cash(stash)
	print("SMOKE: shop OK — cash $%d, palette %d colors" % [
		GameState.cash, GameState.fill_palette().size()])

	# Delivery run: repeatable income that draws heat (Plan.md section
	# 15 "Supply Run" / section 12 heat sources).
	assert(SupplyManager.start_delivery())
	assert(not SupplyManager.start_delivery())  # one package at a time
	assert(SupplyManager._drop_zone != null)
	cash_now = GameState.cash
	var heat_now: float = HeatManager.heat
	SupplyManager.resolve_delivery()
	assert(not SupplyManager.delivery_active)
	assert(GameState.cash == cash_now + 25)
	assert(HeatManager.heat > heat_now)
	print("SMOKE: delivery run paid $25, heat %.1f -> %.1f" % [heat_now, HeatManager.heat])

	# Supplies survive the save/load round trip.
	assert(SaveManager.quick_save())
	var saved_cash: int = GameState.cash
	GameState.cash = 0
	GameState.extra_fill_colors.clear()
	SupplyManager.owned.clear()
	assert(SaveManager.quick_load())
	assert(GameState.cash == saved_cash)
	assert(GameState.fill_palette().size() == palette_size + 1)
	assert(SupplyManager.is_owned("fat_cap"))
	print("SMOKE: supply state survives save/load")

## Assumes: rank is at least Known (the chain finished) and Moth is
## recruited. Milestone 12 dialogue: rank-gated one-time lessons,
## Lupe's routes into the shop/delivery systems, and flag persistence.
func _smoke_dialogue() -> void:
	var player := _smoke_player()
	var prime_actor := get_node_or_null("prime")
	assert(prime_actor != null)
	var prime_visuals: Dictionary = MissionManager.actor_defs[2].get("visuals", {})
	if not prime_visuals.is_empty() \
			and ResourceLoader.exists(String(prime_visuals["states"]["idle"]["model"])):
		assert(prime_actor.get_node_or_null("PrimeGoriModel") != null)
		assert(prime_actor.get_node_or_null("PrimeBlackbook") != null)
	assert(DialogueManager.start("prime"))
	assert(DialogueManager.is_active())
	assert(DialogueManager.current_node()["speaker"] == "Prime")
	var dialogue_choices: Array = DialogueManager.visible_choices()
	assert(dialogue_choices.size() == 3)
	assert(not dialogue_choices[1]["locked"])  # Block King >= Known
	var real_rank: String = GameState.rank
	GameState.rank = "Toy"
	assert(DialogueManager.visible_choices()[1]["locked"])
	assert(not DialogueManager.choose(1))  # locked choices refuse
	GameState.rank = real_rank
	var rep_before_lesson: int = GameState.reputation
	assert(DialogueManager.choose(1))
	assert(GameState.reputation == rep_before_lesson + 40)
	assert(DialogueManager.flags.get("prime_lesson", false))
	assert(DialogueManager.choose(0))  # "Thank you" ends the chat
	assert(not DialogueManager.is_active())
	# Re-taking the lesson pays nothing — it's a lesson, not a faucet.
	rep_before_lesson = GameState.reputation
	assert(DialogueManager.start("prime"))
	assert(DialogueManager.choose(1))
	assert(GameState.reputation == rep_before_lesson)
	DialogueManager.end_dialogue()
	print("SMOKE: Prime dialogue — rank gate + one-time lesson OK")

	# Lupe's tree routes into the shop and delivery systems.
	assert(DialogueManager.start("lupe", player))
	assert(DialogueManager.choose(0))  # "Show me the catalog."
	assert(not DialogueManager.is_active())
	assert(SupplyManager.is_shop_open())
	SupplyManager.close_shop()
	assert(DialogueManager.start("lupe", player))
	assert(DialogueManager.choose(1))  # "Got work for me?"
	assert(not DialogueManager.is_active())
	assert(SupplyManager.delivery_active)
	SupplyManager.resolve_delivery()
	# Moth chats through her tree once recruited.
	assert(DialogueManager.start("moth"))
	assert(DialogueManager.current_node()["speaker"] == "Moth")
	assert(DialogueManager.choose(1))  # the blackbook story
	assert(DialogueManager.current_node()["text"].contains("outlines"))
	DialogueManager.end_dialogue()
	print("SMOKE: Lupe dialogue routes to shop/delivery; Moth chats")

	# Dialogue flags survive the save/load round trip.
	assert(SaveManager.quick_save())
	DialogueManager.flags.clear()
	assert(SaveManager.quick_load())
	assert(DialogueManager.flags.get("prime_lesson", false))
	print("SMOKE: dialogue flags survive save/load")

## Assumes: a played world (Burner Chrome bought, Moth recruited, walls
## held). Milestone 13: blackbook page text builds purely from the
## managers, so read it without touching the HUD.
func _smoke_blackbook() -> void:
	var blackbook = preload("res://Scripts/UI/blackbook_panel.gd").new()
	var writer_page: String = blackbook.page_text(0)
	assert(writer_page.contains(GameState.alias))
	assert(writer_page.contains(GameState.rank))
	assert(writer_page.contains("Mill Yard"))
	var styles_page: String = blackbook.page_text(1)
	assert(styles_page.contains("Tag") and styles_page.contains("Piece"))
	assert(styles_page.contains("Burner Chrome"))  # bought rare color listed
	var crew_page: String = blackbook.page_text(2)
	assert(crew_page.contains("Moth") and crew_page.contains("Recruited"))
	assert(crew_page.contains("Caps") and crew_page.contains("Filler"))
	assert(crew_page.contains("Metro") and crew_page.contains("Getaway"))
	var city_page: String = blackbook.page_text(3)
	assert(city_page.contains("The Buff Kings") and city_page.contains("VEK"))
	assert(city_page.contains("Your name is on"))
	blackbook.free()
	print("SMOKE: blackbook pages — writer/styles/crew/city all read")

## Assumes: the piece can is unlocked and at least two fill colors are
## owned. Milestone 14 freehand: the canvas model works off-tree, the
## style multiplier prices the work, the image survives save/load, and
## repaints archive the metadata without the image payload.
func _smoke_freehand() -> void:
	var freehand = preload("res://Scripts/UI/freehand_panel.gd").new()
	var fh_wall: PaintableWall = WallManager.wall_nodes["wall_bodega_01"]
	freehand.begin(fh_wall)
	var canvas: Image = freehand.image
	assert(canvas != null and canvas.get_width() > 0)
	for i in 60:
		freehand.spray_at(Vector2(
			(i % 10 + 0.5) / 10.0 * canvas.get_width(),
			(floorf(i / 10.0) + 0.5) / 6.0 * canvas.get_height()))
	GameState.cycle_fill_color()
	for i in 20:
		freehand.spray_at(Vector2(canvas.get_width() * 0.5, canvas.get_height() * 0.5))
	var art: Dictionary = freehand.result()
	freehand.free()
	assert(int(art["colors_used"]) == 2)
	assert(float(art["coverage"]) > 0.2)
	var style_mult: float = WallManager.freehand_style_multiplier(
		int(art["colors_used"]), float(art["coverage"]))
	assert(style_mult > 1.0)  # two colors + real coverage beats a stock piece
	var plain_piece: int = WallManager._reputation_for(
		WallManager.styles["piece"], fh_wall.def)
	var paint_before_fh: int = GameState.paint
	var rep_before_fh: int = GameState.reputation
	var fh_result: Dictionary = WallManager.paint_freehand(
		fh_wall, art["image"], int(art["colors_used"]), float(art["coverage"]))
	assert(fh_result["ok"])
	assert(int(fh_result["rep"]) == int(round(plain_piece * style_mult)))
	assert(GameState.paint == paint_before_fh - SupplyManager.paint_cost(WallManager.styles["piece"]))
	assert(GameState.reputation == rep_before_fh + int(fh_result["rep"]))
	var fh_state: Dictionary = WallManager.wall_states["wall_bodega_01"]
	assert(fh_state["state"] == "player_piece")
	assert(fh_state["ownerCrewId"] == "player")
	assert(fh_state["currentGraffiti"]["freehand"])
	assert(String(fh_state["currentGraffiti"]["image"]) != "")
	# The sprayed image survives the save/load round trip and decodes.
	assert(SaveManager.quick_save())
	assert(WallManager.buff_wall("wall_bodega_01"))
	assert(fh_state["currentGraffiti"] == null)
	assert(SaveManager.quick_load())
	fh_state = WallManager.wall_states["wall_bodega_01"]
	assert(fh_state["currentGraffiti"]["freehand"])
	var decoded := Image.new()
	assert(decoded.load_png_from_buffer(Marshalls.base64_to_raw(
		String(fh_state["currentGraffiti"]["image"]))) == OK)
	assert(decoded.get_width() == canvas.get_width())
	# Repainting archives the freehand work without its image payload —
	# walls remember (Plan.md section 9), saves don't bloat.
	var result: Dictionary = WallManager.paint_wall(WallManager.wall_nodes["wall_bodega_01"], "tag")
	assert(result["ok"])
	assert(fh_state["history"][-1].get("freehand", false))
	assert(not fh_state["history"][-1].has("image"))
	print("SMOKE: freehand piece — style x%.2f, +%d rep, image survives save/load" % [
		style_mult, int(fh_result["rep"])])

## Assumes: the mission chain is done (m5 unlocked roller/mural), Moth
## is recruited, the stencil kit is not yet bought, and cash covers it.
## Milestone 16 (Plan.md §8/§9): stencil gates behind Lupe's kit,
## rollers only go on rooftop surfaces, murals need crew present and
## expose the writer to patrols for longer, and rivals fall back to a
## throw-up where surface rules block their signature type.
func _smoke_graffiti_types() -> void:
	var player := _smoke_player()
	# m5 unlocked the big cans; the stencil still needs gear.
	assert(GameState.is_type_unlocked("roller"))
	assert(GameState.is_type_unlocked("mural"))
	assert(not GameState.is_type_unlocked("stencil"))
	GameState.add_paint(60)
	var wall: PaintableWall = WallManager.wall_nodes["wall_corner_01"]
	var result: Dictionary = WallManager.paint_wall(wall, "stencil")
	assert(not result["ok"])
	assert(SupplyManager.buy("stencil_kit")["ok"])
	assert(GameState.is_type_unlocked("stencil"))
	result = WallManager.paint_wall(wall, "stencil")
	assert(result["ok"])
	assert(WallManager.wall_states["wall_corner_01"]["state"] == "player_stencil")
	# Number keys select cans in canonical style order (slot refactor).
	GameState.select_type_slot(3)  # tag, throwup, piece, stencil, ...
	assert(GameState.selected_graffiti_type == "stencil")
	GameState.select_type_slot(0)
	assert(GameState.selected_graffiti_type == "tag")
	# Rollers are rooftop-only; the parapet takes one.
	result = WallManager.paint_wall(wall, "roller")
	assert(not result["ok"] and String(result["reason"]).contains("rooftop"))
	var roof: PaintableWall = WallManager.wall_nodes["wall_roof_mill_01"]
	result = WallManager.paint_wall(roof, "roller")
	assert(result["ok"])
	assert(WallManager.wall_states["wall_roof_mill_01"]["state"] == "player_roller")
	# Murals need crew on the street with you.
	var saved_stages := {}
	for member_id in CrewManager.members:
		saved_stages[member_id] = String(CrewManager.members[member_id]["stage"])
		CrewManager.members[member_id]["stage"] = "mission_active"
	result = WallManager.paint_wall(wall, "mural")
	assert(not result["ok"] and String(result["reason"]).contains("crew"))
	for member_id in saved_stages:
		CrewManager.members[member_id]["stage"] = saved_stages[member_id]
	var rep_before: int = GameState.reputation
	var crew_rep_before: int = GameState.crew_rep
	result = WallManager.paint_wall(wall, "mural")
	assert(result["ok"])
	assert(GameState.reputation == rep_before + int(result["rep"]))
	# Crew-backed work pays crew standing too (§11 split, Milestone 21).
	assert(GameState.crew_rep == crew_rep_before + WallManager.CREW_WORK_CREW_REP)
	assert(WallManager.wall_states["wall_corner_01"]["state"] == "player_mural")
	print("SMOKE: stencil/roller/mural painted — gates all enforced")

	# Long exposure: a guard outside normal spot range (and facing away)
	# misses a quick tag but clocks a mural going up (exposure 2x).
	HeatManager.settle(5.0)
	assert(PatrolManager.guard_count() == 1)
	var guard: PatrolGuard = PatrolManager.guards()[0]
	guard.end_chase()
	guard.global_position = player.global_position + Vector3(12, 0, 0)
	guard.look_at(guard.global_position + Vector3(12, 0, 0), Vector3.UP)
	assert(not guard.can_see(player))
	var spotted: Array = []
	PatrolManager.player_spotted.connect(func(g: PatrolGuard) -> void:
		spotted.append(g))
	result = WallManager.paint_wall(wall, "tag")
	assert(result["ok"] and spotted.is_empty())
	result = WallManager.paint_wall(wall, "mural")
	assert(result["ok"])
	assert(spotted == [guard])
	guard.end_chase()
	HeatManager.settle(10.0)
	print("SMOKE: mural exposure — unseen tag, clocked mural")

	# Rivals play by surface rules: Ghost Line's stencil claim landed at
	# startup, and a blocked signature type falls back to a throw-up.
	assert(WallManager.wall_states["wall_alley_n_01"]["state"] == "rival_stencil")
	var saints: Dictionary = RivalManager.crews["chrome_saints"]
	var saved_response := String(saints["responseType"])
	saints["responseType"] = "roller"  # blocked on the corner store's brick
	RivalManager.respond("wall_corner_01", "chrome_saints")
	assert(WallManager.wall_states["wall_corner_01"]["state"] == "rival_throwup")
	saints["responseType"] = saved_response
	print("SMOKE: rival surface fallback — roller response became a throw-up")

## Assumes: a whole run of painting/deliveries behind us (stats earned
## XP through use) and four rank-ups (Toy → Block King). Milestone 17
## (Plan.md §5/§6/§7/§11): stats level by doing and change the math,
## perks spend rank-up points (max two per tree), standing work pays
## over time while crossed-out work doesn't, unattended districts cool,
## and the save schema bumps to v2 with migration.
func _smoke_progression() -> void:
	# Stats grew through use, not through a menu.
	assert(StatsManager.xp_for("style") > 0)
	assert(StatsManager.xp_for("stealth") > 0)
	assert(StatsManager.xp_for("hustle") > 0)
	# A Style level-up raises the rep math.
	var def := WallManager.wall_def("wall_lot_01")
	var tag_style: Dictionary = WallManager.styles["tag"]
	var level_before := StatsManager.level("style")
	var rep_plain: int = WallManager._reputation_for(tag_style, def)
	StatsManager.add_xp("style", int(StatsManager.stat_defs["style"]["xpPerLevel"]))
	assert(StatsManager.level("style") == level_before + 1)
	assert(WallManager._reputation_for(tag_style, def) > rep_plain)
	# Four rank-ups banked four perk points; one option per tree.
	assert(StatsManager.perk_points == 4)
	var options: Array = StatsManager.choosable_perks()
	assert(options.size() == 5)
	# Street Respect dampens rival retaliation.
	var chance_before := RivalManager.response_chance("wall_mill_02", "buff_kings")
	assert(StatsManager.choose_perk("street_respect"))
	assert(RivalManager.response_chance("wall_mill_02", "buff_kings") < chance_before)
	assert(not StatsManager.choose_perk("street_respect"))  # already owned
	assert(not StatsManager.choose_perk("burner_hand"))  # tree's first perk unpicked
	# The Connect cuts Lupe's prices (12 -> 11 on the paint pack).
	assert(StatsManager.choose_perk("connect"))
	assert(StatsManager.perk_points == 2)
	var cash_before: int = GameState.cash
	assert(SupplyManager.buy("paint_pack")["ok"])
	assert(cash_before - GameState.cash == 11)
	# The perks panel reads pure state — drive it off-tree like the
	# other modal models.
	var perks_panel = preload("res://Scripts/UI/perks_panel.gd").new()
	var perks_text: String = perks_panel.page_text()
	assert(perks_text.contains("Street Respect") and perks_text.contains("The Connect"))
	assert(perks_text.contains("Style %d" % StatsManager.level("style")))
	perks_panel.free()
	# §11 visibility over time: standing work pays a trickle each tick…
	var district_id := "district_mill_yard"
	var district: Dictionary = TerritoryManager.districts[district_id]
	assert(TerritoryManager.standing_player_weight(district_id) > 0.0)
	var rep_before_tick: int = GameState.reputation
	TerritoryManager._on_decay_tick()
	assert(GameState.reputation > rep_before_tick)
	# …crossed-out work stops paying…
	var weight_before := TerritoryManager.standing_player_weight(district_id)
	WallManager.cross_out_wall("wall_lot_01", RivalManager.crews["buff_kings"])
	assert(TerritoryManager.standing_player_weight(district_id) < weight_before)
	# …and unattended districts cool (pure decay math, both branches).
	assert(TerritoryManager.decay_amount(district, 0.1) > 0)
	assert(TerritoryManager.decay_amount(district, 0.9) == 0)
	print("SMOKE: stats/perks/decay — style +1 level, 2 perks chosen, block pays")

	# Progression survives save/load, and v1 saves migrate forward.
	assert(SaveManager.SAVE_VERSION >= 2)
	assert(SaveManager.quick_save())
	var saved_xp: int = StatsManager.xp_for("style")
	var saved_points: int = StatsManager.perk_points
	StatsManager.xp["style"] = 0
	StatsManager.perk_points = 0
	StatsManager.perks_owned.clear()
	assert(SaveManager.quick_load())
	assert(StatsManager.xp_for("style") == saved_xp)
	assert(StatsManager.perk_points == saved_points)
	assert(StatsManager.owns_perk("street_respect") and StatsManager.owns_perk("connect"))
	var migrated: Dictionary = SaveManager._migrate({"version": 1})
	assert(int(migrated["version"]) == SaveManager.SAVE_VERSION)
	assert(migrated.has("stats"))
	print("SMOKE: progression survives save/load; v1 saves migrate forward")

## Assumes: the mill chain is done (canal chain waits on its trigger),
## the player stands in Mill Yard, and earlier sections left paint and
## cash to spare. Milestone 18 (Plan.md §45, §12): cross the
## footbridge, run the Canal Side chain (m6–m8) against Ghost Line
## territory, prove heat is per district and cools faster in the block
## you left, and round-trip the v3 save with v2 migration.
func _smoke_canal_side() -> void:
	var player := _smoke_player()
	assert(GameState.current_district_id == "district_mill_yard")
	assert(not TerritoryManager.is_claimed("district_canal_side"))
	# Ghost Line pre-claimed their canal territory in stencils at boot.
	assert(WallManager.wall_states["wall_canal_01"]["state"] == "rival_stencil")
	HeatManager.heat = 12.0
	var mill_heat: float = HeatManager.heat_in("district_mill_yard")
	# Cross the footbridge: arrival spot, district flip, chain trigger.
	var gate := get_node_or_null("TravelPoint_district_canal_side")
	assert(gate != null)
	gate.interact()
	assert(GameState.current_district_id == "district_canal_side")
	assert(player.global_position.distance_to(Vector3(86, 0.5, 0)) < 1.0)
	assert(not MissionManager.chain_done)
	assert(MissionManager.current_mission()["missionId"] == "m6_new_waters")
	# Heat is per district: this block is cold while the mill simmers,
	# and painting here heats Canal Side only.
	assert(HeatManager.heat == 0.0)
	assert(is_equal_approx(HeatManager.heat_in("district_mill_yard"), mill_heat))
	assert(PatrolManager.guard_count() ==
		PatrolManager.guards_for_level(HeatManager.level_name()))
	GameState.add_paint(60)
	var result: Dictionary = WallManager.paint_wall(WallManager.wall_nodes["wall_canal_03"], "tag")
	assert(result["ok"])
	assert(HeatManager.heat > 0.0)
	assert(is_equal_approx(HeatManager.heat_in("district_mill_yard"), mill_heat))
	result = WallManager.paint_wall(WallManager.wall_nodes["wall_canal_04"], "tag")
	assert(result["ok"])
	# m6 done -> m7's scripted Ghost Line hit landed on the last wall.
	assert(MissionManager.current_mission()["missionId"] == "m7_ghosts_in_the_water")
	assert(WallManager.wall_states["wall_canal_04"]["state"] == "crossed_out")
	result = WallManager.paint_wall(WallManager.wall_nodes["wall_canal_04"], "throwup")
	assert(result["ok"])
	assert(MissionManager.current_mission()["missionId"] == "m8_canal_king")
	# m8: take the block — Ghost Line keeps their three walls (7 of 24
	# weight), the rest is enough to cross 50%.
	for wall_id in ["wall_canal_06", "wall_canal_07", "wall_canal_08"]:
		result = WallManager.paint_wall(WallManager.wall_nodes[wall_id], "tag")
		assert(result["ok"])
	assert(TerritoryManager.is_claimed("district_canal_side"))
	# The canal chain is done; rank Known satisfied the gallery chain's
	# rank trigger (Milestone 21), so it activates immediately.
	assert(bool(MissionManager.chains[1].get("done", false)))
	assert(String(MissionManager.current_mission().get("missionId", "")) == "m9_white_walls")
	print("SMOKE: Canal Side chain complete — m6/m7/m8 against Ghost Line")

	# Leaving the block is laying low: the absent district cools at
	# double rate on the tick.
	HeatManager.heat = 40.0  # canal (current district)
	var back := get_node_or_null("TravelPoint_district_mill_yard")
	assert(back != null)
	back.interact()
	assert(GameState.current_district_id == "district_mill_yard")
	HeatManager.heat = 20.0  # mill (current district)
	HeatManager._on_tick()
	assert(is_equal_approx(HeatManager.heat_in("district_mill_yard"), 18.0))
	assert(is_equal_approx(HeatManager.heat_in("district_canal_side"), 36.0))
	print("SMOKE: per-district heat — present block -2, absent block -4")

	# v3 save shape still migrates under the current schema:
	# per-district heat, district, and chain state round-trip; v2 saves
	# migrate heat into Mill Yard and painted keys gain chain 0.
	assert(SaveManager.SAVE_VERSION >= 3)
	assert(SaveManager.quick_save())
	HeatManager.heat_by_district.clear()
	GameState.set_district("district_canal_side")
	assert(SaveManager.quick_load())
	assert(GameState.current_district_id == "district_mill_yard")
	assert(is_equal_approx(HeatManager.heat_in("district_canal_side"), 36.0))
	assert(String(MissionManager.current_mission().get("missionId", "")) == "m9_white_walls")
	var migrated: Dictionary = SaveManager._migrate({"version": 2,
		"heat": {"heat": 33.0, "ticks_until_cleanup": 2},
		"missions": {"began": true, "chain_done": true,
			"painted_objectives": {"1:0": ["wall_mill_01"]}}})
	assert(int(migrated["version"]) == SaveManager.SAVE_VERSION)
	assert(is_equal_approx(float(migrated["heat"]["by_district"]["district_mill_yard"]), 33.0))
	assert(migrated["missions"]["painted_objectives"].has("0:1:0"))
	print("SMOKE: v3 save round-trips; v2 saves migrate forward")

## Assumes: the player is back in Mill Yard with the roller unlocked
## and at least one guard on the block. Milestone 19: the climb is the
## risk — a fall takes the caught-equivalent rep fine, a clean climb
## reaches the Milestone 16 rooftop roller spot, and a chasing guard
## gives up when the writer holds the high ground.
func _smoke_rooftop_climbing() -> void:
	var player := _smoke_player()
	var climb := get_node_or_null("ClimbZone_climb_mill_west")
	assert(climb != null)
	# A slip costs rep — the street saw you eat it.
	var rep_before: int = GameState.reputation
	climb.resolve(false)
	assert(GameState.reputation == rep_before - mini(20, rep_before))
	# A clean climb puts the writer on the Mill West roof…
	climb.resolve(true)
	assert(player.global_position.distance_to(Vector3(-9, 10.6, -9.5)) < 1.0)
	# …at the rooftop parapet, in roller range.
	GameState.add_paint(20)
	var result: Dictionary = WallManager.paint_wall(
		WallManager.wall_nodes["wall_roof_mill_01"], "roller")
	assert(result["ok"])
	# Security won't climb: a chasing guard gives up on the spot.
	assert(PatrolManager.guard_count() >= 1)
	var guard: PatrolGuard = PatrolManager.guards()[0]
	guard.start_chase(player)
	assert(guard.is_chasing())
	var escaped := [false]
	PatrolManager.chase_escaped.connect(func() -> void: escaped[0] = true)
	guard._chase(0.016)
	assert(not guard.is_chasing())
	assert(escaped[0])
	assert(guard._action_visual_state == "climb")
	print("SMOKE: rooftop climbing — fall fine, roller from the roof, guard climb clip")
	# Back to street level for the sections that follow.
	player.global_position = PLAYER_SPAWN

## Assumes: the Canal Side chain is done, the player can spare paint,
## and train cars spawned. Milestone 20: paint a stopped car in the
## Canal Side yard, then let the schedule roll it through both known
## districts for visibility-over-time rep and save/load persistence.
func _smoke_train_painting() -> void:
	var train_id := "canal_ghost_local"
	var car := get_node_or_null("TrainCar_%s" % train_id)
	assert(car != null)
	var state: Dictionary = TrainManager.state_for(train_id)
	assert(String(state.get("phase", "")) == "stopped")
	assert(state.get("currentGraffiti") == null)
	GameState.add_paint(20)
	var paint_before: int = GameState.paint
	var rep_before: int = GameState.reputation
	var heat_before: float = HeatManager.heat_in("district_canal_side")
	var result: Dictionary = TrainManager.paint_train(train_id)
	assert(result["ok"])
	assert(GameState.paint == paint_before - int(TrainManager.train_def(train_id)["paintCost"]))
	assert(GameState.reputation == rep_before + int(result["rep"]))
	assert(HeatManager.heat_in("district_canal_side") > heat_before)
	assert(state["currentGraffiti"]["alias"] == GameState.alias)
	assert(not TrainManager.paint_train(train_id)["ok"])
	var pass_events: Array = []
	TrainManager.train_passed.connect(func(tid: String, did: String, rep: int) -> void:
		pass_events.append([tid, did, rep]))
	rep_before = GameState.reputation
	for i in int(TrainManager.train_def(train_id)["stopTicks"]):
		TrainManager._on_tick()
	assert(String(state.get("phase", "")) == "passing")
	assert(pass_events.size() == 2)
	assert(pass_events[0][1] == "district_canal_side")
	assert(pass_events[1][1] == "district_mill_yard")
	assert(GameState.reputation == rep_before + int(TrainManager.train_def(train_id)["passRep"]) * 2)
	assert(int(state["currentGraffiti"]["passes"]) == 2)
	var blackbook = preload("res://Scripts/UI/blackbook_panel.gd").new()
	var city_page: String = blackbook.page_text(3)
	assert(city_page.contains("Ghost Local") and city_page.contains("passes 2"))
	blackbook.free()
	assert(SaveManager.SAVE_VERSION >= 4)
	assert(SaveManager.quick_save())
	state["currentGraffiti"] = null
	assert(SaveManager.quick_load())
	state = TrainManager.state_for(train_id)
	assert(state["currentGraffiti"]["alias"] == GameState.alias)
	var migrated: Dictionary = SaveManager._migrate({"version": 3})
	assert(int(migrated["version"]) == SaveManager.SAVE_VERSION)
	assert(migrated.has("trains"))
	print("SMOKE: train painting — car painted, pass-through rep paid, v4 state saved")

## Assumes: rank is Known+ (mill chain), the canal chain is done (the
## gallery chain activated on its rank trigger), the piece can is
## unlocked, and at least two fill colors are owned. Milestone 21
## (Plan.md §18, §43): Vesper buys freehand canvases — the style
## multiplier is the judge's score, a sale pays cash + public rep and
## costs crew rep, and weak work is refused.
func _smoke_gallery() -> void:
	# The rank-triggered chain wants a meeting at the dry dock.
	assert(String(MissionManager.current_mission().get("missionId", "")) == "m9_white_walls")
	assert(MissionManager.current_objective()["type"] == "talk")
	var vesper := get_node_or_null("vesper")
	assert(vesper != null)
	assert(vesper.visible)  # the rank gate opened when the writer hit Known
	# Below Known the scout hides and the gallery won't deal.
	var real_rank: String = GameState.rank
	GameState.rank = "Toy"
	vesper._refresh_rank_gate()
	assert(not vesper.visible)
	assert(not GalleryManager.start_commission())
	GameState.rank = real_rank
	vesper._refresh_rank_gate()
	assert(vesper.visible)
	assert(MissionManager.notify_actor("vesper"))
	assert(MissionManager.current_objective()["type"] == "gallery_sale")

	# A lazy scribble gets refused: paint spent, nothing paid, crew rep
	# untouched — you didn't sell out, you just embarrassed yourself.
	GameState.add_paint(20)
	var freehand = preload("res://Scripts/UI/freehand_panel.gd").new()
	assert(GalleryManager.start_commission())
	assert(not GalleryManager.start_commission())  # one easel at a time
	var size: Array = GalleryManager.config["canvasSize"]
	freehand.begin_canvas("smoke gallery canvas", Vector2(size[0], size[1]))
	freehand.spray_at(Vector2(8, 8))
	var weak: Dictionary = freehand.result()
	var paint_before: int = GameState.paint
	var cash_before: int = GameState.cash
	var rep_before: int = GameState.reputation
	var crew_before: int = GameState.crew_rep
	var result: Dictionary = GalleryManager.submit(
		weak["image"], int(weak["colors_used"]), float(weak["coverage"]))
	assert(result["ok"] and not result["accepted"])
	assert(GameState.paint == paint_before - SupplyManager.paint_cost(WallManager.styles["piece"]))
	assert(GameState.cash == cash_before and GameState.reputation == rep_before)
	assert(GameState.crew_rep == crew_before)
	assert(MissionManager.current_objective()["type"] == "gallery_sale")  # no sale, no progress

	# A real canvas sells: the score is the freehand style multiplier,
	# cash scales with Hustle like other income, public rep rises, and
	# crew rep takes the §18 art-world hit.
	assert(GalleryManager.start_commission())
	freehand.begin_canvas("smoke gallery canvas", Vector2(size[0], size[1]))
	var canvas: Image = freehand.image
	for i in 60:
		freehand.spray_at(Vector2(
			(i % 10 + 0.5) / 10.0 * canvas.get_width(),
			(floorf(i / 10.0) + 0.5) / 6.0 * canvas.get_height()))
	GameState.cycle_fill_color()
	for i in 20:
		freehand.spray_at(Vector2(canvas.get_width() * 0.5, canvas.get_height() * 0.5))
	var art: Dictionary = freehand.result()
	freehand.free()
	var score: float = WallManager.freehand_style_multiplier(
		int(art["colors_used"]), float(art["coverage"]))
	assert(score >= float(GalleryManager.config["acceptScore"]))
	cash_before = GameState.cash
	rep_before = GameState.reputation
	crew_before = GameState.crew_rep
	# Expected price uses the Hustle multiplier as it stands *before*
	# the sale — the sale itself pays Hustle XP and can level it up.
	var expected_cash := roundi(
		float(GalleryManager.config["basePay"]) * score * StatsManager.delivery_multiplier())
	result = GalleryManager.submit(art["image"], int(art["colors_used"]), float(art["coverage"]))
	assert(result["ok"] and result["accepted"])
	assert(is_equal_approx(float(result["score"]), score))
	assert(int(result["cash"]) == expected_cash)
	# The sale price plus m9's $40 completion bonus (paid inside submit
	# via notify_gallery_sale -> mission onComplete).
	assert(GameState.cash == cash_before + 40 + expected_cash)
	assert(GameState.reputation == rep_before + roundi(
		float(GalleryManager.config["repBase"]) * score))
	assert(GameState.crew_rep == crew_before - int(GalleryManager.config["crewRepCost"]))
	assert(GalleryManager.sales_count() == 1)
	# The sale completes the gallery mission — every chain is now done.
	assert(MissionManager.all_chains_done())
	# The blackbook shows both sides of the split.
	var blackbook = preload("res://Scripts/UI/blackbook_panel.gd").new()
	assert(blackbook.page_text(0).contains("Crew rep"))
	assert(blackbook.page_text(3).contains("Gallery sales: 1"))
	blackbook.free()

	# Gallery state and the rep split survive save/load; v4 saves migrate
	# through the gallery and crew-depth schema bumps.
	assert(SaveManager.SAVE_VERSION == 6)
	assert(SaveManager.quick_save())
	var saved_crew: int = GameState.crew_rep
	GameState.crew_rep = 0
	GalleryManager.sales.clear()
	assert(SaveManager.quick_load())
	assert(GameState.crew_rep == saved_crew)
	assert(GalleryManager.sales_count() == 1)
	var migrated: Dictionary = SaveManager._migrate({"version": 4, "game": {}})
	assert(int(migrated["version"]) == SaveManager.SAVE_VERSION)
	assert(migrated.has("gallery"))
	assert(migrated.has("crew") and migrated["crew"].has("getaway_used_levels"))
	assert(int(migrated["game"]["crew_rep"]) == 0)
	print("SMOKE: gallery — refusal, sale (score x%.2f), crew rep split, v6 save" % score)

## Assumes: nothing beyond a paintable wall. Plan_v2.md §3.5: wall
## history is capped — repainting past the cap drops the oldest
## entries instead of growing the save forever.
func _smoke_history_cap() -> void:
	var wall_id := "wall_lot_01"
	var wall: PaintableWall = WallManager.wall_nodes[wall_id]
	var state: Dictionary = WallManager.wall_states[wall_id]
	GameState.add_paint(WallManager.MAX_WALL_HISTORY + 5)
	for i in WallManager.MAX_WALL_HISTORY + 5:
		assert(WallManager.paint_wall(wall, "tag")["ok"])
	assert(state["history"].size() == WallManager.MAX_WALL_HISTORY)
	assert(state["history"][-1]["type"] == "tag")  # newest entry survived
	print("SMOKE: wall history capped at %d entries" % WallManager.MAX_WALL_HISTORY)

## Assumes: data-driven ambient locals are spawned in both current
## districts. Milestone 25: locals walk waypoint loops, pause for fresh
## player work once per wall for a tiny crowd-reaction rep tick, and
## scatter when the block jumps to Hot heat.
func _smoke_ambient_npc_life() -> void:
	GameState.set_district("district_mill_yard")
	var local := get_node("local_mill_01")
	var canal_local := get_node("local_canal_02")
	assert(local != null and canal_local != null)
	assert(local.walking_speed() > 0.0 and canal_local.walking_speed() > 0.0)
	GameState.add_paint(3)
	var rep_before: int = GameState.reputation
	var wall: PaintableWall = WallManager.wall_nodes["wall_mill_01"]
	var result: Dictionary = WallManager.paint_wall(wall, "tag")
	assert(result["ok"])
	assert(local.crowd_target_wall_id() == "wall_mill_01")
	local.global_position = wall.global_position
	local._physics_process(0.016)
	assert(GameState.reputation == rep_before + int(result["rep"]) + 1)
	assert(local.crowd_target_wall_id() == "")
	GameState.add_paint(3)
	var repeat_rep_before: int = GameState.reputation
	var repeat_result: Dictionary = WallManager.paint_wall(wall, "tag")
	assert(repeat_result["ok"])
	assert(local.crowd_target_wall_id() == "")
	assert(GameState.reputation == repeat_rep_before + int(repeat_result["rep"]))
	GameState.add_paint(3)
	var second_wall: PaintableWall = WallManager.wall_nodes["wall_mill_02"]
	local.global_position = second_wall.global_position
	assert(WallManager.paint_wall(second_wall, "tag")["ok"])
	assert(local.crowd_target_wall_id() == "wall_mill_02")
	HeatManager.heat = 0.0
	HeatManager.add_heat(65.0)
	assert(local.crowd_target_wall_id() == "")
	print("SMOKE: ambient NPC life — locals react to paint and scatter at Hot heat")

## Assumes: player exists. The Kronako Iconz rooster GLB replaces the
## debug capsule; player.gd prefers the animated action GLBs
## and falls back to the static GLB/capsule when imports are unavailable, so
## assert the visual that the import state implies.
func _smoke_player_model() -> void:
	var player := _smoke_player()
	var has_model := player.get_node_or_null("CharacterModel") != null
	var has_capsule := player.get_node_or_null("CapsuleFallback") != null
	assert(has_model != has_capsule)  # exactly one visual
	if ResourceLoader.exists(Player.WALK_MODEL_PATH) and ResourceLoader.exists(Player.RUN_MODEL_PATH):
		assert(has_model)
		for state in ["idle", "walk", "walk_back", "run", "run_fast", "jump", "climb", "vault"]:
			assert(player._visual_animation_players.has(state))
			assert(String(player._visual_animation_names[state]) != "")
	print("SMOKE: player visual = %s" % ("animated rooster action set" if has_model else "capsule fallback"))
