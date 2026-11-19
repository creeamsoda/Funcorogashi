extends Node3D
## 特殊フンの見た目確認(ScreenshotRunner 用)。左: ブラックホール中(渦巻き)、右: 高速中(上昇線)。
## 手前に特殊フン(濃紺 = ブラックホール、水色 = 高速)と通常フンを並べる。

class Idle extends Player:
	func _read_move() -> Vector2:
		return Vector2.ZERO

	func _dash_input_held() -> bool:
		return false


func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	var dung := Node3D.new()
	dung.add_to_group("dung_container")
	add_child(dung)
	Config.balance.flee_enabled = false
	var kinds := [DungPickup.Kind.BLACKHOLE, DungPickup.Kind.SPEED, DungPickup.Kind.NORMAL]
	for i in kinds.size():
		var pk := DungPickup.create(1.0)
		pk.kind = kinds[i]
		pk.position = Vector3(-3.0 + i * 3.0, 0, 7)
		dung.add_child(pk)
	var bh := _player(0, Vector3(-6, 0, 0))
	bh._blackhole_t = 100.0
	var sp := _player(1, Vector3(6, 0, 0))
	sp._speed_boost_t = 100.0
	# 近寄りカメラ(全体俯瞰だと線が小さすぎる)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 13, 15), Vector3(0, 0, 2.5))
	cam.make_current()


func _player(pid: int, pos: Vector3) -> Player:
	var p := Idle.new()
	p.player_id = pid
	p.input_device = 9999
	p.position = pos
	add_child(p)
	return p
