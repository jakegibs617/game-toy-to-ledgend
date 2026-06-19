extends Node
## Crew recruitment (Plan.md section 14, Milestone 5). Loads
## Data/npc_data.json, spawns recruitable NPCs, and runs each member's
## recruitment as a small stage machine:
##   not_met -> mission_active -> item_recovered -> recruited
## Recruited members grant passive role bonuses (the lookout makes
## rivals back off more often — see RivalManager). Autoloaded as
## CrewManager.

signal crew_event(message: String)
signal crew_changed
signal stage_changed(member_id: String, stage: String)
signal morale_changed(value: int)

const NPC_PATH := "res://Data/npc_data.json"
const DataLoader := preload("res://Scripts/Data/data_loader.gd")
## Bringing somebody into the crew is the loudest pro-street move there
## is (§11 crew rep, Milestone 21).
const RECRUIT_CREW_REP := 10
const MAX_LOYALTY := 100
## Team morale is a single crew-wide mood, separate from each member's
## personal loyalty. It starts neutral and drifts with shared wins and
## losses (duels, recruits, loyalty milestones, getting caught). At neutral
## it changes nothing; high morale slightly sharpens every role bonus and low
## morale slightly dulls it, through one factor folded into role_bonus_scale.
const MAX_MORALE := 100
const MORALE_NEUTRAL := 50

var members: Dictionary = {}  # memberId -> definition + runtime "stage"
var _parent: Node3D = null
var _pickup_nodes: Dictionary = {}
var _getaway_used_levels: Dictionary = {}
var _loyalty_by_member: Dictionary = {}
var _base_loyalty_by_member: Dictionary = {}
var team_morale := MORALE_NEUTRAL

func _ready() -> void:
	var parsed: Variant = DataLoader.load_json(NPC_PATH, "CrewManager")
	if parsed is Array:
		for m in parsed:
			DataLoader.require_fields(m,
				["memberId", "name", "alias", "role", "position", "color", "dialogue"],
				"CrewManager: member \"%s\"" % String(m.get("memberId", "?")))
			m["stage"] = "not_met"
			members[m["memberId"]] = m
			_base_loyalty_by_member[m["memberId"]] = int(m.get("loyalty", 0))
			_loyalty_by_member[m["memberId"]] = _base_loyalty_by_member[m["memberId"]]
	TerritoryManager.district_claimed.connect(func(district_id: String, _district: Dictionary) -> void:
		auto_fill_district(district_id))

## Spawns NPCs (and any not-yet-recovered mission items) into a scene.
func spawn_npcs(parent: Node3D) -> void:
	_parent = parent
	_pickup_nodes.clear()
	for m in members.values():
		var npc := Npc.new()
		npc.setup(m)
		parent.add_child(npc)
		_sync_pickup_for_member(String(m["memberId"]))

## Talking to an NPC advances their recruitment stage.
func interact(member_id: String) -> void:
	var m: Dictionary = members[member_id]
	var lines: Dictionary = m.get("dialogue", {})
	match String(m["stage"]):
		"not_met":
			m["stage"] = "mission_active"
			stage_changed.emit(member_id, String(m["stage"]))
			_sync_pickup_for_member(member_id)
			crew_event.emit("%s: \"%s\"" % [m["alias"], lines.get("meet", "...")])
		"mission_active":
			crew_event.emit("%s: \"%s\"" % [m["alias"], lines.get("active", "...")])
		"item_recovered":
			m["stage"] = "recruited"
			stage_changed.emit(member_id, String(m["stage"]))
			GameState.add_crew_rep(RECRUIT_CREW_REP)
			crew_event.emit("%s joined your crew — %s! %s" % [
				m["alias"], String(m.get("roleLabel", m["role"])),
				String(m.get("bonusDescription", ""))])
			crew_changed.emit()
			# A fresh recruit lifts the whole crew (any_recruited() is already
			# true here, so the first member's join lands too).
			adjust_morale(6, "%s joined" % String(m["alias"]))
			if String(m.get("role", "")) == "filler":
				for district_id in TerritoryManager.districts:
					if TerritoryManager.is_claimed(String(district_id)):
						auto_fill_district(String(district_id))
		"recruited":
			crew_event.emit("%s: \"%s\"" % [m["alias"], lines.get("recruited", "...")])

