extends Node
## チュートリアル・人数選択まわりの headless 自動テスト:
##  - PlayerSlots の先着順割り当て(押し直しで割り当て・人数超過は無視・切断で空き枠)
##  - チュートリアル: 全員が突進を当てると特殊フン紹介へ進み、5秒後に試合へ
##  - 試合: 開始演出の間は時計が止まり、「スタート！」から進む

func _ready() -> void:
	var fails: Array[String] = []

	# --- PlayerSlots ---
	PlayerSlots.begin_with_pads(2, [3, 5, 7] as Array[int])
	if not PlayerSlots.first_come:
		fails.append("first_come should be on with 3 pads")
	PlayerSlots.observe(7, true)
	PlayerSlots.observe(7, true)   # 押しっぱなしは1回だけ
	PlayerSlots.observe(3, true)
	PlayerSlots.observe(5, true)   # 3人目は無視
	if PlayerSlots.device_for(0) != 7 or PlayerSlots.device_for(1) != 3:
		fails.append("first-come order wrong: %d %d" % [PlayerSlots.device_for(0), PlayerSlots.device_for(1)])
	PlayerSlots._on_joy_connection_changed(7, false)
	if PlayerSlots.device_for(0) < 9000:
		fails.append("disconnected slot should be idle")
	PlayerSlots.observe(5, false)
	PlayerSlots.observe(5, true)
	if PlayerSlots.device_for(0) != 5:
		fails.append("freed slot should be refilled by next input")
	PlayerSlots.begin_with_pads(3, [] as Array[int])
	if PlayerSlots.first_come:
		fails.append("first_come should be off with 0 pads")

	# --- Tutorial (キーボード併用 3人: 矢印, WASD, 待機) ---
	var tut: Node = (load("res://scenes/Tutorial.tscn") as PackedScene).instantiate()
	add_child(tut)
	await get_tree().physics_frame
	var players: Array = tut.players
	if players.size() != 3:
		fails.append("tutorial players=%d" % players.size())
	if get_tree().get_nodes_in_group("npc").size() != 1:
		fails.append("tutorial npc missing")
	if not get_tree().get_nodes_in_group("boost_pad").is_empty():
		fails.append("boost pads should be removed")
	var npc := get_tree().get_nodes_in_group("npc")[0] as Player
	var npc_size := npc.size
	players[0].dash_hit.emit(0, npc.player_id)
	npc.drop_and_stun()
	if not is_equal_approx(npc.size, npc_size):
		fails.append("npc should keep its size")
	if tut._phase != 0:
		fails.append("should still be in hit phase")
	players[1].dash_hit.emit(1, 0)
	await get_tree().create_timer(1.5).timeout
	if tut._phase != 2:
		fails.append("should be explaining (phase=%d)" % tut._phase)
	if get_tree().get_nodes_in_group(DungPickup.SPECIAL_GROUP).size() != 2:
		fails.append("explain should show 2 special dung")
	tut.set_process(false) # 試合へは遷移させない
	tut.queue_free()
	PlayerSlots.end()

	# --- Game intro ---
	MatchSession.mode = "versus"
	PlayerSlots.begin_with_pads(2, [] as Array[int])
	var gm: GameManager = (load("res://scenes/Game.tscn") as PackedScene).instantiate()
	add_child(gm)
	await get_tree().create_timer(0.8).timeout
	if gm.players.size() != 2:
		fails.append("game players=%d" % gm.players.size())
	if not is_equal_approx(gm.time_left, gm.duration):
		fails.append("clock should wait during intro (%.2f)" % gm.time_left)
	await get_tree().create_timer(1.2).timeout
	if gm.time_left >= gm.duration:
		fails.append("clock should run after start")
	PlayerSlots.end()

	var ok := fails.is_empty()
	print("[tutorial_flow_check] result=", "PASS" if ok else "FAIL ", fails)
	get_tree().quit(0 if ok else 1)
