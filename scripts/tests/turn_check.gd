extends Node3D
## 向きのある逃走(Phase 2b)の headless 単体テスト。進みたい方向を直接与えて _update_motion を回す:
##  rate   : 旋回速度は止まっている時が最速、flee_speed で at_speed になる
##  small  : 小さい角度は減速最小限で曲がる
##  sharp  : 大きい角度は減速して回り、向きが合ったら再加速する
##  hold   : 中くらいの角度は最後の回転から hold_time まで直進し、その後曲がる
##  stopped: 止まっている時は回ってから進み出す

const DT := 1.0 / 60.0

var _failures: Array[String] = []


func _ready() -> void:
	var pk := DungPickup.create(1.0)
	add_child(pk)
	pk.set_physics_process(false)
	await get_tree().process_frame
	_test_rate(pk)
	_test_small(pk)
	_test_sharp(pk)
	_test_hold(pk)
	_test_stopped(pk)
	print("[turn_check] result=", ("PASS" if _failures.is_empty() else "FAIL"), " failures=", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_rate(pk: DungPickup) -> void:
	var b := Config.balance
	pk._speed = 0.0
	var stopped := pk.turn_rate()
	pk._speed = b.flee_speed
	var full := pk.turn_rate()
	pk._speed = b.flee_speed * 0.5
	var half := pk.turn_rate()
	print("  [rate] stopped=%.0f half=%.0f full=%.0f" % [stopped, half, full])
	if not (is_equal_approx(stopped, b.flee_turn_rate_stopped) and is_equal_approx(full, b.flee_turn_rate_at_speed)
			and half < stopped and half > full):
		_failures.append("rate")


func _test_small(pk: DungPickup) -> void:
	var b := Config.balance
	var angle := b.flee_small_turn_angle * 0.6
	_reset(pk, b.flee_speed, angle, INF)
	var min_speed := pk._speed
	var modes := {}
	for _i in int(0.5 / DT):
		pk._update_motion(DT)
		min_speed = minf(min_speed, pk._speed)
		modes[pk._mode] = true
	var aligned := rad_to_deg(pk._heading.angle_to(pk._target_dir)) <= 1.0
	print("  [small] min_speed=%.2f/%.2f aligned=%s" % [min_speed, b.flee_speed, aligned])
	if not (DungPickup.TurnMode.SMALL_TURN in modes and not DungPickup.TurnMode.SHARP_TURN in modes
			and min_speed >= b.flee_speed * b.flee_small_turn_speed_ratio - 0.01 and aligned):
		_failures.append("small")


func _test_sharp(pk: DungPickup) -> void:
	var b := Config.balance
	_reset(pk, b.flee_speed, 150.0, INF)
	pk._update_motion(DT)
	var entered := pk._mode == DungPickup.TurnMode.SHARP_TURN
	var min_speed := pk._speed
	var t := 0.0
	while pk._mode == DungPickup.TurnMode.SHARP_TURN and t < 3.0:
		pk._update_motion(DT)
		min_speed = minf(min_speed, pk._speed)
		t += DT
	var turn_time := t
	var reset_turn := pk._since_turn < DT * 2.0
	for _i in int(1.0 / DT):
		pk._update_motion(DT)
	var reaccelerated := pk._speed > b.flee_speed * 0.8
	print("  [sharp] entered=%s min_speed=%.2f turn_time=%.2fs reaccel_speed=%.2f" % [entered, min_speed, turn_time, pk._speed])
	if not (entered and min_speed <= b.flee_sharp_turn_min_speed + 0.3 and turn_time < 3.0 and reset_turn and reaccelerated):
		_failures.append("sharp")


func _test_hold(pk: DungPickup) -> void:
	var b := Config.balance
	var angle := (b.flee_small_turn_angle + b.flee_sharp_turn_angle) * 0.5
	_reset(pk, b.flee_speed, angle, 0.0)
	var start_heading := pk._heading
	var held := true
	var t := 0.0
	while t < b.flee_turn_hold_time - DT * 2.0:
		pk._update_motion(DT)
		held = held and pk._mode == DungPickup.TurnMode.HOLD and pk._heading.is_equal_approx(start_heading)
		t += DT
	var turned := false
	for _i in int(0.3 / DT):
		pk._update_motion(DT)
		turned = turned or pk._mode == DungPickup.TurnMode.MID_TURN
	var moved := not pk._heading.is_equal_approx(start_heading)
	print("  [hold] held_until=%.2fs turned_after=%s heading_changed=%s" % [t, turned, moved])
	if not (held and turned and moved):
		_failures.append("hold")


func _test_stopped(pk: DungPickup) -> void:
	var b := Config.balance
	_reset(pk, 0.0, 120.0, INF)
	var stayed_slow := true
	var t := 0.0
	while rad_to_deg(pk._heading.angle_to(pk._target_dir)) >= b.flee_small_turn_angle and t < 2.0:
		pk._update_motion(DT)
		stayed_slow = stayed_slow and pk._speed <= maxf(b.flee_sharp_turn_min_speed, 0.0) + 0.001
		t += DT
	for _i in int(0.5 / DT):
		pk._update_motion(DT)
	print("  [stopped] turn_in_place=%.2fs stayed_slow=%s speed_after=%.2f" % [t, stayed_slow, pk._speed])
	if not (stayed_slow and t < 2.0 and pk._speed > 1.0):
		_failures.append("stopped")


## 向き +Z、進みたい方向を angle 度だけ回した状態にする。
func _reset(pk: DungPickup, speed: float, angle: float, since_turn: float) -> void:
	pk._heading = Vector3.BACK
	pk._target_dir = Vector3.BACK.rotated(Vector3.UP, deg_to_rad(angle))
	pk._speed = speed
	pk._urgency = 1.0
	pk._mode = DungPickup.TurnMode.CRUISE
	pk._since_turn = since_turn
