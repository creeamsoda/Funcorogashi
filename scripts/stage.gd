extends Node3D
## ステージ: 長方形の床 + 周囲4壁 + 全体俯瞰カメラ + ライト。
## すべてコード生成(primitivesのみ)。壁は "wall" グループに入れる(突進の壁判定用)。

const STAGE_SIZE := Vector2(24.0, 16.0)  ## 内寸 (x, z)
const WALL_HEIGHT := 2.0
const WALL_THICK := 0.6
const FLOOR_THICK := 0.5

func _ready() -> void:
	_build_floor()
	_build_walls()
	_build_camera()
	_build_light()

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.add_to_group("floor")
	add_child(body)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(STAGE_SIZE.x, FLOOR_THICK, STAGE_SIZE.y)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0, -FLOOR_THICK * 0.5, 0)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	col.shape = shape
	col.position = mi.position
	body.add_child(col)

func _build_walls() -> void:
	var hx := STAGE_SIZE.x * 0.5
	var hz := STAGE_SIZE.y * 0.5
	# [中心x, 中心z, sizeX, sizeZ]
	var specs := [
		[0.0, -hz - WALL_THICK * 0.5, STAGE_SIZE.x + WALL_THICK * 2.0, WALL_THICK],  # 北
		[0.0, hz + WALL_THICK * 0.5, STAGE_SIZE.x + WALL_THICK * 2.0, WALL_THICK],   # 南
		[-hx - WALL_THICK * 0.5, 0.0, WALL_THICK, STAGE_SIZE.y],                     # 西
		[hx + WALL_THICK * 0.5, 0.0, WALL_THICK, STAGE_SIZE.y],                      # 東
	]
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	for s in specs:
		var body := StaticBody3D.new()
		body.add_to_group("wall")
		walls.add_child(body)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(s[2], WALL_HEIGHT, s[3])
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		body.add_child(mi)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = mesh.size
		col.shape = shape
		body.add_child(col)
		body.position = Vector3(s[0], WALL_HEIGHT * 0.5, s[1])

func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	add_child(cam)
	cam.position = Vector3(0, 22, 15)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.fov = 60.0

func _build_light() -> void:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	add_child(light)
	light.rotation_degrees = Vector3(-60, -40, 0)
	light.light_energy = 1.2
