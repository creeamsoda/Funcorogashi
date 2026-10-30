extends Node3D
## 突進判定の headless 自動テスト(操作不要):
##  命中(相手ドロップ・自分無傷)/ 壁激突(既定はスタンのみ)/ 相打ち(両者ドロップ)/ 溜め / 曲げ
## プレイヤーの facing を設定して _start_dash() を直接呼び、結果を検証する。
## 入力なし(待機デバイス)なので、_start_dash() 後は最低溜めで自動的に発動する。

var _dung: Node3D

func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate()) # 壁(group "wall")
	_dung = Node3D.new()
	_dung.add_to_group("dung_container")
	add_child(_dung)

	var r_hit := await _test_hit()
	var r_wall := await _test_wall()
	var r_mutual := await _test_mutual()
	var r_loss := await _test_drop_loss()
	var r_vibration_routing := await _test_shared_device_vibration_routing()
	var r_audio := await _test_dash_audio()
	var r_charge := await _test_charge()
	var r_steer := await _test_steer()
	var r_size := await _test_size_effects()

	var ok := r_hit and r_wall and r_mutual and r_loss and r_vibration_routing and r_audio \
		and r_charge and r_steer and r_size
	print("[dash_check] result=", ("PASS" if ok else "FAIL"),
		"  hit=", r_hit, " wall=", r_wall, " mutual=", r_mutual,
		" drop_loss=", r_loss, " vibration_routing=", r_vibration_routing,
		" audio=", r_audio, " charge=", r_charge, " steer=", r_steer, " size=", r_size)
	get_tree().quit(0 if ok else 1)


func _test_hit() -> bool:
	var atk := _mk(0, Vector3(0, 0, 0), Vector3(1, 0, 0))
	var vic := _mk(1, Vector3(3, 0, 0), Vector3(-1, 0, 0))
	await _frames(2)
	var vic0: float = vic.size
	var atk0: float = atk.size
	var dc0: int = _dung.get_child_count()
	var got := {"hit": false}
	var vibrations := {"attacker": 0, "victim": 0}
	atk.dash_hit.connect(func(_a: int, _v: int) -> void: got["hit"] = true)
	atk.vibration_requested.connect(func(_pid: int) -> void: vibrations["attacker"] += 1)
	vic.vibration_requested.connect(func(_pid: int) -> void: vibrations["victim"] += 1)
	atk.facing = Vector3(1, 0, 0)
	atk._start_dash()
	await _seconds(0.9)
	# 攻撃側は無傷(自分はドロップしない=size減らない。相手の落としたフンを回収して増えるのは仕様どおり)
	var hit_se_playing: bool = (atk.get_node("HitSE") as AudioStreamPlayer).playing
	var ok: bool = got["hit"] and vic.size < vic0 and atk.size >= atk0 - 0.0001 \
		and vic.state == Player.State.STUNNED and _dung.get_child_count() > dc0 \
		and vibrations["attacker"] == 0 and vibrations["victim"] == 1 and hit_se_playing
	print("  [hit] atk ", atk0, "->", atk.size, " vic ", vic0, "->", vic.size,
		" vic_state=", vic.state, " dashHit=", got["hit"], " vibration=", vibrations,
		" hit_se=", hit_se_playing)
	_free([atk, vic])
	await _frames(2)
	return ok


## 壁激突は既定でスタンのみ(サイズ不変・ドロップなし)。wall_crash_drops=true で従来どおり落とす。
func _test_wall() -> bool:
	var stun_only := await _wall_crash(false)
	var drops := await _wall_crash(true)
	return stun_only and drops


func _wall_crash(drops_enabled: bool) -> bool:
	var old_flag: bool = Config.balance.wall_crash_drops
	Config.balance.wall_crash_drops = drops_enabled
	var p := _mk(0, Vector3(14, 0, 0), Vector3(1, 0, 0))
	await _frames(2)
	var s0: float = p.size
	var dc0: int = _dung.get_child_count()
	var vibrations := {"count": 0}
	p.vibration_requested.connect(func(_pid: int) -> void: vibrations["count"] += 1)
	p.facing = Vector3(1, 0, 0)
	p._start_dash()
	await _seconds(0.9)
	var wall_se_playing: bool = (p.get_node("WallHitSE") as AudioStreamPlayer).playing
	var size_ok: bool = p.size < s0 if drops_enabled else is_equal_approx(p.size, s0) and _dung.get_child_count() == dc0
	var ok: bool = size_ok and p.state == Player.State.STUNNED \
		and vibrations["count"] == 1 and wall_se_playing
	print("  [wall drops=", drops_enabled, "] size ", s0, "->", p.size, " state=", p.state,
		" vibration=", vibrations["count"], " wall_se=", wall_se_playing)
	Config.balance.wall_crash_drops = old_flag
	_free([p])
	await _frames(2)
	return ok


