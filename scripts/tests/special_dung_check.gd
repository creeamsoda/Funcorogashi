extends Node3D
## 特殊フン(ブラックホール・高速)の headless 自動テスト。
##  collect  : 回収するとそれぞれの効果が付き、効果時間①で切れる
##  pull     : ブラックホール中は範囲②内のフンが速度③で寄ってきて回収され、範囲外は寄らない
##  speed    : 高速中は保有フンが大きくても移動速度が④
##  small    : 特殊フンは小さくても逃げる(球にならない)
##  pincer   : 左右から挟まれた特殊フンは横(上下)へ逃げる
##  wall     : 壁際で壁と反対側から追われた特殊フンは、壁へ突っ込まず壁沿いへ逃げる
##  visual   : 効果中だけ渦巻き/上昇線が出る
##  no_pull  : ブラックホールは特殊フンを引き寄せない
##  source   : 特殊フンはオランウータンの投げたフンからだけ出る(鳥・ラプトルのドロップは通常フン)
##  wander   : プレイヤーがいなくても加速フンは止まらず(IDLE・BRAKING にならず)向きを変えながら動き回り、残像を出す。ブラックホールフンは止まったまま
##  cap      : 盤面上の特殊フンが上限(special_max_on_board)に達していれば、確率100%でも通常フンになる

class Dummy extends Player:
	var move := Vector2.ZERO

	func _read_move() -> Vector2:
		return move

	func _dash_input_held() -> bool:
		return false


var _dung: Node3D
var _report: Array[String] = []


func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	_dung = Node3D.new()
	_dung.add_to_group("dung_container")
	add_child(_dung)
	var results := {
		"collect": await _test_collect(),
		"pull": await _test_pull(),
		"speed": await _test_speed(),
		"small": await _test_small(),
		"pincer": await _test_pincer(),
		"wall": await _test_wall(),
		"visual": await _test_visual(),
		"no_pull": await _test_no_pull(),
		"source": await _test_source(),
		"cap": await _test_cap(),
		"wander": await _test_wander(),
	}
	var ok := true
	for key in results:
		ok = ok and results[key]
	for line in _report:
		print(line)
	print("[special_dung_check] result=", ("PASS" if ok else "FAIL"), " ", results)
	get_tree().quit(0 if ok else 1)


func _test_collect() -> bool:
	var b := Config.balance
	var keep_time := b.special_effect_time
	b.special_effect_time = 0.3
	var p := _player(0, Vector3(0, 0, 0))
	var bh := _pickup(Vector3(0, 0, 0.2), DungPickup.Kind.BLACKHOLE)
	var sp := _pickup(Vector3(0, 0, -0.2), DungPickup.Kind.SPEED)
	await _frames(3)
	var got := p.is_blackhole_active() and p.is_speed_boost_active()
	var both_collected := not is_instance_valid(bh) and not is_instance_valid(sp)
	await get_tree().create_timer(0.5).timeout
	var expired := not p.is_blackhole_active() and not p.is_speed_boost_active()
	_report.append("  [collect] got=%s collected=%s expired=%s" % [got, both_collected, expired])
	b.special_effect_time = keep_time
	_cleanup([p])
	await _frames(2)
	return got and both_collected and expired


func _test_pull() -> bool:
	var b := Config.balance
	var p := _player(0, Vector3(0, 0, 0))
	p.apply_special_dung(DungPickup.Kind.BLACKHOLE)
	p._blackhole_t = 100.0
	var reach := p.body_radius() + b.blackhole_radius
	var near := _pickup(Vector3(reach - 1.0, 0, 0), DungPickup.Kind.NORMAL, 0.2) # 小さい(動かない)フンも寄る
	var far := _pickup(Vector3(-(reach + 3.0), 0, 0), DungPickup.Kind.NORMAL, 0.2)
	var far_start := far.global_position
	await _frames(2)
	var x0 := near.global_position.x
	await _frames(6)
	var dt := 6.0 / Engine.physics_ticks_per_second
	var speed := (x0 - near.global_position.x) / dt if is_instance_valid(near) else b.blackhole_pull_speed
	await get_tree().create_timer(reach / b.blackhole_pull_speed + 0.5).timeout
	var collected := not is_instance_valid(near)
	var far_still := is_instance_valid(far) and far.global_position.distance_to(far_start) < 0.01
	_report.append("  [pull] speed=%.2f (want %.2f) collected=%s far_still=%s" % [speed, b.blackhole_pull_speed, collected, far_still])
	_cleanup([p, far])
	await _frames(2)
	return absf(speed - b.blackhole_pull_speed) < 0.3 and collected and far_still


