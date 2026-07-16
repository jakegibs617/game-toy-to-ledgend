extends StaticBody3D
## Climb zone (Milestone 19, ROADMAP.md §4): a drainpipe/ladder spot at
## the foot of a building. E attempts the climb — make it and you're on
## the roof (where the roller spots from Milestone 16 live); slip and
## you take the caught-equivalent fine (ROADMAP.md: the risk shifts
## from patrols to the climb itself — security won't follow you up).
## `resolve(success)` is split from the interact() roll so the smoke
## test can drive both outcomes deterministically.

var def: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func setup(climb_def: Dictionary) -> void:
	def = climb_def
	name = "ClimbZone_%s" % String(def.get("climbId", "climb"))
	var pos: Array = def.get("position", [0, 0, 0])
	position = Vector3(pos[0], pos[1], pos[2])
	_rng.randomize()

	# An actual rail-and-rung ladder up the wall face marks the route
	# (Product_reqs ladder feature) instead of the old slim pipe hint. The
	# ladder is vertical along the height rise; `top` may sit far off
	# horizontally (it is the landing the climb steps onto on summit).
	var top: Array = def.get("top", [0, 8, 0])
	_build_ladder(float(top[1]) - position.y)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 2.2, 1.0)
	col.shape = shape
	col.position = Vector3(0, 1.1, 0)
	add_child(col)

	var sign_label := Label3D.new()
	sign_label.text = String(def.get("label", "CLIMB"))
	sign_label.font_size = 40
	sign_label.outline_size = 10
	sign_label.pixel_size = 0.005
	sign_label.position = Vector3(0, 2.6, 0)
	sign_label.modulate = Color("#7be05a")
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(sign_label)

## Builds a vertical rail-and-rung ladder spanning the height rise from the
## foot. `span` is the signed exit height (negative for a descent route);
## a near-zero span still draws a short ladder so the route reads.
func _build_ladder(span: float) -> void:
	var y_low := minf(0.0, span)
	var y_high := maxf(0.0, span)
	if y_high - y_low < 2.0:
		y_high = y_low + 2.0
	var length := y_high - y_low
	var mid := (y_low + y_high) / 2.0
	var ladder := Node3D.new()
	ladder.name = "Ladder"
	# Set back 0.4 m against the wall face, as the old pipe hint was.
	ladder.position = Vector3(0, 0, -0.4)
	add_child(ladder)

	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color("#2c352c")
	rail_mat.emission_enabled = true
	rail_mat.emission = Color("#7be05a")
	rail_mat.emission_energy_multiplier = 0.3
	var rung_mat := StandardMaterial3D.new()
	rung_mat.albedo_color = Color("#3d4a3d")
	rung_mat.emission_enabled = true
	rung_mat.emission = Color("#7be05a")
	rung_mat.emission_energy_multiplier = 0.5

	const RAIL_OFFSET := 0.24
	_add_bar(ladder, Vector3(0.08, length, 0.08),
		Vector3(-RAIL_OFFSET, mid, 0), rail_mat)
	_add_bar(ladder, Vector3(0.08, length, 0.08),
		Vector3(RAIL_OFFSET, mid, 0), rail_mat)
	var rung_spacing := 0.45
	var rungs := maxi(int(length / rung_spacing), 1)
	for i in range(rungs + 1):
		var y := minf(y_low + float(i) * rung_spacing, y_high)
		_add_bar(ladder, Vector3(RAIL_OFFSET * 2.0 + 0.08, 0.06, 0.06),
			Vector3(0, y, 0), rung_mat)

func _add_bar(parent: Node3D, size: Vector3, pos: Vector3,
		mat: StandardMaterial3D) -> void:
	var bar := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	bar.mesh = mesh
	bar.position = pos
	bar.material_override = mat
	parent.add_child(bar)

func prompt_text() -> String:
	return "%s\n[E] %s  (%d%% slip risk)" % [
		String(def.get("label", "CLIMB")).replace("\n", " "),
		_prompt_action(),
		roundi(float(def.get("fallChance", 0.15)) * 100.0)]

## Player raycast interaction (same protocol as Npc/TravelPoint).
## Milestone 19 risk pillar: roll the slip when the writer commits at the
## foot. Make it and the climb itself is a controllable, reversible ascent
## the player drives up/down by hand (Product_reqs ladder feature).
func interact() -> void:
	if _rng.randf() < float(def.get("fallChance", 0.15)):
		_apply_fall()
		return
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("begin_climb"):
		var pos: Array = def.get("position", [0, 0, 0])
		var top: Array = def.get("top", [0, 8, 0])
		# Ride the vertical column at the foot; the horizontal step onto the
		# landing happens on summit (complete_climb places at `top`).
		player.begin_climb(
			Vector3(pos[0], pos[1], pos[2]),
			Vector3(float(pos[0]), float(top[1]), float(pos[2])), self)
	else:
		resolve(true)

## The climb's outcome. Public and deterministic for tests/scripted beats
## (the smoke test drives both branches without the interactive climb).
func resolve(success: bool) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if success:
		_place_at_top(player)
		if player.has_method("play_context_animation"):
			player.play_context_animation("climb", 0.85)
		_apply_summit()
	else:
		_apply_fall()

## The interactive climb reached the exit — step onto the landing and run
## the success beat. Called by Player when the vertical climb summits.
func complete_climb() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player != null:
		_place_at_top(player)
	_apply_summit()

func _place_at_top(player: Node3D) -> void:
	var top: Array = def.get("top", [0, 8, 0])
	player.global_position = Vector3(top[0], top[1], top[2])
	if player is CharacterBody3D:
		player.velocity = Vector3.ZERO

func _apply_summit() -> void:
	var target_district := String(def.get("targetDistrictId", ""))
	if target_district != "":
		GameState.set_district(target_district)
	GameState.player_event.emit(_success_message(target_district))

func _apply_fall() -> void:
	# The caught-equivalent fine (ROADMAP.md Milestone 19): the street saw
	# you eat it.
	var penalty := mini(int(def.get("fallRepPenalty", 20)), GameState.reputation)
	if penalty > 0:
		GameState.add_reputation(-penalty)
	GameState.player_event.emit(
		"You slipped — rolled an ankle and your pride. (-%d rep)" % penalty)

func _prompt_action() -> String:
	match String(def.get("targetDistrictId", "")):
		"district_rooftop_row":
			return "Climb to Rooftop Row"
		"district_canal_side":
			return "Descend to Canal Side"
		_:
			return "Climb to the roof"

func _success_message(target_district: String) -> String:
	match target_district:
		"district_rooftop_row":
			return "You made Rooftop Row. Watch the wind; the CANAL DESCENT route gets you back."
		"district_canal_side":
			return "You drop back toward Canal Side. Street level feels loud again."
		_:
			return "You made the climb. The block looks small from up here."
