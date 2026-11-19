extends Node3D
## Track E 見た目確認(結果画面): モックの成績で結果表示。

func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	var res := (load("res://scenes/ui/Results.tscn") as PackedScene).instantiate() as Results
	add_child(res)
	res.animation_speed_scale = 0.12
	res.show_results([
		{"player_id": 0, "size": 3.4, "dash_hits": 6, "dash_hits_received": 5, "dash_drop_amount": 4.2,
			"pickups": 30, "special_pickups": 1, "wall_crashes": 2, "boost_pads": 3},
		{"player_id": 1, "size": 1.2, "dash_hits": 2, "dash_hits_received": 9, "dash_drop_amount": 1.0,
			"pickups": 18, "special_pickups": 2, "wall_crashes": 7, "boost_pads": 3},
		{"player_id": 2, "size": 5.1, "dash_hits": 4, "dash_hits_received": 2, "dash_drop_amount": 6.5,
			"pickups": 41, "special_pickups": 0, "wall_crashes": 1, "boost_pads": 1},
		{"player_id": 3, "size": 2.0, "dash_hits": 3, "dash_hits_received": 4, "dash_drop_amount": 2.0,
			"pickups": 22, "special_pickups": 2, "wall_crashes": 0, "boost_pads": 0},
	])
