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

	var ok := r_hit and r_wall and r_mutual
	print("[dash_check] result=", ("PASS" if ok else "FAIL"),
		"  hit=", r_hit, " self_crash=", r_wall, " mutual=", r_mutual)
	get_tree().quit(0 if ok else 1)


func _test_hit() -> bool:
	var atk := _mk(0, Vector3(0, 0, 0), Vector3(1, 0, 0))
	var vic := _mk(1, Vector3(3, 0, 0), Vector3(-1, 0, 0))
	await _frames(2)
	var vic0: float = vic.size
	var atk0: float = atk.size
	var dc0: int = _dung.get_child_count()
	var got := {"hit": false}
	atk.dash_hit.connect(func(_a: int, _v: int) -> void: got["hit"] = true)
	atk.facing = Vector3(1, 0, 0)
	atk._start_dash()
	await _seconds(0.9)
	# 攻撃側は無傷(自分はドロップしない=size減らない。相手の落としたフンを回収して増えるのは仕様どおり)
	var ok: bool = got["hit"] and vic.size < vic0 and atk.size >= atk0 - 0.0001 \
		and vic.state == Player.State.STUNNED and _dung.get_child_count() > dc0
	print("  [hit] atk ", atk0, "->", atk.size, " vic ", vic0, "->", vic.size,
		" vic_state=", vic.state, " dashHit=", got["hit"])
	_free([atk, vic])
	await _frames(2)
	return ok


func _test_wall() -> bool:
	var p := _mk(0, Vector3(10, 0, 0), Vector3(1, 0, 0))
	await _frames(2)
	var s0: float = p.size
	p.facing = Vector3(1, 0, 0)
	p._start_dash()
	await _seconds(0.9)
	var ok: bool = p.size < s0 and p.state == Player.State.STUNNED
	print("  [wall] size ", s0, "->", p.size, " state=", p.state)
	_free([p])
	await _frames(2)
	return ok


func _test_mutual() -> bool:
	var a := _mk(0, Vector3(-2, 0, 0), Vector3(1, 0, 0))
	var b := _mk(1, Vector3(2, 0, 0), Vector3(-1, 0, 0))
	await _frames(2)
	var a0: float = a.size
	var b0: float = b.size
	a.facing = Vector3(1, 0, 0)
	b.facing = Vector3(-1, 0, 0)
	a._start_dash()
	b._start_dash()
	await _seconds(0.9)
	var ok: bool = a.size < a0 and b.size < b0 \
		and a.state == Player.State.STUNNED and b.state == Player.State.STUNNED
	print("  [mutual] a ", a0, "->", a.size, " b ", b0, "->", b.size,
		" states=", a.state, "/", b.state)
	_free([a, b])
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
			n.queue_free()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _seconds(t: float) -> void:
	await get_tree().create_timer(t).timeout
