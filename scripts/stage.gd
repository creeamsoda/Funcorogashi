class_name Stage
extends Node3D
## ステージ: 長方形の床 + 周囲4壁 + 全体俯瞰カメラ + ライト。
## すべてコード生成(primitivesのみ)。壁は "wall" グループに入れる(突進の壁判定用)。

## アリーナ内寸の半分(x, z)。プレイヤー・動物の境界はすべてここを参照する。
const HALF_X := 18.0
const HALF_Z := 12.0
const STAGE_SIZE := Vector2(HALF_X * 2.0, HALF_Z * 2.0)  ## 内寸 (x, z)
const WALL_HEIGHT := 2.0
const WALL_THICK := 0.6
const FLOOR_THICK := 0.5
## フェンス: 見た目は低く(後で特殊フンが飛び越える前提)、判定は高くして大きなフン球も越えられないようにする。
const FENCE_THICK := 0.4
const FENCE_VISUAL_HEIGHT := 0.9
const FENCE_COLLISION_HEIGHT := 4.0
const FENCE_COLOR := Color(0.62, 0.45, 0.26)
## BalanceConfig.stage_layout / solo_stage_layout の番号順。
const LAYOUT_PATHS := [
	"res://resources/stages/open.tres",
	"res://resources/stages/center.tres",
	"res://resources/stages/corners.tres",
	"res://resources/stages/lanes.tres",
]

## add_child の前に設定する。null(単体テストでの既定)ならフェンスなし。
var layout: StageLayout
var _fence_rects: Array[Dictionary] = []  ## {center: Vector2, axis: Vector2(長さ方向), half: Vector2(長さ/2, 厚み/2)}


static func load_layout(index: int) -> StageLayout:
	return load(LAYOUT_PATHS[clampi(index, 0, LAYOUT_PATHS.size() - 1)]) as StageLayout


func _ready() -> void:
	add_to_group("stage")
	_build_floor()
	_build_walls()
	_build_fences()
	_build_camera()
	_build_light()


## 点(x,z)がフェンスに重なっていたら、近い側へ margin だけ離れた位置まで押し出す。アリーナ内にも収める。
func push_out_of_fences(pos: Vector3, margin: float) -> Vector3:
	var p := Vector2(pos.x, pos.z)
	for _pass in 2:
		for rect in _fence_rects:
			var axis: Vector2 = rect["axis"]
			var side := Vector2(-axis.y, axis.x)
			var rel: Vector2 = p - rect["center"]
			var lx := rel.dot(axis)
			var lz := rel.dot(side)
			var hx: float = rect["half"].x + margin
			var hz: float = rect["half"].y + margin
			if absf(lx) >= hx or absf(lz) >= hz:
				continue
			if hx - absf(lx) < hz - absf(lz):
				lx = signf(lx if lx != 0.0 else 1.0) * hx
			else:
				lz = signf(lz if lz != 0.0 else 1.0) * hz
			p = rect["center"] + axis * lx + side * lz
	var bx := maxf(HALF_X - margin, 0.0)
	var bz := maxf(HALF_Z - margin, 0.0)
	return Vector3(clampf(p.x, -bx, bx), pos.y, clampf(p.y, -bz, bz))


## 点(x,z)からフェンスまでの最短距離(重なっていれば0)。フェンスがなければ INF。
func distance_to_fences(pos: Vector3) -> float:
	var best := INF
	var p := Vector2(pos.x, pos.z)
	for rect in _fence_rects:
		var axis: Vector2 = rect["axis"]
		var rel: Vector2 = p - rect["center"]
		var d := Vector2(maxf(absf(rel.dot(axis)) - rect["half"].x, 0.0),
			maxf(absf(rel.dot(Vector2(-axis.y, axis.x))) - rect["half"].y, 0.0))
		best = minf(best, d.length())
	return best


func fence_count() -> int:
	return _fence_rects.size()


func _build_fences() -> void:
	if layout == null:
		return
	var fences := Node3D.new()
	fences.name = "Fences"
	add_child(fences)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FENCE_COLOR
	for spec in layout.fences:
		var body := StaticBody3D.new()
		body.collision_layer = Player.WALL_LAYER
		body.collision_mask = 0
		body.add_to_group("wall") # 突進の激突判定は外周の壁と同じ(スタン)
		body.add_to_group("fence")
		fences.add_child(body)
		body.position = Vector3(spec.center.x, 0.0, spec.center.y)
		body.rotation.y = -deg_to_rad(spec.rotation_deg)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(spec.length, FENCE_VISUAL_HEIGHT, FENCE_THICK)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position.y = FENCE_VISUAL_HEIGHT * 0.5
		body.add_child(mi)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(spec.length, FENCE_COLLISION_HEIGHT, FENCE_THICK)
		col.shape = shape
		col.position.y = FENCE_COLLISION_HEIGHT * 0.5
		body.add_child(col)
		var a := deg_to_rad(spec.rotation_deg)
		_fence_rects.append({
			"center": spec.center,
			"axis": Vector2(cos(a), sin(a)),
			"half": Vector2(spec.length * 0.5, FENCE_THICK * 0.5),
		})

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Player.WALL_LAYER
	body.collision_mask = 0
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
		body.collision_layer = Player.WALL_LAYER
		body.collision_mask = 0
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
	cam.position = Vector3(0, 26.49, 14.08) # 中心から半径≈30・角度62°の見下ろし(円周上で角度のみ調整)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.fov = 60.0

func _build_light() -> void:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	add_child(light)
	light.rotation_degrees = Vector3(-60, -40, 0)
	light.light_energy = 1.2
