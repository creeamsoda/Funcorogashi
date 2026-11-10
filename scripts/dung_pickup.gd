class_name DungPickup
extends CharacterBody3D
## 地面に落ちたフン。プレイヤー(のフン球)が触れると取り込まれてサイズ増加。
## owner_id 本人のドロップは collectible_at(スタン明けまで)回収不可。
## プレイヤーが近づくと驚いて逃げる(Dung Flee):
##   IDLE(止まっている) ─⓪以内にプレイヤー→ SURPRISED(その場で①秒、震えながらジャンプ)
##   → 驚き終わった瞬間の一番近いプレイヤーから離れる向きへ RUNNING(速度②)
##   → ③以内にプレイヤー(全員)か前方③以内に壁 → また SURPRISED
##     壁に驚いた時は専用の驚き時間の後、離れる向きから左右へ広げて「前方③以内に壁がない」一番近い向きへ逃げる
##     (全方向ふさがりなら驚き続ける)
##   → 驚かずに④秒進んだら BRAKING(減速度⑤)→ 止まったら IDLE
## 壁・フェンスとだけ衝突し、プレイヤーやフン同士とはすり抜ける。
## 見た目は細長い三角形で、頂点側が進行方向。判定(壁・回収・距離)は向きに依らない円のまま。
## ノード原点は地面(y=0)。判定は半径ぶん上に置く。

signal collected(size: float)

## 物理レイヤー(Player の WALL/HUMAN/NPC と重ならないビット)。
const DUNG_LAYER := 8
## 床に触れて引っかからないよう、判定球を少し浮かせる。
const FLOOR_CLEARANCE := 0.05
## 驚きモーション: 驚きの時間いっぱいで1回跳ねる高さ(半径に対する倍率+固定分)と、震えの幅・速さ。
const SURPRISE_JUMP_HEIGHT := 0.45
const SHAKE_AMPLITUDE := 0.08
const SHAKE_FREQUENCY := 40.0
## 三角形の見た目(半径に対する倍率)。
const SHAPE_LENGTH := 2.4
const SHAPE_WIDTH := 1.4
const SHAPE_THICK := 0.9

enum FleeState { IDLE, SURPRISED, RUNNING, BRAKING }
const STATE_COLORS := [Color.WHITE, Color(1.0, 0.9, 0.2), Color(0.2, 1.0, 0.3), Color(0.2, 0.9, 1.0)]

var size: float = 0.5
var owner_id: int = -1
var collectible_at: float = 0.0  ## この秒(get_ticks/1000)以降 owner 本人も回収可

var _mesh_instance: MeshInstance3D
var _shape: SphereShape3D        ## 回収判定(半径+回収余裕)
var _body_shape: SphereShape3D   ## 壁との衝突判定
var _collect_area: Area3D
var _spawned_at: float
var _collected := false
var _placed := false  ## 生成位置のフェンス押し出しを済ませたか(生成側は add_child 後に位置を設定するため初回物理フレームで行う)

## 逃走状態
var _state := FleeState.IDLE
var _state_t := 0.0              ## 今の状態になってからの秒数
var _heading := Vector3.BACK     ## 向き(前方向)。_ready で無作為に回す
var _speed := 0.0                ## 前進速度(m/s)
var _wall_surprise := false      ## 今の驚きが壁によるものか(驚き時間と、驚き後の向きの決め方が変わる)
var _wall_normal := Vector3.ZERO ## 驚いた壁の面の向き(壁から外向き)。驚き後はこの壁へ近づく向きを選ばない
var _shake_seed := 0.0


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
	_heading = Vector3.BACK.rotated(Vector3.UP, randf() * TAU)
	_shake_seed = randf() * 100.0
	_build_visual()
	_update_visual()
	add_to_group(DebugOverlay.GROUP)


func _process(_dt: float) -> void:
	if Config.balance.pickup_despawn_enabled and _now() - _spawned_at >= Config.balance.pickup_despawn_time:
		queue_free()


func _physics_process(delta: float) -> void:
	if not _placed:
		_placed = true
		_push_out_of_fences()
	if _collected or not Config.balance.flee_enabled:
		return
	_update_flee(delta)
	velocity = _heading * _speed
	if _speed > 0.0:
		move_and_slide()
		# 壁に押し付けられた分は前進速度から失う(壁沿いに滑る分だけ残る)
		_speed = clampf(get_real_velocity().dot(_heading), 0.0, _speed)
	global_position.y = 0.0
	_update_visual()


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


