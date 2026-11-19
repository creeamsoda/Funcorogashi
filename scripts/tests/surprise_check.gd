extends Node3D
## 驚いて逃げるフンの headless 単体テスト。調整値はテスト内で固定して検証する:
##  idle    : 止まっている時は⓪以内で驚き、⓪の外では驚かない。驚き中①秒はその場から動かない
##  basis   : 驚き中にプレイヤーが回り込んだら、驚き終わった瞬間の位置から離れる向きへ進む。驚き中もその時点の逃げる向きを向く
##  speed   : 逃走中は速度②
##  moving  : 逃走中は③の外(⓪の内)では驚かず、③以内に入ると驚く(逃げ元のプレイヤーでも)
##  wall    : 逃走中、前方③以内に壁が来ると驚く。壁の驚きは専用の時間で、終わったら離れる向きに一番近い
##            「前方③以内に壁がない向き」へ逃げ、続けて壁に驚かない(プレイヤーが壁用の範囲内にいる時)
##  wall_stop: 壁に驚き終わった時、壁用の範囲内にプレイヤーがいなければ壁を向いたまま止まる
##  enclosed: 四方を囲まれて逃げ道がなければ、壁に驚き続けてその場から動かない
##  brake   : 驚かずに④秒進むと減速度⑤で止まり、止まると止まっている時の範囲⓪に戻る

const VALUES := {
	"flee_enabled": true, "flee_idle_alert_radius": 4.0, "flee_surprise_time": 0.5, "flee_speed": 5.0,
	"flee_moving_alert_radius": 2.0, "flee_run_time": 1.0, "flee_stop_decel": 10.0, "flee_speed_size_penalty": 0.0,
	"flee_wall_surprise_time": 0.3, "flee_wall_search_step": 10.0, "flee_wall_escape_radius": 4.0,
}

var _saved := {}
var _failures: Array[String] = []


