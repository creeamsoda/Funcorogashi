extends Node3D
## Track E 見た目確認(結果画面): モックの成績で結果表示。

func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	var res := (load("res://scenes/ui/Results.tscn") as PackedScene).instantiate() as Results
	add_child(res)
	res.show_results([
		{"player_id": 0, "size": 3.4, "dash_hits": 5},
		{"player_id": 1, "size": 1.2, "dash_hits": 9},
		{"player_id": 2, "size": 5.1, "dash_hits": 2},
		{"player_id": 3, "size": 2.0, "dash_hits": 4},
	])