## 溜め: 押している間は発動せず、離すと発動。溜め量で速度・継続時間が下限〜上限に補間される。
## 最低溜め前に離しても最低溜めまで待ち、押し続けると hold_max 後に自動発動する。
func _test_charge() -> bool:
	var b := Config.balance
	var p := _mk(0, Vector3(-15, 0, -9), Vector3(1, 0, 0))
	p.set_physics_process(false)
	await _frames(2)
	var dt := 1.0 / 60.0

	p._start_dash()
	p._process_charging(dt, false)
	var waits_for_min := p.state == Player.State.DASH_CHARGING
	while p.state == Player.State.DASH_CHARGING:
		p._process_charging(dt, false)
	var min_ok := p.state == Player.State.DASHING \
		and is_equal_approx(p._dash_speed, b.dash_speed_min) and is_equal_approx(p._dash_duration, b.dash_duration_min)

	p._end_dash()
	p._start_dash()
	var held_frames := 0
	while held_frames < int(b.dash_charge_time / dt) + 2:
		p._process_charging(dt, true)
		held_frames += 1
	var held_keeps_charging := p.state == Player.State.DASH_CHARGING
	p._process_charging(dt, false)
	var max_ok := p.state == Player.State.DASHING \
		and is_equal_approx(p._dash_speed, b.dash_speed_max) and is_equal_approx(p._dash_duration, b.dash_duration_max)

	p._end_dash()
	p._start_dash()
	p._charge_t = b.dash_charge_time + b.dash_charge_hold_max
	p._process_charging(dt, true)
	var auto_release := p.state == Player.State.DASHING

	var mid := b.dash_charge_ratio((b.dash_charge_min + b.dash_charge_time) * 0.5)
	var ratio_ok := b.dash_charge_ratio(0.0) == 0.0 and b.dash_charge_ratio(b.dash_charge_time) == 1.0 \
		and mid > 0.0 and mid < 1.0

	var ok := waits_for_min and min_ok and held_keeps_charging and max_ok and auto_release and ratio_ok
	print("  [charge] waits_min=", waits_for_min, " min=", min_ok, " held=", held_keeps_charging,
		" max=", max_ok, " auto=", auto_release, " ratio=", ratio_ok)
	_free([p])
	await _frames(2)
	return ok


## 突進中の曲げは旋回上限(度/秒)まで。最大溜めは最小溜めより曲がりにくい。減速後に止まる。
class SteerPlayer extends Player:
	var stick := Vector2.ZERO
	func _read_move() -> Vector2:
		return stick


func _test_steer() -> bool:
	var b := Config.balance
	var p := SteerPlayer.new()
	p.player_id = 0
	p.input_device = 9999
	add_child(p)
	p.global_position = Vector3(-15, 0, 0)
	p.set_physics_process(false)
	await _frames(2)
	var dt := 1.0 / 60.0

	var turned := {}
	for label in ["min", "max"]:
		p.global_position = Vector3(-15, p.body_radius(), 0)
		p.facing = Vector3(1, 0, 0)
		p.stick = Vector2.ZERO
		p._start_dash()
		p._charge_t = b.dash_charge_min if label == "min" else b.dash_charge_time
		p._process_charging(dt, false)
		p.stick = Vector2(0, 1) # 真横(+Z)へ曲げたい
		p._process_dashing(0.1)
		turned[label] = rad_to_deg(Vector3(1, 0, 0).angle_to(p._dash_dir))
		p._end_dash()
	var min_ok := absf(turned["min"] - b.dash_turn_rate * 0.1) < 0.5
	var max_ok := absf(turned["max"] - b.dash_turn_rate_at_max * 0.1) < 0.5

	p.global_position = Vector3(-15, p.body_radius(), 0)
	p.facing = Vector3(1, 0, 0)
	p.stick = Vector2.ZERO
	p._start_dash()
	p._process_charging(b.dash_charge_min, false)
	var steps := 0
	while p.state == Player.State.DASHING and steps < 600:
		p._process_dashing(dt)
		steps += 1
	var stops := p.state == Player.State.ROLLING \
		and absf(steps * dt - (b.dash_duration_min + b.dash_end_decel_time)) < dt * 2.0

	var ok := min_ok and max_ok and stops
	print("  [steer] turned_min=", snappedf(turned["min"], 0.1), " turned_max=", snappedf(turned["max"], 0.1),
		" stops_after=", snappedf(steps * dt, 0.01), "s ok=", min_ok, "/", max_ok, "/", stops)
	_free([p])
	await _frames(2)
	return ok


