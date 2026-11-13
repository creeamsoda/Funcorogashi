class_name Stage
extends Node3D
## ステージ: 床 + 外壁(長方形 or 円形。layout.arena_shape) + 全体俯瞰カメラ + ライト。
## すべてコード生成(primitivesのみ)。壁は "wall" グループに入れる(突進の壁判定用)。

## 長方形アリーナ内寸の半分(x, z)。円形アリーナでもこの長方形の内側に収まる(動物の出入り判定の外枠)。
## 実際の内外判定は Stage.is_inside_arena / clamp_to_arena を使う。
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
const PILLAR_COLOR := Color(0.45, 0.32, 0.20)
## BalanceConfig.stage_layout / solo_stage_layout の番号順。
const LAYOUT_PATHS := [
	"res://resources/stages/open.tres",
	"res://resources/stages/center.tres",
	"res://resources/stages/corners.tres",
	"res://resources/stages/lanes.tres",
	"res://resources/stages/circle_cross.tres",
	"res://resources/stages/pedestal.tres",
	"res://resources/stages/boost_pads.tres",
]
## 加速板の色(板・風)。
const BOOST_PAD_COLOR := Color(1.0, 0.55, 0.1)
const BOOST_WIND_COLOR := Color(0.95, 0.30, 0.0)  ## 板より濃いオレンジ(板の上でも見えるように)
## 台座の分割数(円周・スロープ)と色。
const PEDESTAL_SEGMENTS := 48
const PEDESTAL_TOP_COLOR := Color(0.97, 0.97, 0.97)   ## 天面・スロープ上面
const PEDESTAL_SIDE_COLOR := Color(0.32, 0.32, 0.35)  ## 台座側面・スロープ側面
## 天面の張り出し(スロープ上端→天面の接続)が元の円へ戻るまでの角度。
const PEDESTAL_LOBE_DEG := 150.0
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

## 杭: 外壁と同じ高さの角柱。"wall" グループ(突進で激突してスタン)。
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
		var body := StaticBody3D.new()
		body.collision_layer = Player.WALL_LAYER
		body.collision_mask = 0
		body.add_to_group("wall")
		body.add_to_group("pillar")
		root.add_child(body)
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
	var body := StaticBody3D.new()
	body.collision_layer = Player.WALL_LAYER
	body.collision_mask = 0
	body.name = "Floor"
	body.add_to_group("floor")
	add_child(body)
	var mi := MeshInstance3D.new()
	var shape: Shape3D
	if is_circle():
		var r := arena_radius() + WALL_THICK
		var cyl := CylinderMesh.new()
		cyl.top_radius = r
		cyl.bottom_radius = r
		cyl.height = FLOOR_THICK
		cyl.radial_segments = CIRCLE_WALL_SEGMENTS
		mi.mesh = cyl
		var cs := CylinderShape3D.new()
		cs.radius = r
		cs.height = FLOOR_THICK
		shape = cs
	else:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(STAGE_SIZE.x, FLOOR_THICK, STAGE_SIZE.y)
		mi.mesh = mesh
		var bs := BoxShape3D.new()
		bs.size = mesh.size
		shape = bs
	mi.position = Vector3(0, -FLOOR_THICK * 0.5, 0)
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

## 加速板: 床に貼った薄いオレンジの板(判定なし)と、上空に常時流れるオレンジの風(突進無敵と同じ流線)。
func _build_boost_pads() -> void:
	if layout == null or layout.boost_pads.is_empty():
		return
	var pads := Node3D.new()
	pads.name = "BoostPads"
	add_child(pads)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BOOST_PAD_COLOR
	mat.emission_enabled = true
	mat.emission = BOOST_PAD_COLOR * 0.25
	for i in layout.boost_pads.size():
		var spec := layout.boost_pads[i]
		var mi := MeshInstance3D.new()
		mi.name = "BoostPad%d" % i
		var mesh := BoxMesh.new()
		mesh.size = Vector3(spec.size.x, 0.02, spec.size.y)
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = Vector3(spec.center.x, 0.011, spec.center.y)
		mi.add_to_group("boost_pad")
		pads.add_child(mi)
		var wind := DashSpeedLines.new()
		wind.name = "BoostWind%d" % i
		pads.add_child(wind)
		wind.setup_area(Vector3(spec.center.x, 0.8, spec.center.y), Vector3(spec.wind_dir.x, 0.0, spec.wind_dir.y),
			Vector3(spec.size.x * 0.5, 0.6, spec.size.y * 0.5), BOOST_WIND_COLOR)