## Returns true if the item was collected (mission must be active).
func collect_item(member_id: String) -> bool:
	var m: Dictionary = members[member_id]
	if String(m["stage"]) != "mission_active":
		crew_event.emit("A worn blackbook. Someone must be missing it.")
		return false
	m["stage"] = "item_recovered"
	stage_changed.emit(member_id, String(m["stage"]))
	_sync_pickup_for_member(member_id)
	crew_event.emit("Recovered %s — bring it back to %s." % [
		String(m["item"]["name"]), m["alias"]])
	return true

func _sync_pickup_for_member(member_id: String) -> void:
	if _parent == null or not is_instance_valid(_parent) or not members.has(member_id):
		return
	var m: Dictionary = members[member_id]
	var should_exist := m.has("item") and String(m.get("stage", "")) == "mission_active"
	var existing: PickupItem = _pickup_nodes.get(member_id, null)
	if existing != null and not is_instance_valid(existing):
		_pickup_nodes.erase(member_id)
		existing = null
	if should_exist and existing == null:
		var item := PickupItem.new()
		item.setup(member_id, m["item"])
		_parent.add_child(item)
		_pickup_nodes[member_id] = item
	elif not should_exist and existing != null:
		existing.queue_free()
		_pickup_nodes.erase(member_id)

func first_with_role(role: String) -> Dictionary:
	for m in members.values():
		if String(m["stage"]) == "recruited" and String(m["role"]) == role:
			return m
	return {}

func has_role(role: String) -> bool:
	return not first_with_role(role).is_empty()

func any_recruited() -> bool:
	for m in members.values():
		if String(m["stage"]) == "recruited":
			return true
	return false

func member_loyalty(member_id: String) -> int:
	if not members.has(member_id):
		return 0
	return int(_loyalty_by_member.get(member_id, members[member_id].get("loyalty", 0)))

func loyalty_text(member_id: String) -> String:
	var value := member_loyalty(member_id)
	if value >= 85:
		return "ride-or-die"
	if value >= 65:
		return "solid"
	if value >= 45:
		return "warm"
	if value >= 25:
		return "testing you"
	return "distant"

## Crew role bonuses deepen as the member has reasons to trust the
## writer. At 50 loyalty the data-defined bonus is unchanged; 100
## loyalty is a small upgrade, not a second progression tree. The whole
## crew's morale then nudges the result up or down by a small factor.
func role_bonus_scale(role: String) -> float:
	var member := first_with_role(role)
	if member.is_empty():
		return 0.0
	var loyalty_scale := clampf(0.75 + float(member_loyalty(String(member["memberId"]))) / 200.0, 0.75, 1.25)
	return loyalty_scale * morale_factor()

## Maps team morale to a tight [0.9, 1.1] multiplier centred on neutral, so a
## default-morale crew (and every existing balance assertion) reads exactly
## 1.0 and only a crew that has been winning or losing together shifts it.
func morale_factor() -> float:
	return morale_factor_for(team_morale)

func morale_factor_for(value: int) -> float:
	return 0.9 + clampf(float(value), 0.0, float(MAX_MORALE)) / float(MAX_MORALE) * 0.2

func morale_text() -> String:
	if team_morale >= 80:
		return "tight"
	if team_morale >= 60:
		return "up"
	if team_morale >= 40:
		return "steady"
	if team_morale >= 20:
		return "shaky"
	return "fractured"

## Shifts crew-wide morale and announces a crossed 20-point band so the writer
## feels the team mood turn without a readout for every point. No-op when no
## one is recruited yet — a crew of one writer has no morale to move.
func adjust_morale(delta: int, reason := "") -> void:
	if delta == 0 or not any_recruited():
		return
	var before := team_morale
	team_morale = clampi(team_morale + delta, 0, MAX_MORALE)
	if team_morale == before:
		return
	morale_changed.emit(team_morale)
	if team_morale / 20 != before / 20:
		var tail := " (%s)" % reason if reason != "" else ""
		crew_event.emit("Crew morale is %s — %d/%d%s." % [
			morale_text(), team_morale, MAX_MORALE, tail])

