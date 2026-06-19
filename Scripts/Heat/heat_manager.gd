extends Node
## Heat system (Plan.md section 12) plus the City Cleanup faction
## (sections 18 and 33). Painting builds heat — more for bigger work on
## riskier walls — which raises reputation rewards for risky actions
## but also speeds up cleanup sweeps that buff painted walls back to
## gray. Heat is **per district** (Milestone 18): paint heats the block
## the wall is on, and a block cools twice as fast while the player is
## elsewhere — leaving the block IS laying low. The bare `heat`
## property reads/writes the district the player is standing in.
## Autoloaded as HeatManager.

signal heat_changed(new_heat: float, gained: float)
signal heat_level_changed(level: String, rising: bool)
signal cleanup_event(message: String, wall_id: String)

## One simulation tick = one "in-game hour" (matches RivalManager).
const TICK_SECONDS := 12.0
## Cleanup sweeps run every N ticks — a compressed "in-game day"
## (Plan.md section 33) so buffing shows up within a play session.
const CLEANUP_PERIOD_TICKS := 6
const DECAY_PER_TICK := 2.0
## Unattended blocks cool faster (Plan.md section 12, Milestone 18).
const ABSENT_DECAY_MULT := 2.0
const MAX_HEAT := 100.0
const GraffitiFonts := preload("res://Scripts/Walls/graffiti_font_library.gd")

const LEVELS := [
	{"name": "Cold", "min": 0.0},
	{"name": "Low", "min": 10.0},
	{"name": "Watched", "min": 35.0},
	{"name": "Hot", "min": 60.0},
	{"name": "Blazing", "min": 85.0},
]

## districtId -> heat. Districts default to 0 — only touched ones
## appear, so the dict stays JSON-friendly for saves.
var heat_by_district: Dictionary = {}
## Facade: the heat of the district the player is in. Every pre-M18
## call site (and the HUD) keeps working through this property.
var heat: float:
	get:
		return heat_in(GameState.current_district_id)
	set(value):
		_set_heat(GameState.current_district_id, value, 0.0)
var _ticks_until_cleanup := CLEANUP_PERIOD_TICKS
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	WallManager.wall_painted.connect(_on_wall_painted)
	GameState.district_changed.connect(func(_district_id: String) -> void:
		# Same signal the HUD/patrols already watch — re-announce the
		# new block's heat so displays and guard counts snap over.
		heat_changed.emit(heat, 0.0))
	var timer := Timer.new()
	timer.wait_time = TICK_SECONDS
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)

func heat_in(district_id: String) -> float:
	return float(heat_by_district.get(district_id, 0.0))

func level_name(district_id := "") -> String:
	var value := heat_in(district_id) if district_id != "" else heat
	var result: String = LEVELS[0]["name"]
	for level in LEVELS:
		if value >= float(level["min"]):
			result = String(level["name"])
	return result

## Plan.md section 12: higher heat means greater reputation reward for
## risky actions. Tops out at 1.5x when the district's heat is maxed.
func rep_multiplier(district_id := "") -> float:
	var value := heat_in(district_id) if district_id != "" else heat
	return 1.0 + value / 200.0

func add_heat(amount: float, district_id := "") -> void:
	var did := district_id if district_id != "" else GameState.current_district_id
	if amount > 0.0:
		amount *= GameState.difficulty_heat_multiplier()
	_set_heat(did, heat_in(did) + amount, amount)

## Buffs a wall immediately. Split from the sweep's chance roll so
## tests and scripted missions can trigger cleanup deterministically.
func force_cleanup(wall_id: String) -> bool:
	if not WallManager.buff_wall(wall_id):
		return false
	cleanup_event.emit("City workers buffed %s back to gray." %
		String(WallManager.wall_def(wall_id).get("name", wall_id)), wall_id)
	return true

## Getting caught closes the incident (Milestone 10 patrols): the
## current block's heat settles down to at most `ceiling` — they got
## their man, the block cools off.
func settle(ceiling: float) -> void:
	if heat > ceiling:
		_set_heat(GameState.current_district_id, ceiling, 0.0)

