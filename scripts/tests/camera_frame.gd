extends Node3D
## カメラ画角の調整用シーン。ステージ+4人+オランウータン(近い南外)を置き、
## 起動引数 --camy / --camz でカメラ位置を差し替えて見え方を比較する。
##   例: -- --camy=26 --camz=18

const SPOTS := [Vector3(-9, 0, -6), Vector3(9, 0, -6), Vector3(-9, 0, 6), Vector3(9, 0, 6)]

func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	var dung := Node3D.new()
	dung.add_to_group("dung_container")
	add_child(dung)

	for i in 4:
		var p: Player = (load("res://scenes/Player.tscn") as PackedScene).instantiate()
		p.player_id = i
		p.input_device = 9999
		add_child(p)
		p.global_position = SPOTS[i]

	var ora := load("res://scenes/animals/Orangutan.tscn").instantiate() as Node3D
	add_child(ora)
	ora.position = Vector3(0, 1.4, 15) # 南の壁外(手前)に固定

	var camy := 26.0
	var camz := 16.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--camy="):
			camy = float(a.trim_prefix("--camy="))
		elif a.begins_with("--camz="):
			camz = float(a.trim_prefix("--camz="))

	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, camy, camz)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.fov = 60.0
	cam.make_current()