## 中央の台座: 円錐台(天面=壁の高さ)と、その周りを半周して天面へつながるスロープ。
## 天面はスロープ上端の先へ張り出した卵形(楕円ぎみ)にし、スロープ上端がそのまま天面へ続くようにする。
## 見た目と判定は同じ三角形から作る(判定は1つの ConcavePolygonShape3D)。"wall" グループなので突進で激突できる。
## 斜面(スロープ上面・天面)は床として登れ、急な側面とスロープの外側面は壁になる。
## 色は 上面(天面・スロープ上面)=白、側面(台座側面・スロープ側面)=濃いグレー。
func _build_pedestal() -> void:
	if layout == null or not layout.pedestal_enabled:
		return
	var h := WALL_HEIGHT
	var rt := layout.pedestal_top_radius
	var rb := maxf(layout.pedestal_base_radius, rt)
	var w := layout.pedestal_ramp_width
	var n := PEDESTAL_SEGMENTS
	var top_faces := PackedVector3Array()
	var top_normals := PackedVector3Array()
	var side_faces := PackedVector3Array()
	var side_normals := PackedVector3Array()
	# 円錐台: スロープ上端(奥)から、スロープの続く向きへ一周する。上端では断面がスロープ上端と同じ
	# (天面が rt+w まで張り出し、外側は垂直な壁)で、PEDESTAL_LOBE_DEG かけて元の円錐台へ戻る。
	var end_a := _ramp_angle(1.0)
	var top_c := Vector3(0, h, 0)
	for i in n:
		var s0 := _lobe(float(i) / float(n))
		var s1 := _lobe(float(i + 1) / float(n))
		var a0 := end_a - TAU * float(i) / float(n)
		var a1 := end_a - TAU * float(i + 1) / float(n)
		var u0 := Vector3(cos(a0), 0, sin(a0))
		var u1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := u0 * lerpf(rb, rt + w, s0)
		var b1 := u1 * lerpf(rb, rt + w, s1)
		var t0 := u0 * lerpf(rt, rt + w, s0) + Vector3.UP * h
		var t1 := u1 * lerpf(rt, rt + w, s1) + Vector3.UP * h
		_add_quad(side_faces, side_normals, b0, b1, t1, t0, (u0 + u1).normalized() + Vector3.UP * 0.3)
		_add_tri(top_faces, top_normals, top_c, t0, t1, Vector3.UP)
	# スロープ: 手前(+z, 角度90°)から右(+x, 0°)を回って奥(-z, -90°)へ。t=0 で地面、t=1 で天面の高さ。
	var steps := PEDESTAL_SEGMENTS
	for j in steps:
		var p0 := _ramp_points(float(j) / float(steps), rt, rb, w, h)
		var p1 := _ramp_points(float(j + 1) / float(steps), rt, rb, w, h)
		_add_quad(top_faces, top_normals, p0["inner"], p0["outer"], p1["outer"], p1["inner"], Vector3.UP)
		_add_quad(side_faces, side_normals, p0["outer"], p0["ground"], p1["ground"], p1["outer"],
			(p0["u"] + p1["u"]).normalized())

	var body := StaticBody3D.new()
	body.name = "Pedestal"
	body.collision_layer = Player.WALL_LAYER
	body.collision_mask = 0
	body.add_to_group("wall")
	body.add_to_group("pedestal")
	add_child(body)
	var mesh := ArrayMesh.new()
	_add_surface(mesh, top_faces, top_normals, PEDESTAL_TOP_COLOR)
	_add_surface(mesh, side_faces, side_normals, PEDESTAL_SIDE_COLOR)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var all_faces := top_faces.duplicate()
	all_faces.append_array(side_faces)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(all_faces)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)


## スロープ上の t(0〜1) の角度(xz 平面の atan2(z, x))。手前 90° から奥 -90° へ。
func _ramp_angle(t: float) -> float:
	return PI * 0.5 - PI * t


## 天面の張り出し量(0〜1)。f はスロープ上端から続く向きへ回った割合(0〜1で一周)。
## 上端(f=0)で 1、PEDESTAL_LOBE_DEG 回ったところで 0 へなめらかに戻る。
func _lobe(f: float) -> float:
	var deg := f * 360.0
	if deg >= PEDESTAL_LOBE_DEG:
		return 0.0
	return 0.5 * (1.0 + cos(PI * deg / PEDESTAL_LOBE_DEG))


## スロープ上の t(0〜1) の断面: 内側上端・外側上端・外側の地面・外向き単位ベクトル。
## 内側は円錐台の側面に沿う(高さ t*h での側面の半径)。
func _ramp_points(t: float, rt: float, rb: float, w: float, h: float) -> Dictionary:
	var a := _ramp_angle(t)
	var u := Vector3(cos(a), 0, sin(a))
	var y := h * t
	var ri := lerpf(rb, rt, t)
	return {
		"u": u,
		"inner": u * ri + Vector3.UP * y,
		"outer": u * (ri + w) + Vector3.UP * y,
		"ground": u * (ri + w),
	}


## 四角形 a-b-c-d を三角形2枚で追加する。法線は outward_hint の側を向ける(面の巻き順に依らない)。
func _add_quad(faces: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward_hint: Vector3) -> void:
	_add_tri(faces, normals, a, b, c, outward_hint)
	_add_tri(faces, normals, a, c, d, outward_hint)


func _add_tri(faces: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, outward_hint: Vector3) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.length_squared() < 1e-10:
		return # 面積0(スロープ下端の高さ0の側面など)
	nrm = nrm.normalized()
	if nrm.dot(outward_hint) < 0.0:
		var tmp := b
		b = c
		c = tmp
		nrm = -nrm
	# Godot は時計回りが表。表が外を向くよう a,c,b の順に積む。
	faces.append_array([a, c, b])
	normals.append_array([nrm, nrm, nrm])


func _add_surface(mesh: ArrayMesh, faces: PackedVector3Array, normals: PackedVector3Array, color: Color) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


## 円形外壁: 箱を円周に並べる。内面が arena_radius に接するよう配置し、継ぎ目が空かないよう少し長くする。
func _build_circle_walls() -> void:
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	var r := arena_radius() + WALL_THICK * 0.5
	var seg_len := 2.0 * (arena_radius() + WALL_THICK) * tan(PI / CIRCLE_WALL_SEGMENTS) + 0.05
	var size := Vector3(seg_len, WALL_HEIGHT, WALL_THICK)
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	for i in CIRCLE_WALL_SEGMENTS:
		var a := TAU * float(i) / float(CIRCLE_WALL_SEGMENTS)
		var body := StaticBody3D.new()
		body.collision_layer = Player.WALL_LAYER
		body.collision_mask = 0
		body.add_to_group("wall")
		walls.add_child(body)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		body.add_child(mi)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		body.position = Vector3(cos(a) * r, WALL_HEIGHT * 0.5, sin(a) * r)
		body.rotation.y = -a + PI * 0.5 # 箱の長さ方向(X)を接線方向へ


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
