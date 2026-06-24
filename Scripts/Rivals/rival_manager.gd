extends Node
## Rival crew simulation (Plan.md sections 13 and 33). Loads
## Data/crews.json, claims each crew's home walls at session start, and
## retaliates when the player paints in crew territory or covers crew
## work: weak graffiti gets "TOY" crossed out, stronger work gets
## covered by the crew's own graffiti. Autoloaded as RivalManager.

signal rival_event(message: String, wall_id: String)

const CREWS_PATH := "res://Data/crews.json"
const DataLoader := preload("res://Scripts/Data/data_loader.gd")
## One simulation tick = one "in-game hour" (Plan.md section 33).
const TICK_SECONDS := 12.0
## A retaliation can never land sooner than this after the player paints
## (Product_reqs.md): rivals do not teleport their TOY over a fresh tag.
const MIN_RESPONSE_DELAY_MS := 30000
const WALL_DUEL_REP_BONUS := 18
const WALL_DUEL_CREW_REP := 4
const WALL_DUEL_FORFEIT_REP_PENALTY := 10
const WALL_DUEL_FORFEIT_CREW_REP_PENALTY := 2
const WALL_DUEL_FORFEIT_MORALE_PENALTY := 8
## A wall duel the writer never answers is not a permanent free pass: the
## crew holds the wall and the callout forfeits after this many simulation
## ticks (one tick = TICK_SECONDS), with a last-chance warning one tick out.
## Stored as a per-duel countdown so it survives save/load like _pending.
const WALL_DUEL_DEADLINE_TICKS := 8

var crews: Dictionary = {}  # crewId -> crew definition
var _pending: Array[Dictionary] = []  # queued responses {wallId, crewId, ticks, readyAt}
var _in_flight: Dictionary = {}  # wallId -> true while a tagger is en route
var active_wall_duels: Dictionary = {}  # wallId -> duel dictionary
var _claimed_initial := false
var _rng := RandomNumberGenerator.new()
## Set by district.gd (windowed only) to spawn the visible rival who
## runs up and tags the wall; headless leaves it empty and responds
## instantly so the smoke test path is unchanged.
var _tagger_spawner := Callable()

func _ready() -> void:
	var parsed: Variant = DataLoader.load_json(CREWS_PATH, "RivalManager")
	if parsed is Array:
		for crew in parsed:
			DataLoader.require_fields(crew,
				["crewId", "name", "tag", "leaderAlias", "aggression",
				"responseType", "fillColor", "outlineColor", "crossOutColor", "territory"],
				"RivalManager: crew \"%s\"" % String(crew.get("crewId", "?")))
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
					wall_id, crew, _response_type_for(crew, wall_id))

func _on_wall_painted(wall_id: String, graffiti: Dictionary) -> void:
	if String(graffiti.get("creatorId", "")) != "player":
		return
	if _resolve_wall_duel_if_answered(wall_id, graffiti):
		return
	var crew := _offended_crew(wall_id)
	if crew.is_empty():
		return
	crew["relationshipToPlayer"] = int(crew.get("relationshipToPlayer", 0)) - 10
	if _in_flight.has(wall_id):
		return  # a tagger is already running at this wall
	for p in _pending:
		if p["wallId"] == wall_id:
			return
	_pending.append({
		"wallId": wall_id,
		"crewId": crew["crewId"],
		"ticks": 1 + _rng.randi_range(0, 1),
		"readyAt": Time.get_ticks_msec() + MIN_RESPONSE_DELAY_MS,
	})
	# A recruited lookout spots the trouble coming (Plan.md section 14).
	var lookout := CrewManager.first_with_role("lookout")
	if not lookout.is_empty():
		CrewManager.note_role_helped("lookout", 2)
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
	var now := Time.get_ticks_msec()
	var remaining: Array[Dictionary] = []
	for p in _pending:
		p["ticks"] = int(p["ticks"]) - 1
		# Hold the response until both the tick countdown elapses and the
		# 30-second floor has passed, so TOY never lands sooner than that.
		if p["ticks"] > 0 or now < int(p.get("readyAt", 0)):
			remaining.append(p)
		else:
			_try_respond(String(p["wallId"]), String(p["crewId"]))
	_pending = remaining
	_age_wall_duels()

## Counts down each open duel's deadline. One tick before expiry the writer
## gets a last-chance callout; at expiry the wall stays with the crew and the
## duel forfeits (recording the loss through the same path as a manual bail).
func _age_wall_duels() -> void:
	for wall_id in active_wall_duels.keys():
		var duel: Dictionary = active_wall_duels[wall_id]
		var left := int(duel.get("ticksLeft", WALL_DUEL_DEADLINE_TICKS)) - 1
		duel["ticksLeft"] = left
		if left <= 0:
			forfeit_wall_duel(wall_id, true)
		elif left == 1 and not bool(duel.get("warned", false)):
			duel["warned"] = true
			var wall_name := String(WallManager.wall_def(wall_id).get("name", wall_id))
			rival_event.emit("Last chance: paint %s back now or %s keeps it." % [
				wall_name, String(duel.get("crewName", "the crew"))], wall_id)

