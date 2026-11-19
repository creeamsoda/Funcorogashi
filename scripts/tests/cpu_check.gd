extends Node3D
## CPU(CpuBeetle / CpuBrain / CpuDashModel)の headless 自動テスト(操作不要)。
##  scripted : 台本どおりの仮想入力で、CPUが人間と同じように移動・溜め・突進・被弾する(C2)
##  predict  : 溜め時間⇔届く距離の予測が実際の突進とほぼ一致する(C3)
##  inverse  : 距離→溜め時間→距離 が往復で一致する(C3)
##  sense    : 壁までの距離・通り道の判定・先読み位置(C3)
##  solo     : 「ひとりで遊ぶ」で人間1人+CPU3体が生成され、CPUは入力割り当て・振動から外れる(C2)
##  results  : 結果にCPUの印が付き、結果画面に「CPU」の名札が出る(C2)
##  evade    : 自分を狙って溜める相手に気づき、直角方向へ短い突進で避ける(C5)
##  attack   : 止まっている相手へ突進を当てる(C5)

var _failures: Array[String] = []
var _dung: Node3D


func _ready() -> void:
	Config.balance.dash_accel_time = 0.15
	Config.balance.stage_layout = 0 # 障害物なしの広場
	await _test_solo_setup()
	add_child(_open_stage())
	_dung = Node3D.new()
	_dung.add_to_group("dung_container")
	add_child(_dung)
	await _frames(2)
	await _test_scripted()
	await _test_predict()
	_test_inverse()
	await _test_sense()
	await _test_evade()
	await _test_attack()
	await _test_results_tag()
	print("[cpu_check] result=", "PASS" if _failures.is_empty() else "FAIL", " failures=", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _open_stage() -> Stage:
	var stage := load("res://scenes/Stage.tscn").instantiate() as Stage
	stage.layout = Stage.load_layout(0)
	return stage


## C2: 台本の入力で移動 → 溜め → 突進 → 人間の突進で被弾。
func _test_scripted() -> void:
	var cpu := _cpu(Vector3(-6, 0, 0))
	cpu.set_scripted_input(Vector2(1, 0), false)
	var start := cpu.global_position
	await _physics(30)
	var moved := cpu.global_position.x - start.x
	_expect(moved > 2.0 and absf(cpu.global_position.z) < 0.05, "scripted move right (moved=%.2f)" % moved)
	_expect(cpu.facing.is_equal_approx(Vector3.RIGHT), "scripted facing")
	cpu.set_scripted_input(Vector2.ZERO, true)
	await _physics(2)
	_expect(cpu.state == Player.State.DASH_CHARGING, "scripted press starts charge")
	await _physics(20)
	cpu.set_scripted_input(Vector2.ZERO, false)
	await _physics(2)
	_expect(cpu.state == Player.State.DASHING, "scripted release launches dash")
	await _physics(80)
	_expect(cpu.state == Player.State.ROLLING, "dash ends")

	# 人間の突進を受けてドロップ+スタン
	cpu.set_scripted_input(Vector2.ZERO, false)
	cpu.global_position = Vector3(4, cpu.body_radius(), 6)
	var human := _human(Vector3(0.5, 0, 6))
	human.facing = Vector3.RIGHT
	var before := cpu.size
	cpu.add_size(4.0)
	before = cpu.size
	await _physics(2)
	human._start_dash()
	await get_tree().create_timer(0.8).timeout
	_expect(cpu.state == Player.State.STUNNED or cpu.size < before, "CPU takes dash hit (size %.2f -> %.2f)" % [before, cpu.size])
	_expect(cpu.size < before, "CPU drops dung on hit")
	await _cleanup([cpu, human])


## C3: いろいろな溜め時間で、予測の距離と実際に進んだ距離を比べる。
func _test_predict() -> void:
	var worst := 0.0
	for hold: float in [0.15, 0.4, 0.7, 1.0]:
		var cpu := _cpu(Vector3(-15, 0, 0))
		cpu.facing = Vector3.RIGHT
		await _physics(2)
		var start := cpu.global_position
		cpu.set_scripted_input(Vector2.ZERO, true)
		await _physics(1)
		var charge_frames := int(round(hold * Engine.physics_ticks_per_second))
		while cpu.state == Player.State.DASH_CHARGING and cpu._charge_t + 1.0 / Engine.physics_ticks_per_second < hold:
			await get_tree().physics_frame
		cpu.set_scripted_input(Vector2.ZERO, false)
		var used_hold := cpu._charge_t + 1.0 / Engine.physics_ticks_per_second
		while cpu.state != Player.State.DASHING:
			await get_tree().physics_frame
		var launch := cpu.global_position
		while cpu.state == Player.State.DASHING:
			await get_tree().physics_frame
		var actual := CpuSense.flat(cpu.global_position).distance_to(CpuSense.flat(launch))
		var predicted := CpuDashModel.reach_for_hold(used_hold, cpu.size)
		var err := absf(actual - predicted) / predicted
		worst = maxf(worst, err)
		print("  [predict] hold=%.2f(frames %d) predicted=%.2f actual=%.2f err=%.1f%%" % [used_hold, charge_frames, predicted, actual, err * 100.0])
		_expect(err < 0.08, "dash reach prediction hold=%.2f" % hold)
		_expect(start.x <= launch.x + 0.01, "charging does not move backwards")
		await _cleanup([cpu])
	print("  [predict] worst_error=%.1f%%" % (worst * 100.0))


func _test_inverse() -> void:
	for size: float in [1.0, 10.0, 40.0]:
		for dist: float in [5.0, 8.0, 12.0, 16.0]:
			var hold := CpuDashModel.hold_for_reach(dist, size)
			var back := CpuDashModel.reach_for_hold(hold, size)
			var in_range := dist >= CpuDashModel.min_reach(size) and dist <= CpuDashModel.max_reach(size)
			if in_range:
				_expect(absf(back - dist) < 0.05, "inverse reach size=%.0f dist=%.0f (got %.2f)" % [size, dist, back])
			else:
				_expect(back >= dist or is_equal_approx(hold, CpuDashModel.full_hold_time(size)), "inverse clamp size=%.0f dist=%.0f" % [size, dist])
	# 時間⇔距離: 止まるまでの時間で届く距離ちょうど
	var ratio := 0.5
	var reach := CpuDashModel.reach_for_ratio(ratio)
	var t := CpuDashModel.time_to_travel(reach - 0.001, ratio)
	var total := CpuDashModel.duration_for_ratio(ratio) + Config.balance.dash_end_decel_time
	_expect(absf(t - total) < 0.02, "time_to_travel reaches stop time (%.3f vs %.3f)" % [t, total])
	_expect(is_inf(CpuDashModel.time_to_travel(reach + 1.0, ratio)), "time_to_travel beyond reach")


func _test_sense() -> void:
	var cpu := _cpu(Vector3(0, 0, 0))
	cpu.set_scripted_input(Vector2.ZERO, false)
	await _physics(2)
	var sense := cpu.brain.sense
	var d := sense.wall_distance(cpu.global_position, Vector3.RIGHT, 40.0)
	_expect(absf(d - Stage.HALF_X) < 0.2, "wall distance to east wall (%.2f)" % d)
	_expect(sense.clear_path(cpu.global_position, Vector3(10, 0, 5), cpu.body_radius()), "clear path inside arena")
	_expect(not sense.clear_path(cpu.global_position, Vector3(30, 0, 0), cpu.body_radius()), "path through wall is blocked")
	var nearest := sense.nearest_wall(Vector3(0, 0, -10))
	_expect((nearest["dir"] as Vector3).dot(Vector3.FORWARD) > 0.9 and float(nearest["distance"]) < 2.5, "nearest wall north")
	var node := Node3D.new()
	add_child(node)
	node.global_position = Vector3(16, 0, 0)
	var p := CpuSense.predict(node, Vector3(10, 0, 0), 1.0, 0.5)
	_expect(p.x <= Stage.HALF_X - 0.5 + 0.001, "prediction clamped inside arena")
	node.queue_free()
	await _cleanup([cpu])


## C5: 正面で溜める人間に気づいて、直角に短い突進で避ける。
func _test_evade() -> void:
	Config.cpu.reaction_delay = 0.2
	var cpu := _cpu(Vector3(4, 0, 0))
	cpu.profile.aggression = 0.0
	var human := _human(Vector3(-4, 0, 0))
	human.facing = Vector3.RIGHT
	await _physics(30)
	cpu.scripted = false
	var start := cpu.global_position
	cpu.brain.counters["evade_dashes"] = 0
	human._start_dash() # 人間が溜め始める(ボタンは押しっぱなし扱い: 入力デバイス待機なので押していない→最低溜めで発動)
	human.state = Player.State.DASH_CHARGING
	human.set_physics_process(false) # 溜めたまま止めておく
	var evaded := false
	for _i in 60:
		await get_tree().physics_frame
		if cpu.brain.counters["evade_dashes"] > 0:
			evaded = true
	human.set_physics_process(true)
	await _physics(40)
	var side := absf(cpu.global_position.z - start.z)
	_expect(evaded, "CPU starts evade dash")
	_expect(side > 2.0, "CPU moves perpendicular (dz=%.2f)" % side)
	cpu.profile.aggression = 1.0
	await _cleanup([cpu, human])


## C5: 止まっている人間へ攻撃の突進を当てる。
func _test_attack() -> void:
	var cpu := _cpu(Vector3(-6, 0, 3))
	cpu.profile.aim_error_deg = 0.0
	cpu.scripted = false
	var human := _human(Vector3(3, 0, -1))
	human.add_size(10.0)
	human.can_collect = false
	var hits := {"n": 0}
	cpu.dash_hit.connect(func(a: int, _v: int) -> void:
		if a == cpu.player_id:
			hits.n += 1)
	for _i in 300:
		await get_tree().physics_frame
		if hits.n > 0:
			break
	_expect(hits.n > 0, "CPU lands an attack dash on a still target (attack_dashes=%d)" % cpu.brain.counters["attack_dashes"])
	cpu.profile.aim_error_deg = Config.cpu.aim_error_deg
	await _cleanup([cpu, human])


## C2: ひとりで遊ぶ = 人間1人+CPU3体。CPUは "player" に残り、入力は待機。
func _test_solo_setup() -> void:
	var gm: GameManager = (load("res://scenes/Game.tscn") as PackedScene).instantiate()
	gm.mode = "solo"
	add_child(gm)
	await _frames(3)
	var cpus := 0
	var humans := 0
	for p in gm.players:
		if p is CpuBeetle:
			cpus += 1
			_expect(p.is_in_group("player"), "CPU stays in player group")
			_expect(not InputRouter.is_joypad(p.input_device) and not PlayerInput.is_keyboard(p.input_device), "CPU has no input device")
		else:
			humans += 1
	_expect(gm.players.size() == 4 and cpus == 3 and humans == 1, "solo spawns 1 human + 3 CPU (h=%d c=%d)" % [humans, cpus])
	_expect(not (gm.players[0] is CpuBeetle), "P1 is the human")
	var ended := {"results": []}
	gm.match_ended.connect(func(r: Array) -> void: ended.results = r)
	gm.time_left = 0.01
	await _physics(6)
	var cpu_flags := 0
	for r in ended.results:
		if bool(r.get("cpu", false)):
			cpu_flags += 1
	_expect(cpu_flags == 3, "results mark 3 CPUs (results=%s)" % str(ended.results))
	gm.queue_free()
	await _frames(3)


func _test_results_tag() -> void:
	var res := (load("res://scenes/ui/Results.tscn") as PackedScene).instantiate() as Results
	add_child(res)
	res.show_results([
		{"player_id": 0, "size": 3.0, "cpu": false},
		{"player_id": 1, "size": 5.0, "cpu": true},
	])
	await _frames(2)
	var tags := res.find_children("CpuTag", "Label", true, false)
	_expect(tags.size() == 1 and (tags[0] as Label).text == "CPU", "results show CPU tag")
	res.queue_free()
	await _frames(2)


func _cpu(pos: Vector3) -> CpuBeetle:
	var cpu := CpuBeetle.new()
	cpu.player_id = 1
	cpu.profile = Config.cpu.duplicate() as CpuProfile
	cpu.set_scripted_input(Vector2.ZERO, false) # 既定は台本(何もしない)。思考させるテストは scripted を戻す
	add_child(cpu)
	cpu.global_position = Vector3(pos.x, cpu.body_radius(), pos.z)
	return cpu


func _human(pos: Vector3) -> Player:
	var player := (load("res://scenes/Player.tscn") as PackedScene).instantiate() as Player
	player.player_id = 0
	player.input_device = 9999
	add_child(player)
	player.global_position = Vector3(pos.x, player.body_radius(), pos.z)
	return player


func _cleanup(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			(n as Player).stop_gameplay()
			n.queue_free()
	for child in _dung.get_children():
		child.queue_free()
	await _frames(2)


func _physics(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _expect(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
		push_error(label)
