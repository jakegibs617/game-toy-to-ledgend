class_name Npc
extends StaticBody3D
## A recruitable NPC, built at runtime from Data/npc_data.json.
## The player's interaction ray focuses it; E talks via CrewManager.

const LOOKOUT_IDLE_MODEL_PATH := "res://Assets/Characters/lookout_meerkat_idle.glb"
const LOOKOUT_WALK_MODEL_PATH := "res://Assets/Characters/lookout_meerkat_walking.glb"
const LOOKOUT_RUN_MODEL_PATH := "res://Assets/Characters/lookout_meerkat_running.glb"
const LOOKOUT_ALERT_MODEL_PATH := "res://Assets/Characters/lookout_meerkat_alert.glb"
const LOOKOUT_MODEL_SOURCE_HEIGHT := 1.7
const LOOKOUT_IDLE_ANIMATION_NAME := "Armature|clip0|baselayer"
const LOOKOUT_WALK_ANIMATION_NAME := "Armature|walking_man|baselayer"
const LOOKOUT_RUN_ANIMATION_NAME := "Armature|running|baselayer"
const LOOKOUT_ALERT_ANIMATION_NAME := "Armature|Alert|baselayer"

var data: Dictionary = {}
var _visual_root: Node3D
var _base_color := Color("#cccccc")
var _lookout_indicator: MeshInstance3D
var _visual_models: Dictionary = {}
var _visual_animation_players: Dictionary = {}
var _visual_animation_names: Dictionary = {}
var _active_visual_state := ""

func setup(npc_data: Dictionary) -> void:
	data = npc_data
	name = String(data["memberId"])
	var pos: Array = data.get("position", [0, 0, 0])
	position = Vector3(pos[0], pos[1], pos[2])

	_base_color = Color(String(data.get("color", "#cccccc")))
	_build_character()
	_build_collision()
	_build_label()
	if String(data.get("role", "")) == "lookout":
		_build_lookout_gear()
		set_process(true)
	else:
		set_process(false)

func _process(_delta: float) -> void:
	if String(data.get("role", "")) != "lookout":
		return
	var recruited := String(data.get("stage", "")) == "recruited"
	if _lookout_indicator != null:
		_lookout_indicator.visible = recruited
	if not recruited:
		_set_visual_state("idle")
		return
	_set_visual_state("alert")
	var guard := _nearest_guard()
	if guard == null:
		return
	var to := guard.global_position - global_position
	to.y = 0.0
	if to.length() > 0.1:
		_visual_root.rotation.y = atan2(-to.x, -to.z)

func _build_character() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "CharacterVisual"
	add_child(_visual_root)
	if String(data.get("role", "")) == "lookout" and _try_build_lookout_model():
		return
	_build_capsule_character()

