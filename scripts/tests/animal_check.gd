extends Node3D
## Track D ドロップ機構の headless 自動テスト(操作不要)。
## 3種を出現させ、数秒後に dung_container に生成されたフン数を検証する。
## 注: headless はフレームが高速なので待機は実時間タイマーで行う。

func _ready() -> void:
	var dung := Node3D.new()
	dung.name = "Dung"
	dung.add_to_group("dung_container")
	add_child(dung)

	# 動物由来フンの元サイズに実量倍率が掛かることを確認。
	var old_amount_multiplier: float = Config.balance.animal_dung_amount_multiplier
	Config.balance.animal_dung_amount_multiplier = 2.0
	var probe := Animal.new()
	add_child(probe)
	probe.drop_pickup(Vector3.ZERO, 0.6)
	await get_tree().process_frame
	var amount_ok := false
	for child in dung.get_children():
		if child is DungPickup:
			amount_ok = is_equal_approx((child as DungPickup).size, 1.2)
			child.queue_free()
	probe.queue_free()
	Config.balance.animal_dung_amount_multiplier = old_amount_multiplier
	await get_tree().process_frame

	add_child(load("res://scenes/animals/Bird.tscn").instantiate())
	add_child(load("res://scenes/animals/Raptor.tscn").instantiate())
	add_child(load("res://scenes/animals/Orangutan.tscn").instantiate())

	await get_tree().create_timer(4.0).timeout

	var n := dung.get_child_count()
	var ok := n > 0 and amount_ok
	print("[animal_check] result=", ("PASS" if ok else "FAIL"),
		" pickups=", n, " amount_multiplier=", amount_ok)
	get_tree().quit(0 if ok else 1)
