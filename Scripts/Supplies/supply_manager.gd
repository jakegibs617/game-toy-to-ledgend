extends Node
## Supply economy (GDD §21; "supply inventory" from the
## section 36 Should-Have list). Cash comes from mission payouts and
## Lupe's repeatable delivery runs; it buys paint packs, caps that cut
## the paint cost of bigger work, and rare fill colors — all data-driven
## from Data/supplies.json. Lupe is the shop front: interacting with her
## when no mission objective wants her opens the catalog. Autoloaded as
## SupplyManager.

signal supply_event(message: String)
signal shop_toggled(open: bool)
## Hustle XP sources (Milestone 17): StatsManager listens.
signal item_bought(item_id: String)
signal delivery_completed(cash: int)
## Fired when the equipped spray cap changes (HUD/blackbook listen).
signal cap_changed(cap_id: String)

const SUPPLIES_PATH := "res://Data/supplies.json"
const CAPS_PATH := "res://Data/caps.json"
const DataLoader := preload("res://Scripts/Data/data_loader.gd")
## Walking away from Lupe closes the catalog so the number keys go back
## to selecting cans.
const SHOP_CLOSE_DISTANCE := 6.0

var catalog: Array = []
var delivery: Dictionary = {}
var owned: Dictionary = {}  # itemId -> true for one-time upgrades
## Equipped paint tools (GDD §21: "caps modify spray behaviour"). The
## stock cap is always owned; bought caps/tools trade paint cost, rep, heat,
## and gear suspicion against each other. One tool is equipped at a time and
## drives the next paint.
var caps_by_id: Dictionary = {}      # capId -> cap definition
var cap_order: Array = []            # capIds in catalog order
var owned_caps: Dictionary = {}      # capId -> true
var equipped_cap := ""
var delivery_active := false
var _next_drop := 0         # round-robin pointer into delivery drops
var _active_drop := -1      # drop index of the running delivery
var _shop_anchor: Node3D = null
var _drop_zone: Area3D = null

func _ready() -> void:
	var parsed: Variant = DataLoader.load_json(SUPPLIES_PATH, "SupplyManager")
	if parsed is Dictionary:
		catalog = parsed.get("shop", [])
		delivery = parsed.get("delivery", {})
		for item_def in catalog:
			DataLoader.require_fields(item_def, ["itemId", "name", "desc", "price"],
				"SupplyManager: item \"%s\"" % String(item_def.get("itemId", "?")))
		if not delivery.is_empty():
			DataLoader.require_fields(delivery, ["name", "cash", "heat", "drops"],
				"SupplyManager: delivery")
	_load_caps()

func _load_caps() -> void:
	var parsed: Variant = DataLoader.load_json(CAPS_PATH, "SupplyManager")
	if parsed is Dictionary:
		for cap_def in parsed.get("caps", []):
			DataLoader.require_fields(cap_def,
				["capId", "name", "desc", "paintDelta", "repMultiplier", "suspicion"],
				"SupplyManager: cap \"%s\"" % String(cap_def.get("capId", "?")))
			var cap_id := String(cap_def["capId"])
			caps_by_id[cap_id] = cap_def
			cap_order.append(cap_id)
			if bool(cap_def.get("default", false)):
				owned_caps[cap_id] = true
				if equipped_cap == "":
					equipped_cap = cap_id
	if equipped_cap == "" and not cap_order.is_empty():
		equipped_cap = String(cap_order[0])
		owned_caps[equipped_cap] = true

func _physics_process(_delta: float) -> void:
	if _shop_anchor != null:
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if player == null or not is_instance_valid(_shop_anchor) \
				or player.global_position.distance_to(_shop_anchor.global_position) > SHOP_CLOSE_DISTANCE:
			close_shop()
	if delivery_active and _drop_zone != null:
		for body in _drop_zone.get_overlapping_bodies():
			if body is Player:
				resolve_delivery()
				break

func is_shop_open() -> bool:
	return _shop_anchor != null

func toggle_shop(anchor: Node3D) -> void:
	if is_shop_open():
		close_shop()
	else:
		_shop_anchor = anchor
		shop_toggled.emit(true)

func close_shop() -> void:
	if _shop_anchor == null:
		return
	_shop_anchor = null
	shop_toggled.emit(false)

func item(item_id: String) -> Dictionary:
	for def in catalog:
		if String(def["itemId"]) == item_id:
			return def
	return {}

func is_owned(item_id: String) -> bool:
	return bool(owned.get(item_id, false))

