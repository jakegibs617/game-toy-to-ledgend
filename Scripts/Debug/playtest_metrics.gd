extends Node
## Optional playtest instrumentation for Plan_v3.md Milestone 27.
## It listens to existing system signals but records nothing until a
## capture is explicitly started, so normal play and saves stay clean.

signal metrics_event(name: String, details: Dictionary)

const METRICS_PATH := "user://toy_to_legend_playtest_metrics.json"

var enabled := false
var write_to_disk := false
var label := ""
var started_msec := 0
var beats: Dictionary = {}
var counters: Dictionary = {}
var events: Array = []

func _ready() -> void:
	_connect_signals()
	if OS.get_environment("PLAYTEST_METRICS") == "1" \
			and OS.get_environment("SMOKE_TEST") != "1":
		write_to_disk = true
		start_capture("playtest")

func start_capture(capture_label := "playtest") -> void:
	label = capture_label
	started_msec = Time.get_ticks_msec()
	beats.clear()
	counters.clear()
	events.clear()
	enabled = true
	record_event("capture_started", {"label": label})

func stop_capture() -> Dictionary:
	var snapshot := capture_snapshot()
	if enabled:
		record_event("capture_stopped", {})
	enabled = false
	return snapshot

func capture_snapshot() -> Dictionary:
	return {
		"label": label,
		"elapsedSeconds": _elapsed_seconds(),
		"beats": beats.duplicate(true),
		"counters": counters.duplicate(true),
		"events": events.duplicate(true),
	}

func summary_text() -> String:
	var names: Array = beats.keys()
	names.sort()
	var parts: PackedStringArray = []
	for name in names:
		var beat: Dictionary = beats[name]
		parts.append("%s=%.2fs" % [name, float(beat.get("time", 0.0))])
	return "%s beats: %s; counters: %s" % [
		label,
		", ".join(parts),
		JSON.stringify(counters),
	]

func record_event(name: String, details := {}) -> void:
	if not enabled:
		return
	var entry := {
		"name": name,
		"time": _elapsed_seconds(),
		"details": (details as Dictionary).duplicate(true),
	}
	events.append(entry)
	metrics_event.emit(name, entry["details"])
	if write_to_disk:
		_flush_to_disk()

func mark_first(name: String, details := {}) -> void:
	if not enabled or beats.has(name):
		return
	var beat := {
		"time": _elapsed_seconds(),
		"details": (details as Dictionary).duplicate(true),
	}
	beats[name] = beat
	record_event(name, beat["details"])

func increment(name: String, amount := 1, details := {}) -> void:
	if not enabled:
		return
	counters[name] = int(counters.get(name, 0)) + amount
	record_event(name, details)

func balance_snapshot() -> Dictionary:
	return {
		"graffiti": _graffiti_balance(),
		"missions": _mission_balance(),
		"districts": _district_balance(),
		"heat": _heat_balance(),
		"patrols": _patrol_balance(),
		"trains": _train_balance(),
		"gallery": _gallery_balance(),
		"stats": _stats_balance(),
		"supplies": _supply_balance(),
		"caps": _cap_balance(),
		"crew": _crew_balance(),
	}

func balance_summary_text() -> String:
	var snapshot := balance_snapshot()
	return "styles=%d missions=%d districts=%d trains=%d shop_items=%d caps=%d morale=%.2fx..%.2fx heat_tick=%.1fs" % [
		(snapshot["graffiti"] as Dictionary).size(),
		(snapshot["missions"] as Array).size(),
		(snapshot["districts"] as Dictionary).size(),
		(snapshot["trains"] as Dictionary).size(),
		(snapshot["supplies"] as Dictionary).size(),
		(snapshot["caps"] as Dictionary).size(),
		float((snapshot["crew"] as Dictionary).get("moraleFactorMin", 1.0)),
		float((snapshot["crew"] as Dictionary).get("moraleFactorMax", 1.0)),
		float((snapshot["heat"] as Dictionary).get("tickSeconds", 0.0)),
	]

