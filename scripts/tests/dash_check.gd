extends Node3D
## 突進判定の headless 自動テスト(操作不要):
##  命中(相手ドロップ・自分無傷)/ 自滅(壁で自分ドロップ)/ 相打ち(両者ドロップ)
## プレイヤーの facing を設定して _start_dash() を直接呼び、結果を検証する。

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

	var ok := r_hit and r_wall and r_mutual and r_loss and r_vibration_routing and r_audio
	print("[dash_check] result=", ("PASS" if ok else "FAIL"),
		"  hit=", r_hit, " self_crash=", r_wall, " mutual=", r_mutual,
		" drop_loss=", r_loss, " vibration_routing=", r_vibration_routing,
		" audio=", r_audio)
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


func _test_wall() -> bool:
	var p := _mk(0, Vector3(10, 0, 0), Vector3(1, 0, 0))
	await _frames(2)
	var s0: float = p.size
	var vibrations := {"count": 0}
	p.vibration_requested.connect(func(_pid: int) -> void: vibrations["count"] += 1)
	p.facing = Vector3(1, 0, 0)
	p._start_dash()
	await _seconds(0.9)
	var wall_se_playing: bool = (p.get_node("WallHitSE") as AudioStreamPlayer).playing
	var ok: bool = p.size < s0 and p.state == Player.State.STUNNED \
		and vibrations["count"] == 1 and wall_se_playing
	print("  [wall] size ", s0, "->", p.size, " state=", p.state,
		" vibration=", vibrations["count"], " wall_se=", wall_se_playing)
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
	p._windup_t = 0.0
	p._process_windup(0.0)
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
