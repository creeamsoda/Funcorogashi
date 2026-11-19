class_name Stage
extends Node3D
## ステージ: 床 + 外壁(長方形 or 円形。layout.arena_shape) + 全体俯瞰カメラ + ライト。
## コード生成(外壁の見た目だけ岩モデル。RockWall)。壁は "wall" グループに入れる(突進の壁判定用)。

## 長方形アリーナ内寸の半分(x, z)。円形アリーナでもこの長方形の内側に収まる(動物の出入り判定の外枠)。
## 実際の内外判定は Stage.is_inside_arena / clamp_to_arena を使う。
const HALF_X := 18.0
const HALF_Z := 12.0
const STAGE_SIZE := Vector2(HALF_X * 2.0, HALF_Z * 2.0)  ## 内寸 (x, z)
const WALL_HEIGHT := 2.0
const WALL_THICK := 0.6
const FLOOR_THICK := 0.5
## 床の見た目だけ外壁の外まで広げる幅(外壁の岩の根元に下の空間が見えないように)。判定は内寸のまま。
const FLOOR_VISUAL_MARGIN := 2.4
## フェンス: 見た目は低く(後で特殊フンが飛び越える前提)、判定は高くして大きなフン球も越えられないようにする。
const FENCE_THICK := 0.4
const FENCE_VISUAL_HEIGHT := 0.9
const FENCE_COLLISION_HEIGHT := 4.0
const FENCE_COLOR := Color(0.62, 0.45, 0.26)
const PILLAR_COLOR := Color(0.32, 0.32, 0.35)  ## 杭(濃いグレー。茶色のフンと見分けやすく)
## BalanceConfig.stage_layout の番号順。
const LAYOUT_PATHS := [
	"res://resources/stages/open.tres",
	"res://resources/stages/center.tres",
	"res://resources/stages/corners.tres",
	"res://resources/stages/lanes.tres",
	"res://resources/stages/circle_cross.tres",
	"res://resources/stages/pedestal.tres",
	"res://resources/stages/boost_pads.tres",
]
## 加速板の床面(オレンジの下地+外へ広がる灰色の枠線。色・線は BalanceConfig)。
const BOOST_PAD_SHADER := preload("res://resources/shaders/boost_pad.gdshader")
## 台座の色。
const PEDESTAL_TOP_COLOR := Color(0.97, 0.97, 0.97)   ## 天面・スロープ上面
const PEDESTAL_SIDE_COLOR := Color(0.32, 0.32, 0.35)  ## 台座側面・スロープ側面
## これより上向きの面を「床」とみなす(法線のy成分。cos45°)。台座側面(急斜面)は床にならない。
const FLOOR_MIN_NORMAL_Y := 0.7
## 円形外壁の分割数(箱を並べて円にする)。
const CIRCLE_WALL_SEGMENTS := 48
## 円形アリーナでのカメラ距離の倍率(奥行きが長方形より長いので少し引く)。
const CIRCLE_CAMERA_SCALE := 1.12

## 現在シーンにあるステージ(境界判定用)。無ければ長方形の既定値で判定する。
static var _active: Stage = null

## add_child の前に設定する。null(単体テストでの既定)ならフェンスなし。
var layout: StageLayout
var _fence_rects: Array[Dictionary] = []
var _pillar_rects: Array[Dictionary] = []  ## 杭(_fence_rects と同じ形式)。押し出し・距離はフェンスと同じに扱う  ## {center: Vector2, axis: Vector2(長さ方向), half: Vector2(長さ/2, 厚み/2)}
var _boost_pad_material: ShaderMaterial  ## 加速板の床面(全板で共有。BalanceConfig を毎フレーム反映)


static func load_layout(index: int) -> StageLayout:
	return load(LAYOUT_PATHS[clampi(index, 0, LAYOUT_PATHS.size() - 1)]) as StageLayout


func _ready() -> void:
	add_to_group("stage")
	_active = self
	_build_floor()
	_build_walls()
	_build_fences()
	_build_pillars()
	_build_pedestal()
	_build_boost_pads()
	_build_camera()
	_build_light()


func _exit_tree() -> void:
	if _active == self:
		_active = null


func is_circle() -> bool:
	return layout != null and layout.arena_shape == StageLayout.ArenaShape.CIRCLE


func arena_radius() -> float:
	return layout.arena_radius if layout != null else 0.0


## 点(x,z)が外壁から margin 以上内側にあるか(現在のステージの形で判定)。
static func is_inside_arena(pos: Vector3, margin: float = 0.0) -> bool:
	if _active != null and _active.is_circle():
		return Vector2(pos.x, pos.z).length() < _active.arena_radius() - margin
	return absf(pos.x) < HALF_X - margin and absf(pos.z) < HALF_Z - margin


