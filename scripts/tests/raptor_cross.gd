extends Node3D
## ラプトル横断中の見た目確認(スクショ用)。左→右で固定して見やすくする。

func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	var dung := Node3D.new()
	dung.add_to_group("dung_container")
	add_child(dung)
	add_child(load("res://scenes/animals/Raptor.tscn").instantiate())
