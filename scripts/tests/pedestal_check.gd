extends Node3D
## 中央の台座ステージ(Pedestal)の headless 自動テスト:
##  shape    : 天面の高さ=壁の高さ、スロープ中ほどは半分の高さ、台座の外は地面
##  climb    : スロープを歩いて天面まで登れる
##  fall     : 天面の縁から自由に落ちて地面に戻る
##  no_climb : 台座の急な側面には登れない
##  step     : スロープ下端付近の小さい段差は横から乗り越えられ、高い段差は越えられない
##  dung_edge: 天面で逃げるフンは縁から飛び降りない
##  dung_ramp: スロープ上で逃げるフンは坂に沿って地面へ下りられる

const PEDESTAL_INDEX := 5

class Walker extends Player:
	var waypoints: Array[Vector3] = []
	var dir := Vector3.ZERO
	func _read_move() -> Vector2:
		while not waypoints.is_empty():
			var d := waypoints[0] - global_position
			d.y = 0.0
			if d.length() < 0.4:
				waypoints.pop_front()
				continue
			return Vector2(d.x, d.z).normalized()
		return Vector2(dir.x, dir.z)

var _failures: Array[String] = []
var _stage: Stage


func _ready() -> void:
	_stage = load("res://scenes/Stage.tscn").instantiate() as Stage
	_stage.layout = Stage.load_layout(PEDESTAL_INDEX)
	add_child(_stage)
	var dung := Node3D.new()
	dung.add_to_group("dung_container")
	add_child(dung)
	await _frames(2)
	_test_shape()
	await _test_climb_and_fall()
	await _test_no_climb()
	await _test_step()
	await _test_dung_edge()
	await _test_dung_ramp()
	print("[pedestal_check] result=", ("PASS" if _failures.is_empty() else "FAIL"), " failures=", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_shape() -> void:
	var top := Stage.top_ground_height(Vector3.ZERO)
	var mid := Stage.top_ground_height(Vector3(5.2, 0, 0)) # t=0.5(右)
	var out := Stage.top_ground_height(Vector3(-8, 0, 0))
	print("  [shape] top=%.2f ramp_mid=%.2f outside=%.2f" % [top, mid, out])
	if absf(top - Stage.WALL_HEIGHT) > 0.01:
		_failures.append("top=%.2f" % top)
	if absf(mid - Stage.WALL_HEIGHT * 0.5) > 0.1:
		_failures.append("ramp_mid=%.2f" % mid)
	if absf(out) > 0.01:
		_failures.append("outside=%.2f" % out)


## スロープの中心線(内側+幅/2)に沿って登る。
func _ramp_path() -> Array[Vector3]:
	var l := _stage.layout
	var pts: Array[Vector3] = [Vector3(0, 0, l.pedestal_base_radius + l.pedestal_ramp_width * 0.5 + 0.5)]
	for i in range(1, 21):
		var t := float(i) / 20.0
		var a := PI * 0.5 - PI * t
		var r := lerpf(l.pedestal_base_radius, l.pedestal_top_radius, t) + l.pedestal_ramp_width * 0.5
		pts.append(Vector3(cos(a) * r, 0, sin(a) * r))
	pts.append(Vector3(0, 0, -1.0)) # 天面へ
	return pts


func _test_climb_and_fall() -> void:
	var p := _walker(Vector3(0, 0, 7.5))
	p.waypoints = _ramp_path()
	await _frames(360)
	var feet := p.global_position.y - p.body_radius()
	print("  [climb] pos=%s feet=%.2f" % [p.global_position, feet])
	if absf(feet - Stage.WALL_HEIGHT) > 0.1:
		_failures.append("climb feet=%.2f" % feet)
	# 天面から左(スロープのない側)へ歩いて落ちる
	p.waypoints.clear()
	p.dir = Vector3.LEFT
	await _frames(90)
	feet = p.global_position.y - p.body_radius()
	print("  [fall] pos=%s feet=%.2f" % [p.global_position, feet])
	if feet > 0.05 or p.global_position.x > -4.6:
		_failures.append("fall feet=%.2f x=%.2f" % [feet, p.global_position.x])
	p.queue_free()
	await _frames(2)


func _test_no_climb() -> void:
	var p := _walker(Vector3(-7, 0, 0))
	p.dir = Vector3.RIGHT
	await _frames(120)
	var feet := p.global_position.y - p.body_radius()
	print("  [no_climb] pos=%s feet=%.2f" % [p.global_position, feet])
	if feet > 0.3:
		_failures.append("no_climb feet=%.2f" % feet)
	p.queue_free()
	await _frames(2)


## スロープ下端付近(低い所)へ外側から入れば乗れる。高い所(t=0.4)では外側面に阻まれる。
func _test_step() -> void:
	for case in [[0.08, true], [0.4, false]]:
		var t: float = case[0]
		var a := PI * 0.5 - PI * t
		var u := Vector3(cos(a), 0, sin(a))
		var l := _stage.layout
		var ro := lerpf(l.pedestal_base_radius, l.pedestal_top_radius, t) + l.pedestal_ramp_width
		var p := _walker(u * (ro + 1.0))
		p.dir = -u
		await _frames(60)
		var feet := p.global_position.y - p.body_radius()
		var on_ramp := feet > Stage.WALL_HEIGHT * t * 0.5
		print("  [step t=%.2f] feet=%.2f on_ramp=%s" % [t, feet, on_ramp])
		if on_ramp != case[1]:
			_failures.append("step t=%.2f feet=%.2f" % [t, feet])
		p.queue_free()
		await _frames(2)


func _test_dung_edge() -> void:
	var pk := DungPickup.create(3.0)
	get_tree().get_first_node_in_group("dung_container").add_child(pk)
	pk.global_position = Vector3(1.0, 0, 0)
	await _frames(2)
	pk._heading = Vector3.RIGHT
	pk._speed = 9.0
	pk._enter_state(DungPickup.FleeState.RUNNING)
	await _frames(90)
	print("  [dung_edge] pos=%s" % pk.global_position)
	if absf(pk.global_position.y - Stage.WALL_HEIGHT) > 0.05:
		_failures.append("dung_edge y=%.2f" % pk.global_position.y)
	pk.queue_free()
	await _frames(2)


## スロープ上端付近から、坂を下る向き(手前へ戻る向き)へ走らせると高さが下がる。
func _test_dung_ramp() -> void:
	var l := _stage.layout
	var t := 0.3
	var a := PI * 0.5 - PI * t
	var r := lerpf(l.pedestal_base_radius, l.pedestal_top_radius, t) + l.pedestal_ramp_width * 0.5
	var pk := DungPickup.create(3.0)
	get_tree().get_first_node_in_group("dung_container").add_child(pk)
	pk.global_position = Vector3(cos(a) * r, 0, sin(a) * r)
	await _frames(2)
	var y0 := pk.global_position.y
	pk._heading = Vector3(-sin(a), 0, cos(a)) # t が減る向き(下り)
	pk._speed = 3.0
	pk._enter_state(DungPickup.FleeState.RUNNING)
	await _frames(20)
	print("  [dung_ramp] y %.2f -> %.2f" % [y0, pk.global_position.y])
	if absf(y0 - Stage.WALL_HEIGHT * t) > 0.1 or pk.global_position.y > y0 - 0.1:
		_failures.append("dung_ramp y %.2f -> %.2f" % [y0, pk.global_position.y])
	pk.queue_free()
	await _frames(2)


func _walker(at: Vector3) -> Walker:
	var p := Walker.new()
	p.player_id = 0
	p.input_device = 9999
	add_child(p)
	p.global_position = at
	return p


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
