class_name CpuBrain
extends RefCounted
## CPUの思考(ユーティリティAI)。think_interval ごとに各ゴールを点数づけして一番高いものを実行し、
## 毎フレーム「スティック(move)」と「突進ボタンを押しているか(dash)」だけを出力する。
## 位置や速度を直接いじらない(移動・溜め・突進・被弾は Player と同じルール)。
##
## ゴール(フンコロバトル_CPU実装計画 §1-2):
##   COLLECT … 近くの大きなフンを狙う。動かないフンは触れて回収。近くの動くフンは壁と反対側へ回り込んで押し込み、
##             遠くの動くフンは届く距離に合わせて溜めた突進で取りに行く。特殊フンは点数を上げ、時間がたって遠ければ諦める。
##   ATTACK  … 1位をやや優先して相手を選び、動きを先読みして届く距離に合わせて溜めて離す。
##   EVADE   … 自分へ向けて溜めている相手に気づいたら(reaction_delay 後)、迫る向きと直角へ溜めずに短い突進を打つ。
##   WANDER  … 狙うものがないとき、場の中ほどへ歩く。

enum Goal { WANDER, COLLECT, ATTACK, EVADE }
enum DashKind { NONE, ATTACK, COLLECT, EVADE }

const GOAL_NAMES := ["wander", "collect", "attack", "evade"]
const GOAL_COLORS := [Color(0.7, 0.7, 0.7), Color(0.3, 1.0, 0.4), Color(1.0, 0.3, 0.3), Color(0.3, 0.9, 1.0)]
## 今のゴールを続けるときの点数の上乗せ(ゴールが細かく切り替わり続けないように)。
const KEEP_GOAL_BONUS := 1.2
## 攻撃の点数の基準(相手が落とすフンの量に掛ける)。回収の点数と釣り合わせる係数。
const ATTACK_SCORE_SCALE := 0.8
## 回避の歩き(クールタイム中)を続ける時間(秒)。
const EVADE_WALK_TIME := 0.5
## 動くフンへ回り込むとき、フンから取る距離の余裕(m。驚く距離に足す)。
const HERD_STANDOFF_MARGIN := 1.2
## 回り込み位置に着いたとみなす距離(m)。
const HERD_ARRIVE_DISTANCE := 1.3
## 通り道の動かないフンを拾うために寄り道する距離(m)。
const DETOUR_PICKUP_DISTANCE := 2.0
## 回り道(詰まり解消)を続ける時間(秒)。
const UNSTUCK_TIME := 0.6
## 突進を壁・杭の手前で止めるための余裕(m)。突進中に狙いへ曲げる分のずれも見込む。
const DASH_WALL_MARGIN := 0.8

var body: Player
var profile: CpuProfile
var sense: CpuSense
var rng := RandomNumberGenerator.new()

## 出力(毎フレーム CpuBeetle が読む)
var move := Vector2.ZERO
var dash := false

## 今のゴールと狙い
var goal: Goal = Goal.WANDER
var target_dung: DungPickup
var target_player: Player
var target_point := Vector3.ZERO  ## デバッグ表示用の「狙いの先」

## 集計(テスト・調整用)
var counters := {"attack_dashes": 0, "collect_dashes": 0, "evade_dashes": 0, "give_ups": 0, "unstuck": 0,
	"crash_attack": 0, "crash_collect": 0, "crash_evade": 0, "crash_other": 0}

var _think_t := 0.0
var _goal_started_at := 0.0
var _last_attack_target_id := -1
var _attack_ready_at := 0.0          ## この時刻までは次の攻撃を考えない(攻撃の頻度 = aggression)
var _given_up: Dictionary = {}       ## DungPickup instance_id -> 諦めが解ける時刻
var _threat_seen: Dictionary = {}    ## 相手の player_id -> 自分を狙った溜めに気づいた時刻
var _evade_from: Player              ## 回避中の相手
var _evade_walk_t := 0.0
var _herd_positioned := false        ## 動くフンの回り込みが済んだか(押し込み中)
var _wander_point := Vector3.ZERO
var _wander_t := 0.0
var _clock := 0.0

## 突進の計画(押してから突進が終わるまで)
var _dash_kind: DashKind = DashKind.NONE
var _dash_pressed_frame := false     ## 押し始めの1フレームを出したか
var _aim_error := 0.0                ## 今回の狙いのぶれ(ラジアン)
var _evade_dir := Vector3.ZERO

## 詰まり検出
var _stuck_check_pos := Vector3.ZERO
var _stuck_t := 0.0
var _unstuck_t := 0.0
var _unstuck_dir := Vector3.ZERO