func advance_time_ticks(ticks: int) -> void:
	for _i in range(maxi(ticks, 0)):
		_on_tick()

func save_state() -> Dictionary:
	return {
		"by_district": heat_by_district.duplicate(true),
		"ticks_until_cleanup": _ticks_until_cleanup,
	}

func load_state(data: Dictionary) -> void:
	_ticks_until_cleanup = int(data.get("ticks_until_cleanup", _ticks_until_cleanup))
	heat_by_district = data.get("by_district", {}).duplicate(true)
	heat_changed.emit(heat, 0.0)

## Heat from one player graffiti: the style's base heat scaled by wall
## risk — high-risk zones and landmark walls draw the most attention.
## The heat lands on the district the WALL is in (Milestone 18).
func _on_wall_painted(wall_id: String, graffiti: Dictionary) -> void:
	if String(graffiti.get("creatorId", "")) != "player":
		return
	var def := WallManager.wall_def(wall_id)
	var style: Dictionary = WallManager.styles.get(String(graffiti.get("type", "tag")), {})
	var risk := float(def.get("risk", 1))
	var font_style := GraffitiFonts.style_def(String(graffiti.get("fontStyle", "")))
	# Stealth stat/perks dampen the noise (Milestone 17).
	add_heat(float(style.get("heatValue", 4)) * (0.5 + 0.25 * risk)
		* float(font_style.get("exposure", 1.0))
		* StatsManager.heat_multiplier(),
		String(def.get("districtId", "")))

func _on_tick() -> void:
	# Every block cools; the ones the player left cool twice as fast
	# (Milestone 18: leaving the block is laying low).
	for district_id in heat_by_district.keys():
		var value := heat_in(String(district_id))
		if value <= 0.0:
			continue
		var decay := DECAY_PER_TICK if String(district_id) == GameState.current_district_id \
			else DECAY_PER_TICK * ABSENT_DECAY_MULT
		_set_heat(String(district_id), maxf(value - decay, 0.0), 0.0)
	_ticks_until_cleanup -= 1
	if _ticks_until_cleanup <= 0:
		_ticks_until_cleanup = CLEANUP_PERIOD_TICKS
		_run_cleanup_sweep()

## City cleanup pass: each painted wall rolls against its cleanupChance,
## inflated by its own district's heat for the player's work (Plan.md
## section 12: higher heat, faster cleanup response). At most one wall
## is buffed per sweep so the city never wipes the whole map at once.
func _run_cleanup_sweep() -> void:
	var fixer_helped := false
	for wall_id in WallManager.wall_states:
		var state: Dictionary = WallManager.wall_states[wall_id]
		if state.get("currentGraffiti") == null:
			continue
		var def := WallManager.wall_def(String(wall_id))
		var chance := float(def.get("cleanupChance", 0.1))
		if String(state.get("ownerCrewId", "")) == "player":
			chance *= 1.0 + heat_in(String(def.get("districtId", ""))) / 40.0
			if CrewManager.has_role("fixer"):
				fixer_helped = true
				chance *= CrewManager.cleanup_chance_multiplier()
		if _rng.randf() <= minf(chance, 0.85):
			if fixer_helped:
				CrewManager.note_role_helped("fixer", 1)
			force_cleanup(String(wall_id))
			return
	if fixer_helped:
		CrewManager.note_role_helped("fixer", 1)

func _set_heat(district_id: String, new_heat: float, gained: float) -> void:
	var old_heat := heat_in(district_id)
	var old_level := level_name(district_id)
	heat_by_district[district_id] = clampf(new_heat, 0.0, MAX_HEAT)
	# Listeners (HUD label, patrol counts) track the player's block;
	# other districts simmer silently until the player returns.
	if district_id == GameState.current_district_id:
		heat_changed.emit(heat, gained)
		var new_level := level_name(district_id)
		if new_level != old_level:
			heat_level_changed.emit(new_level, heat_in(district_id) > old_heat)
