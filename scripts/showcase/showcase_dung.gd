@tool
class_name ShowcaseDung
extends ShowcaseItem
## 紹介画像用シーン(Showcase.tscn)に置く地面のフン。向き = ノードの -Z(逃げる向き)。
## 実行すると本物の DungPickup を生成し、逃走・回収・時間切れ消滅を止めてその場に置き続ける。

const KIND_NAMES := ["通常", "ブラックホール", "加速"]

@export_range(0.1, 20.0, 0.1, "or_greater") var dung_size: float = 1.0:
	set(v):
		dung_size = v
		_changed()
@export_enum("通常", "ブラックホール", "加速") var kind: int = DungPickup.Kind.NORMAL:
	set(v):
		kind = v
		_changed()
## 逃げている最中の土煙を出す(小さくて逃げないフンには出ない)。
@export var fleeing: bool = false:
	set(v):
		fleeing = v
		_changed()

var pickup: DungPickup
var _built_key := ""
var _preview: Node3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_build_preview()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var key := "%.3f|%d|%s" % [dung_size, kind, fleeing]
	if key != _built_key:
		_built_key = key
		_spawn()
	if pickup != null and pickup.is_inside_tree():
		pickup._heading = forward()
		pickup._update_visual()


func describe() -> String:
	return "フン %s / サイズ %.1f%s" % [KIND_NAMES[kind], dung_size, " / 逃走中" if fleeing else ""]


func pick_radius() -> float:
	return _radius() + 0.3


func scale_size(factor: float) -> void:
	dung_size *= factor


func _spawn() -> void:
	if pickup != null:
		pickup.queue_free()
	pickup = DungPickup.create(dung_size)
	pickup.kind = kind as DungPickup.Kind
	pickup.name = "Dung"
	pickup.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(pickup)
	# 逃走・回収・消滅を止め、見た目だけ出す。
	pickup.set_physics_process(false)
	pickup.set_process(false)
	pickup.collision_layer = 0
	pickup._collect_area.set_deferred("monitoring", false)
	pickup._placed = true
	pickup._state = DungPickup.FleeState.RUNNING if fleeing else DungPickup.FleeState.IDLE
	pickup._heading = forward()
	pickup._update_visual()


func _radius() -> float:
	if Engine.is_editor_hint():
		return ShowcaseBeetle.editor_radius(dung_size, "pickup_size_to_scale")
	return Config.balance.radius_for_size(dung_size, Config.balance.pickup_size_to_scale)


func _changed() -> void:
	if Engine.is_editor_hint():
		_build_preview()


func _build_preview() -> void:
	if not is_inside_tree():
		return
	if _preview != null:
		_preview.queue_free()
	_preview = Node3D.new()
	add_child(_preview, false, Node.INTERNAL_MODE_BACK)
	var r := _radius()
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	mi.mesh = sphere
	mi.position.y = r
	var mat := StandardMaterial3D.new()
	mat.albedo_color = DungPickup.KIND_COLORS[kind]
	mi.material_override = mat
	_preview.add_child(mi)
