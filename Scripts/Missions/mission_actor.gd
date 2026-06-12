class_name MissionActor
extends StaticBody3D
## A non-recruitable mission NPC (e.g. Lupe the supply contact), built
## at runtime from the "actors" block of Data/missions.json. Same
## placeholder look as Npc; E reports to MissionManager, falling back
## to an idle line when no objective wants this actor.

const LUPE_IDLE_MODEL_PATH := "res://Assets/Characters/lupe_rat_idle.glb"
const LUPE_IDLE_02_MODEL_PATH := "res://Assets/Characters/lupe_rat_idle_02.glb"
const LUPE_WALK_MODEL_PATH := "res://Assets/Characters/lupe_rat_walking.glb"
const LUPE_RUN_MODEL_PATH := "res://Assets/Characters/lupe_rat_running.glb"
const LUPE_ALERT_MODEL_PATH := "res://Assets/Characters/lupe_rat_alert_turn_right.glb"
const LUPE_MODEL_SOURCE_HEIGHT := 1.7
const LUPE_IDLE_ANIMATION_NAME := "Armature|clip0|baselayer"
const LUPE_IDLE_02_ANIMATION_NAME := "Armature|Idle_02|baselayer"
const LUPE_WALK_ANIMATION_NAME := "Armature|walking_man|baselayer"
const LUPE_RUN_ANIMATION_NAME := "Armature|running|baselayer"
const LUPE_ALERT_ANIMATION_NAME := "Armature|Alert_Quick_Turn_Right|baselayer"
const PRIME_IDLE_MODEL_PATH := "res://Assets/Characters/prime_gori_idle.glb"
const PRIME_IDLE_02_MODEL_PATH := "res://Assets/Characters/prime_gori_idle_02.glb"
const PRIME_LISTENING_MODEL_PATH := "res://Assets/Characters/prime_gori_listening.glb"
const PRIME_WALK_MODEL_PATH := "res://Assets/Characters/prime_gori_walking.glb"
const PRIME_RUN_MODEL_PATH := "res://Assets/Characters/prime_gori_running.glb"
const PRIME_MODEL_SOURCE_HEIGHT := 1.7
const PRIME_IDLE_ANIMATION_NAME := "Armature|clip0|baselayer"
const PRIME_IDLE_02_ANIMATION_NAME := "Armature|Idle_02|baselayer"
const PRIME_LISTENING_ANIMATION_NAME := "Armature|Listening_Gesture|baselayer"
const PRIME_WALK_ANIMATION_NAME := "Armature|walking_man|baselayer"
const PRIME_RUN_ANIMATION_NAME := "Armature|running|baselayer"
const AnimatedModelSet := preload("res://Scripts/Characters/animated_model_set.gd")

var data: Dictionary = {}
var _visual_models: Dictionary = {}
var _visual_animation_players: Dictionary = {}
var _visual_animation_names: Dictionary = {}
var _active_visual_state := ""
var _min_rank := ""
var _collision: CollisionShape3D = null

func setup(actor_data: Dictionary) -> void:
	data = actor_data
	name = String(data["actorId"])
	var pos: Array = data.get("position", [0, 0, 0])
	position = Vector3(pos[0], pos[1], pos[2])

	var actor_id := String(data.get("actorId", ""))
	if actor_id == "lupe" and _try_build_lupe_model():
		_build_shop_props()
	elif actor_id == "prime" and _try_build_prime_model():
		_build_prime_props()
	else:
		_build_capsule_visual()
	_build_collision()
	_build_label()
	# Rank-gated contacts (the gallery scout, §43 "appears at rank
	# Known") stay out of the world until the writer's name is big
	# enough — invisible and untouchable by the interact ray.
	_min_rank = String(data.get("minRank", ""))
	if _min_rank != "":
		GameState.rank_changed.connect(func(_rank: String) -> void:
			_refresh_rank_gate())
		_refresh_rank_gate()

func _refresh_rank_gate() -> void:
	var unlocked := GameState.rank_index(GameState.rank) >= GameState.rank_index(_min_rank)
	visible = unlocked
	if _collision != null:
		_collision.disabled = not unlocked

