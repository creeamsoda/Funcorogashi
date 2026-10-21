class_name DungPickup
extends CharacterBody3D
## 地面に落ちたフン。プレイヤー(のフン球)が触れると取り込まれてサイズ増加。
## owner_id 本人のドロップは collectible_at(スタン明けまで)回収不可。
## 近づくプレイヤーから逃げる(Dung Flee)。壁・フェンスとだけ衝突し、プレイヤーやフン同士とはすり抜ける。
## ノード原点は地面(y=0)。見た目・判定は半径ぶん上に置く。

signal collected(size: float)

## 物理レイヤー(Player の WALL/HUMAN/NPC と重ならないビット)。
const DUNG_LAYER := 8
## 床に触れて引っかからないよう、判定球を少し浮かせる。
const FLOOR_CLEARANCE := 0.05
## 逃げ中の跳ねる見た目(怯え)。
const HOP_HEIGHT := 0.18
const HOP_FREQUENCY := 9.0

var size: float = 0.5
var owner_id: int = -1
var collectible_at: float = 0.0  ## この秒(get_ticks/1000)以降 owner 本人も回収可

var _mesh: SphereMesh
var _mesh_instance: MeshInstance3D
var _shape: SphereShape3D        ## 回収判定(半径+回収余裕)
var _body_shape: SphereShape3D   ## 壁との衝突判定
var _collect_area: Area3D
var _spawned_at: float
var _collected := false

## 逃走状態
var _threat_dir := Vector3.ZERO  ## 脅威から離れたい方向(重み付き合計)
var _move_dir := Vector3.ZERO    ## 実際に進む方向(旋回速度で追従)
var _target_dir := Vector3.ZERO  ## 障害物回避後に選んだ方向
var _urgency := 0.0              ## 0..1 近さ(速度倍率)
var _rethink_t := 0.0            ## 次に方向を考え直すまで
var _flee_time := 0.0            ## 連続逃走時間(疲労用)
var _hop_t := 0.0


## ファクトリ。GameManager.spawn_pickup() から使う。
static func create(p_size: float, p_owner_id: int = -1) -> DungPickup:
	var d := (load("res://scenes/DungPickup.tscn") as PackedScene).instantiate() as DungPickup
	d.size = p_size
	d.owner_id = p_owner_id
	return d


func _ready() -> void:
	collision_layer = DUNG_LAYER
	collision_mask = Player.WALL_LAYER
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_spawned_at = _now()
	_build_visual()
	add_to_group(DebugOverlay.GROUP)


func _process(_dt: float) -> void:
	if Config.balance.pickup_despawn_enabled and _now() - _spawned_at >= Config.balance.pickup_despawn_time:
		queue_free()


func _physics_process(delta: float) -> void:
	if _collected or not Config.balance.flee_enabled:
		return
	_rethink_t -= delta
	if _rethink_t <= 0.0:
		_rethink_t = maxf(Config.balance.flee_reaction_time, 0.0)
		_think()
	_steer(delta)
	velocity = _move_dir * _current_speed()
	velocity.y = 0.0
	if not velocity.is_zero_approx():
		move_and_slide()
	global_position.y = 0.0
	_update_hop(delta)


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


## --- 逃走 ---

## 検知半径内のプレイヤーから離れる方向と緊迫度を求め、障害物を避けて進む方向を選ぶ。
func _think() -> void:
	var b := Config.balance
	var radius := maxf(b.flee_detect_radius, 0.01)
	var panic := clampf(b.flee_panic_distance, 0.0, radius - 0.01)
	_threat_dir = Vector3.ZERO
	_urgency = 0.0
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as Player
		if p == null or not p.gameplay_active or p.state == Player.State.STUNNED:
			continue
		var away := global_position - p.global_position
		away.y = 0.0
		# 球の縁同士の距離で測る(大きなフン球ほど遠くから怖がる)
		var d := maxf(away.length() - p.body_radius() - _radius(), 0.0)
		if d >= radius:
			continue
		var w := 1.0 - d / radius
		var dir := away.normalized() if away.length() > 0.001 else Vector3.RIGHT
		_threat_dir += dir * w * w
		_urgency = maxf(_urgency, clampf((radius - d) / (radius - panic), 0.0, 1.0))
	if _threat_dir.length() < 0.001:
		_target_dir = Vector3.ZERO
		return
	_target_dir = _choose_direction(_threat_dir.normalized())


