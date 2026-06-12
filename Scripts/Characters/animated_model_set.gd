extends RefCounted
## Shared loader for the swap-visibility animated character pattern:
## each visual state is a separate GLB whose AnimationPlayer is primed
## and paused at frame 0; callers toggle per-state visibility to
## "switch animations". Used by the player, crew NPCs, mission actors,
## and patrol guards (preload this script — Hard-won rule on the
## headless class_name cache).

## Instantiates the GLB at `path` under `container`, primes its first
## (or `preferred_animation`) clip, and registers it in the caller's
## models/players/names dictionaries keyed by `visual_state`.
static func add_animated_model(container: Node3D, path: String,
		visual_state: String, preferred_animation: String,
		models: Dictionary, players: Dictionary,
		animation_names: Dictionary) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var packed: PackedScene = load(path)
	if packed == null:
		return false
	var model := packed.instantiate()
	model.name = "%sModel" % visual_state.capitalize()
	model.visible = false
	container.add_child(model)
	var player := find_animation_player(model)
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
	models[visual_state] = model
	players[visual_state] = player
	animation_names[visual_state] = StringName(chosen)
	player.play(StringName(chosen))
	player.pause()
	player.seek(0.0, true)
	return true

## Data-driven version of the same pattern. `visuals` is a JSON-safe
## block with sourceHeight, optional rotationY degrees, and states:
## state -> {model, clip}. Callers keep their own model/player/name
## dictionaries so their animation selection logic remains local.
static func build_from_manifest(parent: Node3D, visuals: Dictionary,
		models: Dictionary, players: Dictionary,
		animation_names: Dictionary, target_height := 1.7) -> Node3D:
	var states: Dictionary = visuals.get("states", {})
	if states.is_empty():
		return null
	var container := Node3D.new()
	container.name = String(visuals.get("containerName", "AnimatedModel"))
	var source_height := float(visuals.get("sourceHeight", target_height))
	if source_height > 0.0:
		container.scale = Vector3.ONE * (target_height / source_height)
	container.rotation.y = deg_to_rad(float(visuals.get("rotationY", 0.0)))
	parent.add_child(container)
	var built := false
	for state in states:
		var def: Dictionary = states[state]
		built = add_animated_model(container, String(def.get("model", "")),
			String(state), String(def.get("clip", "")), models, players,
			animation_names) or built
	if not built:
		container.queue_free()
		return null
	return container

static func find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var found := find_animation_player(child)
		if found != null:
			return found
	return null