## 動物やドロップがフェンスに重なる位置へ落ちた場合、フェンスの外へ出す。
func _push_out_of_fences() -> void:
	var stage := get_tree().get_first_node_in_group("stage") as Stage
	if stage != null and stage.fence_count() > 0:
		global_position = stage.push_out_of_fences(global_position, _radius() + 0.1)


## --- 逃走 ---

func _update_flee(delta: float) -> void:
	var b := Config.balance
	_state_t += delta
	match _state:
		FleeState.IDLE:
			_speed = 0.0
			if _nearest_threat_distance() <= b.flee_idle_alert_radius:
				_surprise(false)
		FleeState.SURPRISED:
			_speed = 0.0
			if _state_t >= _surprise_duration():
				_start_running()
		FleeState.RUNNING, FleeState.BRAKING:
			if _nearest_threat_distance() <= b.flee_moving_alert_radius:
				_surprise(false)
				return
			var hit := _wall_ahead(_heading)
			if not hit.is_empty():
				var n: Vector3 = hit["normal"]
				n.y = 0.0
				_wall_normal = n.normalized() if n.length() > 0.001 else -_heading
				_surprise(true)
				return
			if _state == FleeState.RUNNING and _state_t >= b.flee_run_time:
				_enter_state(FleeState.BRAKING)
			if _state == FleeState.BRAKING:
				_speed = move_toward(_speed, 0.0, maxf(b.flee_stop_decel, 0.0) * delta)
				if _speed <= 0.0:
					_enter_state(FleeState.IDLE)


func _enter_state(next: FleeState) -> void:
	_state = next
	_state_t = 0.0


## その場で止まって驚く。by_wall なら壁に驚いた扱い(専用の驚き時間、終わったら壁を避ける)。
func _surprise(by_wall: bool) -> void:
	_wall_surprise = by_wall
	_speed = 0.0
	_enter_state(FleeState.SURPRISED)


func _surprise_duration() -> float:
	return Config.balance.flee_wall_surprise_time if _wall_surprise else Config.balance.flee_surprise_time


## 驚き終わった瞬間の一番近いプレイヤーから離れる向きへ、速度②で進み出す。
## プレイヤーに驚いた時は壁を避けない(壁に向かえば前方の壁でまた驚く)。
## 壁に驚いた時は、離れる向きから左右へ広げて前方③以内に壁がない一番近い向きを選ぶ。全方向ふさがりなら驚き続ける。
func _start_running() -> void:
	var away := _heading
	var nearest := _nearest_threat()
	if nearest != null:
		var d := global_position - nearest.global_position
		d.y = 0.0
		if d.length() > 0.001:
			away = d.normalized()
	if _wall_surprise:
		var free := _find_free_direction(away)
		if free.is_zero_approx():
			_surprise(true) # 逃げ道なし: その場で驚き続ける(追い詰められた状態)
			return
		away = free
	_heading = away
	_wall_surprise = false
	_speed = Config.balance.flee_speed / (1.0 + maxf(Config.balance.flee_speed_size_penalty, 0.0) * size)
	_enter_state(FleeState.RUNNING)


## base から左右交互に flee_wall_search_step 度ずつ広げ、最初に見つかった逃げられる向き。なければ ZERO。
## 逃げられる向き = 前方③以内に壁がなく、驚いた壁へ近づかない(壁と平行か離れる)向き。
## 驚いた壁へ斜めに近づく向きを許すと、少し進むだけでまた③以内になり、驚きを繰り返しながら壁際を這ってしまう。
func _find_free_direction(base: Vector3) -> Vector3:
	var step := clampf(Config.balance.flee_wall_search_step, 1.0, 90.0)
	var angle := 0.0
	while angle <= 180.0:
		for side in ([1.0] if angle == 0.0 else [1.0, -1.0]):
			var cand := base.rotated(Vector3.UP, deg_to_rad(angle * side))
			if cand.dot(_wall_normal) >= -0.01 and not _blocked_ahead(cand):
				return cand
		angle += step
	return Vector3.ZERO


## 向き dir の前方③以内に壁(フェンス含む)があるか。
func _blocked_ahead(dir: Vector3) -> bool:
	return not _wall_ahead(dir).is_empty()


