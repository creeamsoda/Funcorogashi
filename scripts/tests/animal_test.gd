extends Node3D
## Track D 見た目確認: 3種の動物をステージ上に配置(スクショ用)。

func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	var dung := Node3D.new()
	dung.name = "Dung"
	dung.add_to_group("dung_container")
	add_child(dung)

	var bird := load("res://scenes/animals/Bird.tscn").instantiate() as Node3D
	add_child(bird)
	bird.position = Vector3(-6, 2.5, -4)

	var rap := load("res://scenes/animals/Raptor.tscn").instantiate() as Node3D
	add_child(rap)
	rap.position = Vector3(2, 0.4, 1)

	var ora := load("res://scenes/animals/Orangutan.tscn").instantiate() as Node3D
	add_child(ora)
	ora.position = Vector3(8, 1.4, 9)
