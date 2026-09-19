extends Node3D
## MVP視認性UIのheadless自動テスト:
## 王冠の順位追従/残り30秒で非表示、突進準備時の本体+フン点滅、着弾予告の生成/消去。


func _ready() -> void:
	var crown_ok := await _test_crown()
	var blink_ok := await _test_windup_blink()
	var preview_ok := await _test_landing_preview()
	var ok := crown_ok and blink_ok and preview_ok
	print("[ui_feedback_check] result=", ("PASS" if ok else "FAIL"),
		" crown=", crown_ok, " blink=", blink_ok, " landing_preview=", preview_ok)
	get_tree().quit(0 if ok else 1)


func _test_crown() -> bool:
	var gm: GameManager = (load("res://scenes/Game.tscn") as PackedScene).instantiate()
	add_child(gm)
	await get_tree().process_frame
	await get_tree().physics_frame
	var p0 := gm.players[0]
	var p1 := gm.players[1]
	var c0 := p0.get_node_or_null("LeaderCrown") as Label3D
	var c1 := p1.get_node_or_null("LeaderCrown") as Label3D
	var initial_ok := c0 != null and c0.text == "👑" and c0.visible and c1 != null and not c1.visible
	p1.add_size(5.0)
	await get_tree().process_frame
	var switched := not c0.visible and c1.visible
	gm.time_left = GameManager.CROWN_HIDE_TIME + 0.01
	await get_tree().process_frame
	await get_tree().process_frame
	var hidden := not c0.visible and not c1.visible
	gm.queue_free()
	await get_tree().process_frame
	return initial_ok and switched and hidden


func _test_windup_blink() -> bool:
	var p: Player = (load("res://scenes/Player.tscn") as PackedScene).instantiate()
	p.input_device = 9999
	add_child(p)
	await get_tree().process_frame
	var ball := p.get_node("DungBall") as MeshInstance3D
	var beetle := p.get_node("Beetle") as MeshInstance3D
	p._start_dash()
	var ball_flashes := false
	var beetle_flashes := false
	for _i in 12:
		await get_tree().create_timer(0.02).timeout
		var ball_color: Color = (ball.material_override as StandardMaterial3D).albedo_color
		var beetle_color: Color = (beetle.material_override as StandardMaterial3D).albedo_color
		ball_flashes = ball_flashes or ball_color.is_equal_approx(Player.WINDUP_FLASH_COLOR)
		beetle_flashes = beetle_flashes or beetle_color.is_equal_approx(Player.WINDUP_FLASH_COLOR)
	p.queue_free()
	await get_tree().process_frame
	return ball_flashes and beetle_flashes


func _test_landing_preview() -> bool:
	var dung := Node3D.new()
	dung.add_to_group("dung_container")
	add_child(dung)
	var td := ThrownDung.create(Vector3(0, 3, 0), Vector3(2, 0, 1), 1.0)
	dung.add_child(td)
	await get_tree().process_frame
	var preview := dung.get_node_or_null("LandingPreview") as MeshInstance3D
	var preview_ok := preview != null
	if preview != null:
		var mat := preview.material_override as StandardMaterial3D
		preview_ok = mat != null and mat.albedo_color.a < 0.5
	await get_tree().create_timer(1.3).timeout
	var landed := false
	for child in dung.get_children():
		if child is DungPickup:
			landed = true
	var cleared := dung.get_node_or_null("LandingPreview") == null
	dung.queue_free()
	await get_tree().process_frame
	return preview_ok and landed and cleared