func _init(p_body: Player, p_profile: CpuProfile) -> void:
	body = p_body
	profile = p_profile
	sense = CpuSense.new(body)
	rng.seed = hash(body.player_id * 7919 + Time.get_ticks_usec())
	_think_t = rng.randf_range(0.0, profile.think_interval) # CPU同士の考えるタイミングをずらす


## 毎物理フレーム、Player の入力読み取りより前に呼ぶ。
func update(delta: float) -> void:
	_clock += delta
	sense.update(delta)
	_update_threats()
	match body.state:
		Player.State.STUNNED:
			_set_output(Vector3.ZERO, false)
			_dash_kind = DashKind.NONE
			_think_t = minf(_think_t, 0.05) # スタン明けにすぐ考え直す
		Player.State.DASHING:
			_steer_dash()
		Player.State.DASH_CHARGING:
			_hold_charge(delta)
		_:
			_update_rolling(delta)


## --- 通常移動中 ---

func _update_rolling(delta: float) -> void:
	if Stage.is_on_boost_pad(body.global_position):
		# 板の上(押し出された等): 最大溜めの突進が出るので、激突しない向きへ倒す
		var open := _open_direction(CpuSense.flat(body.facing).normalized())
		target_point = CpuSense.flat(body.global_position) + open * 3.0
		_set_output(open, false)
		return
	if _dash_kind != DashKind.NONE and not _dash_pressed_frame:
		_dash_kind = DashKind.NONE # 押したのに溜めに入れなかった(クールタイム等)
	_dash_pressed_frame = false
	if _try_evade():
		return
	_think_t -= delta
	if _think_t <= 0.0:
		_think()
		_think_t = profile.think_interval * rng.randf_range(0.8, 1.2)
	match goal:
		Goal.COLLECT:
			_run_collect(delta)
		Goal.ATTACK:
			_run_attack(delta)
		Goal.EVADE:
			_run_evade_walk(delta)
		_:
			_run_wander(delta)


## --- ゴールの選択 ---

func _think() -> void:
	_prune_given_up()
	if goal == Goal.EVADE and _evade_walk_t > 0.0:
		return
	var collect := _best_dung()
	var attack := _best_attack_target()
	var collect_score: float = collect["score"]
	var attack_score: float = attack["score"]
	if goal == Goal.COLLECT:
		collect_score *= KEEP_GOAL_BONUS
	elif goal == Goal.ATTACK:
		attack_score *= KEEP_GOAL_BONUS
	if _special_should_give_up():
		_give_up(target_dung)
		collect = _best_dung()
		collect_score = collect["score"]
	if attack_score > collect_score and attack_score > 0.0:
		_set_goal(Goal.ATTACK)
		target_player = attack["player"]
	elif collect_score > 0.0:
		var next: DungPickup = collect["dung"]
		if next != target_dung:
			_herd_positioned = false
			if goal == Goal.COLLECT:
				_goal_started_at = _clock
		_set_goal(Goal.COLLECT)
		target_dung = next
	else:
		_set_goal(Goal.WANDER)


func _set_goal(next: Goal) -> void:
	if next != goal:
		goal = next
		_goal_started_at = _clock
		_herd_positioned = false


## 回収の候補で一番点数の高いフン。{dung, score}
func _best_dung() -> Dictionary:
	var me := CpuSense.flat(body.global_position)
	var best: DungPickup = null
	var best_score := 0.0
	for d in sense.dungs():
		if _given_up.has(d.get_instance_id()):
			continue
		var dist := me.distance_to(CpuSense.flat(d.global_position))
		var value := CpuSense.dung_gain(d)
		if d.is_special():
			value = maxf(value, 0.5) * profile.special_score_bonus
		var reach_scale := 1.0 if dist <= profile.collect_radius else 0.35 # 遠いフンは最後の候補
		# 動かないフンは確実に取れる。動くフンは追い込みの手間がかかる分だけ控えめにする。
		var ease_scale := 1.0 if d.is_static() else 0.8
		var score := value * reach_scale * ease_scale / (1.0 + dist / 4.0)
		if d == target_dung:
			score *= KEEP_GOAL_BONUS
		if score > best_score:
			best_score = score
			best = d
	return {"dung": best, "score": best_score}


