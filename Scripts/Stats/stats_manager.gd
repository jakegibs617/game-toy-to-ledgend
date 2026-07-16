extends Node
## Player progression depth (Milestone 17 — GDD §5, §6, §7).
## Owns the 3-stat subset (Style/Stealth/Hustle) that improves through
## use, and the perk system (one choice per rank-up, two perks per §7
## tree). Other managers ask this one for multipliers; XP flows in via
## the managers' signals, so nothing here polls. Autoloaded as
## StatsManager (after the systems it listens to, before SaveManager).
##
## XP sources (GDD §6 "improve through use"):
##   Style   — every player paint, by the work's paint cost
##   Stealth — paints nobody witnessed (+5), chases escaped (+8)
##   Hustle  — shop purchases (+5), delivery runs (+10)

signal stat_changed(stat: String, level: int)
signal perk_point_earned(points: int)
signal perk_chosen(perk: Dictionary)

const STATS_PATH := "res://Data/stats.json"
const PERKS_PATH := "res://Data/perks.json"
const DataLoader := preload("res://Scripts/Data/data_loader.gd")
const UNSEEN_PAINT_XP := 5
const ESCAPE_XP := 8
const PURCHASE_XP := 5
const DELIVERY_XP := 10

var stat_defs: Dictionary = {}
var perk_trees: Dictionary = {}
var xp: Dictionary = {}            # stat -> accumulated xp
var perk_points := 0
var perks_owned: Dictionary = {}   # perkId -> true
var _highest_rank_index := 0       # rank-ups grant points once, no farm via demotion

func _ready() -> void:
	var parsed_stats: Variant = DataLoader.load_json(STATS_PATH, "StatsManager")
	if parsed_stats is Dictionary:
		stat_defs = parsed_stats
		for stat in stat_defs:
			DataLoader.require_fields(stat_defs[stat],
				["label", "desc", "xpPerLevel", "maxLevel"],
				"StatsManager: stat \"%s\"" % String(stat))
			xp[stat] = 0
	var parsed_perks: Variant = DataLoader.load_json(PERKS_PATH, "StatsManager")
	if parsed_perks is Dictionary:
		perk_trees = parsed_perks
		for tree in perk_trees:
			for perk in perk_trees[tree]:
				DataLoader.require_fields(perk, ["perkId", "name", "desc", "effects"],
					"StatsManager: perk in \"%s\"" % String(tree))
	_highest_rank_index = GameState.rank_index(GameState.rank)
	GameState.rank_changed.connect(_on_rank_changed)
	WallManager.wall_painted.connect(_on_wall_painted)
	PatrolManager.paint_observed.connect(_on_paint_observed)
	PatrolManager.chase_escaped.connect(func() -> void: add_xp("stealth", ESCAPE_XP))
	SupplyManager.item_bought.connect(func(_item_id: String) -> void:
		add_xp("hustle", PURCHASE_XP))
	SupplyManager.delivery_completed.connect(func(_cash: int) -> void:
		add_xp("hustle", DELIVERY_XP))

func xp_for(stat: String) -> int:
	return int(xp.get(stat, 0))

func level(stat: String) -> int:
	var def: Dictionary = stat_defs.get(stat, {})
	var per := maxi(int(def.get("xpPerLevel", 50)), 1)
	return mini(xp_for(stat) / per, int(def.get("maxLevel", 5)))

func add_xp(stat: String, amount: int) -> void:
	if not stat_defs.has(stat) or amount <= 0:
		return
	var before := level(stat)
	xp[stat] = xp_for(stat) + amount
	if level(stat) != before:
		stat_changed.emit(stat, level(stat))

## ---- Multipliers the other managers ask for -------------------------

## Rep payout multiplier (Style stat + style/typed perks). `type` is
## the graffiti style key ("" for anything untyped).
func rep_multiplier(type := "") -> float:
	var bonus := level("style") * float(stat_defs.get("style", {}).get("repBonusPerLevel", 0.0))
	bonus += _effect_sum("repBonus")
	for perk in _owned_perks():
		bonus += float(perk["effects"].get("typeRepBonus", {}).get(type, 0.0))
	return 1.0 + bonus

## Heat from the player's painting (Stealth stat + perks). Never below
## 0.4 — paint is never silent.
func heat_multiplier() -> float:
	var cut := level("stealth") * float(stat_defs.get("stealth", {}).get("heatCutPerLevel", 0.0))
	cut += _effect_sum("heatCut")
	return maxf(1.0 - cut, 0.4)