## Plan_v3.md Milestone 31: documented desktop budgets for the prototype.
## These are soft ceilings — `runtime_budget_snapshot` flags anything over
## so we notice runtime waste before adding another district or crowd
## system, not hard limits that fail the build.
const RUNTIME_BUDGETS := {
	"worldNodeCount": 4000,   # nodes under the active district root
	"meshInstances": 2500,    # MeshInstance3D under the district root
	"walls": 80,              # spawned paintable walls
	"materialCacheSize": 64,  # district street/material cache entries
}

## Plan_v3.md Milestone 31 profiling pass. Returns a JSON-serializable
## picture of what the running city costs: node counts, spawned
## wall/train/prop counts, material cache size, character-visual import
## status, and a frame snapshot where the renderer is live. `root` is the
## active district node (it owns the material cache); pass the scene root.
func runtime_budget_snapshot(root: Node) -> Dictionary:
	var histogram := {}
	var world_nodes := _node_type_histogram(root, histogram) if root != null else 0
	var tree := root.get_tree() if root != null else null
	var interactables := tree.get_nodes_in_group("interactable").size() if tree != null else 0
	var snapshot := {
		"worldNodeCount": world_nodes,
		"meshInstances": int(histogram.get("MeshInstance3D", 0)),
		"walls": WallManager.wall_nodes.size(),
		"trains": TrainManager.train_nodes.size(),
		"interactables": interactables,
		"materialCacheSize": _material_cache_size(root),
		"nodeTypes": histogram,
		"characterVisual": _character_visual_report(tree),
		"frame": _frame_snapshot(),
	}
	snapshot["overBudget"] = _over_budget(snapshot)
	return snapshot

## Compact one-line readout for smoke logs and the RUNTIME_BUDGET print.
func runtime_budget_summary_text(root: Node) -> String:
	var snapshot := runtime_budget_snapshot(root)
	var over: Array = snapshot["overBudget"]
	var visual: Dictionary = snapshot["characterVisual"]
	return "world_nodes=%d meshes=%d walls=%d trains=%d interactables=%d material_cache=%d visual=%s%s" % [
		int(snapshot["worldNodeCount"]),
		int(snapshot["meshInstances"]),
		int(snapshot["walls"]),
		int(snapshot["trains"]),
		int(snapshot["interactables"]),
		int(snapshot["materialCacheSize"]),
		String(visual.get("kind", "?")),
		"" if over.is_empty() else "; OVER BUDGET: %s" % ", ".join(over),
	]

## Recursively tally descendants of `root` by engine class. Returns the
## total node count (inclusive of `root`) and fills `histogram` in place.
func _node_type_histogram(root: Node, histogram: Dictionary) -> int:
	var cls := root.get_class()
	histogram[cls] = int(histogram.get(cls, 0)) + 1
	var total := 1
	for child in root.get_children():
		total += _node_type_histogram(child, histogram)
	return total

## The district node owns the street/building material cache (Milestone
## 24). Returns its entry count, or -1 when the root doesn't expose one.
func _material_cache_size(root: Node) -> int:
	if root != null and "_material_cache" in root:
		return (root.get("_material_cache") as Dictionary).size()
	return -1

## Which player model set actually loaded: the animated rooster clips, the
## static GLB fallback, or the capsule placeholder (import unavailable).
func _character_visual_report(tree: SceneTree) -> Dictionary:
	if tree == null:
		return {"kind": "none"}
	var player := tree.get_first_node_in_group("player")
	if player == null or not player.has_method("visual_report"):
		return {"kind": "none"}
	return player.visual_report()

## Live renderer frame snapshot. Process/render monitors read 0 on the
## headless server, which is exactly what we want recorded there.
func _frame_snapshot() -> Dictionary:
	return {
		"fps": Engine.get_frames_per_second(),
		"processMsec": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"renderObjects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"staticMemMb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"treeNodeCount": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}

## Names of the budget categories currently exceeded (materialCacheSize of
## -1 means "not measurable here" and never counts as over).
func _over_budget(snapshot: Dictionary) -> Array:
	var over: Array = []
	for key in RUNTIME_BUDGETS:
		var value := int(snapshot.get(key, 0))
		if value >= 0 and value > int(RUNTIME_BUDGETS[key]):
			over.append(key)
	return over

