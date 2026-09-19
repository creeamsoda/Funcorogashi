class_name DungPickup
extends Area3D
## 地面に落ちたフン。プレイヤー(のフン球)が触れると取り込まれてサイズ増加。
## owner_id 本人のドロップは collectible_at(スタン明け)まで回収不可。

signal collected(size: float)

var size: float = 0.5
var owner_id: int = -1
var collectible_at: float = 0.0  ## この秒(get_ticks/1000)以降 owner 本人も回収可

var _mesh: SphereMesh
var _shape: SphereShape3D
var _spawned_at: float


## ファクトリ。GameManager.spawn_pickup() から使う。
static func create(p_size: float, p_owner_id: int = -1) -> DungPickup:
	var d := (load("res://scenes/DungPickup.tscn") as PackedScene).instantiate() as DungPickup
	d.size = p_size
	d.owner_id = p_owner_id
	return d


func _ready() -> void:
	_spawned_at = _now()
	_build_visual()
	body_entered.connect(_on_body_entered)


func _process(_dt: float) -> void:
	if Config.balance.pickup_despawn_enabled and _now() - _spawned_at >= Config.balance.pickup_despawn_time:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if not (body is Player):
		return
	var p := body as Player
	if owner_id == p.player_id and _now() < collectible_at:
		return # 自分のドロップはスタン明けまで回収不可
	p.add_size(size)
	collected.emit(size)
	queue_free()


func _radius() -> float:
	return maxf(0.2, size * 0.4)


func _build_visual() -> void:
	_shape = SphereShape3D.new()
	_shape.radius = _radius() + Config.balance.pickup_collect_radius
	var col := CollisionShape3D.new()
	col.shape = _shape
	add_child(col)

	_mesh = SphereMesh.new()
	_mesh.radius = _radius()
	_mesh.height = _radius() * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.24, 0.14)
	mi.material_override = mat
	add_child(mi)

	position.y = _radius()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
