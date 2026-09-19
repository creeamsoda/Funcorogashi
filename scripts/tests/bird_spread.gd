extends Node3D
## 鳥の斜め横断 見た目確認: 複数の鳥を出して角度のばらつきを確認(スクショ用)。

func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	var dung := Node3D.new()
	dung.add_to_group("dung_container")
	add_child(dung)
	for i in 4:
		add_child(load("res://scenes/animals/Bird.tscn").instantiate())
