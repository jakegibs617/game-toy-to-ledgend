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

	# A slim pipe up the wall face hints at the route.
	var pipe := MeshInstance3D.new()
	var pipe_mesh := BoxMesh.new()
	var top: Array = def.get("top", [0, 8, 0])
	var height: float = maxf(float(top[1]) - position.y, 2.0)
	pipe_mesh.size = Vector3(0.25, height, 0.25)
	pipe.mesh = pipe_mesh
	pipe.position = Vector3(0, height / 2.0, -0.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#3d4a3d")
	mat.emission_enabled = true
	mat.emission = Color("#7be05a")
	mat.emission_energy_multiplier = 0.35
	pipe.material_override = mat
	add_child(pipe)

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

func prompt_text() -> String:
	return "%s\n[E] %s  (%d%% slip risk)" % [
		String(def.get("label", "CLIMB")).replace("\n", " "),
		_prompt_action(),
		roundi(float(def.get("fallChance", 0.15)) * 100.0)]

## Player raycast interaction (same protocol as Npc/TravelPoint).
func interact() -> void:
	resolve(_rng.randf() >= float(def.get("fallChance", 0.15)))

## The climb's outcome. Public and deterministic for tests/scripted beats.
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
		var target_district := String(def.get("targetDistrictId", ""))
		if target_district != "":
			GameState.set_district(target_district)
		GameState.player_event.emit(_success_message(target_district))
	else:
		# The caught-equivalent fine (Plan_v2.md Milestone 19): the
		# street saw you eat it.
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
