extends Node3D
## Track B 操作テスト用シーン: Stage + プレイヤー1体(キーボード操作)。
##   矢印キー: 移動 / Space: フン成長(疑似取り込み)
## スクショ検証用: 起動引数 --size=N で開始サイズを上書きできる。

func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())

	var player: Player = (load("res://scenes/Player.tscn") as PackedScene).instantiate()
	player.player_id = 0
	player.input_device = -1

	var sz := -1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			sz = float(a.trim_prefix("--size="))
	if sz > 0.0:
		player.initial_size = sz

	add_child(player)
	player.position = Vector3(0, 0.5, 0)
	player.size_changed.connect(func(id: int, s: float) -> void:
		print("P", id, " size=", "%.2f" % s))
