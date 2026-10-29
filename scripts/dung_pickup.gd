class_name DungPickup
extends CharacterBody3D
## 地面に落ちたフン。プレイヤー(のフン球)が触れると取り込まれてサイズ増加。
## owner_id 本人のドロップは collectible_at(スタン明けまで)回収不可。
## 近づくプレイヤーから逃げる(Dung Flee)。壁・フェンスとだけ衝突し、プレイヤーやフン同士とはすり抜ける。
## 向き(_heading)を持ち、常に前へ進む。速いほど曲がりにくく、急に曲がる時は減速して回ってから再加速する。
## 見た目は細長い三角形で、頂点側が進行方向。判定(壁・回収・距離)は向きに依らない円のまま。
## ノード原点は地面(y=0)。判定は半径ぶん上に置く。

signal collected(size: float)

## 物理レイヤー(Player の WALL/HUMAN/NPC と重ならないビット)。
const DUNG_LAYER := 8
## 床に触れて引っかからないよう、判定球を少し浮かせる。
const FLOOR_CLEARANCE := 0.05
## 逃げ中の跳ねる見た目(怯え)。
const HOP_HEIGHT := 0.18
const HOP_FREQUENCY := 9.0
## 三角形の見た目(半径に対する倍率)。
const SHAPE_LENGTH := 2.4
const SHAPE_WIDTH := 1.4
const SHAPE_THICK := 0.9
## この速さ未満を「止まっている」とみなす(止まっている時は回ってから進み出す)。
const STOPPED_SPEED := 0.3

## 曲がり方。HOLD = 中くらいの角度だが最後の回転から間もないので直進、MID_TURN = 待った後に曲がっている。
enum TurnMode { CRUISE, SMALL_TURN, HOLD, MID_TURN, SHARP_TURN }
const MODE_COLORS := [Color.WHITE, Color(0.2, 1.0, 0.3), Color(1.0, 0.9, 0.2), Color(0.2, 0.9, 1.0), Color(1.0, 0.3, 1.0)]

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
var _threat_dir := Vector3.ZERO  ## 脅威から離れたい方向(重み付き合計)
var _target_dir := Vector3.ZERO  ## 障害物回避後に選んだ、進みたい方向
var _heading := Vector3.BACK     ## 向き(前方向)。_ready で無作為に回す
var _speed := 0.0                ## 前進速度(m/s)
var _mode := TurnMode.CRUISE
var _since_turn := INF           ## 最後の回転(急旋回・中角度の旋回の完了)からの秒数
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
	_heading = Vector3.BACK.rotated(Vector3.UP, randf() * TAU)
	_build_visual()
	_update_visual(0.0)
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
	_rethink_t -= delta
	if _rethink_t <= 0.0:
		_rethink_t = maxf(Config.balance.flee_reaction_time, 0.0)
		_think()
	_update_motion(delta)
	velocity = _heading * _speed
	if _speed > 0.0:
		move_and_slide()
		# 壁に押し付けられた分は前進速度から失う(壁沿いに滑る分だけ残る)
		_speed = clampf(get_real_velocity().dot(_heading), 0.0, _speed)
	global_position.y = 0.0
	_update_visual(delta)


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

## 検知半径内のプレイヤーから離れる方向と緊迫度を求め、障害物を避けて進みたい方向を選ぶ。
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


