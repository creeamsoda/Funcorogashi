class_name DungPickup
extends CharacterBody3D
## 地面に落ちたフン。プレイヤー(のフン球)が触れると取り込まれてサイズ増加。
## owner_id 本人のドロップは collectible_at(スタン明けまで)回収不可。
## プレイヤーが近づくと驚いて逃げる(Dung Flee):
##   IDLE(止まっている) ─⓪以内にプレイヤー→ SURPRISED(その場で①秒、震えながらジャンプ。その時点の逃げる向きを向き続ける)
##   → 驚き終わった瞬間の一番近いプレイヤーから離れる向きへ RUNNING(速度②)
##   → ③以内にプレイヤー(全員)か前方③以内に壁 → また SURPRISED
##     壁に驚いた時は専用の驚き時間の後、flee_wall_escape_radius 以内にプレイヤーがいれば、離れる向きから左右へ広げて
##     「前方③以内に壁がない」一番近い向きへ逃げる(全方向ふさがりなら驚き続ける)。いなければ壁の前で止まる(IDLE)
##   → 驚かずに④秒進んだら BRAKING(減速度⑤)→ 止まったら IDLE
## 壁・フェンスとだけ衝突し、プレイヤーやフン同士とはすり抜ける。
## 見た目は細長い三角形で、頂点側が進行方向。判定(壁・回収・距離)は向きに依らない円のまま。
## flee_static_max_size 以下の小さいフンは逃げず(動かない)、見た目も球(仮。後で差し替え予定)。
## ノード原点は地面(y=0)。判定は半径ぶん上に置く。
## 特殊フン(kind が NORMAL 以外): 色で見分ける。サイズに関係なく必ず逃げ、速度・驚き時間は専用の値。
##   逃げる向きは「範囲内の全プレイヤーから離れる」と「先が開けている(壁から遠い)」を合わせて評価した一番よい向き。
##   回収したプレイヤーに効果(ブラックホール/高速)を与える。
## ブラックホール効果中のプレイヤーの範囲内にいる通常フンは、逃げずにそのプレイヤーへ引き寄せられる(特殊フンは寄らない)。

signal collected(size: float)

## 物理レイヤー(Player の WALL/HUMAN/NPC と重ならないビット)。
const DUNG_LAYER := 8
## 床に触れて引っかからないよう、判定球を少し浮かせる。
const FLOOR_CLEARANCE := 0.05
## 前方の崖(下りられない段差)を探す間隔(m)。
const CLIFF_PROBE_STEP := 0.25
## 驚きモーション: 驚きの時間いっぱいで1回跳ねる高さ(半径に対する倍率+固定分)と、震えの幅・速さ。
const SURPRISE_JUMP_HEIGHT := 0.45
const SHAKE_AMPLITUDE := 0.08
const SHAKE_FREQUENCY := 40.0
## 三角形の見た目(半径に対する倍率)。
const SHAPE_LENGTH := 2.4
const SHAPE_WIDTH := 1.4
const SHAPE_THICK := 0.9

enum FleeState { IDLE, SURPRISED, RUNNING, BRAKING }
enum Kind { NORMAL, BLACKHOLE, SPEED }
const SPECIAL_GROUP := "special_dung"
const KIND_COLORS := [Color(0.38, 0.24, 0.14), Color(0.05, 0.08, 0.32), Color(0.45, 0.85, 1.0)]
const STATE_COLORS := [Color.WHITE, Color(1.0, 0.9, 0.2), Color(0.2, 1.0, 0.3), Color(0.2, 0.9, 1.0)]

var size: float = 0.5
var owner_id: int = -1
var kind: Kind = Kind.NORMAL     ## add_child 前に設定する
var collectible_at: float = 0.0  ## この秒(get_ticks/1000)以降 owner 本人も回収可

var _mesh_instance: MeshInstance3D
var _static_visual := false      ## 今の見た目が動かないフン用の球か
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


## オランウータンのフン用: 設定の確率で特殊フンの種類を選ぶ(どれにも当たらなければ NORMAL)。
## 盤面上の特殊フンが上限 special_max_on_board 個に達していれば NORMAL。context はツリー参照用の任意のノード。
static func roll_kind(context: Node) -> Kind:
	var b := Config.balance
	if count_special_on_board(context.get_tree()) >= b.special_max_on_board:
		return Kind.NORMAL
	var r := randf()
	if r < b.special_blackhole_chance:
		return Kind.BLACKHOLE
	if r < b.special_blackhole_chance + b.special_speed_chance:
		return Kind.SPEED
	return Kind.NORMAL


