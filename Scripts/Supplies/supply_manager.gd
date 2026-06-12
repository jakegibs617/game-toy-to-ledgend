extends Node
## Supply economy (Plan.md section 21; "supply inventory" from the
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

const SUPPLIES_PATH := "res://Data/supplies.json"
const DataLoader := preload("res://Scripts/Data/data_loader.gd")
## Walking away from Lupe closes the catalog so the number keys go back
## to selecting cans.
const SHOP_CLOSE_DISTANCE := 6.0

var catalog: Array = []
var delivery: Dictionary = {}
var owned: Dictionary = {}  # itemId -> true for one-time upgrades
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
	if not def.get("repeatable", false):
		owned[item_id] = true
	item_bought.emit(item_id)
	supply_event.emit("Bought %s — %s. (-$%d)" % [item_name, String(def.get("desc", "")), price])
	return {"ok": true}

## Sticker price after the Hustle stat and supply perks (Milestone 17).
func item_price(def: Dictionary) -> int:
	return maxi(1, roundi(int(def.get("price", 0)) * StatsManager.price_multiplier()))

## Effective paint cost of a graffiti style with owned cap upgrades
## applied (Plan.md section 21: caps modify spray behavior). Never
## discounts below 1 — paint stays a real constraint.
func paint_cost(style: Dictionary) -> int:
	var cost := int(style.get("paintCost", 1))
	for def in catalog:
		if is_owned(String(def["itemId"])) and def.has("paintDiscount"):
			cost = maxi(1, cost - int(def["paintDiscount"]))
	return cost

## Lupe's repeatable errand (Plan.md section 15 "Supply Run"): carry a
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
	var cash := roundi(int(delivery.get("cash", 0)) * StatsManager.delivery_multiplier())
	GameState.add_cash(cash)
	HeatManager.add_heat(float(delivery.get("heat", 0.0)))
	delivery_completed.emit(cash)
	supply_event.emit("Package delivered. (+$%d) Wrong people clocked the handoff — heat's up." % cash)

func save_state() -> Dictionary:
	return {
		"owned": owned.duplicate(true),
		"delivery_active": delivery_active,
		"next_drop": _next_drop,
		"active_drop": _active_drop,
	}

func load_state(data: Dictionary) -> void:
	owned = data.get("owned", {}).duplicate(true)
	delivery_active = bool(data.get("delivery_active", false))
	_next_drop = int(data.get("next_drop", 0))
	_active_drop = int(data.get("active_drop", -1))
	close_shop()
	_clear_drop_zone()
	if delivery_active and _active_drop >= 0:
		_spawn_drop_zone()

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