## 点(x,z)を外壁から margin 内側の範囲に収める(y はそのまま)。
static func clamp_to_arena(pos: Vector3, margin: float = 0.0) -> Vector3:
	if _active != null and _active.is_circle():
		var r := maxf(_active.arena_radius() - margin, 0.0)
		var p := Vector2(pos.x, pos.z).limit_length(r)
		return Vector3(p.x, pos.y, p.y)
	var bx := maxf(HALF_X - margin, 0.0)
	var bz := maxf(HALF_Z - margin, 0.0)
	return Vector3(clampf(pos.x, -bx, bx), pos.y, clampf(pos.z, -bz, bz))


## 高低差のあるステージ(台座あり)か。false なら全員 y=0 平面上で動く従来どおりの挙動。
static func has_elevation() -> bool:
	return _active != null and _active.layout != null and _active.layout.pedestal_enabled


## 点(x,z)が加速板の上か。板が無いステージでは常に false。
static func is_on_boost_pad(pos: Vector3) -> bool:
	if _active == null or _active.layout == null:
		return false
	for pad in _active.layout.boost_pads:
		if absf(pos.x - pad.center.x) <= pad.size.x * 0.5 and absf(pos.z - pad.center.y) <= pad.size.y * 0.5:
			return true
	return false


## (x, z) の真上 from_y から下向きに depth だけ探した最初の地面。{y, normal} か、無ければ空。
static func probe_ground(pos: Vector3, from_y: float, depth: float) -> Dictionary:
	if _active == null or not _active.is_inside_tree():
		return {}
	var from := Vector3(pos.x, from_y, pos.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * depth, Player.WALL_LAYER)
	var hit := _active.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	return {"y": (hit["position"] as Vector3).y, "normal": hit["normal"]}


## (x, z) で一番高い地面の高さ(空から見下ろした高さ)。地面がなければ 0。
static func top_ground_height(pos: Vector3) -> float:
	var g := probe_ground(pos, 50.0, 60.0)
	return g["y"] if not g.is_empty() else 0.0


## 生成物(フン)を置ける地面へ移す: 真上から見た地面に置き、急斜面(台座側面)なら台座の外側へ押し出す。
static func settle_on_ground(pos: Vector3) -> Vector3:
	if not has_elevation():
		return Vector3(pos.x, 0.0, pos.z)
	var p := Vector3(pos.x, 0.0, pos.z)
	var out := Vector3(p.x, 0.0, p.z).normalized()
	if out.is_zero_approx():
		out = Vector3.BACK
	for _i in 60:
		var g := probe_ground(p, 50.0, 60.0)
		if g.is_empty():
			return Vector3(p.x, 0.0, p.z)
		if (g["normal"] as Vector3).y >= FLOOR_MIN_NORMAL_Y:
			return Vector3(p.x, g["y"], p.z)
		p += out * 0.25
	return Vector3(p.x, 0.0, p.z)


## 円形アリーナで margin 内側の円の外へ出ていたら、外向き法線(xz)を返す。それ以外は ZERO。
static func arena_outward_normal(pos: Vector3, margin: float = 0.0) -> Vector3:
	if _active == null or not _active.is_circle():
		return Vector3.ZERO
	var p := Vector2(pos.x, pos.z)
	if p.length() < _active.arena_radius() - margin or p.length() < 0.001:
		return Vector3.ZERO
	p = p.normalized()
	return Vector3(p.x, 0.0, p.y)


## 点(x,z)がフェンスに重なっていたら、近い側へ margin だけ離れた位置まで押し出す。アリーナ内にも収める。
func push_out_of_fences(pos: Vector3, margin: float) -> Vector3:
	var p := Vector2(pos.x, pos.z)
	for _pass in 2:
		for rect in _fence_rects + _pillar_rects:
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
	return clamp_to_arena(Vector3(p.x, pos.y, p.y), margin)


## 点(x,z)からフェンスまでの最短距離(重なっていれば0)。フェンスがなければ INF。
func distance_to_fences(pos: Vector3) -> float:
	var best := INF
	var p := Vector2(pos.x, pos.z)
	for rect in _fence_rects + _pillar_rects:
		var axis: Vector2 = rect["axis"]
		var rel: Vector2 = p - rect["center"]
		var d := Vector2(maxf(absf(rel.dot(axis)) - rect["half"].x, 0.0),
			maxf(absf(rel.dot(Vector2(-axis.y, axis.x))) - rect["half"].y, 0.0))
		best = minf(best, d.length())
	return best


