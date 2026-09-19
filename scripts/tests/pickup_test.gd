extends Node3D
## Track C 見た目確認: ステージに大小のドロップフンを散布(スクショ用)。

func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 10:
		var pk := DungPickup.create(rng.randf_range(0.4, 1.4), -1)
		add_child(pk)
		pk.global_position = Vector3(rng.randf_range(-10, 10), 0, rng.randf_range(-6, 6))
