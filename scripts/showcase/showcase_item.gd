@tool
class_name ShowcaseItem
extends Node3D
## 紹介画像用シーン(Showcase.tscn)に置くもの(キャラ・フン)の共通部分。向き = ノードの -Z。


## 選択中の表示に使う一行の説明。
func describe() -> String:
	return name


## マウスで選べる半径(床面上)。
func pick_radius() -> float:
	return 0.5


## 大きさを factor 倍にする(ホイール操作)。
func scale_size(_factor: float) -> void:
	pass


func forward() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized() if not f.is_zero_approx() else Vector3.FORWARD


func face_toward(point: Vector3) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length() > 0.05:
		rotation.y = atan2(-d.x, -d.z)