## 盤面上の(回収済みで消える途中を除く)特殊フンの数。
static func count_special_on_board(tree: SceneTree) -> int:
	var n := 0
	for node in tree.get_nodes_in_group(SPECIAL_GROUP):
		if not node.is_queued_for_deletion() and not (node as DungPickup)._collected:
			n += 1
	return n


func is_special() -> bool:
	return kind != Kind.NORMAL


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
	if is_special():
		add_to_group(SPECIAL_GROUP)


func _process(_dt: float) -> void:
	if Config.balance.pickup_despawn_enabled and _now() - _spawned_at >= Config.balance.pickup_despawn_time:
		queue_free()


func _physics_process(delta: float) -> void:
	if not _placed:
		_placed = true
		_push_out_of_fences()
	_sync_static_visual()
	if _collected:
		return
	var puller := _blackhole_puller()
	if puller != null:
		_move_pulled(puller)
		_update_visual()
		return
	if not Config.balance.flee_enabled or is_static():
		return
	_update_flee(delta)
	velocity = _heading * _speed
	if _speed > 0.0:
		var before := global_position
		move_and_slide()
		# 壁に押し付けられた分は前進速度から失う(壁沿いに滑る分だけ残る)
		_speed = clampf(get_real_velocity().dot(_heading), 0.0, _speed)
		if Stage.has_elevation():
			_follow_ground(before)
	if not Stage.has_elevation():
		global_position.y = 0.0
	_update_visual()


func _on_body_entered(body: Node) -> void:
	if _collected or is_queued_for_deletion() or not (body is Player):
		return
	var p := body as Player
	if not p.gameplay_active or not p.can_collect or p.is_queued_for_deletion():
		return
	if _locked_for(p):
		return # 自分のドロップはスタン明けまで回収不可
	# 動物由来(ownerなし)は実量に獲得倍率を掛ける。プレイヤーが落としたフンは実量を保持する。
	var gain: float = size * Config.balance.size_gain_per_pickup if owner_id < 0 else size
	_collected = true # 同一フレームの複数body_enteredでも1回だけ加算する。
	p.add_size(gain)
	p.play_pickup_se(gain)
	if is_special():
		p.apply_special_dung(kind)
	collected.emit(gain)
	queue_free()


## 動物やドロップがフェンスに重なる位置・円形外壁の外へ落ちた場合、内側へ出す。
## 高低差のあるステージでは真上から見た地面(台の上・スロープ)に置く。
func _push_out_of_fences() -> void:
	var stage := get_tree().get_first_node_in_group("stage") as Stage
	if stage != null and stage.needs_push_out():
		global_position = stage.push_out_of_fences(global_position, _radius() + 0.1)
	if Stage.has_elevation():
		global_position = Stage.settle_on_ground(global_position)


## 移動後の地面に合わせて高さを変える。足元が段差(step_height)を超えて低い・急斜面なら移動を取り消して壁扱いで驚く
## (自分から段差を飛び降りない。スロープのようになだらかな下りや小さい段差は下りられる)。
func _follow_ground(before: Vector3) -> void:
	if _settle_after_move(before):
		return
	_speed = 0.0
	if _state == FleeState.RUNNING or _state == FleeState.BRAKING:
		_wall_normal = -_heading
		_surprise(true)


## 移動後の地面の高さに合わせる。下りられない段差・急斜面なら移動前の位置に戻して false。
func _settle_after_move(before: Vector3) -> bool:
	var y := _ground_height_at(global_position, before.y)
	if is_nan(y):
		global_position = before
		return false
	global_position.y = y
	return true


## 基準の高さ ref_y から段差の範囲(上下 step_height)で見つかる床の高さ。なければ NAN。
func _ground_height_at(pos: Vector3, ref_y: float) -> float:
	var step: float = Config.balance.step_height
	var g := Stage.probe_ground(pos, ref_y + _radius() + step, _radius() + step * 2.0 + 0.05)
	if g.is_empty() or (g["normal"] as Vector3).y < Stage.FLOOR_MIN_NORMAL_Y:
		return NAN
	return g["y"]


## 小さすぎて逃げない(動かない)フンか。
## 特殊フンは小さくても逃げる。
func is_static() -> bool:
	return not is_special() and size <= Config.balance.flee_static_max_size


## --- ブラックホール ---

