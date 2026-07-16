extends Node
## Security patrols (GDD sections 12, 18, 25). Spawns guards onto
## fixed routes from Data/patrols.json; higher heat fields more patrols.
## A guard that sees the player painting spikes heat and gives chase
## (section 25: security interrupts painting and increases heat).
## Getting caught costs reputation and paint but settles heat — the
## incident is closed. A recruited lookout calls out patrols near the
## player's painting spot (section 14). Autoloaded as PatrolManager.

signal patrol_event(message: String)
signal player_spotted(guard: PatrolGuard)
signal player_caught(guard: PatrolGuard)
## Every player paint reports whether security witnessed it — clean
## getaways feed the Stealth stat (Milestone 17).
signal paint_observed(spotted: bool)
signal chase_escaped

const PATROLS_PATH := "res://Data/patrols.json"
const DataLoader := preload("res://Scripts/Data/data_loader.gd")
const WARN_COOLDOWN_MS := 10000

var config: Dictionary = {}
var _routes: Array = []
var _guards: Array[PatrolGuard] = []
var _parent: Node3D = null
var _player: Player = null
var _last_warn_ms := -WARN_COOLDOWN_MS

func _ready() -> void:
	var parsed: Variant = DataLoader.load_json(PATROLS_PATH, "PatrolManager")
	if parsed is Dictionary:
		config = parsed
		_routes = config.get("routes", [])
		DataLoader.require_fields(config, ["guardsPerLevel", "routes"], "PatrolManager: config")
		for route in _routes:
			DataLoader.require_fields(route, ["routeId", "speed", "waypoints"],
				"PatrolManager: route \"%s\"" % String(route.get("routeId", "?")))
	WallManager.wall_painted.connect(_on_wall_painted)
	HeatManager.heat_changed.connect(func(_heat: float, _gained: float) -> void:
		_sync_guard_count())
	GameState.difficulty_changed.connect(func(_preset_id: String) -> void:
		_sync_guard_count())
	# Milestone 18: patrols belong to a block. Crossing districts swaps
	# the active guard set for the new block's routes, quietly.
	GameState.district_changed.connect(func(_district_id: String) -> void:
		_respawn_for_district())

## Called by the district scene once the player exists.
func spawn_patrols(parent: Node3D, player: Player) -> void:
	_parent = parent
	_player = player
	_guards.clear()
	_sync_guard_count(true)

func guard_count() -> int:
	return _guards.size()

func guards() -> Array[PatrolGuard]:
	return _guards

## GDD §12: higher heat causes more patrols.
func guards_for_level(level: String) -> int:
	var per_level: Dictionary = config.get("guardsPerLevel", {})
	var base := int(per_level.get(level, 1))
	var patrol_mult := GameState.difficulty_patrol_multiplier()
	var scaled := ceili(float(base) * patrol_mult) if patrol_mult >= 1.0 \
		else floori(float(base) * patrol_mult)
	return mini(maxi(scaled, 1 if base > 0 else 0), _current_routes().size())

## Routes belonging to the player's current district (Milestone 18).
func _current_routes() -> Array:
	var result: Array = []
	for route in _routes:
		if String(route.get("districtId", "district_mill_yard")) == GameState.current_district_id:
			result.append(route)
	return result

## District switch: clear every guard (chasing or not — they don't
## follow across the water) and respawn from the new block's routes.
func _respawn_for_district() -> void:
	for guard in _guards:
		if is_instance_valid(guard):
			guard.queue_free()
	_guards.clear()
	_sync_guard_count(true)