## 向き dir の前方③以内の壁との交点(intersect_ray の結果)。なければ空。
func _wall_ahead(dir: Vector3) -> Dictionary:
	var reach := _radius() + Config.balance.flee_moving_alert_radius
	var origin := global_position + Vector3(0, _radius() + FLOOR_CLEARANCE, 0)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach, Player.WALL_LAYER, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


## 驚く対象のプレイヤー(人間・スタン中でない)。
func _threats() -> Array[Player]:
	var out: Array[Player] = []
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as Player
		if p != null and p.gameplay_active and p.state != Player.State.STUNNED:
			out.append(p)
	return out


## プレイヤーの球の縁からフンの縁までの距離。
func _edge_distance(p: Player) -> float:
	var d := global_position - p.global_position
	d.y = 0.0
	return maxf(d.length() - p.body_radius() - _radius(), 0.0)


func _nearest_threat() -> Player:
	var best: Player = null
	var best_d := INF
	for p in _threats():
		var d := _edge_distance(p)
		if d < best_d:
			best_d = d
			best = p
	return best


func _nearest_threat_distance() -> float:
	var p := _nearest_threat()
	return _edge_distance(p) if p != null else INF


## 向きに合わせて三角形を回す。驚き中は震えながら1回跳ねる。
func _update_visual() -> void:
	_mesh_instance.rotation.y = atan2(_heading.x, _heading.z)
	if _state != FleeState.SURPRISED:
		_mesh_instance.position = Vector3.ZERO
		return
	var t := clampf(_state_t / maxf(_surprise_duration(), 0.01), 0.0, 1.0)
	var jump := sin(t * PI) * (SURPRISE_JUMP_HEIGHT + _radius() * 0.3)
	var phase := (_state_t + _shake_seed) * SHAKE_FREQUENCY
	_mesh_instance.position = Vector3(sin(phase) * SHAKE_AMPLITUDE, jump, cos(phase * 1.3) * SHAKE_AMPLITUDE)


## F2 デバッグ表示: 回収範囲(黄)・止まっている時の驚き範囲⓪(赤)・進行中の驚き範囲③(赤、前方は線)・
## 向き(状態の色: 白=停止 黄=驚き中 緑=逃走中 水色=減速中)。
func debug_draw(overlay: DebugOverlay) -> void:
	var b := Config.balance
	var base := Vector3(global_position.x, 0.05, global_position.z)
	overlay.circle(base, _shape.radius, Color(1.0, 0.85, 0.2))
	if not b.flee_enabled:
		return
	var edge := _radius()
	if _state == FleeState.IDLE:
		overlay.circle(base, edge + b.flee_idle_alert_radius, Color(1.0, 0.3, 0.3), 40)
	elif _state != FleeState.SURPRISED:
		overlay.circle(base, edge + b.flee_moving_alert_radius, Color(1.0, 0.3, 0.3), 32)
		overlay.line(base, base + _heading * (edge + b.flee_moving_alert_radius), Color(1.0, 0.3, 0.3))
	overlay.line(base, base + _heading * (edge + 1.0), STATE_COLORS[_state])


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

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Body"
	_mesh_instance.mesh = _build_triangle_mesh(r)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.24, 0.14)
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


## 上から見て細長い二等辺三角形の柱。頂点が +Z(前)。重心付近を原点にして回転が自然に見えるようにする。
func _build_triangle_mesh(r: float) -> ArrayMesh:
	var half_len := r * SHAPE_LENGTH * 0.5
	var half_w := r * SHAPE_WIDTH * 0.5
	var up := Vector3(0, r * SHAPE_THICK, 0)
	var tip := Vector3(0, 0, half_len * 1.2)
	var left := Vector3(-half_w, 0, -half_len * 0.8)
	var right := Vector3(half_w, 0, -half_len * 0.8)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Godot の表面は外から見て時計回り
	var faces := [
		[tip + up, left + up, right + up],                         # 上面
		[tip, right, left],                                        # 底面
		[tip, left + up, tip + up], [tip, left, left + up],        # 左側面
		[right, tip + up, right + up], [right, tip, tip + up],     # 右側面
		[left, right + up, left + up], [left, right, right + up],  # 後面
	]
	for face in faces:
		for v in face:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