func fence_count() -> int:
	return _fence_rects.size()


func pillar_count() -> int:
	return _pillar_rects.size()


## 生成物をフェンス・杭から押し出す必要があるか(障害物がある、または円形アリーナ)。
func needs_push_out() -> bool:
	return fence_count() > 0 or pillar_count() > 0 or is_circle()


## 壁・床などの静的な判定(Player.WALL_LAYER)を parent の下に作る。
func _static_body(parent: Node, groups: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Player.WALL_LAYER
	body.collision_mask = 0
	for g in groups:
		body.add_to_group(g)
	parent.add_child(body)
	return body


## 突進で激突する "wall" グループの静的な判定。
func _wall_body(parent: Node, extra_groups: Array[String] = []) -> StaticBody3D:
	return _static_body(parent, ["wall"] + extra_groups)


func _build_fences() -> void:
	if layout == null:
		return
	var fences := Node3D.new()
	fences.name = "Fences"
	add_child(fences)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FENCE_COLOR
	for spec in layout.fences:
		var body := _wall_body(fences, ["fence"]) # 突進の激突判定は外周の壁と同じ(スタン)
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

## 杭: 外壁と同じ高さの濃いグレーの角柱。"wall" グループ(突進で激突してスタン)。
func _build_pillars() -> void:
	if layout == null or layout.pillars.is_empty():
		return
	var root := Node3D.new()
	root.name = "Pillars"
	add_child(root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PILLAR_COLOR
	var sz := Vector3(layout.pillar_size, WALL_HEIGHT, layout.pillar_size)
	var mesh := BoxMesh.new()
	mesh.size = sz
	var shape := BoxShape3D.new()
	shape.size = sz
	for c in layout.pillars:
		var body := _wall_body(root, ["pillar"])
		body.position = Vector3(c.x, WALL_HEIGHT * 0.5, c.y)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		body.add_child(mi)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		_pillar_rects.append({
			"center": c,
			"axis": Vector2(1, 0),
			"half": Vector2(layout.pillar_size * 0.5, layout.pillar_size * 0.5),
		})


func _build_floor() -> void:
	var body := _static_body(self, ["floor"])
	body.name = "Floor"
	var mi := MeshInstance3D.new()
	var shape: Shape3D
	if is_circle():
		var r := arena_radius() + WALL_THICK
		var cyl := CylinderMesh.new()
		cyl.top_radius = arena_radius() + FLOOR_VISUAL_MARGIN
		cyl.bottom_radius = cyl.top_radius
		cyl.height = FLOOR_THICK
		cyl.radial_segments = CIRCLE_WALL_SEGMENTS
		mi.mesh = cyl
		var cs := CylinderShape3D.new()
		cs.radius = r
		cs.height = FLOOR_THICK
		shape = cs
	else:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(STAGE_SIZE.x + FLOOR_VISUAL_MARGIN * 2.0, FLOOR_THICK, STAGE_SIZE.y + FLOOR_VISUAL_MARGIN * 2.0)
		mi.mesh = mesh
		var bs := BoxShape3D.new()
		bs.size = Vector3(STAGE_SIZE.x, FLOOR_THICK, STAGE_SIZE.y)
		shape = bs
	mi.position = Vector3(0, -FLOOR_THICK * 0.5, 0)
	mi.material_override = ToonMaterial.create(Config.balance.floor_color)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = mi.position
	body.add_child(col)

func _build_walls() -> void:
	if is_circle():
		_build_circle_walls()
		return
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
		var body := _wall_body(walls)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(s[2], WALL_HEIGHT, s[3])
		col.shape = shape
		body.add_child(col)
		body.position = Vector3(s[0], WALL_HEIGHT * 0.5, s[1])
	# 見た目は岩(内面の4辺に沿って並べる)。
	var rocks := _rock_root()
	var rng := RockWall.new_rng()
	RockWall.build_line(rocks, Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3.BACK, rng)     # 北
	RockWall.build_line(rocks, Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3.LEFT, rng)       # 東
	RockWall.build_line(rocks, Vector3(hx, 0, hz), Vector3(-hx, 0, hz), Vector3.FORWARD, rng)    # 南
	RockWall.build_line(rocks, Vector3(-hx, 0, hz), Vector3(-hx, 0, -hz), Vector3.RIGHT, rng)    # 西


## 外壁の見た目(岩)をまとめるノード。判定は持たない。
func _rock_root() -> Node3D:
	var rocks := Node3D.new()
	rocks.name = "WallRocks"
	add_child(rocks)
	return rocks


## 加速板: 床に貼った薄い板(判定なし。オレンジ地に灰色の枠線が外へ広がる)。上空の風エフェクトは出さない。
func _build_boost_pads() -> void:
	if layout == null or layout.boost_pads.is_empty():
		return
	var pads := Node3D.new()
	pads.name = "BoostPads"
	add_child(pads)
	_boost_pad_material = ShaderMaterial.new()
	_boost_pad_material.shader = BOOST_PAD_SHADER
	_sync_boost_pad_material()
	# 調整パネル(F1)の変更をその場で見られるように毎フレーム反映する(一時停止中も届く)
	get_tree().process_frame.connect(_sync_boost_pad_material)
	for i in layout.boost_pads.size():
		var spec := layout.boost_pads[i]
		var mi := MeshInstance3D.new()
		mi.name = "BoostPad%d" % i
		var mesh := BoxMesh.new()
		mesh.size = Vector3(spec.size.x, 0.02, spec.size.y)
		mi.mesh = mesh
		mi.material_override = _boost_pad_material
		mi.set_instance_shader_parameter("pad_half_size", spec.size * 0.5)
		mi.position = Vector3(spec.center.x, 0.011, spec.center.y)
		mi.add_to_group("boost_pad")
		pads.add_child(mi)


## 加速板の床面の色・線を BalanceConfig から反映する(全板で1つのマテリアルを共有。板のサイズは instance uniform)。
func _sync_boost_pad_material() -> void:
	var bal := Config.balance
	_boost_pad_material.set_shader_parameter("base_color", bal.boost_pad_base_color)
	_boost_pad_material.set_shader_parameter("line_color", bal.boost_pad_line_color)
	_boost_pad_material.set_shader_parameter("line_spacing", maxf(bal.boost_pad_line_spacing, 0.01))
	_boost_pad_material.set_shader_parameter("line_width", bal.boost_pad_line_width)
	_boost_pad_material.set_shader_parameter("scroll_speed", bal.boost_pad_line_speed)


## 中央の台座(形は PedestalMesh)。見た目と判定は同じ三角形から作る(判定は1つの ConcavePolygonShape3D)。
## "wall" グループなので突進で激突できる。斜面(スロープ上面・天面)は床として登れ、急な側面とスロープの外側面は壁になる。
## 色は 上面(天面・スロープ上面)=白、側面(台座側面・スロープ側面)=濃いグレー。
func _build_pedestal() -> void:
	if layout == null or not layout.pedestal_enabled:
		return
	var rt := layout.pedestal_top_radius
	var rb := maxf(layout.pedestal_base_radius, rt)
	var shape_data := PedestalMesh.build(rt, rb, layout.pedestal_ramp_width, WALL_HEIGHT)
	var body := _wall_body(self, ["pedestal"])
	body.name = "Pedestal"
	var mi := MeshInstance3D.new()
	mi.mesh = shape_data.to_array_mesh(PEDESTAL_TOP_COLOR, PEDESTAL_SIDE_COLOR)
	body.add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(shape_data.all_faces())
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)


## 円形外壁: 判定の箱を円周に並べる。内面が arena_radius に接するよう配置し、継ぎ目が空かないよう少し長くする。
## 見た目は箱ではなく岩(RockWall)。
func _build_circle_walls() -> void:
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	var r := arena_radius() + WALL_THICK * 0.5
	var seg_len := 2.0 * (arena_radius() + WALL_THICK) * tan(PI / CIRCLE_WALL_SEGMENTS) + 0.05
	var size := Vector3(seg_len, WALL_HEIGHT, WALL_THICK)
	var shape := BoxShape3D.new()
	shape.size = size
	for i in CIRCLE_WALL_SEGMENTS:
		var a := TAU * float(i) / float(CIRCLE_WALL_SEGMENTS)
		var body := _wall_body(walls)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		body.position = Vector3(cos(a) * r, WALL_HEIGHT * 0.5, sin(a) * r)
		body.rotation.y = -a + PI * 0.5 # 箱の長さ方向(X)を接線方向へ
	RockWall.build_circle(_rock_root(), arena_radius(), RockWall.new_rng())


func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	add_child(cam)
	cam.position = Vector3(0, 26.49, 14.08) # 中心から半径≈30・角度62°の見下ろし(円周上で角度のみ調整)
	if is_circle():
		cam.position *= CIRCLE_CAMERA_SCALE
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.fov = 60.0

func _build_light() -> void:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	add_child(light)
	light.rotation_degrees = Vector3(-60, -40, 0)
	light.light_energy = 1.2
