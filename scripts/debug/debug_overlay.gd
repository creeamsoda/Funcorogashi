class_name DebugOverlay
extends MeshInstance3D
## 開発用のデバッグ線描画(F2)。"debug_draw" グループのノードが debug_draw(overlay) で線を積み、
## 毎フレームまとめて描き直す。地形に埋もれないよう深度テストなしで手前に描く。

const GROUP := "debug_draw"

var _immediate := ImmediateMesh.new()
var _points := PackedVector3Array()
var _colors := PackedColorArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mesh = _immediate
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 10
	material_override = mat
	visible = false


func _process(_dt: float) -> void:
	_immediate.clear_surfaces()
	if not visible:
		return
	_points.clear()
	_colors.clear()
	for node in get_tree().get_nodes_in_group(GROUP):
		if node.has_method("debug_draw"):
			node.debug_draw(self)
	if _points.is_empty():
		return
	_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in _points.size():
		_immediate.surface_set_color(_colors[i])
		_immediate.surface_add_vertex(_points[i])
	_immediate.surface_end()


func line(from: Vector3, to: Vector3, color: Color) -> void:
	_points.append(from)
	_points.append(to)
	_colors.append(color)
	_colors.append(color)


## 地面と平行な円(XZ平面)。
func circle(center: Vector3, radius: float, color: Color, segments: int = 32) -> void:
	var prev := center + Vector3(radius, 0.0, 0.0)
	for i in range(1, segments + 1):
		var a := TAU * float(i) / float(segments)
		var next := center + Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		line(prev, next, color)
		prev = next


func line_count() -> int:
	return _points.size() / 2
