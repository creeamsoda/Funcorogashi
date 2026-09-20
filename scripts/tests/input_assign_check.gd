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

	var four_pads := InputRouter.sources_from_pads(4, [2, 4, 6, 8])
	var four_devices: Array[int] = []
	for source in four_pads:
		four_devices.append(source["device"])
	var individual_ok: bool = four_devices == [2, 4, 6, 8]
	var two_pads := InputRouter.sources_from_pads(4, [3, 7])
	var fallback_ok: bool = two_pads[0]["device"] == 3 and two_pads[1]["device"] == 7 \
		and two_pads[2]["device"] == -1 and two_pads[3]["device"] == -2
	var combined_detection_ok: bool = InputRouter.is_combined_joycon_name("Nintendo Switch Joy-Con (L/R)") \
		and not InputRouter.is_combined_joycon_name("Nintendo Switch Joy-Con (L)") \
		and not InputRouter.is_combined_joycon_name("Nintendo Switch Joy-Con (R)")
	ok = ok and individual_ok and fallback_ok and combined_detection_ok
	print("[input_assign_check] result=", ("PASS" if ok else "FAIL"),
		" pads=", pads.size(), " devices=", str(devs),
		" individual=", individual_ok, " fallback=", fallback_ok,
		" combined_detection=", combined_detection_ok)
	get_tree().quit(0 if ok else 1)
