extends Node3D
## Track C 回収ロジックの headless 自動テスト(操作不要)。
## プレイヤーとドロップフンを重ねて配置し、回収→サイズ増→pickup消滅を検証する。

func _ready() -> void:
	var player: Player = (load("res://scenes/Player.tscn") as PackedScene).instantiate()
	player.player_id = 0
	add_child(player)
	player.global_position = Vector3.ZERO
	var before: float = player.size

	var pickup := DungPickup.create(0.5, -1)
	var got := {"hit": false}
	pickup.collected.connect(func(_s: float) -> void: got.hit = true)
	add_child(pickup)
	pickup.global_position = Vector3.ZERO

	for _i in 4:
		await get_tree().physics_frame

	var expected: float = before + 0.5 * Config.balance.size_gain_per_pickup
	var gain_ok := is_equal_approx(player.size, expected)
	var neutral_se_ok := (player.get_node("GetNeutralSE") as AudioStreamPlayer).playing

	# プレイヤー由来のドロップは動物用倍率を掛けず、実量をそのまま回収する。
	var player_drop := DungPickup.create(0.5, 1)
	add_child(player_drop)
	player_drop.global_position = Vector3.ZERO
	for _i in 4:
		await get_tree().physics_frame
	var player_drop_ok := is_equal_approx(player.size, expected + 0.5) \
		and not is_instance_valid(player_drop)

	# 地面フンの見た目倍率がプレイヤーの size_to_scale から独立していることを確認。
	var old_player_scale: float = Config.balance.size_to_scale
	var old_pickup_scale: float = Config.balance.pickup_size_to_scale
	var old_visual_mode: int = Config.balance.size_visual_mode
	var old_radius_max: float = Config.balance.visual_radius_max
	Config.balance.visual_radius_max = 0.0
	Config.balance.size_visual_mode = 0
	Config.balance.size_to_scale = 0.05
	Config.balance.pickup_size_to_scale = 0.4
	var scale_probe := DungPickup.create(2.0, -1)
	var scale_ok := is_equal_approx(scale_probe._radius(), 0.8)

	# 体積ベースでは内部サイズ8倍→見た目半径2倍。プレイヤーと地面フンの双方に適用する。
	Config.balance.size_visual_mode = 1
	var reference := maxf(Config.balance.size_start, 0.001)
	var volume_amount := reference * 8.0
	var visual_amount := Config.balance.visual_size(volume_amount)
	var volume_formula_ok := is_equal_approx(visual_amount, reference * 2.0)
	scale_probe.size = volume_amount
	var pickup_volume_ok := is_equal_approx(
		scale_probe._radius(), maxf(0.2, visual_amount * Config.balance.pickup_size_to_scale))
	player.size = volume_amount
	var player_volume_ok := is_equal_approx(
		player._radius(), maxf(0.2, visual_amount * Config.balance.size_to_scale))

	# 対数表示も開始サイズでLinearと一致し、終盤はVolumeBasedより差が見えやすい曲線になる。
	Config.balance.size_visual_mode = 2
	var log_start_ok := is_equal_approx(Config.balance.visual_size(reference), reference)
	var log_amount := Config.balance.visual_size(volume_amount)
	var log_curve_ok := log_amount > visual_amount and log_amount < volume_amount
	var pickup_log_ok := is_equal_approx(
		scale_probe._radius(), maxf(0.2, log_amount * Config.balance.pickup_size_to_scale))
	var player_log_ok := is_equal_approx(
		player._radius(), maxf(0.2, log_amount * Config.balance.size_to_scale))

	# 半径上限はプレイヤーと地面フンの見た目だけを制限する。
	Config.balance.visual_radius_max = 0.6
	Config.balance.size_to_scale = 1.0
	Config.balance.pickup_size_to_scale = 1.0
	var radius_cap_ok := is_equal_approx(player._radius(), 0.6) \
		and is_equal_approx(scale_probe._radius(), 0.6)

	# 表示モードや半径上限にかかわらず内部サイズの増加量は制限されない。
	var logical_before := player.size
	player.add_size(0.25)
	var logical_growth_ok := is_equal_approx(player.size, logical_before + 0.25)

	# 実獲得量のしきい値で通常・大きめ・最大級の取得SEが選ばれる。
	var high_amount := lerpf(
		Config.balance.pickup_se_neutral_max,
		Config.balance.pickup_se_high_high_min,
		0.5
	)
	player.play_pickup_se(high_amount)
	var high_se_ok := (player.get_node("GetHighSE") as AudioStreamPlayer).playing
	player.play_pickup_se(Config.balance.pickup_se_high_high_min)
	var high_high_se_ok := (player.get_node("GetHighHighSE") as AudioStreamPlayer).playing
	var pickup_se_ok := neutral_se_ok and high_se_ok and high_high_se_ok

	scale_probe.free()
	Config.balance.size_to_scale = old_player_scale
	Config.balance.pickup_size_to_scale = old_pickup_scale
	Config.balance.size_visual_mode = old_visual_mode
	Config.balance.visual_radius_max = old_radius_max

	var volume_ok := volume_formula_ok and pickup_volume_ok and player_volume_ok
	var log_ok := log_start_ok and log_curve_ok and pickup_log_ok and player_log_ok
	var ok: bool = got.hit and gain_ok and player_drop_ok and scale_ok and volume_ok and log_ok \
		and radius_cap_ok \
		and logical_growth_ok \
		and pickup_se_ok \
		and not is_instance_valid(pickup)
	print("[pickup_check] result=", ("PASS" if ok else "FAIL"),
		" collected=", got.hit, " size ", before, " -> ", player.size,
		" animal_gain=", gain_ok, " player_drop_full_amount=", player_drop_ok,
		" scale_independent=", scale_ok, " volume_visual=", volume_ok,
		" log_visual=", log_ok, " radius_cap=", radius_cap_ok,
		" logical_growth=", logical_growth_ok, " pickup_se=", pickup_se_ok,
		" pickup_freed=", not is_instance_valid(pickup))
	for child in player.get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stop()
	player.queue_free()
	for _i in 2:
		await get_tree().physics_frame
	get_tree().quit(0 if ok else 1)
