extends Node
## District territory scoring (Plan.md sections 24 and 35, Milestone 6).
## Loads Data/districts.json. Each wall contributes its visibility as
## weight toward whoever owns it; blank walls keep their weight
## unclaimed, so taking a block means actually covering it. Crossing
## the district's claim threshold once grants a reputation reward.
## Autoloaded as TerritoryManager.

signal territory_changed(district_id: String)
signal district_claimed(district_id: String, district: Dictionary)

const DISTRICTS_PATH := "res://Data/districts.json"
## Disrespected (crossed-out) work holds only half its weight.
const CROSSED_OUT_FACTOR := 0.5

var districts: Dictionary = {}  # districtId -> definition + runtime "claimed"

func _ready() -> void:
	var parsed: Variant = _load_json(DISTRICTS_PATH)
	if parsed is Array:
		for d in parsed:
			d["claimed"] = false
			districts[d["districtId"]] = d
	WallManager.wall_painted.connect(
		func(wall_id: String, _graffiti: Dictionary) -> void: _on_wall_changed(wall_id))
	WallManager.wall_crossed_out.connect(_on_wall_changed)

func is_claimed(district_id: String) -> bool:
	return bool(districts.get(district_id, {}).get("claimed", false))

## owner -> share of the district's total wall weight (0..1).
func influence(district_id: String) -> Dictionary:
	var weights: Dictionary = {}
	var total := 0.0
	for def in WallManager.wall_defs:
		if String(def.get("districtId", "")) != district_id:
			continue
		var weight := float(def.get("visibility", 1))
		total += weight
		var state: Dictionary = WallManager.wall_states.get(String(def["wallId"]), {})
		var owner := String(state.get("ownerCrewId", "none"))
		if owner == "none" or String(state.get("state", "blank")) == "blank":
			continue
		if String(state.get("state", "")) == "crossed_out":
			weight *= CROSSED_OUT_FACTOR
		weights[owner] = float(weights.get(owner, 0.0)) + weight
	var shares: Dictionary = {}
	if total > 0.0:
		for owner in weights:
			shares[owner] = float(weights[owner]) / total
	return shares

func owner_label(owner: String) -> String:
	if owner == "player":
		return "You"
	return String(RivalManager.crews.get(owner, {}).get("tag", owner))

## One footer line for the map: shares by owner, then claim status.
func summary_text(district_id: String) -> String:
	var district: Dictionary = districts.get(district_id, {})
	var shares := influence(district_id)
	var owners: Array = shares.keys()
	owners.sort_custom(func(a: String, b: String) -> bool: return shares[a] > shares[b])
	var parts: PackedStringArray = []
	var taken := 0.0
	for owner in owners:
		taken += float(shares[owner])
		parts.append("%s %d%%" % [owner_label(owner), roundi(float(shares[owner]) * 100)])
	parts.append("Open %d%%" % roundi(maxf(1.0 - taken, 0.0) * 100))
	var status := "CLAIMED — this block is yours" if district.get("claimed", false) \
		else "claim at %d%%" % roundi(float(district.get("claimThreshold", 0.5)) * 100)
	return "%s   (%s)" % ["  ·  ".join(parts), status]

func _on_wall_changed(wall_id: String) -> void:
	var district_id := String(WallManager.wall_def(wall_id).get("districtId", ""))
	if not districts.has(district_id):
		return
	territory_changed.emit(district_id)
	var district: Dictionary = districts[district_id]
	if district["claimed"]:
		return
	if float(influence(district_id).get("player", 0.0)) >= float(district.get("claimThreshold", 0.5)):
		district["claimed"] = true
		GameState.add_reputation(int(district.get("claimRepBonus", 100)))
		district_claimed.emit(district_id, district)

func _load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TerritoryManager: cannot open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("TerritoryManager: invalid JSON in %s" % path)
	return parsed
