class_name DungModel
extends RefCounted

## 逃げるフン(地面に落ちて動くフン)の見た目(うんちモデル)。
## GLB のメッシュを「水平方向の幅1・底面が y=0・上から見た中心が原点」に正規化して1つだけ持ち、
## 必要な幅に拡大したメッシュを返す。色は使う側の material_override で付ける。

const SCENE: PackedScene = preload("res://resources/models/poop/poop.glb")

static var _source: Mesh
static var _to_unit: Transform3D


## 水平方向の幅が width になるうんちメッシュ。底面が y=0。
static func mesh_with_width(width: float) -> Mesh:
	if _source == null and not _load_source():
		return BoxMesh.new()
	var to_size := Transform3D(Basis.from_scale(Vector3.ONE * width), Vector3.ZERO) * _to_unit
	var st := SurfaceTool.new()
	for i in _source.get_surface_count():
		st.append_from(_source, i, to_size)
	return st.commit()


static func _load_source() -> bool:
	var root := SCENE.instantiate()
	var found := _find_mesh(root)
	root.free()
	if found == null:
		push_error("poop.glb にメッシュが見つかりません。")
		return false
	var aabb := found.get_aabb()
	var k := 1.0 / maxf(maxf(aabb.size.x, aabb.size.z), 0.001)
	var center := aabb.get_center()
	var bottom_center := Vector3(center.x, aabb.position.y, center.z)
	_to_unit = Transform3D(Basis.from_scale(Vector3.ONE * k), -bottom_center * k)
	_source = found
	return true


static func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
