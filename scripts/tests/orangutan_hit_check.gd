extends Node3D
## オランウータン直撃効果の headless 自動テスト(操作不要):
##  プレイヤーめがけて投擲 → 直撃で ボーナス(サイズ増)+軽スロウ、地面フンは残さない。
##  (既定 orangutan_hit_effect=0 BonusSlow を想定)

func _ready() -> void:
	var dung := Node3D.new()
	dung.add_to_group("dung_container")
	add_child(dung)

	var p: Player = (load("res://scenes/Player.tscn") as PackedScene).instantiate()
	p.player_id = 0
	p.input_device = 9999
	add_child(p)
	p.global_position = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var s0: float = p.size

	var td := ThrownDung.create(Vector3(0, 5, -5), Vector3.ZERO, 1.0)
	add_child(td)

	await get_tree().create_timer(1.4).timeout

	var got_bonus: bool = p.size > s0
	var got_slow: bool = p._slow_t > 0.0
	var no_ground: bool = dung.get_child_count() == 0
	var ok: bool = got_bonus and got_slow and no_ground
	print("[orangutan_hit_check] result=", ("PASS" if ok else "FAIL"),
		"  size ", s0, "->", p.size, " slow_t=", "%.2f" % p._slow_t,
		" ground_pickups=", dung.get_child_count())
	get_tree().quit(0 if ok else 1)
