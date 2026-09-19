extends Node3D
## 入力割り当ての headless 自動テスト(コントローラ0台想定):
##  P1=-1(矢印) / P2=-2(WASD) / P3,P4=待機(>=9000)

func _ready() -> void:
	var gm: GameManager = (load("res://scenes/Game.tscn") as PackedScene).instantiate()
	add_child(gm)
	await get_tree().process_frame

	var pads := Input.get_connected_joypads()
	var devs: Array[int] = []
	for p in gm.players:
		devs.append(p.input_device)

	var ok := gm.players.size() == Config.balance.player_count
	if pads.size() == 0:
		ok = ok and devs[0] == -1 and devs[1] == -2 and devs[2] >= 9000 and devs[3] >= 9000
	print("[input_assign_check] result=", ("PASS" if ok else "FAIL"),
		" pads=", pads.size(), " devices=", str(devs))
	get_tree().quit(0 if ok else 1)