func _test_speed() -> bool:
	var b := Config.balance
	var p := _player(0, Vector3(-10, 0, 0))
	p.size = 30.0
	p._apply_size_visual()
	var slow := p._move_speed()
	p.apply_special_dung(DungPickup.Kind.SPEED)
	p.move = Vector2(1, 0)
	await _frames(3)
	var x0 := p.global_position.x
	await _frames(10)
	var measured := (p.global_position.x - x0) / (10.0 / Engine.physics_ticks_per_second)
	_report.append("  [speed] normal=%.2f boosted=%.2f (want %.2f)" % [slow, measured, b.speed_boost_move_speed])
	_cleanup([p])
	await _frames(2)
	return absf(measured - b.speed_boost_move_speed) < 0.3 and slow < b.speed_boost_move_speed


func _test_small() -> bool:
	var pk := _pickup(Vector3(0, 0, 0), DungPickup.Kind.SPEED, 0.1)
	await _frames(2)
	var ok := not pk.is_static() and not ((pk.get_node("Body") as MeshInstance3D).mesh is SphereMesh)
	_report.append("  [small] static=%s" % pk.is_static())
	_cleanup([pk])
	await _frames(2)
	return ok


func _test_pincer() -> bool:
	var pk := _pickup(Vector3(0, 0, 0), DungPickup.Kind.BLACKHOLE)
	var a := _player(0, Vector3(-2.5, 0, 0))
	var c := _player(1, Vector3(2.5, 0, 0))
	var start := pk.global_position
	await get_tree().create_timer(Config.balance.special_flee_surprise_time + 0.3).timeout
	var moved := pk.global_position - start
	var ok := absf(moved.z) > 1.0 and absf(moved.x) < absf(moved.z) * 0.5
	_report.append("  [pincer] moved=(%.2f, %.2f)" % [moved.x, moved.z])
	_cleanup([pk, a, c])
	await _frames(2)
	return ok


func _test_wall() -> bool:
	# 上の外壁(z = -HALF_Z)の少し手前。プレイヤーは反対側(+Z)から近づく。
	var z := -Stage.HALF_Z + 2.0
	var pk := _pickup(Vector3(0, 0, z), DungPickup.Kind.SPEED)
	var p := _player(0, Vector3(0, 0, z + 3.0))
	var start := pk.global_position
	await get_tree().create_timer(Config.balance.special_flee_surprise_time + 0.3).timeout
	var moved := pk.global_position - start
	var wall_surprised := pk._wall_surprise
	var ok := absf(moved.x) > 1.0 and absf(moved.x) > absf(moved.z) * 2.0
	_report.append("  [wall] moved=(%.2f, %.2f) wall_surprise=%s" % [moved.x, moved.z, wall_surprised])
	_cleanup([pk, p])
	await _frames(2)
	return ok


func _test_visual() -> bool:
	var p := _player(0, Vector3(0, 0, 8))
	await _frames(2)
	var swirl := p.get_node("BlackholeSwirl") as EffectPlayer
	var rise := p.get_node("SpeedBoostLines") as DashSpeedLines
	var off := not swirl.is_active() and not rise.emitting
	p.apply_special_dung(DungPickup.Kind.BLACKHOLE)
	p.apply_special_dung(DungPickup.Kind.SPEED)
	await _frames(3)
	var on := swirl.is_active() and rise.emitting
	_report.append("  [visual] off_before=%s on_during=%s" % [off, on])
	_cleanup([p])
	await _frames(2)
	return off and on


func _test_no_pull() -> bool:
	var keep_flee := Config.balance.flee_enabled
	Config.balance.flee_enabled = false # 逃げによる移動と区別するため
	var p := _player(0, Vector3(0, 0, 0))
	p._blackhole_t = 100.0
	var reach := p.body_radius() + Config.balance.blackhole_radius
	var sp := _pickup(Vector3(reach - 1.0, 0, 0), DungPickup.Kind.BLACKHOLE)
	var start := sp.global_position
	await _frames(20)
	var still := is_instance_valid(sp) and sp.global_position.distance_to(start) < 0.01
	_report.append("  [no_pull] special_still=%s" % still)
	Config.balance.flee_enabled = keep_flee
	_cleanup([p, sp])
	await _frames(2)
	return still


