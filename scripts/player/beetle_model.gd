class_name BeetleModel
extends RefCounted
## フンコロガシの3Dモデル(GLB)を組み立てる。本編のプレイヤーと結果画面で共用する。
## 「Beetle」ノード(フン球側を+Zにした基準ノード)の下に「Model」としてGLBを置き、
## 基準姿勢でサイズを合わせてから頭を下げ、足先を地面(Beetleの原点)へ揃える。

const SCENE: PackedScene = preload("res://resources/models/beetle/beetle.glb")
## 仮キューブの全長0.9を基準に、脚を含むモデル全長を約1.2倍にする。
const REFERENCE_LENGTH := 0.9
const VISUAL_SIZE_RATIO := 1.2
## 初期の12度姿勢でサイズを合わせ、傾きの調整でモデル自体が拡大しないようにする。
const SIZE_REFERENCE_DEGREES := 12.0
const HEAD_DOWN_DEGREES := 45.0
## 球の外接矩形へ少し入れ、球面に腹側を近づける。
const BALL_GAP := -0.10
## 甲虫のツヤ(フン球は roughness 0.6 のマット)。小さいほどハイライトが小さく鋭い。
const GLOSS_ROUGHNESS := 0.1
const GLOSS_SPECULAR := 1.0
## 縁の照り返しの強さと、白(1)寄りか下地の色(0)寄りか。
const GLOSS_RIM := 0.4
const GLOSS_RIM_TINT := 0.3

var root: Node3D
var model: Node3D
var meshes: Array[MeshInstance3D] = []
## 個体ごとに複製したマテリアル(元マテリアル1つにつき1つ)。点滅などで色を書き換える。
var materials: Array[StandardMaterial3D] = []
## Beetleローカルで、頭を下げた後のモデル後端(+Z側)までの距離。
var rear_extent := 0.0


## parent の下に Beetle ノードを作って組み立てる。
## 全身(胴・脚・羽)を color 一色で塗る。転がすフン球と同じ見え方にするため、
## GLBのマテリアル(羽の灰色テクスチャなど)は使わず、球と同じ ToonMaterial.create で作り直す。
static func create(parent: Node, color: Color) -> BeetleModel:
	var b := BeetleModel.new()
	b.root = Node3D.new()
	b.root.name = "Beetle"
	parent.add_child(b.root)
	b.model = SCENE.instantiate() as Node3D
	b.model.name = "Model"
	# GLBの頭は-Z、腹は+Z。サイズは基準姿勢で測り、頭下げの角度と分離する。
	b.model.rotation.x = deg_to_rad(-SIZE_REFERENCE_DEGREES)
	b.root.add_child(b.model)
	# 個体ごとに、GLBの元マテリアル1つにつき1つ作る(片面/両面の設定だけ引き継ぐ)。
	var own: Dictionary = {}
	for node in b.model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		b.meshes.append(part)
		for surface in part.mesh.get_surface_count():
			var source := part.get_active_material(surface) as StandardMaterial3D
			if not own.has(source):
				var mat := ToonMaterial.create(color)
				mat.cull_mode = source.cull_mode
				_apply_gloss(mat)
				own[source] = mat
				b.materials.append(mat)
			part.set_surface_override_material(surface, own[source])
	var bounds := mesh_bounds(b.meshes, b.root)
	b.model.scale = Vector3.ONE * REFERENCE_LENGTH * VISUAL_SIZE_RATIO / bounds.size.z
	b.model.rotation.x = deg_to_rad(-HEAD_DOWN_DEGREES)
	bounds = mesh_bounds(b.meshes, b.root)
	# 傾けた後の足先を地面へ合わせ、腹側の張り出しに応じて球との間隔を取る。
	b.model.position.y = -bounds.position.y + 0.005
	b.rear_extent = bounds.end.z
	return b


## 甲虫らしいツヤ。色はフン球と同じまま、はっきりした小さなハイライトと縁の照り返しで球と見分ける。
static func _apply_gloss(mat: StandardMaterial3D) -> void:
	mat.roughness = GLOSS_ROUGHNESS
	mat.metallic_specular = GLOSS_SPECULAR
	mat.rim_enabled = true
	mat.rim = GLOSS_RIM
	mat.rim_tint = GLOSS_RIM_TINT


## 半径 radius のフン球の中心から見た、Beetle ノードを置く水平距離(球の後ろ側)。
func distance_from_ball(radius: float) -> float:
	return radius + rear_extent + BALL_GAP


## space のローカル空間で、脚まで含めた実頂点の範囲を測る。
static func mesh_bounds(parts: Array[MeshInstance3D], space: Node3D) -> AABB:
	var bounds := AABB()
	var has_point := false
	for part in parts:
		var to_space := space.global_transform.affine_inverse() * part.global_transform
		for surface in part.mesh.get_surface_count():
			var vertices: PackedVector3Array = part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := to_space * vertex
				if not has_point:
					bounds = AABB(point, Vector3.ZERO)
					has_point = true
				else:
					bounds = bounds.expand(point)
	return bounds