## Attempts to buy a catalog item with the player's cash.
## Returns {ok} on success or {ok: false, reason} on failure.
func buy(item_id: String) -> Dictionary:
	var def := item(item_id)
	if def.is_empty():
		return {"ok": false, "reason": "Unknown item."}
	var item_name := String(def.get("name", item_id))
	if not def.get("repeatable", false) and is_owned(item_id):
		return {"ok": false, "reason": "%s: you've already got one." % item_name}
	var price := item_price(def)
	if not GameState.try_spend_cash(price):
		return {"ok": false, "reason": "Not enough cash for the %s ($%d)." % [item_name, price]}
	if def.has("paint"):
		GameState.add_paint(int(def["paint"]))
	if def.has("color"):
		var color: Dictionary = def["color"]
		GameState.add_fill_color(String(color["name"]), String(color["hex"]))
	if def.has("unlockType"):
		# Bought gear unlocks a graffiti type (Milestone 16: the stencil
		# kit IS the stencil unlock — no separate flag to drift).
		GameState.unlock_type(String(def["unlockType"]))
	if def.has("grantsCap"):
		# Buying a cap adds it to the kit and equips it so the trade-off is
		# live immediately (preserves the old "buy Fat Cap → discount on" feel).
		grant_cap(String(def["grantsCap"]), true)
	if not def.get("repeatable", false):
		owned[item_id] = true
	item_bought.emit(item_id)
	if CrewManager.has_role("supply_runner"):
		CrewManager.note_role_helped("supply_runner", 1)
	supply_event.emit("Bought %s — %s. (-$%d)" % [item_name, String(def.get("desc", "")), price])
	return {"ok": true}

## Sticker price after the Hustle stat and supply perks (Milestone 17).
func item_price(def: Dictionary) -> int:
	return maxi(1, roundi(int(def.get("price", 0))
		* GameState.difficulty_shop_price_multiplier()
		* StatsManager.price_multiplier()
		* CrewManager.shop_price_multiplier()))

## Effective paint cost of a graffiti style with the equipped tool applied
## (GDD §21: caps modify spray behavior). Never below 1 — paint
## stays a real constraint even with a fat cap.
func paint_cost(style: Dictionary) -> int:
	return maxi(1, int(style.get("paintCost", 1)) + cap_paint_delta(style))

func cap_def(cap_id: String) -> Dictionary:
	return caps_by_id.get(cap_id, {})

func equipped_cap_def() -> Dictionary:
	return cap_def(equipped_cap)

func cap_paint_delta(style := {}) -> int:
	if not _equipped_cap_applies_to(style):
		return 0
	return int(equipped_cap_def().get("paintDelta", 0))

## Detail/coverage tools trade rep against the others; the equipped tool scales
## a player paint's reputation (folded into WallManager._begin_player_paint).
func cap_rep_multiplier(style := {}) -> float:
	if not _equipped_cap_applies_to(style):
		return 1.0
	return maxf(0.1, float(equipped_cap_def().get("repMultiplier", 1.0)))

func cap_heat_multiplier(style := {}) -> float:
	if not _equipped_cap_applies_to(style):
		return 1.0
	return maxf(0.1, float(equipped_cap_def().get("heatMultiplier", 1.0)))

## A bulky or showy cap adds to gear suspicion (GameState.gear_suspicion_multiplier).
func cap_suspicion() -> float:
	return float(equipped_cap_def().get("suspicion", 0.0))

func _equipped_cap_applies_to(style: Dictionary) -> bool:
	var applies_to: Array = equipped_cap_def().get("appliesTo", [])
	if applies_to.is_empty() or style.is_empty():
		return true
	return String(style.get("type", "")) in applies_to

func owns_cap(cap_id: String) -> bool:
	return bool(owned_caps.get(cap_id, false))

func grant_cap(cap_id: String, equip := false) -> void:
	if not caps_by_id.has(cap_id):
		return
	owned_caps[cap_id] = true
	if equip:
		equip_cap(cap_id)

func equip_cap(cap_id: String) -> bool:
	if not owns_cap(cap_id) or cap_id == equipped_cap:
		return false
	equipped_cap = cap_id
	cap_changed.emit(equipped_cap)
	supply_event.emit("Tool: %s — %s." % [
		String(equipped_cap_def().get("name", cap_id)),
		String(equipped_cap_def().get("desc", ""))])
	return true

## Cycles the equipped cap through the owned caps (catalog order). Bound to a
## key/button like the can and color cycles so it reads as the same gesture.
func cycle_cap(step: int) -> void:
	var owned_order: Array = []
	for cap_id in cap_order:
		if owns_cap(String(cap_id)):
			owned_order.append(String(cap_id))
	if owned_order.size() <= 1:
		return
	var current := maxi(owned_order.find(equipped_cap), 0)
	var next := wrapi(current + step, 0, owned_order.size())
	equip_cap(String(owned_order[next]))