## 攻撃の候補で一番点数の高い相手。{player, score}
func _best_attack_target() -> Dictionary:
	var best: Player = null
	var best_score := 0.0
	if profile.aggression <= 0.0 or _clock < _attack_ready_at:
		return {"player": best, "score": 0.0}
	var me := CpuSense.flat(body.global_position)
	var leader := sense.leader()
	for p in sense.opponents():
		if p.state == Player.State.STUNNED or p.is_dash_invincible():
			continue
		var dist := me.distance_to(CpuSense.flat(p.global_position))
		if dist > profile.attack_max_distance * 1.5:
			continue
		var gain := p.size * clampf(Config.balance.drop_ratio, 0.0, 1.0) * (1.0 - Config.balance.drop_loss_ratio)
		# 近さ・当てやすさ: 攻撃の間合いに近いほど高い
		var ideal := clampf(dist, profile.attack_min_distance, profile.attack_max_distance)
		var ease_scale := 1.0 / (1.0 + absf(dist - ideal) / 3.0) / (1.0 + dist / 10.0)
		var bias := 1.0
		if p == leader and leader != body:
			bias += profile.leader_bias
		if p.player_id == _last_attack_target_id:
			bias -= profile.same_target_penalty
		var score := gain * ease_scale * maxf(bias, 0.0) * profile.aggression * ATTACK_SCORE_SCALE
		if score > best_score:
			best_score = score
			best = p
	return {"player": best, "score": best_score}


func _special_should_give_up() -> bool:
	if goal != Goal.COLLECT or not _valid_dung(target_dung):
		return false
	var elapsed := _clock - _goal_started_at
	var dist := CpuSense.flat(body.global_position).distance_to(CpuSense.flat(target_dung.global_position))
	if target_dung.is_special():
		return elapsed >= profile.special_give_up_time and dist >= profile.special_give_up_distance
	# 通常の動くフンも、長く追って取れなければ諦める
	return not target_dung.is_static() and elapsed >= profile.special_give_up_time * 2.0 \
		and dist >= profile.special_give_up_distance


func _give_up(d: DungPickup) -> void:
	if d == null:
		return
	_given_up[d.get_instance_id()] = _clock + profile.give_up_cooldown
	counters["give_ups"] += 1
	target_dung = null
	_herd_positioned = false


func _prune_given_up() -> void:
	for id in _given_up.keys():
		if _clock >= float(_given_up[id]):
			_given_up.erase(id)


## --- 回収 ---

func _run_collect(delta: float) -> void:
	if not _valid_dung(target_dung):
		target_dung = null
		_think_t = 0.0
		_run_wander(delta)
		return
	var me := CpuSense.flat(body.global_position)
	var dpos := CpuSense.flat(target_dung.global_position)
	target_point = dpos
	var dist := me.distance_to(dpos)
	if target_dung.is_static():
		_walk_toward(dpos, delta, false)
		return
	# 遠くの動くフン: 届く距離に合わせて溜めた突進で取りに行く
	if dist >= profile.dash_collect_min_distance and _can_dash():
		var aim := _predict_dung(target_dung, dist)
		if _try_start_dash(DashKind.COLLECT, aim, me.distance_to(aim) + 1.0, me.distance_to(aim)):
			return
	if dist >= profile.dash_collect_min_distance:
		_walk_toward(dpos, delta, true)
		return
	_run_herd(delta, me, dpos)


## 近くの動くフン: フンから見て一番近い壁・角の反対側へ回り込み、そこから押し込んで追い詰める。
func _run_herd(delta: float, me: Vector3, dpos: Vector3) -> void:
	var wall := sense.nearest_wall(dpos)
	var push_dir: Vector3 = wall["dir"]
	if push_dir == Vector3.ZERO:
		push_dir = (dpos - me).normalized()
	var standoff := Config.balance.flee_idle_alert_radius + body.body_radius() + HERD_STANDOFF_MARGIN
	var approach := CpuSense.clamp_inside(dpos - push_dir * standoff, body.body_radius() + 0.4)
	# 壁際で十分に追い込めていれば(壁が近い)回り込み不要
	var cornered: bool = float(wall["distance"]) < 1.5
	if not _herd_positioned:
		var to_dung := (dpos - me)
		var behind := to_dung.normalized().dot(push_dir) > 0.6 # 自分→フンの向きが、フン→壁の向きと揃っている
		if behind or cornered or me.distance_to(approach) < HERD_ARRIVE_DISTANCE:
			_herd_positioned = true
	if _herd_positioned:
		target_point = dpos
		_walk_toward(dpos, delta, false)
		# 押し込んでいるうちにフンの向こう側へ出てしまったら回り込み直す
		if (dpos - me).normalized().dot(push_dir) < -0.3 and me.distance_to(dpos) > 2.0:
			_herd_positioned = false
	else:
		target_point = approach
		_walk_toward(approach, delta, true, dpos, standoff - 0.5)