func _build_capsule_visual() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "CapsuleFallback"
	var capsule := CapsuleMesh.new()
	capsule.height = 1.7
	capsule.radius = 0.32
	mesh.mesh = capsule
	mesh.position = Vector3(0, 0.85, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(String(data.get("color", "#cccccc")))
	mesh.material_override = mat
	add_child(mesh)

func _build_collision() -> void:
	_collision = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.7
	shape.radius = 0.32
	_collision.shape = shape
	_collision.position = Vector3(0, 0.85, 0)
	add_child(_collision)

func _build_label() -> void:
	var label := Label3D.new()
	label.text = String(data.get("name", "?"))
	label.font_size = 64
	label.outline_size = 12
	label.pixel_size = 0.004
	label.position = Vector3(0, 2.1, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _try_build_lupe_model() -> bool:
	if not ResourceLoader.exists(LUPE_IDLE_MODEL_PATH):
		return false
	var container := Node3D.new()
	container.name = "LupeRatModel"
	_apply_model_transform(container, LUPE_MODEL_SOURCE_HEIGHT)
	var built := false
	built = _add_animated_model(
		container, LUPE_IDLE_MODEL_PATH, "idle", LUPE_IDLE_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, LUPE_IDLE_02_MODEL_PATH, "idle_02", LUPE_IDLE_02_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, LUPE_WALK_MODEL_PATH, "walk", LUPE_WALK_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, LUPE_RUN_MODEL_PATH, "run", LUPE_RUN_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, LUPE_ALERT_MODEL_PATH, "alert", LUPE_ALERT_ANIMATION_NAME) or built
	if not built:
		return false
	add_child(container)
	_set_visual_state("idle_02")
	return true

func _try_build_prime_model() -> bool:
	if not ResourceLoader.exists(PRIME_IDLE_MODEL_PATH):
		return false
	var container := Node3D.new()
	container.name = "PrimeGoriModel"
	_apply_model_transform(container, PRIME_MODEL_SOURCE_HEIGHT)
	var built := false
	built = _add_animated_model(
		container, PRIME_IDLE_MODEL_PATH, "idle", PRIME_IDLE_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, PRIME_IDLE_02_MODEL_PATH, "idle_02", PRIME_IDLE_02_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, PRIME_LISTENING_MODEL_PATH, "listening", PRIME_LISTENING_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, PRIME_WALK_MODEL_PATH, "walk", PRIME_WALK_ANIMATION_NAME) or built
	built = _add_animated_model(
		container, PRIME_RUN_MODEL_PATH, "run", PRIME_RUN_ANIMATION_NAME) or built
	if not built:
		return false
	add_child(container)
	_set_visual_state("listening")
	return true

func _add_animated_model(container: Node3D, path: String,
		visual_state: String, preferred_animation: String) -> bool:
	return AnimatedModelSet.add_animated_model(container, path, visual_state,
		preferred_animation, _visual_models, _visual_animation_players,
		_visual_animation_names)

func _apply_model_transform(model: Node3D, source_height: float) -> void:
	var s := 1.7 / source_height
	model.scale = Vector3.ONE * s
	model.position = Vector3.ZERO
	model.rotation.y = PI

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
	if not player.is_playing() or String(player.current_animation) != String(animation):
		player.play(animation)

func _build_shop_props() -> void:
	var crate := MeshInstance3D.new()
	crate.name = "SupplyCrate"
	var crate_mesh := BoxMesh.new()
	crate_mesh.size = Vector3(0.9, 0.45, 0.55)
	crate.mesh = crate_mesh
	crate.position = Vector3(-0.75, 0.25, 0.18)
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = Color("#7b5836")
	crate.material_override = crate_mat
	add_child(crate)

	for i in range(3):
		var can := MeshInstance3D.new()
		can.name = "PaintCan"
		var can_mesh := CylinderMesh.new()
		can_mesh.top_radius = 0.09
		can_mesh.bottom_radius = 0.09
		can_mesh.height = 0.28
		can.mesh = can_mesh
		can.position = Vector3(-1.0 + i * 0.22, 0.64, 0.12)
		var can_mat := StandardMaterial3D.new()
		can_mat.albedo_color = [Color("#e0301e"), Color("#7fe7dc"), Color("#e0a030")][i]
		can.material_override = can_mat
		add_child(can)

func _build_prime_props() -> void:
	var crate := MeshInstance3D.new()
	crate.name = "OldHeadMilkCrate"
	var crate_mesh := BoxMesh.new()
	crate_mesh.size = Vector3(0.55, 0.42, 0.55)
	crate.mesh = crate_mesh
	crate.position = Vector3(0.68, 0.22, 0.22)
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = Color("#2b2f36")
	crate.material_override = crate_mat
	add_child(crate)

	var blackbook := MeshInstance3D.new()
	blackbook.name = "PrimeBlackbook"
	var book_mesh := BoxMesh.new()
	book_mesh.size = Vector3(0.42, 0.04, 0.3)
	blackbook.mesh = book_mesh
	blackbook.position = Vector3(0.68, 0.46, 0.22)
	blackbook.rotation_degrees.y = -18.0
	var book_mat := StandardMaterial3D.new()
	book_mat.albedo_color = Color("#15151a")
	blackbook.material_override = book_mat
	add_child(blackbook)

	var marker := MeshInstance3D.new()
	marker.name = "PrimeMarker"
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.035
	marker_mesh.bottom_radius = 0.035
	marker_mesh.height = 0.42
	marker.mesh = marker_mesh
	marker.position = Vector3(0.49, 0.51, 0.12)
	marker.rotation_degrees.z = 82.0
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color("#d9d2bc")
	marker.material_override = marker_mat
	add_child(marker)

func prompt_text() -> String:
	if data.get("shop", false):
		return "[E] %s (%s) — talk / shop" % [
			String(data.get("name", "?")), String(data.get("roleLabel", ""))]
	return "[E] Talk to %s (%s)" % [
		String(data.get("name", "?")), String(data.get("roleLabel", ""))]

func interact() -> void:
	if MissionManager.notify_actor(String(data["actorId"])):
		return
	# Outside mission beats: a dialogue tree if the actor has one
	# (Milestone 12), else the shop catalog (Milestone 11), else an
	# idle line.
	var dialogue_id := String(data.get("dialogueId", ""))
	if dialogue_id != "" and DialogueManager.start(dialogue_id, self):
		return
	if data.get("shop", false):
		SupplyManager.toggle_shop(self)
		return
	var idle := String(data.get("dialogue", {}).get("idle", ""))
	if idle != "":
		MissionManager.mission_event.emit(idle)