func _connect_signals() -> void:
	GameState.rank_changed.connect(func(rank: String) -> void:
		mark_first("first_rank_up", {"rank": rank, "rep": GameState.reputation}))
	GameState.district_changed.connect(func(district_id: String) -> void:
		if district_id == "district_canal_side":
			mark_first("canal_side_entry", {"rep": GameState.reputation})
		elif district_id == "district_rooftop_row":
			mark_first("rooftop_row_entry", {"rep": GameState.reputation}))
	GameState.paint_changed.connect(func(new_paint: int) -> void:
		if new_paint <= 0:
			increment("paint_starvation_moments", 1, {"paint": new_paint})
		elif new_paint <= 3:
			mark_first("first_low_paint", {"paint": new_paint}))
	GameState.cash_changed.connect(func(new_cash: int) -> void:
		if new_cash <= 0:
			increment("cash_starvation_moments", 1, {"cash": new_cash})
		elif new_cash <= 5:
			mark_first("first_low_cash", {"cash": new_cash}))
	GameState.player_event.connect(func(message: String) -> void:
		if message.begins_with("You slipped"):
			increment("fall_count", 1, {"message": message}))
	WallManager.wall_painted.connect(func(wall_id: String, graffiti: Dictionary) -> void:
		if String(graffiti.get("creatorId", "")) == "player":
			mark_first("first_paint", {
				"wallId": wall_id,
				"type": String(graffiti.get("type", "")),
				"rep": int(graffiti.get("repValue", 0)),
			}))
	TerritoryManager.district_claimed.connect(func(district_id: String, _district: Dictionary) -> void:
		mark_first("%s_claimed" % district_id, {"rep": GameState.reputation}))
	PatrolManager.player_caught.connect(func(_guard: PatrolGuard) -> void:
		increment("caught_count", 1, {
			"rep": GameState.reputation,
			"paint": GameState.paint,
			"heat": HeatManager.heat,
		}))
	TrainManager.train_painted.connect(func(train_id: String, graffiti: Dictionary) -> void:
		mark_first("first_train_painted", {
			"trainId": train_id,
			"rep": int(graffiti.get("repValue", 0)),
		}))
	GalleryManager.commission_resolved.connect(func(result: Dictionary) -> void:
		if bool(result.get("accepted", false)):
			mark_first("first_gallery_sale", result)
		else:
			mark_first("first_gallery_refusal", result))

func _elapsed_seconds() -> float:
	if started_msec <= 0:
		return 0.0
	return float(Time.get_ticks_msec() - started_msec) / 1000.0

