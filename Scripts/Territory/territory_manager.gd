extends Node
## District territory scoring (GDD sections 24 and 35, Milestone 6).
## Loads Data/districts.json. Each wall contributes its visibility as
## weight toward whoever owns it; blank walls keep their weight
## unclaimed, so taking a block means actually covering it. Crossing
## the district's claim threshold once grants a reputation reward.
## Autoloaded as TerritoryManager.

signal territory_changed(district_id: String)
signal district_claimed(district_id: String, district: Dictionary)
signal territory_event(message: String)

const DISTRICTS_PATH := "res://Data/districts.json"
const DataLoader := preload("res://Scripts/Data/data_loader.gd")
## Disrespected (crossed-out) work holds only half its weight.
const CROSSED_OUT_FACTOR := 0.5
## Reputation decay tick (Milestone 17, GDD §11 "visibility
## over time"): every compressed in-game "day", standing work pays and
## unattended districts cool.
const DECAY_TICK_SECONDS := 36.0

var districts: Dictionary = {}  # districtId -> definition + runtime "claimed"

func _ready() -> void:
	var parsed: Variant = DataLoader.load_json(DISTRICTS_PATH, "TerritoryManager")
	if parsed is Array:
		for d in parsed:
			DataLoader.require_fields(d,
				["districtId", "name", "claimThreshold", "claimRepBonus"],
				"TerritoryManager: district \"%s\"" % String(d.get("districtId", "?")))
			d["claimed"] = false
			districts[d["districtId"]] = d
	WallManager.wall_painted.connect(
		func(wall_id: String, _graffiti: Dictionary) -> void: _on_wall_changed(wall_id))
	WallManager.wall_crossed_out.connect(_on_wall_changed)
	WallManager.wall_buffed.connect(_on_wall_changed)
	var timer := Timer.new()
	timer.wait_time = DECAY_TICK_SECONDS
	timer.autostart = true
	timer.timeout.connect(_on_decay_tick)
	add_child(timer)

func is_claimed(district_id: String) -> bool:
	return bool(districts.get(district_id, {}).get("claimed", false))

func save_state() -> Dictionary:
	var claimed := {}
	for district_id in districts:
		claimed[district_id] = bool(districts[district_id].get("claimed", false))
	return {"claimed": claimed}

func load_state(data: Dictionary) -> void:
	var claimed: Dictionary = data.get("claimed", {})
	for district_id in claimed:
		if districts.has(district_id):
			districts[district_id]["claimed"] = bool(claimed[district_id])
			territory_changed.emit(String(district_id))

## owner -> share of the district's total wall weight (0..1).
func influence(district_id: String) -> Dictionary:
	var weights: Dictionary = {}
	var total := 0.0
	for def in WallManager.wall_defs:
		if String(def.get("districtId", "")) != district_id:
			continue
		# Territory-neutral surfaces (e.g. a storefront window you scratch)
		# don't count toward who holds the block (Product_reqs.md glass).
		if bool(def.get("territoryNeutral", false)):
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
	if owner == "city":
		return "City"  # cleanup pressure (GDD §24)
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

## Visibility weight of the player's work that still pays: owned walls
## whose graffiti stands clean. Crossed-out and buffed work stops
## paying (GDD §11) — buffed walls belong to the city again,
## crossed-out ones are excluded here.
func standing_player_weight(district_id: String) -> float:
	var weight := 0.0
	for def in WallManager.wall_defs:
		if String(def.get("districtId", "")) != district_id:
			continue
		if bool(def.get("territoryNeutral", false)):
			continue
		var state: Dictionary = WallManager.wall_states.get(String(def["wallId"]), {})
		if String(state.get("ownerCrewId", "")) == "player" \
				and String(state.get("state", "")) != "crossed_out":
			weight += float(def.get("visibility", 1))
	return weight

## Rep lost per decay tick in a district the player doesn't dominate
## (share below the claim threshold = "unattended"); territory perks
## slow the fade. Pure so the smoke test can probe both branches.
func decay_amount(district: Dictionary, player_share: float) -> int:
	if player_share >= float(district.get("claimThreshold", 0.5)):
		return 0
	return roundi(float(district.get("decayRep", 4)) * StatsManager.decay_multiplier())

func advance_decay_ticks(ticks: int) -> void:
	for _i in range(maxi(ticks, 0)):
		_on_decay_tick()

## The §11 loop: standing work keeps paying a trickle; letting a block
## slip below the claim threshold costs rep every tick. Holding
## territory is now upkeep, not a trophy. Decay only bites where the
## player has fame to lose — some standing work or a claim — so an
## untouched district doesn't drain a new writer.
func _on_decay_tick() -> void:
	for district_id in districts:
		var district: Dictionary = districts[district_id]
		var weight := standing_player_weight(String(district_id))
		var payout := int(floor(weight
			* float(district.get("payoutPerWeight", 0.1))
			* StatsManager.payout_multiplier()))
		var decay := 0
		if weight > 0.0 or bool(district.get("claimed", false)):
			decay = decay_amount(district, float(influence(String(district_id)).get("player", 0.0)))
		var net := payout - decay
		if net != 0:
			GameState.add_reputation(maxi(net, -GameState.reputation))
		if decay > 0 and net < 0:
			territory_event.emit("Your name is fading in %s — get back out there."
				% String(district.get("name", district_id)))

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
