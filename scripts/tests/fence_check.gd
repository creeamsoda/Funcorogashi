extends Node3D
## フェンス・ステージ配置(Phase 3)の headless 自動テスト:
##  layouts : 全配置が読めて本数が想定どおり、フェンスは "wall" グループ
##  spawns  : 全配置で対戦(4人・2人)と一人プレイの開始位置がフェンスから離れている
##  crash   : フェンスへの突進激突はスタンのみ(フンを落とさない)
##  push_out: フェンスに重なる位置に落ちたフンはフェンスの外へ出る
##  no_pass : 逃げるフンはフェンスをすり抜けない
##  game    : 試合で BalanceConfig の選択が反映される(対戦・ひとりで遊ぶとも stage_layout)

const EXPECTED_COUNTS := [0, 4, 8, 2, 8, 0, 0]
const MIN_SPAWN_CLEARANCE := 1.5

class Chaser extends Player:
	var target: Node3D
	func _read_move() -> Vector2:
		if not is_instance_valid(target):
			return Vector2.ZERO
		var d := target.global_position - global_position
		return Vector2(d.x, d.z).normalized()

var _failures: Array[String] = []


func _ready() -> void:
	await _test_layouts_and_spawns()
	await _test_crash()
	await _test_push_out()
	await _test_no_pass()
	await _test_game()
	print("[fence_check] result=", ("PASS" if _failures.is_empty() else "FAIL"), " failures=", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_layouts_and_spawns() -> void:
	var spots: Array = GameManager.SPAWN_SPOTS + GameManager.SPAWN_SPOTS_2P
	for i in Stage.LAYOUT_PATHS.size():
		var stage := _stage(i)
		await get_tree().physics_frame
		if stage.fence_count() != EXPECTED_COUNTS[i]:
			_failures.append("count[%d]=%d" % [i, stage.fence_count()])
		for f in get_tree().get_nodes_in_group("fence"):
			if not f.is_in_group("wall"):
				_failures.append("fence_not_wall[%d]" % i)
		var nearest := INF
		var layout_spots: Array = spots.duplicate()
		if not stage.layout.spawn_spots.is_empty(): # レイアウト側で4人の初期位置を上書きしている
			layout_spots = Array(stage.layout.spawn_spots) + GameManager.SPAWN_SPOTS_2P
		if not stage.layout.pillars.is_empty():
			# 中央に杭があるステージ(加速板+杭)は対戦専用。一人プレイの開始位置(中央)は対象外
			layout_spots.pop_back()
		for spot in layout_spots:
			nearest = minf(nearest, stage.distance_to_fences(spot))
		if nearest < MIN_SPAWN_CLEARANCE:
			_failures.append("spawn_clearance[%d]=%.2f" % [i, nearest])
		print("  [layout %d %s] fences=%d spawn_clearance=%.2f" % [i, stage.layout.layout_id, stage.fence_count(), nearest])
		stage.free()


## 中央の柵: 東の縦フェンス(x=13)へ向けて突進する。
func _test_crash() -> void:
	var stage := _stage(1)
	var dung := _dung_root()
	var p := Chaser.new()
	p.player_id = 0
	p.input_device = 9999
	add_child(p)
	p.global_position = Vector3(10, 0, 0)
	p.facing = Vector3.RIGHT
	await _frames(2)
	var s0 := p.size
	p._start_dash()
	await get_tree().create_timer(0.8).timeout
	var ok := p.state == Player.State.STUNNED and is_equal_approx(p.size, s0) and dung.get_child_count() == 0
	print("  [crash] state=%d size %.2f->%.2f drops=%d" % [p.state, s0, p.size, dung.get_child_count()])
	if not ok:
		_failures.append("crash")
	p.stop_gameplay()
	p.queue_free()
	stage.queue_free()
	dung.queue_free()
	await _frames(2)


func _test_push_out() -> void:
	var stage := _stage(1)
	var dung := _dung_root()
	var old_flee: bool = Config.balance.flee_enabled
	Config.balance.flee_enabled = false # 押し出しだけを確認する
	var pk := DungPickup.create(1.0)
	dung.add_child(pk)
	pk.global_position = Vector3(1.0, 0, -5.5) # 北側の横フェンスのど真ん中
	await _frames(2)
	var clearance := stage.distance_to_fences(pk.global_position)
	print("  [push_out] pos=%s clearance=%.2f radius=%.2f" % [pk.global_position, clearance, pk._radius()])
	if clearance < pk._radius():
		_failures.append("push_out")
	Config.balance.flee_enabled = old_flee
	stage.queue_free()
	dung.queue_free()
	await _frames(2)


## フェンス(z=-5.5)の手前にいるフンを、反対側から追い立ててもフェンスの向こうへ抜けない。
func _test_no_pass() -> void:
	var stage := _stage(1)
	var dung := _dung_root()
	var pk := DungPickup.create(1.0)
	dung.add_child(pk)
	pk.global_position = Vector3(0, 0, -7.5)
	var c := Chaser.new()
	c.player_id = 0
	c.input_device = 9999
	c.target = pk
	add_child(c)
	c.global_position = Vector3(0, 0, -11)
	var crossed := false
	var t := 0.0
	while t < 2.0 and is_instance_valid(pk) and not pk.is_queued_for_deletion():
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if pk.global_position.z > -5.5 and absf(pk.global_position.x) < 5.0:
			crossed = true
	print("  [no_pass] crossed=%s caught=%s" % [crossed, not is_instance_valid(pk) or pk.is_queued_for_deletion()])
	if crossed:
		_failures.append("no_pass")
	c.stop_gameplay()
	c.queue_free()
	if is_instance_valid(pk):
		pk.queue_free()
	stage.queue_free()
	dung.queue_free()
	await _frames(2)


func _test_game() -> void:
	var old_versus: int = Config.balance.stage_layout
	Config.balance.stage_layout = 3
	# 対戦も「ひとりで遊ぶ」(CPU戦)も同じ stage_layout を使う
	for mode in ["versus", "solo"]:
		var gm: GameManager = (load("res://scenes/Game.tscn") as PackedScene).instantiate()
		gm.mode = mode
		add_child(gm)
		await _frames(2)
		var stage := gm.get_node("World").get_child(0) as Stage
		var want: int = EXPECTED_COUNTS[3]
		print("  [game %s] fences=%d" % [mode, stage.fence_count()])
		if stage.fence_count() != want:
			_failures.append("game_%s" % mode)
		gm.queue_free()
		await _frames(2)
	Config.balance.stage_layout = old_versus


func _stage(index: int) -> Stage:
	var stage := load("res://scenes/Stage.tscn").instantiate() as Stage
	stage.layout = Stage.load_layout(index)
	add_child(stage)
	return stage


func _dung_root() -> Node3D:
	var dung := Node3D.new()
	dung.add_to_group("dung_container")
	add_child(dung)
	return dung


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