func _try_respond(wall_id: String, crew_id: String) -> void:
	var crew: Dictionary = crews.get(crew_id, {})
	var state: Dictionary = WallManager.wall_states.get(wall_id, {})
	if crew.is_empty() or String(state.get("ownerCrewId", "")) != "player":
		return  # The player's work is already gone; nothing to avenge.
	if _rng.randf() <= response_chance(wall_id, crew_id):
		_begin_response(wall_id, crew_id)

## Lets district.gd supply the visible tagger; unset headless.
func set_tagger_spawner(spawner: Callable) -> void:
	_tagger_spawner = spawner

## A scripted cross-out (mission story beats) routed through the same
## visible tagger as a retaliation, so the writer watches the rival run up
## and tag instead of "TOY" snapping on instantly (Product_reqs.md). With
## no spawner (headless/no world) it crosses out immediately, unchanged.
func scripted_cross_out(wall_id: String, crew: Dictionary, text := "TOY") -> void:
	if _tagger_spawner.is_valid() and not _in_flight.has(wall_id):
		var expected_id := _current_graffiti_id(wall_id)
		_in_flight[wall_id] = true
		_tagger_spawner.call(wall_id, crew, func() -> void:
			_in_flight.erase(wall_id)
			# Don't cross out fresh work: if the writer repainted this wall
			# while the rival was en route, the run-up is a no-op.
			if _current_graffiti_id(wall_id) == expected_id:
				WallManager.cross_out_wall(wall_id, crew, text))
	else:
		WallManager.cross_out_wall(wall_id, crew, text)

func _current_graffiti_id(wall_id: String) -> String:
	var state: Dictionary = WallManager.wall_states.get(wall_id, {})
	var current = state.get("currentGraffiti")
	return String(current.get("graffitiId", "")) if current != null else ""

## Spawns the rival who runs up and tags the wall, applying the paint
## only when they arrive. With no spawner (headless/no world) the paint
## lands immediately, preserving the original instant behavior.
func _begin_response(wall_id: String, crew_id: String) -> void:
	if _tagger_spawner.is_valid():
		var crew: Dictionary = crews.get(crew_id, {})
		_in_flight[wall_id] = true
		_tagger_spawner.call(wall_id, crew, func() -> void: respond(wall_id, crew_id))
	else:
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
		chance *= 1.0 - (1.0 - 0.6) * CrewManager.role_bonus_scale("lookout")
	var state: Dictionary = WallManager.wall_states.get(wall_id, {})
	var current: Dictionary = state.get("currentGraffiti") if state.get("currentGraffiti") != null else {}
	chance *= GameState.toy_response_multiplier(String(current.get("fontStyle", "")))
	return chance * StatsManager.response_damp()  # crew perks (Milestone 17)

## Executes a rival response immediately. Split out from the chance
## roll so tests and scripted missions can trigger it deterministically.
func respond(wall_id: String, crew_id: String) -> void:
	_in_flight.erase(wall_id)  # the tagger (if any) has arrived
	_clear_pending_for_wall(wall_id)
	var crew: Dictionary = crews[crew_id]
	var state: Dictionary = WallManager.wall_states[wall_id]
	if String(state.get("ownerCrewId", "")) != "player":
		return
	var current: Dictionary = state.get("currentGraffiti") if state.get("currentGraffiti") != null else {}
	var type_label := String(
		WallManager.styles.get(String(current.get("type", "tag")), {}).get("label", "work"))
	var def := WallManager.wall_def(wall_id)
	var wall_name := String(def.get("name", wall_id))
	var weight := int(def.get("visibility", 1))
	var who := "%s (%s)" % [String(crew.get("leaderAlias", "?")), String(crew.get("name", crew_id))]
	# Weak work in respected territory gets the "TOY" treatment
	# (Plan.md section 13); stronger work gets covered instead.
	if String(current.get("type", "tag")) == "tag" or GameState.rank in ["Toy", "Rookie"]:
		WallManager.cross_out_wall(wall_id, crew, "TOY")
		rival_event.emit('%s wrote "TOY" over your %s on %s! (-%d influence)' % [
			who, type_label, wall_name, weight], wall_id)
		_open_wall_duel(wall_id, crew, "cross_out")
	else:
		WallManager.apply_rival_graffiti(wall_id, crew, _response_type_for(crew, wall_id))
		rival_event.emit("%s covered your %s on %s. (-%d influence)" % [
			who, type_label, wall_name, weight], wall_id)
		_open_wall_duel(wall_id, crew, "cover")