func note_role_helped(role: String, amount := 2) -> void:
	var member := first_with_role(role)
	if member.is_empty() or amount <= 0:
		return
	var member_id := String(member["memberId"])
	var before := member_loyalty(member_id)
	var after := mini(MAX_LOYALTY, before + amount)
	if after == before:
		return
	_loyalty_by_member[member_id] = after
	member["loyalty"] = after
	stage_changed.emit(member_id, String(member.get("stage", "")))
	if after == MAX_LOYALTY or after / 10 > before / 10:
		crew_event.emit("%s trusts the crew more. Loyalty %d/%d." % [
			String(member.get("alias", member_id)), after, MAX_LOYALTY])
		# A member's loyalty milestone is good news the rest of the crew feels.
		adjust_morale(2, "%s is solid" % String(member.get("alias", member_id)))

## Rico "Caps" (Milestone 22): once a block is already yours, he fills
## a few open/non-player walls with no-rep throw-ups so held territory
## looks lived-in. Passive crew work deliberately does not advance
## player paint objectives.
func auto_fill_district(district_id: String) -> int:
	var filler := first_with_role("filler")
	if filler.is_empty() or not TerritoryManager.is_claimed(district_id):
		return 0
	var target_count := int(filler.get("autoFillCount", 2))
	var filled := 0
	for def in WallManager.wall_defs:
		if filled >= target_count:
			break
		if String(def.get("districtId", "")) != district_id:
			continue
		var wall_id := String(def.get("wallId", ""))
		var state: Dictionary = WallManager.wall_states.get(wall_id, {})
		if String(state.get("ownerCrewId", "none")) == "player":
			continue
		if not WallManager.paint_block_reason("throwup", def).is_empty():
			continue
		var result := WallManager.apply_crew_graffiti(wall_id, filler, "throwup")
		if result.get("ok", false):
			filled += 1
	if filled > 0:
		crew_event.emit("%s filled %d open %s spot%s with throw-ups." % [
			String(filler.get("alias", "Caps")), filled,
			String(TerritoryManager.districts.get(district_id, {}).get("name", district_id)),
			"" if filled == 1 else "s"])
	return filled

## Jay "Metro" (Milestone 22): one free escape per heat level. The
## charge is keyed by level name, so moving from Hot to Blazing makes a
## new route available, but repeated catches at the same level do not.
func try_getaway_escape(heat_level: String) -> bool:
	var getaway := first_with_role("getaway")
	if getaway.is_empty() or heat_level == "":
		return false
	if bool(_getaway_used_levels.get(heat_level, false)):
		return false
	_getaway_used_levels[heat_level] = true
	note_role_helped("getaway", 4)
	crew_event.emit("%s calls the route — free escape at %s heat." % [
		String(getaway.get("alias", "Metro")), heat_level])
	return true

## Supply Runner role: a recruited runner knows who sells clean cans and
## which drop routes pay better. Multipliers are data-driven per member
## so future runners can tune the economy without changing code.
func shop_price_multiplier() -> float:
	var runner := first_with_role("supply_runner")
	if runner.is_empty():
		return 1.0
	var raw := maxf(float(runner.get("shopPriceMultiplier", 1.0)), 0.5)
	return 1.0 - (1.0 - raw) * role_bonus_scale("supply_runner")

func delivery_multiplier() -> float:
	var runner := first_with_role("supply_runner")
	if runner.is_empty():
		return 1.0
	return 1.0 + (maxf(float(runner.get("deliveryMultiplier", 1.0)), 1.0) - 1.0) \
		* role_bonus_scale("supply_runner")

## Hype role: turns spectators into louder street credit and helps club
## sets travel further. Crowd rep is a tiny integer tick, so data uses
## an additive bonus there and a multiplier for nightlife payouts.
func crowd_reaction_rep(base := 1) -> int:
	var hype := first_with_role("hype")
	if hype.is_empty():
		return base
	return maxi(base, base + roundi(float(hype.get("crowdRepBonus", 1)) * role_bonus_scale("hype")))

func hype_payout_multiplier() -> float:
	var hype := first_with_role("hype")
	if hype.is_empty():
		return 1.0
	return 1.0 + (maxf(float(hype.get("nightlifeMultiplier", 1.0)), 1.0) - 1.0) \
		* role_bonus_scale("hype")

