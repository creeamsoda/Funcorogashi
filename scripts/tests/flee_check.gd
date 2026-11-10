extends Node3D
## 逃げるフン(Phase 2)の headless 自動テスト。追跡役のプレイヤーをスクリプトで動かし、実際の物理で検証する:
##  open   : 1人で真っすぐ追った時に取れるまでの時間(計測のみ。逃げ元にも③で驚くため、追い続ければ取れる)
##  corner : 角へ追い込めば取れる
##  pincer : 壁際で2人で挟めば取れる
##  dash   : 最大溜めの突進なら開けた場所でも取れる
##  drop   : 被弾で落ちたフンは、攻撃側が⓪以内なら猶予なくすぐ驚く
##  stunned: スタン中のプレイヤーからは逃げない
##  static : flee_static_max_size 以下の小さいフンは近づかれても動かず、見た目は球
## 各シナリオの所要時間を出力するので、調整時の目安にも使う。

class Chaser extends Player:
	var target: Node3D
	var want_dash := false
	var chase := true

	func _read_move() -> Vector2:
		if not chase or not is_instance_valid(target):
			return Vector2.ZERO
		var d := target.global_position - global_position
		var v := Vector2(d.x, d.z)
		return v.normalized() if v.length() > 0.01 else Vector2.ZERO

	func _dash_input_held() -> bool:
		return want_dash


var _dung: Node3D
var _report: Array[String] = []


func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	_dung = Node3D.new()
	_dung.add_to_group("dung_container")
	add_child(_dung)

	var results := {
		"open": await _test_open(),
		"corner": await _test_corner(),
		"pincer": await _test_pincer(),
		"dash": await _test_dash(),
		"drop": await _test_drop(),
		"stunned": await _test_stunned(),
		"static": await _test_static(),
	}
	var ok := true
	for key in results:
		ok = ok and results[key]
	for line in _report:
		print(line)
	print("[flee_check] result=", ("PASS" if ok else "FAIL"), " ", results)
	get_tree().quit(0 if ok else 1)


func _test_open() -> bool:
	var pk := _pickup(Vector3(-4, 0, 0))
	var c := _chaser(0, Vector3(-9, 0, 0), pk)
	var caught := await _run_until_caught(pk, 5.0)
	_report.append("  [open] caught_at=%.2fs (計測のみ)" % caught)
	_cleanup([c, pk])
	await _frames(2)
	return true


func _test_corner() -> bool:
	var pk := _pickup(Vector3(15.5, 0, 9.5))
	var c := _chaser(0, Vector3(10, 0, 4), pk)
	var caught := await _run_until_caught(pk, 5.0)
	_report.append("  [corner] caught_at=%.2fs" % caught)
	_cleanup([c, pk])
	await _frames(2)
	return caught >= 0.0


func _test_pincer() -> bool:
	var pk := _pickup(Vector3(0, 0, 10))
	var a := _chaser(0, Vector3(-6, 0, 8), pk)
	var b := _chaser(1, Vector3(6, 0, 8), pk)
	var caught := await _run_until_caught(pk, 5.0)
	_report.append("  [pincer] caught_at=%.2fs" % caught)
	_cleanup([a, b, pk])
	await _frames(2)
	return caught >= 0.0


## 溜めながらじわじわ近づき、最大溜めで離す。突進中も相手へ曲げる。
func _test_dash() -> bool:
	var pk := _pickup(Vector3(-6, 0, 0))
	var c := _chaser(0, Vector3(-12, 0, 0), pk)
	await _frames(2)
	c.want_dash = true
	c._start_dash()
	await get_tree().create_timer(Config.balance.dash_charge_time).timeout
	c.want_dash = false
	var caught := await _run_until_caught(pk, 1.5)
	_report.append("  [dash] caught_after_release=%.2fs" % caught)
	_cleanup([c, pk])
	await _frames(2)
	return caught >= 0.0


