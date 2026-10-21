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
var _collected := false


## ファクトリ。GameManager.spawn_pickup() から使う。
static func create(p_size: float, p_owner_id: int = -1) -> DungPickup:
	var d := (load("res://scenes/DungPickup.tscn") as PackedScene).instantiate() as DungPickup
	d.size = p_size
	d.owner_id = p_owner_id
	return d


func _ready() -> void:
	collision_layer = 0
	collision_mask = Player.HUMAN_LAYER
	_spawned_at = _now()
	_build_visual()
	body_entered.connect(_on_body_entered)
	add_to_group(DebugOverlay.GROUP)


func _process(_dt: float) -> void:
	if Config.balance.pickup_despawn_enabled and _now() - _spawned_at >= Config.balance.pickup_despawn_time:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if _collected or is_queued_for_deletion() or not (body is Player):
		return
	var p := body as Player
	if not p.gameplay_active or not p.can_collect or p.is_queued_for_deletion():
		return
	if owner_id == p.player_id and _now() < collectible_at:
		return # 自分のドロップはスタン明けまで回収不可
	# 動物由来(ownerなし)は実量に獲得倍率を掛ける。プレイヤーが落としたフンは実量を保持する。
	var gain: float = size * Config.balance.size_gain_per_pickup if owner_id < 0 else size
	_collected = true # 同一フレームの複数body_enteredでも1回だけ加算する。
	p.add_size(gain)
	p.play_pickup_se(gain)
	collected.emit(gain)
	queue_free()


## F2 デバッグ表示: 回収判定の範囲。
func debug_draw(overlay: DebugOverlay) -> void:
	overlay.circle(Vector3(global_position.x, 0.05, global_position.z), _shape.radius, Color(1.0, 0.85, 0.2))


func _radius() -> float:
	return Config.balance.radius_for_size(size, Config.balance.pickup_size_to_scale)


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
