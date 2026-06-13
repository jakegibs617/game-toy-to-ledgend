extends StaticBody3D
## Climb zone (Milestone 19, Plan_v2.md §4): a drainpipe/ladder spot at
## the foot of a building. E attempts the climb — make it and you're on
## the roof (where the roller spots from Milestone 16 live); slip and
## you take the caught-equivalent fine (Plan_v2.md: the risk shifts
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
	# (Product_reqs ladder feature) instead of the old slim pipe hint.
	var top: Array = def.get("top", [0, 8, 0])
	var top_local := Vector3(
		float(top[0]) - position.x,
		float(top[1]) - position.y,
		float(top[2]) - position.z)
	_build_ladder(top_local)

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

## Builds rails + rungs running from the zone foot up to the exit, so the
## route reads as a climbable ladder. `top_local` is the exit in zone space.
func _build_ladder(top_local: Vector3) -> void:
	var length := maxf(top_local.length(), 2.0)
	var dir := top_local.normalized() if top_local.length() > 0.001 else Vector3.UP
	var ladder := Node3D.new()
	ladder.name = "Ladder"
	var basis := Basis()
	if not dir.is_equal_approx(Vector3.UP):
		basis = Basis(Quaternion(Vector3.UP, dir))
	# Set back 0.4 m against the wall face, as the old pipe hint was.
	ladder.transform = Transform3D(basis, Vector3(0, 0, -0.4))
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
		Vector3(-RAIL_OFFSET, length / 2.0, 0), rail_mat)
	_add_bar(ladder, Vector3(0.08, length, 0.08),
		Vector3(RAIL_OFFSET, length / 2.0, 0), rail_mat)
	var rung_spacing := 0.45
	var rungs := maxi(int(length / rung_spacing), 1)
	for i in range(rungs + 1):
		var y := minf(float(i) * rung_spacing, length)
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
		player.begin_climb(
			Vector3(pos[0], pos[1], pos[2]),
			Vector3(top[0], top[1], top[2]), self)
	else:
		resolve(true)

## The climb's outcome. Public and deterministic for tests/scripted beats
## (the smoke test drives both branches without the interactive climb).
func resolve(success: bool) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if success:
		var top: Array = def.get("top", [0, 8, 0])
		player.global_position = Vector3(top[0], top[1], top[2])
		if player is CharacterBody3D:
			player.velocity = Vector3.ZERO
		if player.has_method("play_context_animation"):
			player.play_context_animation("climb", 0.85)
		_apply_summit()
	else:
		_apply_fall()

## The interactive climb reached the exit — run the success beat (the
## player has already climbed into place). Called by Player.begin_climb.
func complete_climb() -> void:
	_apply_summit()

func _apply_summit() -> void:
	var target_district := String(def.get("targetDistrictId", ""))
	if target_district != "":
		GameState.set_district(target_district)
	GameState.player_event.emit(_success_message(target_district))

func _apply_fall() -> void:
	# The caught-equivalent fine (Plan_v2.md Milestone 19): the street saw
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