## 被弾で落ちたフンは猶予なく逃げる(本人はスタン中なので怖がらない。近くの攻撃側から逃げる)。
func _test_drop() -> bool:
	var victim := _chaser(1, Vector3(0, 0, 0), null)
	var attacker := _chaser(0, Vector3(-2.5, 0, 0), null)
	attacker.chase = false
	victim.chase = false
	victim.size = 8.0
	victim._apply_size_visual()
	await _frames(2)
	victim.drop_and_stun()
	await _frames(1)
	# 攻撃側が止まっている時の驚き範囲⓪に入っているフンだけが対象(遠くに散ったフンは逃げなくてよい)
	var start := {}
	for child in _dung.get_children():
		if child is DungPickup:
			var pk := child as DungPickup
			var edge := pk.global_position.distance_to(attacker.global_position) - attacker.body_radius() - pk._radius()
			if edge < Config.balance.flee_idle_alert_radius - 0.5:
				start[pk] = pk.global_position
	await _frames(2)
	# 散らばり方は乱数なので、攻撃側のすぐ横に落ちてそのまま回収されたフンは数えない
	var remaining := 0
	var reacted := 0
	for pk in start:
		if is_instance_valid(pk) and not (pk as DungPickup).is_queued_for_deletion():
			remaining += 1
			if (pk as DungPickup)._state != DungPickup.FleeState.IDLE:
				reacted += 1
	_report.append("  [drop] near_attacker=%d remaining=%d surprised=%d" % [start.size(), remaining, reacted])
	_cleanup([victim, attacker])
	for child in _dung.get_children():
		child.queue_free()
	await _frames(2)
	return reacted == remaining


func _test_stunned() -> bool:
	var pk := _pickup(Vector3(0, 0, -5))
	var c := _chaser(0, Vector3(0, 0, -7.5), pk)
	c.chase = false
	c._enter_stun() # フンが気付く前(最初の物理フレームより前)にスタンさせる
	c._stun_t = 10.0
	var start := pk.global_position
	await get_tree().create_timer(Config.balance.flee_surprise_time + 0.5).timeout
	var still := pk.global_position.distance_to(start) < 0.05 and pk._state == DungPickup.FleeState.IDLE
	_report.append("  [stunned] dung_moved=%.2fm dung_state=%d" % [pk.global_position.distance_to(start), pk._state])
	_cleanup([c, pk])
	await _frames(2)
	return still


func _test_static() -> bool:
	var start := Vector3(0, 0, -6)
	var pk := DungPickup.create(Config.balance.flee_static_max_size)
	pk.position = start
	_dung.add_child(pk)
	var c := _chaser(0, Vector3(-3, 0, -6), pk)
	c.chase = false
	await get_tree().create_timer(1.0).timeout
	var body := pk.get_node("Body") as MeshInstance3D
	var still := pk.global_position.distance_to(start) < 0.01
	var sphere := body.mesh is SphereMesh
	var is_static := pk.is_static()
	_report.append("  [static] still=%s sphere=%s" % [still, sphere])
	_cleanup([c, pk])
	await _frames(2)
	return is_static and still and sphere


func _pickup(pos: Vector3) -> DungPickup:
	var pk := DungPickup.create(1.0)
	pk.position = pos
	_dung.add_child(pk)
	return pk


func _chaser(pid: int, pos: Vector3, target: Node3D) -> Chaser:
	var c := Chaser.new()
	c.player_id = pid
	c.input_device = 9999
	c.target = target
	c.position = pos # 原点で一瞬フンに重なって回収しないよう、追加前に置く
	add_child(c)
	return c


## 回収されたら経過秒、時間内に回収されなければ -1。
func _run_until_caught(pk: DungPickup, limit: float) -> float:
	var t := 0.0
	while t < limit:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not is_instance_valid(pk) or pk.is_queued_for_deletion():
			return t
	return -1.0


func _cleanup(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			if n is Player:
				(n as Player).stop_gameplay()
			n.queue_free()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
