extends Node3D
## スクリーンショット用の一人用プレイ状態。記録を書かず、14秒時点を表示する。

func _ready() -> void:
	var game := GameManager.new()
	game.mode = "solo"
	game.record_scores = false
	add_child(game)
	game.players[0].input_device = 9999
	game.players[0].add_size(9.0)
	game.players[0].position.x = 3.0
	game._physics_process(14.0)
	game.set_physics_process(false)
	game.get_node("World").process_mode = Node.PROCESS_MODE_DISABLED