func _build_capsule_character() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.height = 1.7
	capsule.radius = 0.32
	mesh.mesh = capsule
	mesh.position = Vector3(0, 0.85, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _base_color
	mesh.material_override = mat
	_visual_root.add_child(mesh)

	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.24
	head_mesh.height = 0.36
	head.mesh = head_mesh
	head.position = Vector3(0, 1.82, 0)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color("#4b3a3f")
	head.material_override = head_mat
	_visual_root.add_child(head)

	var hood := MeshInstance3D.new()
	hood.name = "Hood"
	var hood_mesh := BoxMesh.new()
	hood_mesh.size = Vector3(0.68, 0.18, 0.18)
	hood.mesh = hood_mesh
	hood.position = Vector3(0, 1.58, -0.22)
	var hood_mat := StandardMaterial3D.new()
	hood_mat.albedo_color = _base_color.darkened(0.3)
	hood.material_override = hood_mat
	_visual_root.add_child(hood)

func _try_build_lookout_model() -> bool:
	if not ResourceLoader.exists(LOOKOUT_IDLE_MODEL_PATH):
		return false
	var model_root := Node3D.new()
	model_root.name = "LookoutMeerkatModel"
	_apply_lookout_model_transform(model_root)
	_visual_root.add_child(model_root)
	var built := false
	built = _add_animated_model(
		model_root, LOOKOUT_IDLE_MODEL_PATH, "idle", LOOKOUT_IDLE_ANIMATION_NAME) or built
	built = _add_animated_model(
		model_root, LOOKOUT_WALK_MODEL_PATH, "walk", LOOKOUT_WALK_ANIMATION_NAME) or built
	built = _add_animated_model(
		model_root, LOOKOUT_RUN_MODEL_PATH, "run", LOOKOUT_RUN_ANIMATION_NAME) or built
	built = _add_animated_model(
		model_root, LOOKOUT_ALERT_MODEL_PATH, "alert", LOOKOUT_ALERT_ANIMATION_NAME) or built
	if not built:
		model_root.queue_free()
		return false
	_set_visual_state("idle")
	return true

func _add_animated_model(container: Node3D, path: String,
		visual_state: String, preferred_animation: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var packed: PackedScene = load(path)
	if packed == null:
		return false
	var model := packed.instantiate()
	model.name = "%sModel" % visual_state.capitalize()
	model.visible = false
	container.add_child(model)
	var player := _find_animation_player(model)
	if player == null:
		return false
	var names := player.get_animation_list()
	if names.is_empty():
		return false
	var chosen := String(names[0])
	for animation_name in names:
		if String(animation_name) == preferred_animation:
			chosen = String(animation_name)
			break
	_visual_models[visual_state] = model
	_visual_animation_players[visual_state] = player
	_visual_animation_names[visual_state] = StringName(chosen)
	player.play(StringName(chosen))
	player.pause()
	player.seek(0.0, true)
	return true

func _apply_lookout_model_transform(model: Node3D) -> void:
	var s := 1.7 / LOOKOUT_MODEL_SOURCE_HEIGHT
	model.scale = Vector3.ONE * s
	model.position = Vector3.ZERO
	model.rotation.y = PI

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null

func _set_visual_state(visual_state: String) -> void:
	if _visual_animation_players.is_empty():
		return
	var target := visual_state
	if not _visual_models.has(target):
		target = "idle" if _visual_models.has("idle") else String(_visual_models.keys()[0])
	if _active_visual_state != target:
		for key in _visual_models:
			_visual_models[key].visible = String(key) == target
		_active_visual_state = target
	var player: AnimationPlayer = _visual_animation_players[target]
	var animation: StringName = _visual_animation_names[target]
	if target == "idle":
		if player.is_playing():
			player.pause()
		player.seek(0.0, true)
		return
	if not player.is_playing() or String(player.current_animation) != String(animation):
		player.play(animation)

func _build_collision() -> void:

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.7
	shape.radius = 0.32
	col.shape = shape
	col.position = Vector3(0, 0.85, 0)
	add_child(col)

func _build_label() -> void:
	var label := Label3D.new()
	label.text = String(data.get("alias", "?"))
	label.font_size = 64
	label.outline_size = 12
	label.pixel_size = 0.004
	label.position = Vector3(0, 2.28, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

	var role_label := Label3D.new()
	role_label.name = "RoleLabel"
	role_label.text = String(data.get("roleLabel", data.get("role", ""))).to_upper()
	role_label.font_size = 42
	role_label.outline_size = 10
	role_label.pixel_size = 0.0032
	role_label.position = Vector3(0, 2.08, 0)
	role_label.modulate = _base_color.lightened(0.25)
	role_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(role_label)

func _build_lookout_gear() -> void:
	var phone := MeshInstance3D.new()
	phone.name = "LookoutRadioPhone"
	var phone_mesh := BoxMesh.new()
	phone_mesh.size = Vector3(0.12, 0.26, 0.04)
	phone.mesh = phone_mesh
	phone.position = Vector3(0.4, 1.18, -0.16)
	var phone_mat := StandardMaterial3D.new()
	phone_mat.albedo_color = Color("#1c222d")
	phone.material_override = phone_mat
	_visual_root.add_child(phone)

	_lookout_indicator = MeshInstance3D.new()
	_lookout_indicator.name = "LookoutActiveIndicator"
	var indicator_mesh := SphereMesh.new()
	indicator_mesh.radius = 0.08
	indicator_mesh.height = 0.12
	_lookout_indicator.mesh = indicator_mesh
	_lookout_indicator.position = Vector3(0.42, 2.03, -0.12)
	var indicator_mat := StandardMaterial3D.new()
	indicator_mat.albedo_color = Color("#ffef7a")
	indicator_mat.emission_enabled = true
	indicator_mat.emission = Color("#ffef7a")
	indicator_mat.emission_energy_multiplier = 1.6
	_lookout_indicator.material_override = indicator_mat
	_lookout_indicator.visible = String(data.get("stage", "")) == "recruited"
	_visual_root.add_child(_lookout_indicator)

func _nearest_guard() -> PatrolGuard:
	var best: PatrolGuard = null
	var best_dist := INF
	for guard in PatrolManager.guards():
		if not is_instance_valid(guard):
			continue
		var dist := global_position.distance_squared_to(guard.global_position)
		if dist < best_dist:
			best_dist = dist
			best = guard
	return best

func prompt_text() -> String:
	return "[E] Talk to %s (%s)" % [
		String(data.get("alias", "?")),
		String(data.get("roleLabel", data.get("role", "")))]

func interact() -> void:
	# Once recruited, members with a dialogue tree chat through it
	# (Milestone 12); recruitment stages stay with CrewManager.
	var dialogue_id := String(data.get("dialogueId", ""))
	if String(data.get("stage", "")) == "recruited" and dialogue_id != "" \
			and DialogueManager.start(dialogue_id, self):
		return
	CrewManager.interact(String(data["memberId"]))