## 動くフンの先読み位置(突進で着くまでの時間ぶん)。
func _predict_dung(d: DungPickup, dist: float) -> Vector3:
	var hold := CpuDashModel.hold_for_reach(dist + 1.0, body.size)
	var ratio := CpuDashModel.ratio_for_hold(hold, body.size)
	var t := hold + CpuDashModel.time_to_travel(minf(dist, CpuDashModel.reach_for_ratio(ratio) - 0.01), ratio)
	if is_inf(t):
		t = hold + 0.5
	return CpuSense.predict(d, sense.dung_velocity(d), minf(t, 1.0) * 0.6, 0.6)


func _valid_dung(d: Variant) -> bool:
	return d != null and is_instance_valid(d) and not (d as DungPickup).is_queued_for_deletion() and not (d as DungPickup)._collected


## --- 攻撃 ---

func _run_attack(delta: float) -> void:
	var p := target_player
	if p == null or not is_instance_valid(p) or not p.gameplay_active or p.state == Player.State.STUNNED:
		target_player = null
		_think_t = 0.0
		_run_wander(delta)
		return
	var me := CpuSense.flat(body.global_position)
	var aim := _predict_player(p)
	target_point = aim
	var dist := me.distance_to(aim)
	if _can_dash() and dist >= profile.attack_min_distance and dist <= _attack_range():
		if _try_start_dash(DashKind.ATTACK, aim, dist + profile.attack_overshoot, dist):
			_last_attack_target_id = p.player_id
			_attack_ready_at = _clock + profile.attack_rest_time / maxf(profile.aggression, 0.01)
			return
	# 間合いを取る: 近すぎれば離れ、遠ければ近づく
	var ppos := CpuSense.flat(p.global_position)
	var away := (me - ppos)
	away = away.normalized() if away.length() > 0.01 else Vector3.RIGHT
	var ideal := clampf(profile.attack_min_distance + 2.0, profile.attack_min_distance, _attack_range())
	var stand := CpuSense.clamp_inside(ppos + away * ideal, body.body_radius() + 0.6)
	_walk_toward(stand, delta, true)


func _attack_range() -> float:
	return minf(profile.attack_max_distance, CpuDashModel.max_reach(body.size) - profile.attack_overshoot)


## 相手の先読み位置(溜め・突進で届くまでの時間ぶん)。2回反復して時間と距離を合わせる。
func _predict_player(p: Player) -> Vector3:
	var me := CpuSense.flat(body.global_position)
	var aim := CpuSense.flat(p.global_position)
	var remaining_hold := 0.0
	for _i in 2:
		var dist := me.distance_to(aim)
		var hold := CpuDashModel.hold_for_reach(dist + profile.attack_overshoot, body.size)
		var ratio := CpuDashModel.ratio_for_hold(hold, body.size)
		var travel := CpuDashModel.time_to_travel(minf(dist, CpuDashModel.reach_for_ratio(ratio) - 0.01), ratio)
		if is_inf(travel):
			travel = 0.6
		remaining_hold = hold if body.state != Player.State.DASH_CHARGING else maxf(hold - body._charge_t, 0.0)
		aim = CpuSense.predict(p, p.velocity, remaining_hold + travel, p.body_radius())
	return aim


## --- 回避 ---

## 自分を狙って溜めている相手を見張る。気づいた時刻を覚え、reaction_delay 後に回避する。
func _update_threats() -> void:
	var me := CpuSense.flat(body.global_position)
	var active := {}
	for p in sense.opponents():
		if p.state != Player.State.DASH_CHARGING:
			continue
		var to_me := me - CpuSense.flat(p.global_position)
		var dist := to_me.length()
		if dist > profile.evade_detect_radius or dist < 0.01:
			continue
		var facing := CpuSense.flat(p.facing)
		if facing.is_zero_approx():
			continue
		var angle := rad_to_deg(facing.normalized().angle_to(to_me / dist))
		var body_angle := rad_to_deg(asin(clampf(body.body_radius() / dist, 0.0, 1.0)))
		if angle <= profile.evade_facing_deg + body_angle:
			active[p.player_id] = p
			if not _threat_seen.has(p.player_id):
				_threat_seen[p.player_id] = _clock
	for id in _threat_seen.keys():
		if not active.has(id):
			_threat_seen.erase(id)