## Lupe's repeatable errand (GDD §15 "Supply Run"): carry a
## package to a drop spot for cash. One package at a time; drops rotate.
func start_delivery() -> bool:
	var drops: Array = delivery.get("drops", [])
	if drops.is_empty():
		return false
	if delivery_active:
		supply_event.emit("Lupe: \"One package at a time. Finish the run you've got.\"")
		return false
	_active_drop = _next_drop
	_spawn_drop_zone()
	if _drop_zone == null:  # no scene to host the drop — don't strand the run
		_active_drop = -1
		return false
	delivery_active = true
	_next_drop = (_next_drop + 1) % drops.size()
	supply_event.emit("Delivery run: drop Lupe's package at the %s." % String(drops[_active_drop]["label"]))
	return true

## Completes the running delivery: pays out and draws heat (handing
## off packages in the open gets noticed). Public and deterministic so
## the smoke test can drive it; the drop zone calls it on overlap.
func resolve_delivery() -> void:
	if not delivery_active:
		return
	delivery_active = false
	_active_drop = -1
	_clear_drop_zone()
	# Hustle raises the pay (Milestone 17).
	var cash := roundi(int(delivery.get("cash", 0))
		* StatsManager.delivery_multiplier()
		* CrewManager.delivery_multiplier())
	GameState.add_cash(cash)
	HeatManager.add_heat(float(delivery.get("heat", 0.0)))
	delivery_completed.emit(cash)
	if CrewManager.has_role("supply_runner"):
		CrewManager.note_role_helped("supply_runner", 3)
	supply_event.emit("Package delivered. (+$%d) Wrong people clocked the handoff — heat's up." % cash)

func save_state() -> Dictionary:
	return {
		"owned": owned.duplicate(true),
		"owned_caps": owned_caps.duplicate(true),
		"equipped_cap": equipped_cap,
		"delivery_active": delivery_active,
		"next_drop": _next_drop,
		"active_drop": _active_drop,
	}

func load_state(data: Dictionary) -> void:
	owned = data.get("owned", {}).duplicate(true)
	_restore_caps(data)
	delivery_active = bool(data.get("delivery_active", false))
	_next_drop = int(data.get("next_drop", 0))
	_active_drop = int(data.get("active_drop", -1))
	close_shop()
	_clear_drop_zone()
	if delivery_active and _active_drop >= 0:
		_spawn_drop_zone()

## Rebuilds the cap kit from a save. Re-seeds the default cap, applies any
## saved owned caps, and back-fills from owned shop items so pre-cap-system
## saves (which only recorded owning "fat_cap") still get the Fat Cap.
func _restore_caps(data: Dictionary) -> void:
	owned_caps.clear()
	for cap_id in caps_by_id:
		if bool(caps_by_id[cap_id].get("default", false)):
			owned_caps[cap_id] = true
	for item_id in owned:
		var shop_def := item(String(item_id))
		if shop_def.has("grantsCap"):
			owned_caps[String(shop_def["grantsCap"])] = true
	for cap_id in data.get("owned_caps", {}):
		if caps_by_id.has(String(cap_id)):
			owned_caps[String(cap_id)] = true
	var saved_equipped := String(data.get("equipped_cap", ""))
	if saved_equipped != "" and owns_cap(saved_equipped):
		equipped_cap = saved_equipped
	elif not owns_cap(equipped_cap):
		equipped_cap = String(cap_order[0]) if not cap_order.is_empty() else ""
	cap_changed.emit(equipped_cap)

## Drop zone: an Area3D with an emissive pad and floating label. The
## overlap poll in _physics_process completes the delivery.
func _spawn_drop_zone() -> void:
	_clear_drop_zone()
	var scene := get_tree().current_scene
	var drops: Array = delivery.get("drops", [])
	if scene == null or _active_drop < 0 or _active_drop >= drops.size():
		return
	var drop: Dictionary = drops[_active_drop]
	var pos: Array = drop["position"]
	var zone := Area3D.new()
	zone.name = "delivery_drop"
	zone.position = Vector3(pos[0], pos[1], pos[2])
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 2.5, 3.0)
	col.shape = shape
	zone.add_child(col)

	var pad := MeshInstance3D.new()
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(2.4, 0.1, 2.4)
	pad.mesh = pad_mesh
	pad.position = Vector3(0, -1.1, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#e0a030")
	mat.emission_enabled = true
	mat.emission = Color("#e0a030")
	mat.emission_energy_multiplier = 1.4
	pad.material_override = mat
	zone.add_child(pad)

	var label := Label3D.new()
	label.text = "DROP\n%s" % String(drop.get("label", ""))
	label.font_size = 48
	label.outline_size = 10
	label.pixel_size = 0.005
	label.position = Vector3(0, 1.2, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	zone.add_child(label)
	scene.add_child(zone)
	_drop_zone = zone

func _clear_drop_zone() -> void:
	if _drop_zone != null and is_instance_valid(_drop_zone):
		_drop_zone.queue_free()
	_drop_zone = null
