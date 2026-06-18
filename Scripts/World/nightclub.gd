extends StaticBody3D
## A rep-gated nightclub door (Product_reqs.md "dance / club / DJ rep-based
## invite"). Same interactable protocol as Bench/TravelPoint/ClimbZone
## (group "interactable", prompt_text + interact): interacting checks the
## writer's rank against the club's `minRank` — toys get waved off by the
## bouncer — then charges the cover and asks the HUD to open the dance floor.
## All shape/payout numbers live in Data/nightlife.json (agent rule 3).

const ENTRANCE_HEIGHT := 3.2

var def: Dictionary = {}
var _label := ""
var _min_rank := "Toy"
var _cover := 0

func setup(club: Dictionary) -> void:
	def = club
	_label = String(club.get("label", "CLUB")).replace("\n", " ")
	_min_rank = String(club.get("minRank", "Toy"))
	_cover = int(club.get("cover", 0))
	name = String(club.get("clubId", "nightclub"))
	var pos: Array = club.get("position", [0, 0, 0])
	position = Vector3(pos[0], pos[1], pos[2])
	rotation_degrees = Vector3(0, float(club.get("rotationY", 0.0)), 0)
	add_to_group("interactable")
	_build_facade()

## A dark storefront face with a lit doorway and a neon marquee — enough
## to read as a club without a bespoke model.
func _build_facade() -> void:
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color("#14101c")
	wall.roughness = 0.85
	var door := StandardMaterial3D.new()
	door.albedo_color = Color("#2a1d3d")
	door.roughness = 0.6
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("#ff2f86")
	glow.emission_enabled = true
	glow.emission = Color("#ff2f86")
	glow.emission_energy_multiplier = 2.5

	# Facade slab, a recessed doorway, and a glowing trim band over the door.
	_add_part(Vector3(0, ENTRANCE_HEIGHT * 0.5, 0), Vector3(4.0, ENTRANCE_HEIGHT, 0.4), wall)
	_add_part(Vector3(0, 1.05, 0.18), Vector3(1.4, 2.1, 0.1), door)
	_add_part(Vector3(0, 2.35, 0.22), Vector3(1.7, 0.12, 0.08), glow)

	# Collision: the facade slab so the writer can't walk through the wall.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, ENTRANCE_HEIGHT, 0.4)
	col.shape = shape
	col.position = Vector3(0, ENTRANCE_HEIGHT * 0.5, 0)
	add_child(col)

	var sign_label := Label3D.new()
	sign_label.text = _label
	sign_label.font_size = 40
	sign_label.outline_size = 10
	sign_label.pixel_size = 0.005
	sign_label.position = Vector3(0, ENTRANCE_HEIGHT + 0.5, 0.22)
	sign_label.modulate = Color("#ff2f86")
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(sign_label)

func _add_part(local_pos: Vector3, part_size: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = part_size
	mesh.mesh = box
	mesh.position = local_pos
	mesh.material_override = material
	add_child(mesh)

func prompt_text() -> String:
	if not GameState.rank_meets(_min_rank):
		return "%s\nBouncer only lets in rank %s+" % [_label, _min_rank]
	if _cover > 0:
		return "%s\n[E] Step inside (cover $%d)" % [_label, _cover]
	return "%s\n[E] Step inside" % _label

## Player raycast interaction (same protocol as Bench/TravelPoint).
func interact() -> void:
	if not GameState.rank_meets(_min_rank):
		GameState.player_event.emit(
			"The bouncer waves you off. \"%s only, toy.\"" % _min_rank)
		return
	if _cover > 0 and not GameState.try_spend_cash(_cover):
		GameState.player_event.emit("Not enough cash for the $%d cover." % _cover)
		return
	# Bouncer nods you in; the HUD opens the dance floor.
	GameState.nightclub_requested.emit(def)
