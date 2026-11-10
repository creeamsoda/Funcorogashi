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
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hidden := not c0.visible and not c1.visible
	gm.queue_free()
	await get_tree().process_frame
	return initial_ok and switched and hidden


func _test_windup_blink() -> bool:
	var player_scene := load("res://scenes/Player.tscn") as PackedScene
	var p := player_scene.instantiate() as Player
	p.input_device = 9999
	add_child(p)
	p.set_physics_process(false)
	var other := player_scene.instantiate() as Player
	other.player_id = 1
	other.input_device = 9999
	add_child(other)
	other.set_physics_process(false)
	other.position.x = 6.0
	await get_tree().process_frame
	var ball := p.get_node("DungBall") as MeshInstance3D
	var materials := _beetle_materials(p)
	var other_materials := _beetle_materials(other)
	var original_colors: Array[Color] = []
	var original_textures: Array[Texture2D] = []
	var other_colors: Array[Color] = []
	var independent := not materials.is_empty() and materials.size() == other_materials.size()
	for mat in materials:
		original_colors.append(mat.albedo_color)
		original_textures.append(mat.albedo_texture)
		for other_mat in other_materials:
			independent = independent and mat != other_mat
	for mat in other_materials:
		other_colors.append(mat.albedo_color)
	var shell := p.get_node("Beetle").find_child("WingShell", true, false) as MeshInstance3D
	var other_shell := other.get_node("Beetle").find_child("WingShell", true, false) as MeshInstance3D
	var player_colors := shell != null and other_shell != null
	if player_colors:
		player_colors = not (shell.get_active_material(0) as StandardMaterial3D).albedo_color.is_equal_approx(
			(other_shell.get_active_material(0) as StandardMaterial3D).albedo_color)

	p._start_dash()
	p._charge_t = Player.CHARGE_FLASH_INTERVAL * 0.5
	p._update_beetle()
	var ball_flashes := (ball.material_override as StandardMaterial3D).albedo_color.is_equal_approx(Player.WINDUP_FLASH_COLOR)
	var beetle_flashes := not materials.is_empty()
	var other_unchanged := true
	for mat in materials:
		beetle_flashes = beetle_flashes and mat.albedo_color.is_equal_approx(Player.WINDUP_FLASH_COLOR)
	for i in other_materials.size():
		other_unchanged = other_unchanged and other_materials[i].albedo_color.is_equal_approx(other_colors[i])

	p._charge_t = Player.CHARGE_FLASH_INTERVAL * 1.5
	p._update_beetle()
	var blink_restores := _materials_restored(materials, original_colors, original_textures) \
		and (ball.material_override as StandardMaterial3D).albedo_color.is_equal_approx(Player.PLAYER_COLORS[p.player_id % Player.PLAYER_COLORS.size()])
	p._charge_t = Player.CHARGE_FLASH_INTERVAL * 0.5
	p._update_beetle()
	p._end_dash()
	p._update_beetle()
	var dash_restores := _materials_restored(materials, original_colors, original_textures)
	print("  [windup_blink] surfaces=", materials.size(), " all_flash=", beetle_flashes,
		" ball=", ball_flashes, " independent=", independent, " player_colors=", player_colors,
		" other_unchanged=", other_unchanged, " blink_restore=", blink_restores,
		" dash_restore=", dash_restores)
	p.queue_free()
	other.queue_free()
	await get_tree().process_frame
	return ball_flashes and beetle_flashes and independent and player_colors \
		and other_unchanged and blink_restores and dash_restores


func _beetle_materials(player: Player) -> Array[StandardMaterial3D]:
	var materials: Array[StandardMaterial3D] = []
	for node in player.get_node("Beetle").find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var mat := mesh_instance.get_active_material(surface) as StandardMaterial3D
			if mat == null:
				push_error("Beetle surface has no StandardMaterial3D: %s[%d]" % [node.name, surface])
				return []
			materials.append(mat)
	return materials


func _materials_restored(materials: Array[StandardMaterial3D], colors: Array[Color], textures: Array[Texture2D]) -> bool:
	for i in materials.size():
		if not materials[i].albedo_color.is_equal_approx(colors[i]) or materials[i].albedo_texture != textures[i]:
			return false
	return not materials.is_empty()


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