## Guard sight range against the player (Stealth stat + Ghost perk).
func spot_range_multiplier() -> float:
	var cut := level("stealth") * float(stat_defs.get("stealth", {}).get("spotCutPerLevel", 0.0))
	cut += _effect_sum("spotCut")
	return maxf(1.0 - cut, 0.5)

## Shop price multiplier (Hustle stat + The Connect perk).
func price_multiplier() -> float:
	var cut := level("hustle") * float(stat_defs.get("hustle", {}).get("priceCutPerLevel", 0.0))
	cut += _effect_sum("shopCut")
	return maxf(1.0 - cut, 0.5)

## Delivery payout multiplier (Hustle stat + Runner perk).
func delivery_multiplier() -> float:
	var bonus := level("hustle") * float(stat_defs.get("hustle", {}).get("deliveryBonusPerLevel", 0.0))
	return 1.0 + bonus + _effect_sum("deliveryBonus")

## Rival retaliation chance damp (crew perks; stacks multiplicatively).
func response_damp() -> float:
	var damp := 1.0
	for perk in _owned_perks():
		damp *= float(perk["effects"].get("responseDamp", 1.0))
	return damp

## Standing-work rep payout multiplier (territory perks).
func payout_multiplier() -> float:
	return 1.0 + _effect_sum("payoutBonus")

## Rep decay multiplier for unattended districts (territory perks).
func decay_multiplier() -> float:
	return maxf(1.0 - _effect_sum("decayCut"), 0.0)

## ---- Perks (§7: one choice per rank-up, two per tree) ---------------

## The next pickable perk per tree, in data order — at most one option
## per tree, so the chooser always fits the number-key slots.
func choosable_perks() -> Array:
	var options: Array = []
	for tree in perk_trees:
		for perk in perk_trees[tree]:
			if not perks_owned.get(String(perk["perkId"]), false):
				var option: Dictionary = perk.duplicate(true)
				option["tree"] = tree
				options.append(option)
				break
	return options

func owns_perk(perk_id: String) -> bool:
	return bool(perks_owned.get(perk_id, false))

## Display names of owned perks, in tree order (blackbook/perks panel).
func owned_perk_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for perk in _owned_perks():
		names.append(String(perk["name"]))
	return names

## Spends a perk point on `perk_id` if it's currently choosable.
func choose_perk(perk_id: String) -> bool:
	if perk_points <= 0:
		return false
	for option in choosable_perks():
		if String(option["perkId"]) == perk_id:
			perks_owned[perk_id] = true
			perk_points -= 1
			perk_chosen.emit(option)
			return true
	return false

func save_state() -> Dictionary:
	return {
		"xp": xp.duplicate(true),
		"perk_points": perk_points,
		"perks_owned": perks_owned.duplicate(true),
		"highest_rank_index": _highest_rank_index,
	}

func load_state(data: Dictionary) -> void:
	for stat in data.get("xp", {}):
		if xp.has(stat):
			xp[stat] = int(data["xp"][stat])
	perk_points = int(data.get("perk_points", perk_points))
	perks_owned = data.get("perks_owned", perks_owned).duplicate(true)
	_highest_rank_index = int(data.get("highest_rank_index", _highest_rank_index))

func _on_rank_changed(new_rank: String) -> void:
	var idx := GameState.rank_index(new_rank)
	if idx > _highest_rank_index:
		perk_points += idx - _highest_rank_index
		_highest_rank_index = idx
		perk_point_earned.emit(perk_points)

func _on_wall_painted(_wall_id: String, graffiti: Dictionary) -> void:
	if String(graffiti.get("creatorId", "")) != "player":
		return
	var style: Dictionary = WallManager.styles.get(String(graffiti.get("type", "")), {})
	add_xp("style", int(style.get("paintCost", 1)))

func _on_paint_observed(spotted: bool) -> void:
	if not spotted:
		add_xp("stealth", UNSEEN_PAINT_XP)

func _owned_perks() -> Array:
	var owned: Array = []
	for tree in perk_trees:
		for perk in perk_trees[tree]:
			if perks_owned.get(String(perk["perkId"]), false):
				owned.append(perk)
	return owned

func _effect_sum(key: String) -> float:
	var total := 0.0
	for perk in _owned_perks():
		total += float(perk["effects"].get(key, 0.0))
	return total
