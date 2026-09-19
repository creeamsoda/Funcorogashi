extends Node3D
## Track E 見た目確認(HUD): ステージにHUDを重ねモックデータを表示。

func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	var hud := (load("res://scenes/ui/HUD.tscn") as PackedScene).instantiate() as Hud
	add_child(hud)
	hud.setup(4)
	hud.set_time(137.0)
	hud.set_size(0, 3.4)
	hud.set_size(1, 1.2)
	hud.set_size(2, 5.1)
	hud.set_size(3, 2.0)
