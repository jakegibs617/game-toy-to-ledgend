extends Node
## Rival crew simulation (Plan.md sections 13 and 33). Loads
## Data/crews.json, claims each crew's home walls at session start, and
## retaliates when the player paints in crew territory or covers crew
## work: weak graffiti gets "TOY" crossed out, stronger work gets
## covered by the crew's own graffiti. Autoloaded as RivalManager.

signal rival_event(message: String, wall_id: String)

const CREWS_PATH := "res://Data/crews.json"
## One simulation tick = one "in-game hour" (Plan.md section 33).
const TICK_SECONDS := 12.0

var crews: Dictionary = {}  # crewId -> crew definition
var _pending: Array[Dictionary] = []  # queued responses {wallId, crewId, ticks}
var _claimed_initial := false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	var parsed: Variant = _load_json(CREWS_PATH)
	if parsed is Array:
		for crew in parsed:
			crews[crew["crewId"]] = crew
	WallManager.wall_painted.connect(_on_wall_painted)
	var timer := Timer.new()
	timer.wait_time = TICK_SECONDS
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)

## Paints each crew's home territory once per session so rival
## ownership is visible from the start (Plan.md section 13).
func claim_initial_territory() -> void:
	if _claimed_initial:
		return
	_claimed_initial = true
	for crew in crews.values():
		for wall_id in crew.get("territory", []):
			var state: Dictionary = WallManager.wall_states.get(wall_id, {})
			if state.get("state", "blank") == "blank":
				WallManager.apply_rival_graffiti(
					wall_id, crew, String(crew.get("responseType", "throwup")))

func _on_wall_painted(wall_id: String, graffiti: Dictionary) -> void:
	if String(graffiti.get("creatorId", "")) != "player":
		return
	var crew := _offended_crew(wall_id)
	if crew.is_empty():
		return
	crew["relationshipToPlayer"] = int(crew.get("relationshipToPlayer", 0)) - 10
	for p in _pending:
		if p["wallId"] == wall_id:
			return
	_pending.append({
		"wallId": wall_id,
		"crewId": crew["crewId"],
		"ticks": 1 + _rng.randi_range(0, 1),
	})
	# A recruited lookout spots the trouble coming (Plan.md section 14).
	var lookout := CrewManager.first_with_role("lookout")
	if not lookout.is_empty():
		rival_event.emit('%s: "%s clocked that. Expect them back at %s."' % [
			String(lookout["alias"]), String(crew.get("name", "A crew")),
			String(WallManager.wall_def(wall_id).get("name", wall_id))], wall_id)

## The crew whose territory contains this wall, or whose work the
## player just covered (previous graffiti in the wall's history).
func _offended_crew(wall_id: String) -> Dictionary:
	for crew in crews.values():
		if wall_id in crew.get("territory", []):
			return crew
	var state: Dictionary = WallManager.wall_states.get(wall_id, {})
	var history: Array = state.get("history", [])
	if not history.is_empty():
		var prev: Dictionary = history[-1]
		return crews.get(String(prev.get("crewId", "")), {})
	return {}

func _on_tick() -> void:
	var remaining: Array[Dictionary] = []
	for p in _pending:
		p["ticks"] = int(p["ticks"]) - 1
		if p["ticks"] > 0:
			remaining.append(p)
		else:
			_try_respond(String(p["wallId"]), String(p["crewId"]))
	_pending = remaining

func _try_respond(wall_id: String, crew_id: String) -> void:
	var crew: Dictionary = crews.get(crew_id, {})
	var state: Dictionary = WallManager.wall_states.get(wall_id, {})
	if crew.is_empty() or String(state.get("ownerCrewId", "")) != "player":
		return  # The player's work is already gone; nothing to avenge.
	if _rng.randf() <= response_chance(wall_id, crew_id):
		respond(wall_id, crew_id)

## Aggression + per-wall response chance, dampened when a recruited
## lookout is watching the player's walls (Milestone 5 role bonus).
func response_chance(wall_id: String, crew_id: String) -> float:
	var crew: Dictionary = crews.get(crew_id, {})
	var def := WallManager.wall_def(wall_id)
	var chance := clampf(
		0.35 + 0.12 * float(crew.get("aggression", 2))
		+ float(def.get("rivalResponseChance", 0.0)), 0.0, 0.95)
	if CrewManager.has_role("lookout"):
		chance *= 0.6
	return chance

## Executes a rival response immediately. Split out from the chance
## roll so tests and scripted missions can trigger it deterministically.
func respond(wall_id: String, crew_id: String) -> void:
	var crew: Dictionary = crews[crew_id]
	var state: Dictionary = WallManager.wall_states[wall_id]
	if String(state.get("ownerCrewId", "")) != "player":
		return
	var current: Dictionary = state.get("currentGraffiti") if state.get("currentGraffiti") != null else {}
	var type_label := String(
		WallManager.styles.get(String(current.get("type", "tag")), {}).get("label", "work"))
	var wall_name := String(WallManager.wall_def(wall_id).get("name", wall_id))
	var who := "%s (%s)" % [String(crew.get("leaderAlias", "?")), String(crew.get("name", crew_id))]
	# Weak work in respected territory gets the "TOY" treatment
	# (Plan.md section 13); stronger work gets covered instead.
	if String(current.get("type", "tag")) == "tag" or GameState.rank in ["Toy", "Rookie"]:
		WallManager.cross_out_wall(wall_id, crew, "TOY")
		rival_event.emit('%s wrote "TOY" over your %s on %s!' % [who, type_label, wall_name], wall_id)
	else:
		WallManager.apply_rival_graffiti(wall_id, crew, String(crew.get("responseType", "throwup")))
		rival_event.emit("%s covered your %s on %s." % [who, type_label, wall_name], wall_id)

func _load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("RivalManager: cannot open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("RivalManager: invalid JSON in %s" % path)
	return parsed