func _test_mutual() -> bool:
	var a := _mk(0, Vector3(-2, 0, 0), Vector3(1, 0, 0))
	var b := _mk(1, Vector3(2, 0, 0), Vector3(-1, 0, 0))
	await _frames(2)
	var a0: float = a.size
	var b0: float = b.size
	var vibrations := {"a": 0, "b": 0}
	a.vibration_requested.connect(func(_pid: int) -> void: vibrations["a"] += 1)
	b.vibration_requested.connect(func(_pid: int) -> void: vibrations["b"] += 1)
	a.facing = Vector3(1, 0, 0)
	b.facing = Vector3(-1, 0, 0)
	a._start_dash()
	b._start_dash()
	await _seconds(0.9)
	var hit_se_playing: bool = (a.get_node("HitSE") as AudioStreamPlayer).playing \
		or (b.get_node("HitSE") as AudioStreamPlayer).playing
	var ok: bool = a.size < a0 and b.size < b0 \
		and a.state == Player.State.STUNNED and b.state == Player.State.STUNNED \
		and vibrations["a"] == 1 and vibrations["b"] == 1 and hit_se_playing
	print("  [mutual] a ", a0, "->", a.size, " b ", b0, "->", b.size,
		" states=", a.state, "/", b.state, " vibration=", vibrations,
		" hit_se=", hit_se_playing)
	_free([a, b])
	await _frames(2)
	return ok


func _test_drop_loss() -> bool:
	for child in _dung.get_children():
		child.queue_free()
	await _frames(2)
	var old_drop_ratio: float = Config.balance.drop_ratio
	var old_loss_ratio: float = Config.balance.drop_loss_ratio
	var old_count: int = Config.balance.drop_scatter_count
	Config.balance.drop_ratio = 0.5
	Config.balance.drop_loss_ratio = 0.25
	Config.balance.drop_scatter_count = 4
	var p := _mk(0, Vector3.ZERO, Vector3(1, 0, 0))
	await _frames(2)
	p.size = 8.0
	p._apply_size_visual()
	p.drop_and_stun()
	await _frames(2)
	var ground_total := 0.0
	for child in _dung.get_children():
		if child is DungPickup:
			ground_total += (child as DungPickup).size
	var ok := is_equal_approx(p.size, 4.0) and is_equal_approx(ground_total, 3.0)
	print("  [drop_loss] player=", p.size, " ground=", ground_total,
		" permanently_lost=", 8.0 - p.size - ground_total)
	Config.balance.drop_ratio = old_drop_ratio
	Config.balance.drop_loss_ratio = old_loss_ratio
	Config.balance.drop_scatter_count = old_count
	_free([p])
	await _frames(2)
	return ok


## 同じdeviceを共有する一部だけが対象なら抑止し、共有者全員または専有deviceなら許可する。
func _test_shared_device_vibration_routing() -> bool:
	var a := _mk(0, Vector3(-8, 0, 8), Vector3(1, 0, 0))
	var b := _mk(1, Vector3(0, 0, 8), Vector3(1, 0, 0))
	var c := _mk(2, Vector3(8, 0, 8), Vector3(1, 0, 0))
	a.input_device = 42
	b.input_device = 42
	c.input_device = 43
	await _frames(2)

	var routes: Array[bool] = []
	a.vibration_route_resolved.connect(
		func(_device: int, allowed: bool) -> void: routes.append(allowed)
	)
	a._play_impact_vibrations([a])
	var shared_single_suppressed := routes == [false]
	routes.clear()
	a._play_impact_vibrations([a, b])
	var shared_all_allowed := routes == [true]
	routes.clear()
	a._play_impact_vibrations([c])
	var exclusive_allowed := routes == [true]

	var ok := shared_single_suppressed and shared_all_allowed and exclusive_allowed
	print("  [vibration_routing] shared_one=", shared_single_suppressed,
		" shared_all=", shared_all_allowed, " exclusive=", exclusive_allowed)
	_free([a, b, c])
	await _frames(2)
	return ok


