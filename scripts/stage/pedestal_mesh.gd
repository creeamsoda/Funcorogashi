class_name PedestalMesh
extends RefCounted
## 中央の台座の形(三角形)を作る。Stage._build_pedestal から使う。
## 円錐台(天面=高さ h)と、その周りを半周して天面へつながるスロープ。
## 天面はスロープ上端の先へ張り出した卵形(楕円ぎみ)にし、スロープ上端がそのまま天面へ続くようにする。
## 上面(天面・スロープ上面)と側面(台座側面・スロープ側面)を別々に持つ(色分け用)。

## 円周・スロープの分割数。
const SEGMENTS := 48
## 天面の張り出し(スロープ上端→天面の接続)が元の円へ戻るまでの角度。
const LOBE_DEG := 150.0

var top_faces := PackedVector3Array()
var top_normals := PackedVector3Array()
var side_faces := PackedVector3Array()
var side_normals := PackedVector3Array()


## rt=天面半径 / rb=底面半径 / w=スロープ幅 / h=高さ。
static func build(rt: float, rb: float, w: float, h: float) -> PedestalMesh:
	var m := PedestalMesh.new()
	var n := SEGMENTS
	# 円錐台: スロープ上端(奥)から、スロープの続く向きへ一周する。上端では断面がスロープ上端と同じ
	# (天面が rt+w まで張り出し、外側は垂直な壁)で、LOBE_DEG かけて元の円錐台へ戻る。
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
		_add_quad(m.side_faces, m.side_normals, b0, b1, t1, t0, (u0 + u1).normalized() + Vector3.UP * 0.3)
		_add_tri(m.top_faces, m.top_normals, top_c, t0, t1, Vector3.UP)
	# スロープ: 手前(+z, 角度90°)から右(+x, 0°)を回って奥(-z, -90°)へ。t=0 で地面、t=1 で天面の高さ。
	for j in n:
		var p0 := _ramp_points(float(j) / float(n), rt, rb, w, h)
		var p1 := _ramp_points(float(j + 1) / float(n), rt, rb, w, h)
		_add_quad(m.top_faces, m.top_normals, p0["inner"], p0["outer"], p1["outer"], p1["inner"], Vector3.UP)
		_add_quad(m.side_faces, m.side_normals, p0["outer"], p0["ground"], p1["ground"], p1["outer"],
			(p0["u"] + p1["u"]).normalized())
	return m


## 上面・側面を色分けした見た目用のメッシュ。
func to_array_mesh(top_color: Color, side_color: Color) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_add_surface(mesh, top_faces, top_normals, top_color)
	_add_surface(mesh, side_faces, side_normals, side_color)
	return mesh


## 判定用の全三角形(上面+側面)。
func all_faces() -> PackedVector3Array:
	var faces := top_faces.duplicate()
	faces.append_array(side_faces)
	return faces


## スロープ上の t(0〜1) の角度(xz 平面の atan2(z, x))。手前 90° から奥 -90° へ。
static func _ramp_angle(t: float) -> float:
	return PI * 0.5 - PI * t


## 天面の張り出し量(0〜1)。f はスロープ上端から続く向きへ回った割合(0〜1で一周)。
## 上端(f=0)で 1、LOBE_DEG 回ったところで 0 へなめらかに戻る。
static func _lobe(f: float) -> float:
	var deg := f * 360.0
	if deg >= LOBE_DEG:
		return 0.0
	return 0.5 * (1.0 + cos(PI * deg / LOBE_DEG))


## スロープ上の t(0〜1) の断面: 内側上端・外側上端・外側の地面・外向き単位ベクトル。
## 内側は円錐台の側面に沿う(高さ t*h での側面の半径)。
static func _ramp_points(t: float, rt: float, rb: float, w: float, h: float) -> Dictionary:
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
static func _add_quad(faces: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward_hint: Vector3) -> void:
	_add_tri(faces, normals, a, b, c, outward_hint)
	_add_tri(faces, normals, a, c, d, outward_hint)


static func _add_tri(faces: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, outward_hint: Vector3) -> void:
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


static func _add_surface(mesh: ArrayMesh, faces: PackedVector3Array, normals: PackedVector3Array, color: Color) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
