extends Node3D
## NPC実衝突・被弾・拾得除外・停止と、終了後の得点不変性を確認する。

var _failures: Array[String] = []
var _dung: Node3D


func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	# 配置距離は突進加速0.15秒を前提にしているため、調整値(balance_default)に依存しないよう固定する。
	Config.balance.dash_accel_time = 0.15
	_dung = Node3D.new()
	_dung.add_to_group("dung_container")
	add_child(_dung)
	await _test_dash_and_pickup()
	await _test_three_hits()
	await _test_dash_input_suppression()
	await _test_route_and_lifetime()
	await _test_finish_guards()
	print("[npc_check] result=", "PASS" if _failures.is_empty() else "FAIL",
		" failures=", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_dash_and_pickup() -> void:
	var human := _human(Vector3.ZERO)
	human.can_collect = false # 散布全量を拾われる前に検証する。
	var npc := _npc(PackedVector3Array([Vector3(3, 0, 0), Vector3(17, 0, 0)]), 1.0, 20.0)
	var signals := {"hits": 0, "vibrations": 0}
	human.dash_hit.connect(func(_a: int, _v: int) -> void: signals.hits += 1)
	human.vibration_requested.connect(func(_id: int) -> void: signals.vibrations += 1)
	npc.vibration_requested.connect(func(_id: int) -> void: signals.vibrations += 1)
	_expect(not npc.is_in_group("player") and npc.is_in_group("npc"), "NPC group exclusion")
	_expect(human.collision_mask == 7 and npc.collision_layer == 4 and npc.collision_mask == 2,
		"collision layers")
	_expect(npc._read_move() == Vector2.ZERO and not npc._dash_input_held(), "NPC input exclusion")
	for _i in 2:
		await get_tree().physics_frame
	human.facing = Vector3.RIGHT
	human._start_dash()
	await get_tree().create_timer(0.65).timeout
	_expect(signals.hits == 1 and npc.state == Player.State.STUNNED, "dash hits NPC")
	_expect(signals.vibrations == 0, "NPC hit requests no vibration")
	var detached := 8.0 * clampf(Config.balance.drop_ratio, 0.0, 1.0)
	_expect(is_equal_approx(npc.size, 8.0 - detached), "NPC loses held dung")
	var ground_total := 0.0
	for child in _dung.get_children():
		if child is DungPickup:
			ground_total += child.size
			_expect(child.owner_id == npc.player_id and child.owner_id >= 0, "NPC drop owner")
	_expect(is_equal_approx(ground_total, detached * (1.0 - Config.balance.drop_loss_ratio)),
		"NPC scatter preserves configured amount")

	npc.set_physics_process(false)
	var route_time := npc._route_elapsed
	var lifetime := npc._alive_elapsed
	var location := npc.position
	npc._physics_process(0.1)
	_expect(is_equal_approx(npc._route_elapsed, route_time) and npc.position.is_equal_approx(location),
		"stun freezes NPC route")
	_expect(npc._alive_elapsed > lifetime, "lifetime continues during stun")
	npc._stun_t = 0.0
	npc._physics_process(0.01)
	npc._physics_process(0.1)
	_expect(npc._route_elapsed > route_time, "NPC resumes after stun")

	var pickup := DungPickup.create(1.25, npc.player_id)
	_dung.add_child(pickup)
	pickup.position = Vector3(-12, 0, -8)
	var npc_before := npc.size
	pickup._on_body_entered(npc)
	_expect(not pickup.is_queued_for_deletion() and is_equal_approx(npc.size, npc_before),
		"NPC cannot collect")
	human.can_collect = true
	var human_before := human.size
	pickup._on_body_entered(human)
	pickup._on_body_entered(human)
	_expect(is_equal_approx(human.size, human_before + 1.25), "NPC drop full amount, collected once")

	# 一人用の散布系列はグローバル乱数消費や他個体の散布と独立する。
	human.set_scatter_seed(76543)
	npc.set_scatter_seed(76543)
	for _i in 8:
		var from_human := human._drop_position(Vector3.ZERO)
		randf()
		var from_npc := npc._drop_position(Vector3.ZERO)
		_expect(from_human.is_equal_approx(from_npc), "dedicated deterministic scatter RNG")
	human.stop_gameplay()
	npc.stop_gameplay()
	human.queue_free()
	npc.queue_free()
	for child in _dung.get_children():
		child.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _test_route_and_lifetime() -> void:
	var npc := _npc(PackedVector3Array([Vector3(-22, 0, -8), Vector3(22, 0, -8)]), 4.0, 30.0)
	npc.set_physics_process(false)
	# 実際に壁を横切り、場内へ進めることを物理APIで検証する。
	for _i in 120:
		npc._physics_process(1.0 / 60.0)
	_expect(npc.position.x > -18.0 and npc.state == Player.State.ROLLING,
		"NPC crosses arena wall")
	npc._physics_process(10.0)
	_expect(npc.is_queued_for_deletion(), "NPC exits at route end")
	await get_tree().physics_frame
	await get_tree().physics_frame

	var limited := _npc(PackedVector3Array([Vector3(-10, 0, 6), Vector3(10, 0, 6)]), 1.0, 0.5)
	limited.set_physics_process(false)
	limited.state = Player.State.STUNNED
	limited._stun_t = 100.0
	limited._physics_process(0.6)
	_expect(limited.is_queued_for_deletion(), "stunned NPC expires at max lifetime")
	await get_tree().physics_frame
	await get_tree().physics_frame

	var late := _npc(PackedVector3Array([Vector3(-20, 0, 6), Vector3(20, 0, 6)]), 2.0, 24.0)
	late.set_physics_process(false)
	late.advance_spawn_age(4.0)
	_expect(is_equal_approx(late.position.x, -12.0) and is_equal_approx(late._alive_elapsed, 4.0),
		"late spawn catches up route and lifetime")
	late.advance_spawn_age(21.0)
	_expect(late.is_queued_for_deletion(), "late expired spawn is removed")
	await get_tree().physics_frame
	await get_tree().physics_frame


func _test_three_hits() -> void:
	var previous_ratio := Config.balance.drop_ratio
	Config.balance.drop_ratio = 0.5
	var human := _human(Vector3.ZERO)
	human.can_collect = false
	var npc := _npc(PackedVector3Array([Vector3(4, 0, 0), Vector3(16, 0, 0)]), 1.0, 30.0)
	var observed := {"hits": 0}
	human.dash_hit.connect(func(_a: int, victim: int) -> void:
		_expect(victim == npc.player_id, "all three dashes hit the same NPC")
		observed.hits += 1)
	for hit_index in 3:
		if hit_index > 0:
			await get_tree().create_timer(maxf(Config.balance.dash_cooldown,
				Config.balance.stun_duration) + 0.1).timeout
		_expect(human._cd_t <= 0.0 and npc.state == Player.State.ROLLING,
			"cooldown and NPC stun finish before next dash")
		var gap := human.body_radius() + npc.body_radius() + 2.5 # 突進加速を抜けてから当たる距離
		human.position = Vector3(npc.position.x - gap, human.body_radius(), npc.position.z)
		human.facing = Vector3.RIGHT
		for _i in 2:
			await get_tree().physics_frame
		human._start_dash()
		await get_tree().create_timer(Config.balance.dash_charge_min + 0.5).timeout
		_expect(observed.hits == hit_index + 1, "each physical dash emits exactly one hit")
		_expect(is_equal_approx(npc.size, 8.0 * pow(0.5, hit_index + 1)),
			"three dash sizes are one half, one quarter, one eighth")
	_expect(observed.hits == 3 and is_equal_approx(npc.size, 1.0), "three-hit NPC combo")
	print("  [npc_three_hits] hits=", observed.hits, " final_size=", npc.size)
	human.stop_gameplay()
	npc.stop_gameplay()
	human.queue_free()
	npc.queue_free()
	for child in _dung.get_children():
		child.queue_free()
	Config.balance.drop_ratio = previous_ratio
	await get_tree().physics_frame
	await get_tree().physics_frame


func _test_dash_input_suppression() -> void:
	var human := _human(Vector3.ZERO)
	human.input_device = -1
	human.set_physics_process(false)
	var observed := {"starts": 0}
	human.dashed.connect(func(_id: int) -> void: observed.starts += 1)
	_set_dash_key(true)
	human.suppress_dash_until_release()
	for _i in 4:
		human._physics_process(1.0 / 60.0)
	_expect(human.state == Player.State.ROLLING and observed.starts == 0,
		"held menu key cannot start dash")
	_set_dash_key(false)
	human._physics_process(1.0 / 60.0)
	_set_dash_key(true)
	human._physics_process(1.0 / 60.0)
	_expect(human.state == Player.State.DASH_CHARGING and observed.starts == 1,
		"release then press starts exactly one dash")
	_set_dash_key(false) # 成否にかかわらず、合成入力を必ず解放する。
	human.stop_gameplay()
	human.queue_free()
	print("  [npc_dash_input] starts_after_release=", observed.starts)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _set_dash_key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = PlayerInput.ARROWS_DASH_KEY
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _test_finish_guards() -> void:
	var human := _human(Vector3.ZERO)
	_expect(not human.debug_growth_enabled and not human.debug_growth_used,
		"debug growth defaults disabled and unused")
	human.debug_growth_enabled = true
	human.debug_growth_enabled = false
	_expect(not human.debug_growth_enabled and human.debug_growth_used,
		"debug enable history survives disabling")
	human._start_dash()
	human.stop_gameplay()
	var before := human.size
	var location := human.position
	var pickup := DungPickup.create(5.0)
	_dung.add_child(pickup)
	pickup.position = Vector3(-10, 0, -10)
	pickup._on_body_entered(human)
	human.add_size(8.0)
	human.apply_orangutan_hit()
	human.drop_and_stun()
	human._start_dash()
	human._physics_process(1.0)
	_expect(is_equal_approx(human.size, before) and human.position.is_equal_approx(location),
		"finished player ignores late growth and movement")
	_expect(not pickup.is_queued_for_deletion(), "finished player cannot collect pickup")
	for child in human.get_children():
		if child is AudioStreamPlayer:
			_expect(not child.playing, "finish stops audio")
	human.queue_free()
	pickup.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _human(pos: Vector3) -> Player:
	var player := (load("res://scenes/Player.tscn") as PackedScene).instantiate() as Player
	player.player_id = 0
	player.input_device = 9999
	add_child(player)
	player.position = Vector3(pos.x, player.body_radius(), pos.z)
	return player


func _npc(route: PackedVector3Array, speed: float, lifetime: float) -> NpcBeetle:
	var npc := (load("res://scenes/NpcBeetle.tscn") as PackedScene).instantiate() as NpcBeetle
	npc.player_id = 1001
	npc.initial_size = 8.0
	npc.set_scatter_seed(12345)
	npc.setup_route(route, speed, 0.0, 3.0, lifetime)
	add_child(npc)
	return npc


func _expect(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
		push_error(label)