## 気づいてから reaction_delay たった脅威の相手(一番近い)。いなければ null。
func _ready_threat() -> Player:
	var me := CpuSense.flat(body.global_position)
	var best: Player = null
	var best_d := INF
	for p in sense.opponents():
		if not _threat_seen.has(p.player_id):
			continue
		if _clock - float(_threat_seen[p.player_id]) < profile.reaction_delay:
			continue
		var d := me.distance_to(CpuSense.flat(p.global_position))
		if d < best_d:
			best_d = d
			best = p
	return best


func _try_evade() -> bool:
	var threat := _ready_threat()
	if threat == null:
		return false
	_evade_from = threat
	_evade_dir = _evade_direction(threat)
	target_point = CpuSense.flat(body.global_position) + _evade_dir * 3.0
	if _can_dash():
		# 溜めずにすぐ離す短い突進で、迫る向きと直角へ避ける
		_threat_seen.erase(threat.player_id)
		_dash_kind = DashKind.EVADE
		_dash_pressed_frame = true
		counters["evade_dashes"] += 1
		_set_goal(Goal.EVADE)
		_evade_walk_t = 0.0
		_set_output(_evade_dir, true)
		return true
	# クールタイム中は直角へ歩いて避ける
	_set_goal(Goal.EVADE)
	_evade_walk_t = EVADE_WALK_TIME
	_set_output(_evade_dir, false)
	return true


func _run_evade_walk(delta: float) -> void:
	_evade_walk_t -= delta
	if _evade_walk_t <= 0.0 or _evade_dir == Vector3.ZERO:
		_set_goal(Goal.WANDER)
		_think_t = 0.0
		_run_wander(delta)
		return
	_set_output(_avoid_walls(_evade_dir), false)


## 相手が迫ってくる向きと直角の2方向のうち、壁から遠く、相手の狙いから外れる側。
func _evade_direction(threat: Player) -> Vector3:
	var me := CpuSense.flat(body.global_position)
	var incoming := me - CpuSense.flat(threat.global_position)
	incoming = incoming.normalized() if incoming.length() > 0.01 else CpuSense.flat(threat.facing).normalized()
	var left := Vector3(-incoming.z, 0.0, incoming.x)
	var best := left
	var best_score := -INF
	var aim := CpuSense.flat(threat.facing).normalized()
	var reach := CpuDashModel.min_reach(body.size) + body.body_radius()
	for side in [left, -left]:
		var open := minf(_dash_room(side) + body.body_radius() + DASH_WALL_MARGIN, reach + 3.0)
		var score := open
		if open < reach:
			score -= 10.0 # 壁に激突する向きは選ばない
		# 相手の向きが自分の少し左を向いていれば右へ(狙いから外れる側)
		score += 2.0 * signf(-aim.dot(side))
		if score > best_score:
			best_score = score
			best = side
	return best


## --- 突進の計画と実行 ---

func _can_dash() -> bool:
	return body.state == Player.State.ROLLING and body._cd_t <= 0.0 and not body._dash_suppressed


## aim へ向けて、reach だけ届く突進を始める。前方の壁で激突しそうで、need(最低限届かせたい距離)を
## 確保できなければ始めずに false。
func _try_start_dash(kind: DashKind, aim: Vector3, reach: float, need: float) -> bool:
	var me := CpuSense.flat(body.global_position)
	var to := aim - me
	if to.length() < 0.05:
		return false
	var dir := to.normalized()
	if not sense.clear_path(body.global_position, aim, body.body_radius()):
		return false
	if _path_crosses_boost_pad(me, me + dir * reach):
		return false # 加速板に乗ると最大溜めで打ち直されて狙いどおりに止まれない
	if _dash_room(dir) < need:
		return false
	_dash_kind = kind
	_dash_pressed_frame = true
	_aim_error = deg_to_rad(rng.randf_range(-profile.aim_error_deg, profile.aim_error_deg))
	if kind == DashKind.ATTACK:
		counters["attack_dashes"] += 1
	elif kind == DashKind.COLLECT:
		counters["collect_dashes"] += 1
	_set_output(dir.rotated(Vector3.UP, _aim_error), true)
	if OS.has_environment("CPU_TRACE"):
		print("[launch] kind=%d pos=%s dir=%s aim=%s need=%.1f room=%.1f" % [kind, me, dir, aim, need, _dash_room(dir)])
	return true


## dir へ突進したとき、壁・杭に激突せずに進める距離(余裕 DASH_WALL_MARGIN 込み)。
func _dash_room(dir: Vector3) -> float:
	var hit := _crash_obstacle(dir, CpuDashModel.max_reach(body.size) + body.body_radius() + 1.0)
	if hit.is_empty():
		return INF
	return float(hit["distance"]) - body.body_radius() - DASH_WALL_MARGIN