func _open_wall_duel(wall_id: String, crew: Dictionary, pressure: String) -> void:
	var wall_name := String(WallManager.wall_def(wall_id).get("name", wall_id))
	active_wall_duels[wall_id] = {
		"wallId": wall_id,
		"crewId": String(crew.get("crewId", "")),
		"crewName": String(crew.get("name", "A rival crew")),
		"leaderAlias": String(crew.get("leaderAlias", "?")),
		"pressure": pressure,
		"startedAt": Time.get_unix_time_from_system(),
		"rewardRep": CrewManager.wall_duel_rep_reward(WALL_DUEL_REP_BONUS),
		"rewardCrewRep": CrewManager.wall_duel_crew_rep_reward(WALL_DUEL_CREW_REP),
		"forfeitRepPenalty": int(crew.get("duelForfeitRepPenalty", WALL_DUEL_FORFEIT_REP_PENALTY)),
		"forfeitCrewRepPenalty": int(crew.get("duelForfeitCrewRepPenalty", WALL_DUEL_FORFEIT_CREW_REP_PENALTY)),
		"forfeitMoralePenalty": int(crew.get("duelForfeitMoralePenalty", WALL_DUEL_FORFEIT_MORALE_PENALTY)),
		"ticksLeft": WALL_DUEL_DEADLINE_TICKS,
		"warned": false,
	}
	rival_event.emit("%s wants a wall duel at %s. Paint it back before they settle in." % [
		String(crew.get("leaderAlias", "A rival")), wall_name], wall_id)

func _resolve_wall_duel_if_answered(wall_id: String, graffiti: Dictionary) -> bool:
	if not active_wall_duels.has(wall_id):
		return false
	var duel: Dictionary = active_wall_duels[wall_id]
	active_wall_duels.erase(wall_id)
	var rep_bonus := int(duel.get("rewardRep", WALL_DUEL_REP_BONUS))
	var crew_rep_bonus := int(duel.get("rewardCrewRep", WALL_DUEL_CREW_REP))
	GameState.add_reputation(rep_bonus)
	GameState.add_crew_rep(crew_rep_bonus)
	GameState.note_rival_duel_win()
	CrewManager.note_role_helped("hype", 2)
	CrewManager.note_role_helped("battle_specialist", 4)
	CrewManager.adjust_morale(7, "duel won")
	var won_def := WallManager.wall_def(wall_id)
	var wall_name := String(won_def.get("name", wall_id))
	var wall_weight := int(won_def.get("visibility", 1))
	rival_event.emit("Wall duel won: %s is yours again. +%d rep, +%d crew rep (+%d influence back)." % [
		wall_name, rep_bonus, crew_rep_bonus, wall_weight], wall_id)
	# Answering a callout is the retaliation beat; do not immediately
	# queue a second response from the same paint stroke.
	return true

func _clear_pending_for_wall(wall_id: String) -> void:
	var remaining: Array[Dictionary] = []
	for p in _pending:
		if String(p.get("wallId", "")) != wall_id:
			remaining.append(p)
	_pending = remaining

## Ends a duel as a loss: either the writer walks away (expired=false) or the
## deadline ran out with the wall unanswered (expired=true). Both record the
## loss; only the message differs.
func forfeit_wall_duel(wall_id: String, expired := false) -> bool:
	if not active_wall_duels.has(wall_id):
		return false
	var duel: Dictionary = active_wall_duels[wall_id]
	active_wall_duels.erase(wall_id)
	var rep_penalty := mini(maxi(int(duel.get("forfeitRepPenalty", WALL_DUEL_FORFEIT_REP_PENALTY)), 0), GameState.reputation)
	var crew_penalty := maxi(int(duel.get("forfeitCrewRepPenalty", WALL_DUEL_FORFEIT_CREW_REP_PENALTY)), 0)
	var morale_penalty := maxi(int(duel.get("forfeitMoralePenalty", WALL_DUEL_FORFEIT_MORALE_PENALTY)), 0)
	GameState.note_rival_duel_loss()
	if rep_penalty > 0:
		GameState.add_reputation(-rep_penalty)
	if crew_penalty > 0:
		GameState.add_crew_rep(-crew_penalty)
	CrewManager.adjust_morale(-morale_penalty, "duel lost")
	var wall_name := String(WallManager.wall_def(wall_id).get("name", wall_id))
	var crew_name := String(duel.get("crewName", "the rival crew"))
	var penalty_text := " -%d rep, -%d crew rep." % [rep_penalty, crew_penalty]
	if expired:
		var message := "Wall duel lost: you let the callout cool and %s kept %s.%s" % [
			crew_name, wall_name, penalty_text]
		rival_event.emit(message, wall_id)
	else:
		rival_event.emit("Wall duel lost: %s stayed with %s.%s" % [wall_name, crew_name, penalty_text], wall_id)
	return true

func save_state() -> Dictionary:
	return {
		"pending": _pending.duplicate(true),
		"active_wall_duels": active_wall_duels.duplicate(true),
	}

func load_state(data: Dictionary) -> void:
	_pending.clear()
	var pending_data: Array = data.get("pending", [])
	for entry in pending_data:
		if entry is Dictionary:
			_pending.append((entry as Dictionary).duplicate(true))
	active_wall_duels = data.get("active_wall_duels", {}).duplicate(true)
	_in_flight.clear()

## The crew's signature type, downgraded to a throw-up where surface
## rules block it (Milestone 16) — rivals play by the wall's rules too.
func _response_type_for(crew: Dictionary, wall_id: String) -> String:
	var type := String(crew.get("responseType", "throwup"))
	if WallManager.surface_block_reason(type, WallManager.wall_def(wall_id)) != "":
		return "throwup"
	return type
