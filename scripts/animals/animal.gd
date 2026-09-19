class_name Animal
extends Node3D
## 動物の共通基底。ステージ内寸(HX,HZ)とドロップ処理を持つ。
## ドロップは group "dung_container" のノードへ生成(無ければ自分の親)。

const HX := 12.0
const HZ := 8.0

func drop_pickup(world_pos: Vector3, sz: float) -> void:
	var parent := _dung_parent()
	if parent == null:
		return
	var pk := DungPickup.create(sz)
	parent.add_child(pk)
	pk.global_position = Vector3(world_pos.x, 0.0, world_pos.z)

func _dung_parent() -> Node:
	var c := get_tree().get_first_node_in_group("dung_container")
	return c if c != null else get_parent()

func _make_box(sz: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	add_child(mi)
