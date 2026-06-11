extends Node3D
## Test scene (Plan.md agent rule 9): a single paintable wall in an
## empty room, for exercising graffiti placement in isolation.

const TEST_WALL := {
	"wallId": "wall_test_01",
	"name": "Test Wall",
	"districtId": "district_test",
	"position": [0, 1.6, -4],
	"rotationY": 0,
	"size": [6, 3, 0.3],
	"visibility": 3,
	"risk": 2,
	"surfaceType": "concrete",
	"color": "#9a8f84",
}

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)

	var ground := StaticBody3D.new()
	ground.position = Vector3(0, -0.25, 0)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(30, 0.5, 30)
	mesh.mesh = box
	ground.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	ground.add_child(col)
	add_child(ground)

	WallManager.spawn_wall(TEST_WALL, self)

	var player := Player.new()
	player.position = Vector3(0, 0.5, 3)
	add_child(player)
	var hud := Hud.new()
	add_child(hud)
	hud.bind_player(player)
