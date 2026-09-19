extends Node3D
## ラプトルの挙動 headless 自動テスト:
##  外→場内 / 壁で折り返し(bounces減少) / 場外へ抜け消滅 /
##  ドロップが走行全体に分散しているか(最後のドロップ時刻が序盤で終わっていない)

func _ready() -> void:
	var dung := Node3D.new()
	dung.name = "Dung"
	dung.add_to_group("dung_container")
	add_child(dung)

	var rap := load("res://scenes/animals/Raptor.tscn").instantiate() as Node3D
	add_child(rap)
	var start_outside := not _inside(rap.position)
	var init_bounces: int = rap.get("_bounces_left")
	var min_bounces := init_bounces
	var entered := false
	var last_count := 0
	var last_drop_time := 0.0

	var t := 0.0
	while t < 18.0 and is_instance_valid(rap):
		if _inside(rap.position):
			entered = true
		var b: int = rap.get("_bounces_left")
		if b < min_bounces:
			min_bounces = b
		var c := dung.get_child_count()
		if c > last_count:
			last_count = c
			last_drop_time = t
		await get_tree().create_timer(0.2).timeout
		t += 0.2

	var exited := not is_instance_valid(rap)
	var bounced := min_bounces < init_bounces
	var pickups := dung.get_child_count()
	var spread := last_drop_time > 2.5   # 序盤で打ち切られず走行全体に分散
	var ok: bool = start_outside and entered and bounced and exited and pickups >= 2 and spread
	print("[raptor_check] result=", ("PASS" if ok else "FAIL"),
		" start_outside=", start_outside, " entered=", entered,
		" bounces ", init_bounces, "->", min_bounces, " exited=", exited,
		" pickups=", pickups, " last_drop_t=", "%.1f" % last_drop_time)
	get_tree().quit(0 if ok else 1)

func _inside(p: Vector3) -> bool:
	return absf(p.x) < 12.0 and absf(p.z) < 8.0
