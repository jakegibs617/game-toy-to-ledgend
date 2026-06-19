class_name MissionZone
extends Area3D
## A mission trigger volume (safehouse, "go check your tag" spots).
## Reports to MissionManager when the player steps inside. Polls
## overlaps instead of relying on body_entered so it also fires when
## spawned around a player who is already standing in it.

var actor_id := ""
var one_shot := false
var _player_inside := false

func setup(id: String, pos: Vector3, size: Vector3, one_shot_zone := false) -> void:
	actor_id = id
	one_shot = one_shot_zone
	name = "zone_%s" % id
	position = pos
	if actor_id == "safehouse":
		add_to_group("interactable")
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	add_child(col)

func _physics_process(_delta: float) -> void:
	var inside := false
	for body in get_overlapping_bodies():
		if body is Player:
			inside = true
			break
	if inside and not _player_inside:
		MissionManager.notify_actor(actor_id)
		if one_shot:
			queue_free()
	_player_inside = inside

func prompt_text() -> String:
	return "[E] Crew board\n[R] Rest until the block cools" if actor_id == "safehouse" else ""

func interact() -> void:
	if actor_id == "safehouse":
		GameState.crew_board_requested.emit()
