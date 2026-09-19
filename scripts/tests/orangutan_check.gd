extends Node3D
## オランウータンの投擲 headless 自動テスト:
##  総数 == orangutan_throw_count / 1個ずつ間隔を空けて着弾しているか(同時投擲でない)

func _ready() -> void:
	var dung := Node3D.new()
	dung.name = "Dung"
	dung.add_to_group("dung_container")
	add_child(dung)

	add_child(load("res://scenes/animals/Orangutan.tscn").instantiate())

	var expected: int = Config.balance.orangutan_throw_count
	var times: Array[float] = []
	var last := 0
	var t := 0.0
	while t < 8.0 and times.size() < expected:
		var c := dung.get_child_count()
		while c > last:
			times.append(t)
			last += 1
		await get_tree().create_timer(0.1).timeout
		t += 0.1

	var gap := (times[1] - times[0]) if times.size() >= 2 else -1.0
	var staggered := times.size() >= 2 and gap > 0.3
	var ok: bool = times.size() == expected and staggered
	print("[orangutan_check] result=", ("PASS" if ok else "FAIL"),
		" landed=", times.size(), " expected=", expected, " gap=", "%.2f" % gap)
	get_tree().quit(0 if ok else 1)
