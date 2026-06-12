extends Node
## Heat system (Plan.md section 12) plus the City Cleanup faction
## (sections 18 and 33). Painting builds heat — more for bigger work on
## riskier walls — which raises reputation rewards for risky actions
## but also speeds up cleanup sweeps that buff painted walls back to
## gray. Laying low cools heat one notch per simulation tick.
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
const MAX_HEAT := 100.0

const LEVELS := [
	{"name": "Cold", "min": 0.0},
	{"name": "Low", "min": 10.0},
	{"name": "Watched", "min": 35.0},
	{"name": "Hot", "min": 60.0},
	{"name": "Blazing", "min": 85.0},
]

var heat := 0.0
var _ticks_until_cleanup := CLEANUP_PERIOD_TICKS
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	WallManager.wall_painted.connect(_on_wall_painted)
	var timer := Timer.new()
	timer.wait_time = TICK_SECONDS
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)

func level_name() -> String:
	var result: String = LEVELS[0]["name"]
	for level in LEVELS:
		if heat >= float(level["min"]):
			result = String(level["name"])
	return result

## Plan.md section 12: higher heat means greater reputation reward for
## risky actions. Tops out at 1.5x when heat is maxed.
func rep_multiplier() -> float:
	return 1.0 + heat / 200.0

func add_heat(amount: float) -> void:
	_set_heat(heat + amount, amount)

## Buffs a wall immediately. Split from the sweep's chance roll so
## tests and scripted missions can trigger cleanup deterministically.
func force_cleanup(wall_id: String) -> bool:
	if not WallManager.buff_wall(wall_id):
		return false
	cleanup_event.emit("City workers buffed %s back to gray." %
		String(WallManager.wall_def(wall_id).get("name", wall_id)), wall_id)
	return true

## Getting caught closes the incident (Milestone 10 patrols): heat
## settles down to at most `ceiling` — they got their man, the block
## cools off.
func settle(ceiling: float) -> void:
	if heat > ceiling:
		_set_heat(ceiling, 0.0)

func save_state() -> Dictionary:
	return {"heat": heat, "ticks_until_cleanup": _ticks_until_cleanup}

func load_state(data: Dictionary) -> void:
	_ticks_until_cleanup = int(data.get("ticks_until_cleanup", _ticks_until_cleanup))
	_set_heat(float(data.get("heat", heat)), 0.0)

## Heat from one player graffiti: the style's base heat scaled by wall
## risk — high-risk zones and landmark walls draw the most attention.
func _on_wall_painted(wall_id: String, graffiti: Dictionary) -> void:
	if String(graffiti.get("creatorId", "")) != "player":
		return
	var style: Dictionary = WallManager.styles.get(String(graffiti.get("type", "tag")), {})
	var risk := float(WallManager.wall_def(wall_id).get("risk", 1))
	# Stealth stat/perks dampen the noise (Milestone 17).
	add_heat(float(style.get("heatValue", 4)) * (0.5 + 0.25 * risk)
		* StatsManager.heat_multiplier())

func _on_tick() -> void:
	if heat > 0.0:
		_set_heat(maxf(heat - DECAY_PER_TICK, 0.0), 0.0)  # laying low pays off
	_ticks_until_cleanup -= 1
	if _ticks_until_cleanup <= 0:
		_ticks_until_cleanup = CLEANUP_PERIOD_TICKS
		_run_cleanup_sweep()

## City cleanup pass: each painted wall rolls against its cleanupChance,
## inflated by heat for the player's own work (Plan.md section 12:
## higher heat, faster cleanup response). At most one wall is buffed
## per sweep so the city never wipes the whole map at once.
func _run_cleanup_sweep() -> void:
	for wall_id in WallManager.wall_states:
		var state: Dictionary = WallManager.wall_states[wall_id]
		if state.get("currentGraffiti") == null:
			continue
		var chance := float(WallManager.wall_def(String(wall_id)).get("cleanupChance", 0.1))
		if String(state.get("ownerCrewId", "")) == "player":
			chance *= 1.0 + heat / 40.0
		if _rng.randf() <= minf(chance, 0.85):
			force_cleanup(String(wall_id))
			return

func _set_heat(new_heat: float, gained: float) -> void:
	var old_heat := heat
	var old_level := level_name()
	heat = clampf(new_heat, 0.0, MAX_HEAT)
	heat_changed.emit(heat, gained)
	var new_level := level_name()
	if new_level != old_level:
		heat_level_changed.emit(new_level, heat > old_heat)