## 自分を引き寄せるブラックホール効果中のプレイヤー(範囲内で一番近い)。いなければ null。
## 本人が回収できない間の自分のドロップは引き寄せない(くっついたまま取れなくなるため)。特殊フンも引き寄せない。
func _blackhole_puller() -> Player:
	if is_special():
		return null
	var best: Player = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as Player
		if p == null or not p.gameplay_active or not p.is_blackhole_active():
			continue
		if _locked_for(p):
			continue
		var d := _edge_distance(p)
		if d <= Config.balance.blackhole_radius and d < best_d:
			best_d = d
			best = p
	return best


## 引き寄せ速度③でプレイヤーへ進む(壁・フェンスには当たる)。向きはプレイヤーから逃げようとする向きのまま。
func _move_pulled(p: Player) -> void:
	var to := p.global_position - global_position
	to.y = 0.0
	if to.length() < 0.001:
		return
	to = to.normalized()
	_heading = -to
	_speed = 0.0
	_wall_surprise = false
	_enter_state(FleeState.IDLE)
	velocity = to * Config.balance.blackhole_pull_speed
	var before := global_position
	move_and_slide()
	if Stage.has_elevation():
		_settle_after_move(before) # 段差は下りない
	else:
		global_position.y = 0.0


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
			else:
				_face_escape_direction()
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
	var b := Config.balance
	if is_special():
		return b.special_flee_wall_surprise_time if _wall_surprise else b.special_flee_surprise_time
	return b.flee_wall_surprise_time if _wall_surprise else b.flee_surprise_time


## 今この瞬間に逃げるとしたらの向き。一番近いプレイヤーから離れる向き(いなければ今の向き)。
## プレイヤーに驚いた時は壁を避けない(壁に向かえば前方の壁でまた驚く)。
## 壁に驚いた時は、離れる向きから左右へ広げて前方③以内に壁がない一番近い向き。全方向ふさがりなら ZERO。
func _escape_direction() -> Vector3:
	if is_special():
		return _smart_escape_direction()
	var away := _heading
	var nearest := _nearest_threat()
	if nearest != null:
		var d := global_position - nearest.global_position
		d.y = 0.0
		if d.length() > 0.001:
			away = d.normalized()
	return _find_free_direction(away) if _wall_surprise else away


## 驚き中は、その時点の逃げる向きへ向き続ける(プレイヤーが回り込めば向きも追う)。
## 壁の驚きで近くにプレイヤーがいない間は、今の向き(壁の方)のまま。
func _face_escape_direction() -> void:
	if _wall_surprise and not _player_near_wall_escape():
		return
	var dir := _escape_direction()
	if not dir.is_zero_approx():
		_heading = dir


## 壁に驚き終わった時に逃げるか: flee_wall_escape_radius 以内にプレイヤー(スタン中を除く)がいるか。
func _player_near_wall_escape() -> bool:
	return _nearest_threat_distance() <= Config.balance.flee_wall_escape_radius


## 驚き終わった瞬間の逃げる向きへ、速度②で進み出す。逃げ道がなければ驚き続ける(追い詰められた状態)。
## 壁の驚きで近くにプレイヤーがいなければ、逃げずに壁の前で止まる。
func _start_running() -> void:
	if _wall_surprise and not _player_near_wall_escape():
		_wall_surprise = false
		_enter_state(FleeState.IDLE)
		return
	var dir := _escape_direction()
	if dir.is_zero_approx():
		_surprise(true)
		return
	_heading = dir
	_wall_surprise = false
	var base_speed: float = Config.balance.special_flee_speed if is_special() else Config.balance.flee_speed
	_speed = base_speed / (1.0 + maxf(Config.balance.flee_speed_size_penalty, 0.0) * size)
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


