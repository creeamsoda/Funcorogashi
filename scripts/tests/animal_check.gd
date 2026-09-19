extends Node3D
## Track D ドロップ機構の headless 自動テスト(操作不要)。
## 3種を出現させ、数秒後に dung_container に生成されたフン数を検証する。
## 注: headless はフレームが高速なので待機は実時間タイマーで行う。

func _ready() -> void:
	var dung := Node3D.new()
	dung.name = "Dung"
	dung.add_to_group("dung_container")
	add_child(dung)

	add_child(load("res://scenes/animals/Bird.tscn").instantiate())
	add_child(load("res://scenes/animals/Raptor.tscn").instantiate())
	add_child(load("res://scenes/animals/Orangutan.tscn").instantiate())

	await get_tree().create_timer(4.0).timeout

	var n := dung.get_child_count()
	print("[animal_check] result=", ("PASS" if n > 0 else "FAIL"), " pickups=", n)
	get_tree().quit(0 if n > 0 else 1)
