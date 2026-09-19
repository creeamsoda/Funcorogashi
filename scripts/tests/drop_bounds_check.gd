extends Node3D
## ドロップ散らばりの headless 自動テスト:
##  壁際で自滅させ、生成フンが (1)アリーナ内に収まる (2)本人から一定距離離れている を検証。
##  drop_scatter_radius を大きめにして場外飛び出しを誘発しても内側に収まることを確認。

func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	var dung := Node3D.new()
	dung.add_to_group("dung_container")
	add_child(dung)

	# 散らばり半径を大きめに上書きして厳しめに試す
	Config.balance.drop_scatter_radius = 12.0
	Config.balance.drop_scatter_count = 8

	var p: Player = (load("res://scenes/Player.tscn") as PackedScene).instantiate()
	p.player_id = 0
	p.input_device = 9999
	add_child(p)
	p.global_position = Vector3(17.0, 0, 8.0) # 東の壁ぎわ(アリーナ18x12)
	p.facing = Vector3(1, 0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	p.facing = Vector3(1, 0, 0)
	p._start_dash()
	await get_tree().create_timer(0.9).timeout

	var origin := p.global_position
	var min_r: float = Config.balance.drop_scatter_min_radius
	var count := 0
	var all_inside := true
	var all_far := true
	var nearest := 1e9
	for c in dung.get_children():
		if c is DungPickup:
			count += 1
			var pos: Vector3 = c.global_position
			if absf(pos.x) > 18.01 or absf(pos.z) > 12.01:
				all_inside = false
			var dist := Vector2(pos.x - origin.x, pos.z - origin.z).length()
			nearest = minf(nearest, dist)
			if dist < min_r - 0.5:
				all_far = false

	var ok: bool = count > 0 and all_inside and all_far
	print("[drop_bounds_check] result=", ("PASS" if ok else "FAIL"),
		"  count=", count, " inside=", all_inside, " far>=", min_r, "=", all_far,
		" nearest=", "%.2f" % nearest)
	get_tree().quit(0 if ok else 1)