## 特殊フンの逃げる向き。全周を flee_wall_search_step 度刻みで調べ、前方③以内に壁がない向きのうち一番よい向き。
## 評価: その向きへ壁の手前(最大 special_flee_wall_lookahead)まで進んだとした時、範囲内の全プレイヤーとの距離
## (途中でプレイヤーへ近づく向きなら最接近距離)の最小値 + 平均の少し + 開けた距離 × special_flee_wall_weight。
## → 挟まれたら横へ、壁際で追われたら壁沿いへ、角へは逃げ込まない。
## 壁に驚いた時は、驚いた壁へ近づく向きは選ばない。全方向ふさがりなら ZERO。
func _smart_escape_direction() -> Vector3:
	var b := Config.balance
	var threat_r := maxf(b.special_flee_threat_radius, 0.01)
	var origin := Vector3(global_position.x, 0.0, global_position.z)
	var threats: Array[Vector3] = []
	for p in _threats():
		if _edge_distance(p) <= threat_r:
			threats.append(Vector3(p.global_position.x, 0.0, p.global_position.z))
	var lookahead := maxf(b.special_flee_wall_lookahead, 0.01)
	var margin := _radius() + maxf(b.flee_moving_alert_radius, 0.0)
	var step := clampf(b.flee_wall_search_step, 1.0, 90.0)
	var count := maxi(int(round(360.0 / step)), 4)
	var best := Vector3.ZERO
	var best_score := -INF
	for i in count:
		var cand := Vector3.BACK.rotated(Vector3.UP, TAU * i / count)
		if _wall_surprise and cand.dot(_wall_normal) < -0.01:
			continue
		if _blocked_ahead(cand):
			continue
		var open := _open_distance(cand, lookahead + margin)
		var run := clampf(open - margin, 0.0, lookahead)
		var score := b.special_flee_wall_weight * run + 0.02 * cand.dot(_heading) # 同点なら今の向き(ぶれ防止)
		if not threats.is_empty():
			var nearest := INF
			var total := 0.0
			for t in threats:
				# 進む区間上でそのプレイヤーに一番近づく点(離れる向きなら出発点ではなく到達点で測る)
				var along := clampf((t - origin).dot(cand), 0.0, run)
				var d := t.distance_to(origin + cand * (along if along > 0.0 else run))
				nearest = minf(nearest, d)
				total += d
			score += nearest + 0.1 * total / threats.size()
		if score > best_score:
			best_score = score
			best = cand
	return best


## 向き dir へ壁(フェンス含む)まで何 m 開けているか(最大 reach)。
func _open_distance(dir: Vector3, reach: float) -> float:
	var hit := _wall_ray(dir, reach)
	if hit.is_empty():
		return reach
	return _ray_origin().distance_to(hit["position"])


## 向き dir の前方③以内に壁(フェンス含む)があるか。
func _blocked_ahead(dir: Vector3) -> bool:
	return not _wall_ahead(dir).is_empty()


## 向き dir の前方③以内の壁との交点(intersect_ray の結果)。なければ空。
## 高低差のあるステージでは、下りられない段差(崖)も壁とみなす(normal は崖から手前向き)。
func _wall_ahead(dir: Vector3) -> Dictionary:
	var reach := _radius() + Config.balance.flee_moving_alert_radius
	var hit := _wall_ray(dir, reach)
	if not hit.is_empty() or not Stage.has_elevation():
		return hit
	return _cliff_ahead(dir, reach)


## 判定球の中心の高さから向き dir へ reach だけ、壁(フェンス含む)へのレイを飛ばす。
func _wall_ray(dir: Vector3, reach: float) -> Dictionary:
	var origin := _ray_origin()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach, Player.WALL_LAYER, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


func _ray_origin() -> Vector3:
	return global_position + Vector3(0, _radius() + FLOOR_CLEARANCE, 0)


## 向き dir の前方 reach 以内で、足元から段差を超えて下がる(または急斜面になる)最初の地点。なければ空。
func _cliff_ahead(dir: Vector3, reach: float) -> Dictionary:
	var y := global_position.y
	var dist := 0.0
	while dist < reach:
		dist = minf(dist + CLIFF_PROBE_STEP, reach)
		var p := global_position + dir * dist
		var gy := _ground_height_at(p, y)
		if is_nan(gy):
			return {"position": Vector3(p.x, y, p.z), "normal": -dir}
		y = gy
	return {}


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
	if _static_visual:
		_mesh_instance.rotation.y = 0.0
		_mesh_instance.position = Vector3(0, _radius(), 0)
		return
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
	if not b.flee_enabled or is_static():
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
	_static_visual = is_static()
	_mesh_instance.mesh = _build_mesh(r)
	var mat := ToonMaterial.create(KIND_COLORS[kind])
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


## 動かないフンは球(原点を底にするため _update_visual で半径ぶん持ち上げる)、逃げるフンは三角形。
func _build_mesh(r: float) -> Mesh:
	if not _static_visual:
		return _build_triangle_mesh(r)
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	return sphere


## 調整パネルでしきい値が変わった時に、見た目を球/三角形で切り替える。
func _sync_static_visual() -> void:
	if _static_visual == is_static():
		return
	_static_visual = is_static()
	_mesh_instance.mesh = _build_mesh(_radius())
	_state = FleeState.IDLE
	_state_t = 0.0
	_speed = 0.0
	_update_visual()


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


## 本人のドロップで、まだ回収できない(スタン明け前)か。
func _locked_for(p: Player) -> bool:
	return owner_id == p.player_id and _now() < collectible_at


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
