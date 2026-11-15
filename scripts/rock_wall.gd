class_name RockWall
extends RefCounted

## 外壁の見た目: 岩モデル(3種)を外壁の内面に沿ってランダムに並べる。
## 当たり判定は Stage 側の箱のまま。ここは見た目だけを作る。
## 岩は正面(+Z。面が細かい側)をアリーナの内側へ向け、背面(面が粗い側)は外へ向ける。
## 乱数は固定シードなので、同じステージは毎回同じ並びになる。

const MODEL_PATHS := [
	"res://resources/models/rock/rock.glb",
	"res://resources/models/rock/rock_asymmetric.glb",
	"res://resources/models/rock/rock_camel.glb",
]
const SEED := 20261114
## 隣の岩との間隔 = 岩の幅 × この範囲の乱数。1未満なので岩どうしは重なり、隙間ができにくい。
const SPACING_RANGE := Vector2(0.5, 0.7)
const SCALE_RANGE := Vector2(1.275, 1.65)
## 高さ方向だけに掛ける倍率。横を大きくしても高さは元の岩と同程度(約1.9〜3.0)に抑える。
## 範囲に幅を持たせて、同じ形が並んでも単調に見えないようにする。
const HEIGHT_SCALE_RANGE := Vector2(0.57, 0.77)
## 向きの揺らぎ(度)。大きいと背面がアリーナから見えるので小さめ。
const YAW_JITTER_DEG := 12.0
## 岩の正面が外壁の内面からアリーナ側へはみ出す量の範囲(負なら内面より奥)。
const INSET_RANGE := Vector2(-0.1, 0.15)

## モデルのグレーのうち Config.balance.rock_color そのものになる明るさ(面の濃淡の中央付近)。
const ROCK_REFERENCE_GRAY := 0.58

static var _scenes: Array[PackedScene] = []
static var _tinted_cache: Dictionary = {}  ## 元マテリアル → 黄土色に塗ったトゥーンマテリアル
static var _front_depth: Array[float] = []  ## 原点から正面(+Z)の端までの距離
static var _width: Array[float] = []        ## X方向の幅


## 内面の線分 from→to に沿って岩を並べる。inward はアリーナ側を向く水平の単位ベクトル。
static func build_line(parent: Node3D, from: Vector3, to: Vector3, inward: Vector3, rng: RandomNumberGenerator) -> void:
	_ensure_loaded()
	var length := from.distance_to(to)
	var dir := (to - from) / length
	var t := 0.0
	while t < length:
		var i := rng.randi_range(0, _scenes.size() - 1)
		var s := rng.randf_range(SCALE_RANGE.x, SCALE_RANGE.y)
		_place(parent, from + dir * t, inward, i, s, rng)
		t += _width[i] * s * rng.randf_range(SPACING_RANGE.x, SPACING_RANGE.y)


## 半径 radius の円(内面)に沿って岩を並べる。
static func build_circle(parent: Node3D, radius: float, rng: RandomNumberGenerator) -> void:
	_ensure_loaded()
	var a := 0.0
	while a < TAU:
		var i := rng.randi_range(0, _scenes.size() - 1)
		var s := rng.randf_range(SCALE_RANGE.x, SCALE_RANGE.y)
		var p := Vector3(cos(a), 0.0, sin(a)) * radius
		_place(parent, p, -p.normalized(), i, s, rng)
		a += _width[i] * s * rng.randf_range(SPACING_RANGE.x, SPACING_RANGE.y) / radius


static func new_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


## 内面上の点 at に、正面を inward へ向けた岩を1つ置く。
static func _place(parent: Node3D, at: Vector3, inward: Vector3, i: int, s: float, rng: RandomNumberGenerator) -> void:
	var rock := _scenes[i].instantiate() as Node3D
	var yaw := atan2(inward.x, inward.z) + deg_to_rad(rng.randf_range(-YAW_JITTER_DEG, YAW_JITTER_DEG))
	rock.rotation.y = yaw
	rock.scale = Vector3(s, s * rng.randf_range(HEIGHT_SCALE_RANGE.x, HEIGHT_SCALE_RANGE.y), s)
	# 正面の端が内面付近に来るよう、原点を外側へ下げる。
	var back := _front_depth[i] * s - rng.randf_range(INSET_RANGE.x, INSET_RANGE.y)
	rock.position = at - inward * back
	parent.add_child(rock)
	_apply_toon(rock)


static func _apply_toon(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for surface in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(surface) as BaseMaterial3D
			if source != null:
				mi.set_surface_override_material(surface, _tinted(source))
	for child in node.get_children():
		_apply_toon(child)


## 元マテリアルのグレーの明るさを保ったまま Config.balance.rock_color に塗ったトゥーンマテリアル(元ごとに1つ)。
static func _tinted(source: BaseMaterial3D) -> BaseMaterial3D:
	if _tinted_cache.has(source):
		return _tinted_cache[source]
	var mat := ToonMaterial.shared_from(source).duplicate() as BaseMaterial3D
	var rock_color := Config.balance.rock_color
	var k := source.albedo_color.get_luminance() / ROCK_REFERENCE_GRAY
	mat.albedo_color = Color(
		clampf(rock_color.r * k, 0.0, 1.0),
		clampf(rock_color.g * k, 0.0, 1.0),
		clampf(rock_color.b * k, 0.0, 1.0))
	_tinted_cache[source] = mat
	return mat


static func _ensure_loaded() -> void:
	if not _scenes.is_empty():
		return
	for path in MODEL_PATHS:
		var scene := load(path) as PackedScene
		var probe := scene.instantiate() as Node3D
		var box := _local_aabb(probe, Transform3D.IDENTITY)
		probe.free()
		_scenes.append(scene)
		_front_depth.append(box.end.z)
		_width.append(box.size.x)


## node 以下のメッシュをまとめた AABB(node の座標系)。
static func _local_aabb(node: Node, xform: Transform3D) -> AABB:
	var box := AABB()
	var has := false
	if node is MeshInstance3D:
		box = xform * (node as MeshInstance3D).get_aabb()
		has = true
	for child in node.get_children():
		var c := _local_aabb(child, xform * (child as Node3D).transform) if child is Node3D else AABB()
		if c.size == Vector3.ZERO:
			continue
		box = box.merge(c) if has else c
		has = true
	return box
