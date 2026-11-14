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
## プレイヤー色に塗り替える羽のマテリアル名。
const WING_MATERIAL_NAME := "Wing_Image"

var root: Node3D
var model: Node3D
var meshes: Array[MeshInstance3D] = []
## own_all_materials=true の時は全マテリアル、false の時は羽のマテリアルだけ(複製して上書きしたもの)。
var materials: Array[StandardMaterial3D] = []
## Beetleローカルで、頭を下げた後のモデル後端(+Z側)までの距離。
var rear_extent := 0.0


## parent の下に Beetle ノードを作って組み立てる。
## own_all_materials: 全マテリアルを個体ごとに複製する(点滅など色を書き換える場合)。
static func create(parent: Node, wing_color: Color, own_all_materials: bool) -> BeetleModel:
	var b := BeetleModel.new()
	b.root = Node3D.new()
	b.root.name = "Beetle"
	parent.add_child(b.root)
	b.model = SCENE.instantiate() as Node3D
	b.model.name = "Model"
	# GLBの頭は-Z、腹は+Z。サイズは基準姿勢で測り、頭下げの角度と分離する。
	b.model.rotation.x = deg_to_rad(-SIZE_REFERENCE_DEGREES)
	b.root.add_child(b.model)
	for node in b.model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		b.meshes.append(part)
		for surface in part.mesh.get_surface_count():
			var source := part.get_active_material(surface) as StandardMaterial3D
			var is_wing := source.resource_name == WING_MATERIAL_NAME
			if not own_all_materials and not is_wing:
				continue
			# GLBの共有マテリアルを書き換えず、個体ごとに色を保持する。
			var mat := source.duplicate() as StandardMaterial3D
			if is_wing:
				mat.albedo_color = wing_color
			part.set_surface_override_material(surface, mat)
			b.materials.append(mat)
	var bounds := mesh_bounds(b.meshes, b.root)
	b.model.scale = Vector3.ONE * REFERENCE_LENGTH * VISUAL_SIZE_RATIO / bounds.size.z
	b.model.rotation.x = deg_to_rad(-HEAD_DOWN_DEGREES)
	bounds = mesh_bounds(b.meshes, b.root)
	# 傾けた後の足先を地面へ合わせ、腹側の張り出しに応じて球との間隔を取る。
	b.model.position.y = -bounds.position.y + 0.005
	b.rear_extent = bounds.end.z
	return b


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