## 進みたい方向とのなす角で曲がり方を決め、向きと前進速度を更新する。
##   小さい角度 : 減速最小限で曲がる(SMALL_TURN)
##   中くらい   : 最後の回転から flee_turn_hold_time 経つまで直進(HOLD)、経ったら曲がる(MID_TURN)
##   大きい角度 : 減速しながら回り、向きが合ったら再加速(SHARP_TURN)。止まっている時も回ってから進む
func _update_motion(delta: float) -> void:
	var b := Config.balance
	_since_turn += delta
	if _target_dir.is_zero_approx():
		_mode = TurnMode.CRUISE
		_flee_time = 0.0
		_speed = move_toward(_speed, 0.0, maxf(b.flee_accel, 0.0) * delta)
		return
	_flee_time += delta
	var angle := rad_to_deg(_heading.angle_to(_target_dir))
	var small := clampf(b.flee_small_turn_angle, 0.0, 180.0)
	var sharp := clampf(b.flee_sharp_turn_angle, small, 180.0)
	if _mode == TurnMode.SHARP_TURN or _mode == TurnMode.MID_TURN:
		# 向きが合うまで続ける(閾値付近で状態が行ったり来たりしないように)
		if angle < small:
			_mode = TurnMode.CRUISE
			_since_turn = 0.0
	elif angle >= sharp or (angle >= small and _speed < STOPPED_SPEED):
		_mode = TurnMode.SHARP_TURN
	elif angle >= small:
		_mode = TurnMode.HOLD if _since_turn < b.flee_turn_hold_time else TurnMode.MID_TURN
	elif angle > 1.0:
		_mode = TurnMode.SMALL_TURN
	else:
		_mode = TurnMode.CRUISE
	var target_speed := _target_speed()
	match _mode:
		TurnMode.SHARP_TURN:
			_rotate_toward(_target_dir, delta)
			target_speed = minf(target_speed, maxf(b.flee_sharp_turn_min_speed, 0.0))
		TurnMode.SMALL_TURN, TurnMode.MID_TURN:
			_rotate_toward(_target_dir, delta)
			target_speed *= clampf(b.flee_small_turn_speed_ratio, 0.0, 1.0)
	var rate := b.flee_accel if target_speed > _speed else b.flee_brake_decel
	_speed = move_toward(_speed, target_speed, maxf(rate, 0.0) * delta)


## 前進速度が速いほど遅い旋回速度で、目標の向きへ回す。
func _rotate_toward(dir: Vector3, delta: float) -> void:
	var angle := _heading.signed_angle_to(dir, Vector3.UP)
	var max_step := deg_to_rad(turn_rate()) * delta
	_heading = _heading.rotated(Vector3.UP, clampf(angle, -max_step, max_step)).normalized()


## 今の前進速度での旋回速度(度/秒)。
func turn_rate() -> float:
	var b := Config.balance
	var t := clampf(_speed / maxf(b.flee_speed, 0.01), 0.0, 1.0)
	return lerpf(b.flee_turn_rate_stopped, b.flee_turn_rate_at_speed, t)


## 近さに応じた逃げる速さ(サイズ・疲労を反映)。
func _target_speed() -> float:
	var b := Config.balance
	var target := b.flee_speed * _urgency / (1.0 + maxf(b.flee_speed_size_penalty, 0.0) * size)
	if b.flee_stamina > 0.0 and _flee_time >= b.flee_stamina:
		target *= b.flee_tired_speed_ratio
	return target


## 向きに合わせて三角形を回し、逃げている間は小さく跳ねて「怯え」を見せる。
func _update_visual(delta: float) -> void:
	_mesh_instance.rotation.y = atan2(_heading.x, _heading.z)
	_hop_t = _hop_t + delta if _speed > 0.2 else 0.0
	_mesh_instance.position.y = absf(sin(_hop_t * HOP_FREQUENCY)) * HOP_HEIGHT * _urgency


## F2 デバッグ表示: 回収範囲(黄)・逃走検知半径(薄赤)・全速になる距離(赤)・進みたい方向(赤線)・
## 今の向き(曲がり方の色: 白=直進 緑=小さく曲がる 黄=待って直進 水色=待った後に曲がる 紫=急旋回)。
func debug_draw(overlay: DebugOverlay) -> void:
	var b := Config.balance
	var base := Vector3(global_position.x, 0.05, global_position.z)
	overlay.circle(base, _shape.radius, Color(1.0, 0.85, 0.2))
	if not b.flee_enabled:
		return
	var edge := _radius()
	overlay.circle(base, edge + b.flee_detect_radius, Color(1.0, 0.4, 0.4, 0.5), 40)
	overlay.circle(base, edge + b.flee_panic_distance, Color(1.0, 0.2, 0.2), 32)
	if not _target_dir.is_zero_approx():
		overlay.line(base, base + _target_dir * 2.0, Color(1.0, 0.2, 0.2))
	overlay.line(base, base + _heading * (1.0 + _speed * 0.3), MODE_COLORS[_mode])


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