## 周囲の候補方向を、逃げたい方向との一致と前方の空き具合で採点する。
## どれも採点が0以下(=逃げ道なし)なら止まる。壁際・角・挟み撃ちで追い込まれる。
func _choose_direction(desired: Vector3) -> Vector3:
	var b := Config.balance
	var samples := maxi(b.flee_sample_dirs, 4)
	var look := maxf(b.flee_look_ahead, 0.1)
	var space_state := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, _radius() + FLOOR_CLEARANCE, 0)
	var best := Vector3.ZERO
	var best_score := 0.0
	for i in samples:
		var a := TAU * float(i) / float(samples)
		var cand := Vector3(cos(a), 0.0, sin(a))
		var free := look
		var query := PhysicsRayQueryParameters3D.create(origin, origin + cand * (look + _radius()), Player.WALL_LAYER, [get_rid()])
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			free = maxf(origin.distance_to(hit["position"]) - _radius(), 0.0)
		var space := clampf(free / look, 0.0, 1.0)
		var score := b.flee_weight_flee * cand.dot(desired) * space + b.flee_weight_space * space
		if score > best_score:
			best_score = score
			best = cand
	return best


## 選んだ方向へ旋回速度の上限つきで向きを変える。止まる時は向きを保ったまま減速する。
func _steer(delta: float) -> void:
	if _target_dir.is_zero_approx():
		_flee_time = 0.0
		return
	_flee_time += delta
	if _move_dir.is_zero_approx():
		_move_dir = _target_dir
		return
	var angle := _move_dir.signed_angle_to(_target_dir, Vector3.UP)
	var max_step := deg_to_rad(Config.balance.flee_turn_rate) * delta
	_move_dir = _move_dir.rotated(Vector3.UP, clampf(angle, -max_step, max_step)).normalized()


func _current_speed() -> float:
	var b := Config.balance
	var target := 0.0
	if not _target_dir.is_zero_approx():
		target = b.flee_speed * _urgency / (1.0 + maxf(b.flee_speed_size_penalty, 0.0) * size)
		if b.flee_stamina > 0.0 and _flee_time >= b.flee_stamina:
			target *= b.flee_tired_speed_ratio
	var current := velocity.length()
	var step := maxf(b.flee_accel, 0.0) * get_physics_process_delta_time()
	return move_toward(current, target, step)


## 逃げている間は小さく跳ねて「怯え」を見せる。
func _update_hop(delta: float) -> void:
	var moving := velocity.length() > 0.2
	_hop_t = _hop_t + delta if moving else 0.0
	_mesh_instance.position.y = _radius() + absf(sin(_hop_t * HOP_FREQUENCY)) * HOP_HEIGHT * _urgency


## F2 デバッグ表示: 回収範囲(黄)・逃走検知半径(薄赤)・全速になる距離(赤)・逃げたい方向(赤線)・進む方向(緑線)。
func debug_draw(overlay: DebugOverlay) -> void:
	var b := Config.balance
	var base := Vector3(global_position.x, 0.05, global_position.z)
	overlay.circle(base, _shape.radius, Color(1.0, 0.85, 0.2))
	if not b.flee_enabled:
		return
	var edge := _radius()
	overlay.circle(base, edge + b.flee_detect_radius, Color(1.0, 0.4, 0.4, 0.5), 40)
	overlay.circle(base, edge + b.flee_panic_distance, Color(1.0, 0.2, 0.2), 32)
	if not _threat_dir.is_zero_approx():
		overlay.line(base, base + _threat_dir.normalized() * 2.0, Color(1.0, 0.2, 0.2))
	if not _move_dir.is_zero_approx():
		overlay.line(base, base + _move_dir * (1.0 + velocity.length() * 0.3), Color(0.2, 1.0, 0.3))


## --- 見た目・判定 ---

func _radius() -> float:
	return Config.balance.radius_for_size(size, Config.balance.pickup_size_to_scale)


func _build_visual() -> void:
	var r := _radius()
	_body_shape = SphereShape3D.new()
	_body_shape.radius = r
	var body_col := CollisionShape3D.new()
	body_col.shape = _body_shape
	body_col.position.y = r + FLOOR_CLEARANCE
	add_child(body_col)

	_collect_area = Area3D.new()
	_collect_area.name = "CollectArea"
	_collect_area.collision_layer = 0
	_collect_area.collision_mask = Player.HUMAN_LAYER
	_collect_area.position.y = r
	add_child(_collect_area)
	_shape = SphereShape3D.new()
	_shape.radius = r + Config.balance.pickup_collect_radius
	var col := CollisionShape3D.new()
	col.shape = _shape
	_collect_area.add_child(col)
	_collect_area.body_entered.connect(_on_body_entered)

	_mesh = SphereMesh.new()
	_mesh.radius = r
	_mesh.height = r * 2.0
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _mesh
	_mesh_instance.position.y = r
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.24, 0.14)
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