## A guard reached the player: dock rep, confiscate paint, and settle
## heat — they moved you along, the incident is closed. Public so tests
## and scripted beats can trigger a catch deterministically.
func resolve_catch(guard: PatrolGuard) -> void:
	var heat_level := HeatManager.level_name()
	if CrewManager.try_getaway_escape(heat_level):
		guard.end_chase()
		chase_escaped.emit()
		patrol_event.emit("Metro ghosts you through a service route — no fine this time.")
		return
	guard.end_chase()
	var rep_loss := mini(roundi(int(config.get("caughtRepPenalty", 25))
		* CrewManager.caught_rep_multiplier()), GameState.reputation)
	if rep_loss > 0:
		GameState.add_reputation(-rep_loss)
	var paint_loss := mini(roundi(int(config.get("caughtPaintPenalty", 3))
		* CrewManager.caught_paint_multiplier()), GameState.paint)
	if paint_loss > 0:
		GameState.add_paint(-paint_loss)
	if CrewManager.has_role("fixer"):
		CrewManager.note_role_helped("fixer", 3)
	CrewManager.adjust_morale(-5, "caught")
	player_caught.emit(guard)
	patrol_event.emit("CAUGHT — security moved you along. -%d rep, -%d paint." % [rep_loss, paint_loss])
	HeatManager.settle(float(config.get("caughtHeatCeiling", 25.0)))

func guard_gave_up(_guard: PatrolGuard) -> void:
	chase_escaped.emit()
	patrol_event.emit("You lost them. Security gave up the chase.")

func _on_wall_painted(_wall_id: String, graffiti: Dictionary) -> void:
	if _player == null or String(graffiti.get("creatorId", "")) != "player":
		return
	# Long paints expose the writer (Milestone 16): the style's exposure
	# widens the witness range and drops the facing requirement.
	var style: Dictionary = WallManager.styles.get(String(graffiti.get("type", "tag")), {})
	var exposure := float(style.get("exposure", 1.0))
	for guard in _guards:
		if guard.can_see(_player) \
				or (exposure > 1.0 and guard.noticed_during(_player, exposure)):
			_spotted(guard)
			paint_observed.emit(true)
			return
	paint_observed.emit(false)
	_maybe_lookout_warning()

func _spotted(guard: PatrolGuard) -> void:
	HeatManager.add_heat(float(config.get("spottedHeat", 12.0)))
	guard.start_chase(_player)
	player_spotted.emit(guard)
	patrol_event.emit("SPOTTED — security saw you painting. Run!")

## Nobody saw the paint land, but a recruited lookout calls out close
## patrols (GDD §14: warns player of cops).
func _maybe_lookout_warning() -> void:
	var lookout := CrewManager.first_with_role("lookout")
	if lookout.is_empty():
		return
	var warn_range := float(config.get("warnRange", 12.0))
	for guard in _guards:
		if guard.global_position.distance_to(_player.global_position) <= warn_range:
			var now := Time.get_ticks_msec()
			if now - _last_warn_ms >= WARN_COOLDOWN_MS:
				_last_warn_ms = now
				CrewManager.note_role_helped("lookout", 1)
				patrol_event.emit('%s: "Five-oh close by — keep it moving."' % String(lookout["alias"]))
			return

## Keeps the live guard count matched to the heat level, spawning onto
## routes round-robin and despawning idle guards first when cooling.
func _sync_guard_count(quiet := false) -> void:
	var routes := _current_routes()
	if _parent == null or not is_instance_valid(_parent) or routes.is_empty():
		return
	var target := guards_for_level(HeatManager.level_name())
	var grew := _guards.size() < target
	while _guards.size() < target:
		var guard := PatrolGuard.new()
		guard.setup(routes[_guards.size() % routes.size()], config)
		_parent.add_child(guard)
		_guards.append(guard)
	var shrank := false
	while _guards.size() > target:
		var idx := _removable_guard_index()
		if idx < 0:
			break  # everyone is mid-chase; thin out on a later sync
		var guard := _guards[idx]
		_guards.remove_at(idx)
		guard.queue_free()
		shrank = true
	if quiet:
		return
	if grew:
		patrol_event.emit("More security on the block — watch the streets.")
	elif shrank:
		patrol_event.emit("A patrol clocked out. The block breathes easier.")

func _removable_guard_index() -> int:
	for i in range(_guards.size() - 1, -1, -1):
		if not _guards[i].is_chasing():
			return i
	return -1