func _flush_to_disk() -> void:
	var file := FileAccess.open(METRICS_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("PlaytestMetrics: couldn't write %s" % METRICS_PATH)
		return
	file.store_string(JSON.stringify(capture_snapshot(), "\t"))

func _graffiti_balance() -> Dictionary:
	var rows := {}
	for type in WallManager.styles:
		var style: Dictionary = WallManager.styles[type]
		rows[type] = {
			"label": String(style.get("label", type)),
			"paintCost": SupplyManager.paint_cost(style),
			"baseValue": int(style.get("baseValue", 0)),
			"heatValue": float(style.get("heatValue", 0.0)),
			"surfaces": style.get("surfaces", []),
			"requiresCrew": bool(style.get("requiresCrew", false)),
		}
	return rows

func _mission_balance() -> Array:
	var rows: Array = []
	for chain in MissionManager.chains:
		for mission in chain.get("missions", []):
			rows.append({
				"chainId": String(chain.get("chainId", "")),
				"missionId": String(mission.get("missionId", "")),
				"title": String(mission.get("title", "")),
				"onComplete": mission.get("onComplete", {}),
			})
	return rows

func _district_balance() -> Dictionary:
	var rows := {}
	for district_id in TerritoryManager.districts:
		var district: Dictionary = TerritoryManager.districts[district_id]
		rows[district_id] = {
			"name": String(district.get("name", district_id)),
			"claimThreshold": float(district.get("claimThreshold", 0.0)),
			"claimRepBonus": int(district.get("claimRepBonus", 0)),
			"payoutPerWeight": float(district.get("payoutPerWeight", 0.0)),
			"decayRep": int(district.get("decayRep", 0)),
		}
	return rows

func _heat_balance() -> Dictionary:
	return {
		"tickSeconds": HeatManager.TICK_SECONDS,
		"cleanupPeriodTicks": HeatManager.CLEANUP_PERIOD_TICKS,
		"decayPerTick": HeatManager.DECAY_PER_TICK,
		"absentDecayMult": HeatManager.ABSENT_DECAY_MULT,
		"maxHeat": HeatManager.MAX_HEAT,
		"levels": HeatManager.LEVELS.duplicate(true),
	}

func _patrol_balance() -> Dictionary:
	return PatrolManager.config.duplicate(true)

func _train_balance() -> Dictionary:
	var rows := {}
	for def in TrainManager.train_defs:
		rows[String(def.get("trainId", ""))] = {
			"label": String(def.get("label", "")),
			"paintCost": int(def.get("paintCost", 0)),
			"paintRep": int(def.get("paintRep", 0)),
			"passRep": int(def.get("passRep", 0)),
			"heatValue": float(def.get("heatValue", 0.0)),
			"serviceDistricts": def.get("serviceDistricts", []),
		}
	return rows

func _gallery_balance() -> Dictionary:
	return GalleryManager.config.duplicate(true)

func _stats_balance() -> Dictionary:
	var rows := {
		"stats": StatsManager.stat_defs.duplicate(true),
		"perks": StatsManager.perk_trees.duplicate(true),
		"multipliers": {
			"rep_tag": StatsManager.rep_multiplier("tag"),
			"heat": StatsManager.heat_multiplier(),
			"spotRange": StatsManager.spot_range_multiplier(),
			"price": StatsManager.price_multiplier(),
			"delivery": StatsManager.delivery_multiplier(),
			"crewPrice": CrewManager.shop_price_multiplier(),
			"crewDelivery": CrewManager.delivery_multiplier(),
			"crewHype": CrewManager.hype_payout_multiplier(),
			"crewCleanup": CrewManager.cleanup_chance_multiplier(),
			"payout": StatsManager.payout_multiplier(),
			"decay": StatsManager.decay_multiplier(),
		},
	}
	return rows

func _supply_balance() -> Dictionary:
	var rows := {}
	for item in SupplyManager.catalog:
		rows[String(item.get("itemId", ""))] = {
			"name": String(item.get("name", "")),
			"price": SupplyManager.item_price(item),
			"paint": int(item.get("paint", 0)),
			"unlockType": String(item.get("unlockType", "")),
			"repeatable": bool(item.get("repeatable", false)),
		}
	rows["delivery"] = SupplyManager.delivery.duplicate(true)
	return rows

func _cap_balance() -> Dictionary:
	var rows := {}
	for cap_id in SupplyManager.cap_order:
		var cap: Dictionary = SupplyManager.cap_def(String(cap_id))
		rows[String(cap_id)] = {
			"name": String(cap.get("name", cap_id)),
			"paintDelta": int(cap.get("paintDelta", 0)),
			"repMultiplier": float(cap.get("repMultiplier", 1.0)),
			"suspicion": float(cap.get("suspicion", 0.0)),
			"default": bool(cap.get("default", false)),
		}
	return rows

func _crew_balance() -> Dictionary:
	return {
		"moraleMin": 0,
		"moraleNeutral": CrewManager.MORALE_NEUTRAL,
		"moraleMax": CrewManager.MAX_MORALE,
		"moraleFactorMin": CrewManager.morale_factor_for(0),
		"moraleFactorNeutral": CrewManager.morale_factor_for(CrewManager.MORALE_NEUTRAL),
		"moraleFactorMax": CrewManager.morale_factor_for(CrewManager.MAX_MORALE),
	}