## Fixer role: knows which guard takes a warning and which city crew can
## be slowed down. Penalty multipliers lower caught costs; cleanup
## multiplier lowers sweep odds for player-owned walls.
func caught_rep_multiplier() -> float:
	var fixer := first_with_role("fixer")
	if fixer.is_empty():
		return 1.0
	var raw := clampf(float(fixer.get("caughtRepMultiplier", 1.0)), 0.0, 1.0)
	return 1.0 - (1.0 - raw) * role_bonus_scale("fixer")

func caught_paint_multiplier() -> float:
	var fixer := first_with_role("fixer")
	if fixer.is_empty():
		return 1.0
	var raw := clampf(float(fixer.get("caughtPaintMultiplier", 1.0)), 0.0, 1.0)
	return 1.0 - (1.0 - raw) * role_bonus_scale("fixer")

func cleanup_chance_multiplier() -> float:
	var fixer := first_with_role("fixer")
	if fixer.is_empty():
		return 1.0
	var raw := clampf(float(fixer.get("cleanupChanceMultiplier", 1.0)), 0.0, 1.0)
	return 1.0 - (1.0 - raw) * role_bonus_scale("fixer")

## Battle Specialist role: a rival callout becomes a bigger crew moment.
## Rewards are stamped onto the duel when it opens so saved active callouts
## keep the same stakes even if crew state changes before the answer.
func wall_duel_rep_reward(base: int) -> int:
	var specialist := first_with_role("battle_specialist")
	if specialist.is_empty():
		return base
	var raw := maxf(float(specialist.get("duelRepMultiplier", 1.0)), 1.0)
	return maxi(base, roundi(float(base) * (1.0 + (raw - 1.0) * role_bonus_scale("battle_specialist"))))

func wall_duel_crew_rep_reward(base: int) -> int:
	var specialist := first_with_role("battle_specialist")
	if specialist.is_empty():
		return base
	var bonus := roundi(float(specialist.get("duelCrewRepBonus", 0)) \
		* role_bonus_scale("battle_specialist"))
	return base + maxi(bonus, 0)

func save_state() -> Dictionary:
	var stages := {}
	for member_id in members:
		stages[member_id] = String(members[member_id].get("stage", "not_met"))
	return {
		"stages": stages,
		"getaway_used_levels": _getaway_used_levels.duplicate(true),
		"loyalty_by_member": _loyalty_by_member.duplicate(true),
		"team_morale": team_morale,
	}

func load_state(data: Dictionary) -> void:
	var stages: Dictionary = data.get("stages", {})
	for member_id in stages:
		if members.has(member_id):
			members[member_id]["stage"] = String(stages[member_id])
			stage_changed.emit(String(member_id), String(stages[member_id]))
			_sync_pickup_for_member(String(member_id))
	_getaway_used_levels = data.get("getaway_used_levels", {}).duplicate(true)
	team_morale = clampi(int(data.get("team_morale", MORALE_NEUTRAL)), 0, MAX_MORALE)
	morale_changed.emit(team_morale)
	_loyalty_by_member = _default_loyalty_by_member()
	var saved_loyalty: Dictionary = data.get("loyalty_by_member", {})
	for member_id in saved_loyalty:
		if members.has(member_id):
			_loyalty_by_member[member_id] = int(saved_loyalty[member_id])
	for member_id in members:
		members[member_id]["loyalty"] = member_loyalty(String(member_id))
	crew_changed.emit()

func _default_loyalty_by_member() -> Dictionary:
	var result := {}
	for member_id in members:
		result[member_id] = int(_base_loyalty_by_member.get(member_id, members[member_id].get("loyalty", 0)))
	return result

## One status line per member for the crew menu.
func status_text(m: Dictionary) -> String:
	match String(m["stage"]):
		"not_met":
			return String(m.get("hint", "Somewhere in the district."))
		"mission_active":
			return String(m.get("missionDescription", "Help them out."))
		"item_recovered":
			return "Return %s to them." % String(m.get("item", {}).get("name", "the item"))
		"recruited":
			return "Recruited — %s\n      Loyalty %d/%d (%s) · role scale %.2fx" % [
				String(m.get("bonusDescription", "")),
				member_loyalty(String(m["memberId"])), MAX_LOYALTY,
				loyalty_text(String(m["memberId"])),
				role_bonus_scale(String(m.get("role", "")))]
	return ""