func _test_source() -> bool:
	var b := Config.balance
	var keep := b.special_blackhole_chance
	b.special_blackhole_chance = 1.0
	var bird := Animal.new()
	add_child(bird)
	bird.drop_pickup(Vector3(5, 0, 5), 1.0)
	var thrown := ThrownDung.create(Vector3(-5, 0.6, 5), Vector3(-5, 0, 6), 1.0)
	_dung.add_child(thrown)
	thrown._land()
	await _frames(1)
	var kinds := []
	for child in _dung.get_children():
		if child is DungPickup:
			kinds.append((child as DungPickup).kind)
	var ok := kinds.size() == 2 and kinds.count(DungPickup.Kind.NORMAL) == 1 and kinds.count(DungPickup.Kind.BLACKHOLE) == 1
	_report.append("  [source] kinds=%s (動物ドロップ1・投擲1)" % [kinds])
	b.special_blackhole_chance = keep
	bird.queue_free()
	for child in _dung.get_children():
		child.queue_free()
	await _frames(2)
	return ok


func _test_cap() -> bool:
	var b := Config.balance
	var keep := b.special_blackhole_chance
	b.special_blackhole_chance = 1.0
	var made: Array[DungPickup] = []
	for i in b.special_max_on_board + 2:
		var pk := DungPickup.create(1.0)
		pk.kind = DungPickup.roll_kind(self)
		pk.position = Vector3(-12 + i * 3.0, 0, -6)
		_dung.add_child(pk)
		made.append(pk)
	var on_board := DungPickup.count_special_on_board(get_tree())
	# 1つ回収されたら(消える途中でも)次は特殊フンにできる
	made[0]._collected = true
	var next_kind := DungPickup.roll_kind(self)
	_report.append("  [cap] on_board=%d (max %d) after_collect=%d" % [on_board, b.special_max_on_board, next_kind])
	b.special_blackhole_chance = keep
	for pk in made:
		pk.queue_free()
	await _frames(2)
	return on_board == b.special_max_on_board and next_kind == DungPickup.Kind.BLACKHOLE


func _pickup(pos: Vector3, kind: DungPickup.Kind, sz: float = 1.0) -> DungPickup:
	var pk := DungPickup.create(sz)
	pk.kind = kind
	pk.position = pos
	_dung.add_child(pk)
	return pk


func _player(pid: int, pos: Vector3) -> Dummy:
	var d := Dummy.new()
	d.player_id = pid
	d.input_device = 9999
	d.position = pos
	add_child(d)
	return d


func _cleanup(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			if n is Player:
				(n as Player).stop_gameplay()
			n.queue_free()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _test_wander() -> bool:
	var sp := _pickup(Vector3(0, 0, 0), DungPickup.Kind.SPEED)
	var bh := _pickup(Vector3(0, 0, 6), DungPickup.Kind.BLACKHOLE)
	var bh_start := bh.global_position
	var never_stopped := true
	var turns := 0
	var max_ghosts := 0
	var last_heading := sp._heading
	var t := 0.0
	await _frames(1)
	while t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > 0.1:
			never_stopped = never_stopped and sp._state != DungPickup.FleeState.IDLE and sp._state != DungPickup.FleeState.BRAKING
		if sp._heading.angle_to(last_heading) > deg_to_rad(10.0):
			turns += 1
		last_heading = sp._heading
		max_ghosts = maxi(max_ghosts, sp.get_node("Afterimage").get_child_count())
	var bh_still := bh.global_position.distance_to(bh_start) < 0.05 and bh._state == DungPickup.FleeState.IDLE
	_report.append("  [wander] never_stopped=%s turns=%d ghosts=%d blackhole_still=%s" % [never_stopped, turns, max_ghosts, bh_still])
	_cleanup([sp, bh])
	await _frames(2)
	return never_stopped and turns >= 2 and max_ghosts > 0 and bh_still
