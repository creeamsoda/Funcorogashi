class_name DashArrow
extends Node3D
## 突進の溜め中に足元へ出す平たい矢印(見た目のみ)。+Z向き。
## 軸は長さに合わせて伸ばし、先端は固定サイズで先に置く。長さは溜め量で補間し、最大溜めで金色になる。

const MIN_LENGTH := 1.0
const MAX_LENGTH := 3.5
const WIDTH := 0.35
const HEAD := 0.8
const FULL_COLOR := Color(1.0, 0.85, 0.2)
const ALPHA := 0.85

var _base_color: Color
var _mat: StandardMaterial3D
var _shaft: MeshInstance3D
var _head: MeshInstance3D


func _init(base_color: Color = Color.WHITE) -> void:
	name = "DashArrow"
	visible = false
	_base_color = base_color
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = base_color
	var shaft_mesh := PlaneMesh.new()
	shaft_mesh.size = Vector2(WIDTH, 1.0)
	_shaft = _create_part("Shaft", shaft_mesh)
	var head_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-HEAD * 0.5, 0, 0), Vector3(0, 0, HEAD), Vector3(HEAD * 0.5, 0, 0),
	])
	head_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_head = _create_part("Head", head_mesh)


## フン球(半径 radius)の前縁から facing の方向へ、溜め量 ratio(0..1)に応じた長さで伸ばす。
func show_charge(facing: Vector3, radius: float, ratio: float) -> void:
	visible = true
	var length := lerpf(MIN_LENGTH, MAX_LENGTH, ratio)
	position = Vector3(0, -radius + 0.04, 0)
	rotation.y = atan2(facing.x, facing.z)
	_shaft.scale = Vector3(1, 1, length)
	_shaft.position = Vector3(0, 0, radius + length * 0.5)
	_head.position = Vector3(0, 0, radius + length)
	var color := _base_color.lerp(FULL_COLOR, ratio)
	color.a = ALPHA
	_mat.albedo_color = color


func _create_part(part_name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