func _ready() -> void:
	for key in VALUES:
		_saved[key] = Config.balance.get(key)
		Config.balance.set(key, VALUES[key])
	await _test_idle()
	await _test_basis_and_speed()
	await _test_moving_alert()
	await _test_wall()
	await _test_wall_stop()
	await _test_enclosed()
	await _test_brake()
	for key in _saved:
		Config.balance.set(key, _saved[key])
	print("[surprise_check] result=", ("PASS" if _failures.is_empty() else "FAIL"), " failures=", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_idle() -> void:
	var pk := _pickup(Vector3.ZERO)
	var far := _player(0, Vector3(_center_gap(pk, 4.5), 0, 0))
	await _frames(5)
	var stays_idle := pk._state == DungPickup.FleeState.IDLE
	far.global_position = Vector3(_center_gap(pk, 3.5), 0, 0)
	await _frames(2)
	var surprised := pk._state == DungPickup.FleeState.SURPRISED
	var start := pk.global_position
	await _seconds(0.4)
	var still := pk.global_position.distance_to(start) < 0.01 and pk._state == DungPickup.FleeState.SURPRISED
	print("  [idle] stays_idle_outside=%s surprised_inside=%s still_while_surprised=%s" % [stays_idle, surprised, still])
	if not (stays_idle and surprised and still):
		_failures.append("idle")
	_clear([pk, far])
	await _frames(2)


## +X 側から驚かせ、驚き中に -Z 側へ回り込む → 驚き終わりには +Z へ逃げるはず。
## 驚き中もその時点の逃げる向きを向く(最初は -X、回り込まれたら +Z)。
func _test_basis_and_speed() -> void:
	var pk := _pickup(Vector3.ZERO)
	var p := _player(0, Vector3(_center_gap(pk, 3.0), 0, 0))
	await _frames(2)
	var faces_first := pk._state == DungPickup.FleeState.SURPRISED and pk._heading.angle_to(Vector3.LEFT) < deg_to_rad(5.0)
	p.global_position = Vector3(0, 0, -_center_gap(pk, 1.0))
	await _frames(2)
	var faces_after_move := pk._state == DungPickup.FleeState.SURPRISED and pk._heading.angle_to(Vector3.BACK) < deg_to_rad(5.0)
	print("  [face_while_surprised] first=-X:%s after_move=+Z:%s" % [faces_first, faces_after_move])
	if not (faces_first and faces_after_move):
		_failures.append("face_while_surprised")
	while pk._state == DungPickup.FleeState.SURPRISED:
		await get_tree().physics_frame
	p.global_position = Vector3(30, 0, -30) # 以降は驚かせない
	var away := Vector3.BACK # +Z
	var basis_ok := pk._heading.angle_to(away) < deg_to_rad(5.0)
	await _frames(3)
	var speed_ok := pk._state == DungPickup.FleeState.RUNNING and is_equal_approx(pk._speed, 5.0)
	print("  [basis] heading=%s (+Z期待) ok=%s  [speed] %.2f ok=%s" % [pk._heading, basis_ok, pk._speed, speed_ok])
	if not basis_ok:
		_failures.append("basis")
	if not speed_ok:
		_failures.append("speed")
	_clear([pk, p])
	await _frames(2)


func _test_moving_alert() -> void:
	var pk := _pickup(Vector3.ZERO)
	var chaser := _player(0, Vector3(-_center_gap(pk, 3.0), 0, 0))
	await _frames(2)
	while pk._state != DungPickup.FleeState.RUNNING:
		await get_tree().physics_frame
	# 逃走中: 横 3m(⓪の内・③の外)に別のプレイヤー → 驚かない
	var side := _player(1, pk.global_position + Vector3(0, 0, _center_gap(pk, 3.0)))
	chaser.global_position = Vector3(-40, 0, 0)
	await _frames(3)
	var ignores_outside := pk._state == DungPickup.FleeState.RUNNING
	# 逃げ元のプレイヤーが③以内に追いつく → 驚く
	chaser.global_position = pk.global_position - pk._heading * _center_gap(pk, 1.5)
	side.global_position = Vector3(40, 0, 40)
	await _frames(2)
	var surprised := pk._state == DungPickup.FleeState.SURPRISED
	print("  [moving] ignores_between_3_and_0=%s surprised_within_3=%s" % [ignores_outside, surprised])
	if not (ignores_outside and surprised):
		_failures.append("moving")
	_clear([pk, chaser, side])
	await _frames(2)


## 東の壁(x=18)へ向かって逃げる。前方③以内に壁が来たら驚く(④秒で止まる前に届く位置から)。
func _test_wall() -> void:
	var stage := load("res://scenes/Stage.tscn").instantiate() as Stage
	add_child(stage)
	var pk := _pickup(Vector3(12, 0, 0))
	var p := _player(0, Vector3(12.0 - _center_gap(pk, 3.0), 0, 0))
	await _frames(2)
	while pk._state != DungPickup.FleeState.RUNNING:
		await get_tree().physics_frame
	p.global_position = Vector3(-15, 0, 10)
	var t := 0.0
	while pk._state == DungPickup.FleeState.RUNNING and t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var gap := Stage.HALF_X - pk.global_position.x - pk._radius()
	var ok := pk._state == DungPickup.FleeState.SURPRISED and pk._wall_surprise and gap <= 2.0 + 0.15 and gap > 1.5
	print("  [wall] surprised=%s gap_to_wall=%.2f (③=2.0)" % [pk._state == DungPickup.FleeState.SURPRISED, gap])
	if not ok:
		_failures.append("wall")
	# 壁の驚き中にプレイヤーが近く(③の外・壁用の範囲の内)へ来る。
	# 壁の驚きは専用の時間。終わったら壁のない向きのうち「離れる向き」に一番近い向きへ逃げ、続けて壁に驚かない
	p.global_position = pk.global_position + Vector3(-1.0, 0, 0.6).normalized() * _center_gap(pk, 3.0)
	var surprised_t := 0.0
	while pk._state == DungPickup.FleeState.SURPRISED and surprised_t < 2.0:
		await get_tree().physics_frame
		surprised_t += get_physics_process_delta_time()
	var away := pk.global_position - p.global_position
	away.y = 0.0
	away = away.normalized()
	var turn := rad_to_deg(away.angle_to(pk._heading))
	var free := pk._state == DungPickup.FleeState.RUNNING and _escapable(pk, pk._heading)
	# 1刻み(10度)手前の向きは左右どちらも逃げられない = いま選んだのが一番近い
	var inner := deg_to_rad(maxf(turn - 10.0, 0.0))
	var nearest_free := turn < 1.0 or (not _escapable(pk, away.rotated(Vector3.UP, inner))
		and not _escapable(pk, away.rotated(Vector3.UP, -inner)))
	var no_loop := true
	for _i in 20:
		await get_tree().physics_frame
		no_loop = no_loop and pk._state == DungPickup.FleeState.RUNNING
	var timing := absf(surprised_t - 0.3) < 0.05
	print("  [wall_escape] surprise=%.2fs (壁用0.3) turn=%.0f度 free=%s nearest=%s keeps_running=%s" % [surprised_t, turn, free, nearest_free, no_loop])
	if not (timing and free and nearest_free and no_loop):
		_failures.append("wall_escape")
	_clear([pk, p, stage])
	await _frames(2)


## 壁に驚き終わった時、近くにプレイヤーがいなければ逃げずに壁の前で止まる(壁を向いたまま)。
func _test_wall_stop() -> void:
	var stage := load("res://scenes/Stage.tscn").instantiate() as Stage
	add_child(stage)
	var pk := _pickup(Vector3(12, 0, 0))
	var p := _player(0, Vector3(12.0 - _center_gap(pk, 3.0), 0, 0))
	await _frames(2)
	while pk._state != DungPickup.FleeState.RUNNING:
		await get_tree().physics_frame
	p.global_position = Vector3(-15, 0, 10) # 壁用の範囲の外
	var t := 0.0
	while not (pk._state == DungPickup.FleeState.SURPRISED and pk._wall_surprise) and t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var at_wall := pk.global_position
	while pk._state == DungPickup.FleeState.SURPRISED and t < 5.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	await _frames(10)
	var stopped := pk._state == DungPickup.FleeState.IDLE and pk.global_position.distance_to(at_wall) < 0.05
	var facing_wall := pk._heading.angle_to(Vector3.RIGHT) < deg_to_rad(10.0)
	print("  [wall_stop] idle=%s stayed=%s facing_wall=%s" % [pk._state == DungPickup.FleeState.IDLE, stopped, facing_wall])
	if not (stopped and facing_wall):
		_failures.append("wall_stop")
	_clear([pk, p, stage])
	await _frames(2)


## 壁に驚いた後に選べる向き: 前方③以内に壁がなく、驚いた壁へ近づかない。
func _escapable(pk: DungPickup, dir: Vector3) -> bool:
	return dir.dot(pk._wall_normal) >= -0.01 and not pk._blocked_ahead(dir)


## 四方をフェンスで囲まれて逃げ道がない時は、壁に驚き続けて動かない(追い詰めた状態)。
func _test_enclosed() -> void:
	var layout := StageLayout.new()
	for spec in [[Vector2(0, -1.5), 0.0], [Vector2(0, 1.5), 0.0], [Vector2(-1.5, 0), 90.0], [Vector2(1.5, 0), 90.0]]:
		var f := FenceSpec.new()
		f.center = spec[0]
		f.length = 3.4
		f.rotation_deg = spec[1]
		layout.fences.append(f)
	var stage := load("res://scenes/Stage.tscn").instantiate() as Stage
	stage.layout = layout
	add_child(stage)
	var pk := _pickup(Vector3.ZERO)
	var p := _player(0, Vector3(-_center_gap(pk, 3.0), 0, 0))
	await _frames(2)
	var start := pk.global_position
	var t := 0.0
	var max_move := 0.0
	while t < 1.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		max_move = maxf(max_move, pk.global_position.distance_to(start))
	var ok := pk._state == DungPickup.FleeState.SURPRISED and max_move < 0.3
	print("  [enclosed] state=%d max_move=%.2f" % [pk._state, max_move])
	if not ok:
		_failures.append("enclosed")
	_clear([pk, p, stage])
	await _frames(2)


func _test_brake() -> void:
	var pk := _pickup(Vector3.ZERO)
	var p := _player(0, Vector3(-_center_gap(pk, 3.0), 0, 0))
	await _frames(2)
	while pk._state != DungPickup.FleeState.RUNNING:
		await get_tree().physics_frame
	p.global_position = Vector3(-40, 0, 40)
	var start := pk.global_position
	var t := 0.0
	while pk._state == DungPickup.FleeState.RUNNING and t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var run_time := t
	while pk._state == DungPickup.FleeState.BRAKING and t < 5.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var brake_time := t - run_time
	var dist := pk.global_position.distance_to(start)
	var expected := 5.0 * 1.0 + 5.0 * 5.0 / (2.0 * 10.0)
	var ok := absf(run_time - 1.0) < 0.05 and absf(brake_time - 0.5) < 0.05 \
		and absf(dist - expected) < 0.2 and pk._state == DungPickup.FleeState.IDLE
	print("  [brake] run=%.2fs brake=%.2fs dist=%.2f (期待 %.2f) idle=%s" % [run_time, brake_time, dist, expected, pk._state == DungPickup.FleeState.IDLE])
	if not ok:
		_failures.append("brake")
	_clear([pk, p])
	await _frames(2)


func _pickup(pos: Vector3) -> DungPickup:
	var pk := DungPickup.create(1.0)
	pk.position = pos
	add_child(pk)
	return pk


func _player(pid: int, pos: Vector3) -> Player:
	var p: Player = (load("res://scenes/Player.tscn") as PackedScene).instantiate()
	p.player_id = pid
	p.input_device = 9999
	p.position = pos # 原点で一瞬フンに重なって回収しないよう、追加前に置く
	add_child(p)
	p.set_physics_process(false) # 置いた位置から動かさない
	return p


## 球の縁どうしの距離が edge になる中心間の距離(プレイヤーは開始サイズ)。
func _center_gap(pk: DungPickup, edge: float) -> float:
	return edge + pk._radius() + Config.balance.radius_for_size(Config.balance.size_start, Config.balance.size_to_scale)


func _clear(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			if n is Player:
				(n as Player).stop_gameplay()
			n.queue_free()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _seconds(t: float) -> void:
	await get_tree().create_timer(t).timeout
