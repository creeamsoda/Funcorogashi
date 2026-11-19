extends Node3D
## 加速板ステージ(BoostPads)の headless 自動テスト:
##  layout : 板が2枚(右上・左下、横幅1/3の位置、奥行き方向が長辺)、上空の風エフェクトは出ない
##  boost  : 歩いて板に乗ると即座に突進無敵になり、歩く向きへ突進する(加速状態を経ない)
##  off_pad: 板の外では突進しない
##  stunned: スタン中は板に乗っても突進しない
##  pillars: 杭が5本(中央+4)、外壁と同じ高さ、"wall" グループで、加速板と重ならない

const BOOST_INDEX := 6

class Walker extends Player:
	var dir := Vector3.ZERO
	func _read_move() -> Vector2:
		return Vector2(dir.x, dir.z)

var _failures: Array[String] = []


func _ready() -> void:
	var stage := load("res://scenes/Stage.tscn").instantiate() as Stage
	stage.layout = Stage.load_layout(BOOST_INDEX)
	add_child(stage)
	var dung := Node3D.new()
	dung.add_to_group("dung_container")
	add_child(dung)
	await _frames(2)
	_test_layout(stage)
	await _test_boost()
	await _test_off_pad()
	await _test_stunned()
	_test_pillars(stage)
	print("[boost_pad_check] result=", ("PASS" if _failures.is_empty() else "FAIL"), " failures=", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_layout(stage: Stage) -> void:
	var pads := stage.layout.boost_pads
	var third := Stage.HALF_X * 2.0 / 3.0 * 0.5 # 中心から横幅1/3の位置まで(=6)
	var ok := pads.size() == 2
	for pad in pads:
		ok = ok and absf(absf(pad.center.x) - third) < 0.01 and pad.size.y > pad.size.x
		ok = ok and signf(pad.center.x) == -signf(pad.center.y) # 右上(x+, z-) / 左下(x-, z+)
	var meshes := stage.get_tree().get_nodes_in_group("boost_pad").size()
	var winds := stage.find_children("BoostWind*", "", true, false).size()
	print("  [layout] pads=%d meshes=%d winds=%d" % [pads.size(), meshes, winds])
	if not ok or meshes != 2 or winds != 0:
		_failures.append("layout pads=%d meshes=%d winds=%d" % [pads.size(), meshes, winds])


func _test_boost() -> void:
	var p := _walker(Vector3(3.0, 0, -5.0))
	p.dir = Vector3.RIGHT
	var boosted_frame := -1
	var was_accel := false
	for f in 60:
		await get_tree().physics_frame
		was_accel = was_accel or p.is_dash_accelerating()
		if p.is_dash_invincible():
			boosted_frame = f
			break
	var on_pad := Stage.is_on_boost_pad(p.global_position)
	print("  [boost] frame=%d on_pad=%s dir=%s accel_seen=%s" % [boosted_frame, on_pad, p._dash_dir, was_accel])
	if boosted_frame < 0 or was_accel or p._dash_dir.dot(Vector3.RIGHT) < 0.99:
		_failures.append("boost frame=%d accel=%s" % [boosted_frame, was_accel])
	await _frames(10)
	if p.global_position.x < 8.0:
		_failures.append("boost moved x=%.2f" % p.global_position.x)
	p.queue_free()
	await _frames(2)


func _test_off_pad() -> void:
	var p := _walker(Vector3(-10, 0, 0))
	p.dir = Vector3.FORWARD
	await _frames(40)
	print("  [off_pad] state=%d" % p.state)
	if p.state == Player.State.DASHING:
		_failures.append("off_pad dashed")
	p.queue_free()
	await _frames(2)


func _test_stunned() -> void:
	var p := _walker(Vector3(-6.0, 0, 5.0))
	await _frames(1)
	p._enter_stun()
	p._stun_t = 10.0
	await _frames(10)
	print("  [stunned] state=%d" % p.state)
	if p.state != Player.State.STUNNED:
		_failures.append("stunned state=%d" % p.state)
	p.queue_free()
	await _frames(2)


func _test_pillars(stage: Stage) -> void:
	var bodies := get_tree().get_nodes_in_group("pillar")
	var ok := stage.pillar_count() == 5 and bodies.size() == 5
	var half := stage.layout.pillar_size * 0.5
	for b in bodies:
		ok = ok and b.is_in_group("wall")
		var top := Stage.top_ground_height(b.global_position)
		ok = ok and absf(top - Stage.WALL_HEIGHT) < 0.01
		for pad in stage.layout.boost_pads:
			var gap_x := absf(b.global_position.x - pad.center.x) - pad.size.x * 0.5 - half
			var gap_z := absf(b.global_position.z - pad.center.y) - pad.size.y * 0.5 - half
			if gap_x < 0.0 and gap_z < 0.0:
				ok = false
	if absf(stage.distance_to_fences(Vector3.ZERO)) > 0.001:
		ok = false # 中央の杭は押し出し判定にも入っている
	print("  [pillars] count=%d ok=%s" % [bodies.size(), ok])
	if not ok:
		_failures.append("pillars")


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