## dir へ distance 進む間に、滑れない角度でぶつかる一番近い壁・杭。{distance, normal, position} か空。
## 球の中心と左右の縁の3本のレイで調べる(細い杭も見落とさない)。
func _crash_obstacle(dir: Vector3, distance: float) -> Dictionary:
	var r := body.body_radius()
	var side := Vector3(-dir.z, 0.0, dir.x) * r * 0.9
	var best := {}
	for offset in [Vector3.ZERO, side, -side]:
		var from: Vector3 = body.global_position + offset
		var hit := sense.wall_hit(from, dir, distance)
		if hit.is_empty():
			continue
		var normal := CpuSense.flat(hit["normal"])
		if normal.length() < 0.01:
			continue
		normal = normal.normalized()
		var incidence := rad_to_deg(asin(clampf(-dir.dot(normal), 0.0, 1.0)))
		if incidence <= Config.balance.wall_slide_max_angle * 0.8:
			continue
		var d := CpuSense.flat(hit["position"]).distance_to(CpuSense.flat(from))
		if best.is_empty() or d < float(best["distance"]):
			best = {"distance": d, "normal": normal, "position": CpuSense.flat(hit["position"])}
	return best


## prefer に近い向きのうち、最大溜めの突進でも激突しない(または一番先まで開けている)向き。
## 加速板で最大溜めの突進を打ち直されるときの向きに使う。
func _open_direction(prefer: Vector3) -> Vector3:
	var reach := CpuDashModel.reach_for_ratio(clampf(Config.balance.boost_pad_charge_ratio, 0.0, 1.0))
	var best := prefer
	var best_score := -INF
	for i in 24:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(i) / 24.0)
		var hit := _crash_obstacle(dir, reach + body.body_radius() + DASH_WALL_MARGIN)
		var open := reach + 2.0 if hit.is_empty() else float(hit["distance"])
		var score := open + 1.5 * dir.dot(prefer)
		if score > best_score:
			best_score = score
			best = dir
	return best


## 溜め中: 狙いへ向き続け、届く距離ぶん溜まったら離す。狙いとの間に壁・杭があれば離すのを待つ。
func _hold_charge(delta: float) -> void:
	_dash_pressed_frame = false
	var me := CpuSense.flat(body.global_position)
	match _dash_kind:
		DashKind.EVADE:
			_set_output(_evade_dir, false) # 溜めずにすぐ離す(最低溜めで自動発動)
		DashKind.ATTACK, DashKind.COLLECT:
			var aim := _current_aim()
			var dist := me.distance_to(aim)
			var dir := (aim - me).normalized() if dist > 0.05 else CpuSense.flat(body.facing)
			dir = dir.rotated(Vector3.UP, _aim_error)
			var extra := profile.attack_overshoot if _dash_kind == DashKind.ATTACK else 1.0
			var want := dist + extra
			# 前方の壁に激突しない長さに抑える
			want = minf(want, maxf(_dash_room(dir), CpuDashModel.min_reach(body.size)))
			var hold := CpuDashModel.hold_for_reach(want, body.size)
			var release := body._charge_t + delta >= hold
			var blocked := _dash_room(dir) < minf(dist, CpuDashModel.min_reach(body.size))
			if release and (blocked or not sense.clear_path(body.global_position, aim, body.body_radius())):
				release = false # 杭の陰: 見通しが戻るまで溜めたまま待つ(押しすぎると自動で出る)
				if _charge_auto_release_near(delta):
					dir = _open_direction(dir)
			if _dash_kind == DashKind.ATTACK and not _target_still_valid():
				release = true
			_set_output(dir, not release)
		_:
			_set_output(Vector3.ZERO, false) # 想定外の溜め(加速板など): すぐ離す


## 押しっぱなしで自動発動する直前か。
func _charge_auto_release_near(delta: float) -> bool:
	var b := Config.balance
	if b.dash_charge_hold_max <= 0.0:
		return false
	return body._charge_t + delta * 3.0 >= CpuDashModel.full_hold_time(body.size) + b.dash_charge_hold_max


func _current_aim() -> Vector3:
	if _dash_kind == DashKind.ATTACK and _target_still_valid():
		return _predict_player(target_player)
	if _dash_kind == DashKind.COLLECT and _valid_dung(target_dung):
		var me := CpuSense.flat(body.global_position)
		return _predict_dung(target_dung, me.distance_to(CpuSense.flat(target_dung.global_position)))
	return CpuSense.flat(body.global_position) + CpuSense.flat(body.facing) * 3.0


