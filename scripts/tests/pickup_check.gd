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

	var ok: bool = got.hit and player.size > before and not is_instance_valid(pickup)
	print("[pickup_check] result=", ("PASS" if ok else "FAIL"),
		" collected=", got.hit, " size ", before, " -> ", player.size,
		" pickup_freed=", not is_instance_valid(pickup))
	get_tree().quit(0 if ok else 1)