## chargeは予備動作中に繰り返し、予備動作終了と同時に停止してdashへ切り替わる。
func _test_dash_audio() -> bool:
	var p := _mk(0, Vector3.ZERO, Vector3(1, 0, 0))
	await _frames(2)
	var charge := p.get_node("ChargeSE") as AudioStreamPlayer
	var dash := p.get_node("DashSE") as AudioStreamPlayer
	var streams_loaded := charge.stream != null and dash.stream != null \
		and (p.get_node("HitSE") as AudioStreamPlayer).stream != null \
		and (p.get_node("WallHitSE") as AudioStreamPlayer).stream != null

	p._start_dash()
	var charge_started := charge.playing
	charge.stop()
	p._on_charge_audio_finished()
	var charge_repeated := charge.playing
	p._charge_t = Config.balance.dash_charge_min
	p._process_charging(0.0, false)
	var switched_to_dash := not charge.playing and dash.playing \
		and p.state == Player.State.DASHING

	p._start_dash()
	p._end_dash()
	var charge_stopped_on_cancel := not charge.playing
	var ok := streams_loaded and charge_started and charge_repeated \
		and switched_to_dash and charge_stopped_on_cancel
	print("  [dash_audio] loaded=", streams_loaded, " charge_start=", charge_started,
		" repeat=", charge_repeated, " dash_switch=", switched_to_dash,
		" charge_stop=", charge_stopped_on_cancel)
	_free([p])
	await _frames(2)
	return ok


## 保有フンが大きいほど移動が遅く、最大溜めまでが長い。開始サイズでは影響なし。下限・上限と無効化(0)も確認。
func _test_size_effects() -> bool:
	var b := Config.balance
	var old := [b.move_speed_size_penalty, b.move_speed_size_min_ratio, b.dash_charge_size_penalty, b.dash_charge_size_max_ratio]
	b.move_speed_size_penalty = 0.05
	b.move_speed_size_min_ratio = 0.5
	b.dash_charge_size_penalty = 0.05
	b.dash_charge_size_max_ratio = 2.0
	var start := b.size_start
	var neutral := is_equal_approx(b.move_speed_scale(start), 1.0) and is_equal_approx(b.charge_time_scale(start), 1.0)
	var mid := is_equal_approx(b.move_speed_scale(start + 10.0), 1.0 / 1.5) and is_equal_approx(b.charge_time_scale(start + 10.0), 1.5)
	var clamped := is_equal_approx(b.move_speed_scale(start + 1000.0), 0.5) and is_equal_approx(b.charge_time_scale(start + 1000.0), 2.0)

	# プレイヤー: 大きいと基本の溜め時間ではまだ最大にならず、延びた時間で最大になる。移動も遅い。
	var p := _mk(0, Vector3(-15, 0, 9), Vector3(1, 0, 0))
	p.set_physics_process(false)
	await _frames(2)
	p.size = start + 10.0
	var slower := is_equal_approx(p._move_speed(), b.move_speed_base / 1.5)
	var dt := 1.0 / 60.0
	p._start_dash()
	while p._charge_t < b.dash_charge_time:
		p._process_charging(dt, true)
	var not_full_yet := p.state == Player.State.DASH_CHARGING and p._charge_ratio() < 0.9
	while p._charge_t < b.dash_charge_time * 1.5:
		p._process_charging(dt, true)
	var full_later := is_equal_approx(p._charge_ratio(), 1.0)
	p._process_charging(dt, false)
	var max_dash := is_equal_approx(p._dash_speed, b.dash_speed_max)

	b.move_speed_size_penalty = 0.0
	b.dash_charge_size_penalty = 0.0
	var disabled := is_equal_approx(b.move_speed_scale(start + 50.0), 1.0) and is_equal_approx(b.charge_time_scale(start + 50.0), 1.0)
	b.move_speed_size_penalty = old[0]
	b.move_speed_size_min_ratio = old[1]
	b.dash_charge_size_penalty = old[2]
	b.dash_charge_size_max_ratio = old[3]
	var ok := neutral and mid and clamped and slower and not_full_yet and full_later and max_dash and disabled
	print("  [size] neutral=", neutral, " mid=", mid, " clamped=", clamped, " slower=", slower,
		" not_full_at_base_time=", not_full_yet, " full_later=", full_later, " max_dash=", max_dash, " disabled=", disabled)
	_free([p])
	await _frames(2)
	return ok


func _mk(pid: int, pos: Vector3, face: Vector3) -> Player:
	var p: Player = (load("res://scenes/Player.tscn") as PackedScene).instantiate()
	p.player_id = pid
	p.input_device = 9999 # 待機(自動入力なし)
	add_child(p)
	p.global_position = pos
	p.facing = face
	return p


func _free(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			for child in n.get_children():
				if child is AudioStreamPlayer:
					(child as AudioStreamPlayer).stop()
			n.queue_free()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _seconds(t: float) -> void:
	await get_tree().create_timer(t).timeout
