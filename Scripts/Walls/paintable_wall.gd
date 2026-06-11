class_name PaintableWall
extends StaticBody3D
## A paintable surface, built at runtime from a wall definition in
## Data/walls.json. Placeholder graffiti is rendered as a Label3D
## (plus a backdrop quad for pieces) until real decal art exists.

var def: Dictionary = {}

var _graffiti_anchor: Node3D

func setup(wall_def: Dictionary) -> void:
	def = wall_def
	name = String(def["wallId"])
	var pos: Array = def.get("position", [0, 0, 0])
	position = Vector3(pos[0], pos[1], pos[2])
	rotation_degrees = Vector3(0, float(def.get("rotationY", 0.0)), 0)
	var size: Array = def.get("size", [4, 3, 0.3])
	var box_size := Vector3(size[0], size[1], size[2])

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(String(def.get("color", "#9a8f84")))
	mesh.material_override = mat
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	add_child(col)

	# Graffiti hangs just off the wall's front (+Z) face to avoid z-fighting.
	_graffiti_anchor = Node3D.new()
	_graffiti_anchor.position = Vector3(0, 0, box_size.z / 2.0 + 0.03)
	add_child(_graffiti_anchor)

func display_name() -> String:
	return String(def.get("name", def.get("wallId", "Wall")))

func show_graffiti(graffiti: Dictionary) -> void:
	for child in _graffiti_anchor.get_children():
		child.queue_free()
	var label := Label3D.new()
	label.text = String(graffiti.get("alias", "???"))
	label.modulate = Color(String(graffiti.get("fillColor", "#ffffff")))
	label.outline_modulate = Color(String(graffiti.get("outlineColor", "#000000")))
	match String(graffiti.get("type", "tag")):
		"tag":
			label.font_size = 96
			label.outline_size = 18
			label.pixel_size = 0.004
		"throwup":
			label.font_size = 160
			label.outline_size = 48
			label.pixel_size = 0.006
		"piece":
			label.font_size = 220
			label.outline_size = 64
			label.pixel_size = 0.008
			_add_backdrop()
	_graffiti_anchor.add_child(label)

## Slaps a cross-out (e.g. "TOY") at an angle over the current graffiti.
## Cleared automatically when show_graffiti repaints the wall.
func show_cross_out(cross: Dictionary) -> void:
	var label := Label3D.new()
	label.text = String(cross.get("text", "TOY"))
	label.modulate = Color(String(cross.get("color", "#e0301e")))
	label.outline_modulate = Color("#1a1a1a")
	label.font_size = 150
	label.outline_size = 28
	label.pixel_size = 0.006
	label.position = Vector3(0, 0, 0.02)
	label.rotation_degrees = Vector3(0, 0, -14)
	_graffiti_anchor.add_child(label)

## Dark panel behind a piece so it reads as a larger, filled artwork.
func _add_backdrop() -> void:
	var size: Array = def.get("size", [4, 3, 0.3])
	var quad := QuadMesh.new()
	quad.size = Vector2(float(size[0]) * 0.85, float(size[1]) * 0.8)
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.position = Vector3(0, 0, -0.015)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#26233a")
	mesh.material_override = mat
	_graffiti_anchor.add_child(mesh)