func _target_still_valid() -> bool:
	return target_player != null and is_instance_valid(target_player) and target_player.gameplay_active \
		and target_player.state != Player.State.STUNNED


## 突進中: 狙いへ曲げる(旋回の上限は Player 側)。狙いを通り過ぎたら曲げるのをやめる。
## 止まるまでに激突しそうな壁・杭(滑れない角度)が前にあれば、沿う向き・よける向きへ逃がす。
## 加速板の上では、打ち直される最大溜めの突進が激突しない向きへスティックを倒す。
func _steer_dash() -> void:
	var me := CpuSense.flat(body.global_position)
	var dir := CpuSense.flat(body.facing).normalized()
	if Stage.is_on_boost_pad(body.global_position):
		_dash_kind = DashKind.NONE # 加速板に打ち直された突進は狙いを追わない
		var open := _open_direction(dir)
		target_point = me + open * 3.0
		_set_output(open, false)
		return
	var want := dir
	match _dash_kind:
		DashKind.ATTACK, DashKind.COLLECT:
			var aim := _current_aim()
			var to := aim - me
			if to.length() > 0.5 and to.normalized().dot(dir) > 0.0:
				want = to.normalized().rotated(Vector3.UP, _aim_error)
				target_point = aim
	var hit := _crash_obstacle(dir, _dash_remaining_distance() + body.body_radius() + 0.3)
	if not hit.is_empty():
		var normal: Vector3 = hit["normal"]
		var along := dir - normal * dir.dot(normal)
		if along.length() < 0.05:
			along = Vector3(-normal.z, 0.0, normal.x)
		# 細い杭は中心から離れる側へ、壁は沿う向きへ
		var pos: Vector3 = hit["position"]
		var side := Vector3(-dir.z, 0.0, dir.x)
		if side.dot(me - pos) * side.dot(along) < 0.0 and (me - pos).length() < 3.0:
			along = -along
		want = along.normalized()
	if _dash_kind == DashKind.EVADE or _dash_kind == DashKind.NONE:
		target_point = me + want * 3.0
	_set_output(want, false)


## 今の突進が止まるまでに進む残りの距離。
func _dash_remaining_distance() -> float:
	var decel := maxf(Config.balance.dash_end_decel_time, 0.001)
	var t: float = body._dash_t
	var dur: float = body._dash_duration
	var v: float = body._dash_speed
	if t < dur:
		return v * (dur - t) + v * decel * 0.5
	var s := clampf((t - dur) / decel, 0.0, 1.0)
	return v * decel * 0.5 * (1.0 - s) * (1.0 - s)


## --- 歩き ---

func _run_wander(delta: float) -> void:
	_wander_t -= delta
	var me := CpuSense.flat(body.global_position)
	if _wander_t <= 0.0 or me.distance_to(_wander_point) < 1.0:
		_wander_t = rng.randf_range(1.5, 3.0)
		_wander_point = CpuSense.clamp_inside(
			Vector3(rng.randf_range(-Stage.HALF_X, Stage.HALF_X) * 0.6, 0.0, rng.randf_range(-Stage.HALF_Z, Stage.HALF_Z) * 0.6), 2.0)
	target_point = _wander_point
	_walk_toward(_wander_point, delta, true)


## dest へ歩く。壁・杭・加速板を避け、詰まったら回り道する。
## pickup_detour: 通り道の近くの動かないフンへ寄り道するか。
## keep_from / keep_radius: その点(回り込み中のフン)へ keep_radius より近づかないよう回り込む。
func _walk_toward(dest: Vector3, delta: float, pickup_detour: bool,
		keep_from: Vector3 = Vector3.INF, keep_radius: float = 0.0) -> void:
	var me := CpuSense.flat(body.global_position)
	var to := dest - me
	if to.length() < 0.15:
		_set_output(Vector3.ZERO, false)
		return
	var dir := to.normalized()
	if pickup_detour:
		var near := _nearby_static_dung(me, dir)
		if near != null:
			dir = (CpuSense.flat(near.global_position) - me).normalized()
	if keep_from != Vector3.INF:
		var to_keep := keep_from - me
		var kd := to_keep.length()
		if kd < keep_radius and kd > 0.01 and dir.dot(to_keep / kd) > -0.2:
			# 円周方向へ回り込む(目的地に近い側)
			var tangent := Vector3(-to_keep.z, 0.0, to_keep.x) / kd
			if tangent.dot(dir) < 0.0:
				tangent = -tangent
			dir = (tangent - to_keep / kd * 0.4).normalized()
	dir = _avoid_walls(dir)
	dir = _avoid_boost_pads(me, dir, dest)
	dir = _unstuck(me, dir, delta)
	_set_output(dir, false)


## 前方の壁・フェンス・杭を、壁に沿う向きへそらして避ける。
func _avoid_walls(dir: Vector3) -> Vector3:
	var r := body.body_radius()
	var hit := sense.wall_hit(body.global_position, dir, r + profile.wall_probe_distance)
	if hit.is_empty():
		return dir
	var normal := CpuSense.flat(hit["normal"])
	if normal.length() < 0.01:
		return dir
	normal = normal.normalized()
	var along := dir - normal * dir.dot(normal)
	if along.length() < 0.1:
		along = Vector3(-normal.z, 0.0, normal.x) # 真正面: どちらか横へ
	return (along.normalized() + normal * 0.2).normalized()


## 加速板に乗ると勝手に突進するので、目的地が板の上でなければ板の手前で横へそれる。
func _avoid_boost_pads(me: Vector3, dir: Vector3, dest: Vector3) -> Vector3:
	if Stage.is_on_boost_pad(dest) or Stage.is_on_boost_pad(me):
		return dir
	var ahead := me + dir * (body.body_radius() + 0.9)
	if not Stage.is_on_boost_pad(ahead):
		return dir
	for step in [30.0, -30.0, 60.0, -60.0, 90.0, -90.0]:
		var d := dir.rotated(Vector3.UP, deg_to_rad(step))
		if not Stage.is_on_boost_pad(me + d * (body.body_radius() + 0.9)):
			return d
	return dir


## a から b までの直線が加速板を通るか(a が板の上なら無視)。
func _path_crosses_boost_pad(a: Vector3, b: Vector3) -> bool:
	if Stage.is_on_boost_pad(a):
		return false
	var length := a.distance_to(b)
	var steps := int(ceil(length / 0.5))
	for i in range(1, steps + 1):
		if Stage.is_on_boost_pad(a.lerp(b, float(i) / float(steps))):
			return true
	return false


## 進もうとしてもほとんど動けない状態が stuck_time 続いたら、少しの間ランダムな横向きへ回り道する。
func _unstuck(me: Vector3, dir: Vector3, delta: float) -> Vector3:
	if _unstuck_t > 0.0:
		_unstuck_t -= delta
		return _avoid_walls(_unstuck_dir)
	_stuck_t += delta
	if _stuck_t >= profile.stuck_time:
		var moved := me.distance_to(_stuck_check_pos)
		var expected := Config.balance.move_speed_base * Config.balance.move_speed_scale(body.size) * _stuck_t
		if moved < expected * 0.25:
			_unstuck_t = UNSTUCK_TIME
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			_unstuck_dir = dir.rotated(Vector3.UP, side * deg_to_rad(rng.randf_range(70.0, 130.0)))
			counters["unstuck"] += 1
		_stuck_t = 0.0
		_stuck_check_pos = me
	return dir


## 進行方向の近くにある動かないフン(寄り道して拾う)。
func _nearby_static_dung(me: Vector3, dir: Vector3) -> DungPickup:
	var best: DungPickup = null
	var best_d := DETOUR_PICKUP_DISTANCE
	for d in sense.dungs():
		if not d.is_static() or d == target_dung:
			continue
		var to := CpuSense.flat(d.global_position) - me
		var dist := to.length()
		if dist < best_d and dist > 0.01 and dir.dot(to / dist) > 0.3:
			best_d = dist
			best = d
	return best


func _set_output(dir: Vector3, dash_held: bool) -> void:
	move = Vector2(dir.x, dir.z)
	dash = dash_held


## 壁に激突した(どの突進で激突したかを数える)。
func on_wall_crashed() -> void:
	var key: String = ["crash_other", "crash_attack", "crash_collect", "crash_evade"][_dash_kind]
	counters[key] += 1
	if OS.has_environment("CPU_TRACE"):
		print("[crash] kind=%s pos=%s facing=%s t=%.2f dur=%.2f v=%.1f target=%s state=%s pad=%s" % [key, CpuSense.flat(body.global_position), CpuSense.flat(body.facing), body._dash_t, body._dash_duration, body._dash_speed, target_point, body.state, Stage.is_on_boost_pad(body.global_position)])


func goal_name() -> String:
	return GOAL_NAMES[goal]


func goal_color() -> Color:
	return GOAL_COLORS[goal]
