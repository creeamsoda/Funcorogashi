extends Node
## 実際の画面遷移を通す統合テスト。APPDATAを試験用へ切り替えて実行する。

var _failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	# 検証役はrootに残し、実際のcurrent_sceneをメニュー/試合へ切り替える。
	get_tree().current_scene = null
	MatchSession.show_menu(get_tree())
	await get_tree().scene_changed
	var menu := get_tree().current_scene
	var solo_button := menu.find_child("SoloButton", true, false) as Button
	_check(solo_button != null and solo_button.has_focus(), "menu_focus")
	solo_button.pressed.emit()
	await get_tree().scene_changed
	var game := get_tree().current_scene as GameManager
	game.record_scores = false
	_check(game.mode == "solo" and game.players.size() == 1 and game.duration == 180.0, "solo_start")
	_check(Config.balance.player_count == 4, "shared_player_count")
	var player := game.players[0]
	player.input_device = 9999
	_check(not player.get_node("LeaderCrown").visible, "no_solo_crown")
	_check(not player.debug_growth_enabled, "debug_growth_off")
	var profile := game.score_profile
	var clone := game.course.duplicate(true) as SoloCourse
	_check(profile == MatchSession.score_profile(clone, Config.balance), "profile_stable")
	clone.duration += 1.0
	_check(profile != MatchSession.score_profile(clone, Config.balance), "profile_duration_split")
	var balance := Config.balance.duplicate(true) as BalanceConfig
	balance.drop_ratio += 0.01
	_check(profile != MatchSession.score_profile(game.course, balance), "profile_balance_split")
	game._physics_process(6.2)
	var npcs := get_tree().get_nodes_in_group("npc")
	_check(npcs.size() == 1 and game.players.size() == 1, "npc_not_participant")
	var npc := npcs[0] as NpcBeetle
	_check(npc._alive_elapsed >= 0.19, "npc_late_spawn_age")
	var before_npc := npc.size
	player._resolve_dash_contact(npc)
	_check(npc.size < before_npc and game.stats[0]["dash_hits"] == 1, "npc_hit_stat")
	player.add_size(10.0)
	var finished := {"count": 0}
	game.match_ended.connect(func(_results: Array) -> void: finished["count"] += 1)
	game.time_left = 0.01
	game._physics_process(0.02)
	var final_score: float = game.final_results[0]["size"]
	var before_position := player.position
	player.add_size(100.0)
	player.apply_orangutan_hit()
	player.drop_and_stun()
	player._physics_process(1.0)
	game._end_match()
	game._on_dash_hit(0, npc.player_id)
	_check(finished["count"] == 1, "finish_once")
	_check(player.size == final_score and player.position == before_position, "frozen_after_finish")
	_check(game.stats[0]["dash_hits"] == 1, "ignore_late_hits")
	_check(game.get_node("World").process_mode == Node.PROCESS_MODE_DISABLED, "world_stopped")
	_check(game.spawn_pickup(Vector3.ZERO, 1.0) == null, "ignore_late_supply")
	await get_tree().process_frame
	var result := _solo_result(game)
	_check(result != null, "solo_result")
	var retry := result.find_child("RetryButton", true, false) as Button
	_check(retry != null and retry.has_focus(), "retry_focus")
	retry.pressed.emit()
	await get_tree().scene_changed
	game = get_tree().current_scene as GameManager
	game.record_scores = false
	_check(game.mode == "solo" and game.players.size() == 1, "retry_mode")
	_check(game.time_left > 179.0 and game.stats[0]["dash_hits"] == 0, "retry_clock_stats")
	_check(game.players[0].size == Config.balance.size_start and get_tree().get_nodes_in_group("npc").is_empty(), "retry_world")
	_check(game.score_profile == profile, "retry_profile")
	game.time_left = 0.01
	game._physics_process(0.02)
	await get_tree().process_frame
	_solo_result(game).find_child("MenuButton", true, false).pressed.emit()
	await get_tree().scene_changed
	menu = get_tree().current_scene
	menu.find_child("VersusButton", true, false).pressed.emit()
	await get_tree().scene_changed
	game = get_tree().current_scene as GameManager
	_check(game.mode == "versus" and game.players.size() == 4, "switch_back_versus")
	_check(game.get_node_or_null("World/SoloDirector") == null, "versus_random_spawner")
	game.time_left = 0.01
	game._physics_process(0.02)
	var versus_result: Results
	for child in game.get_children():
		if child is Results:
			versus_result = child
	_check(versus_result != null and game.final_results.size() == 4, "versus_results")
	versus_result.animation_speed_scale = 0.01
	await versus_result.presentation_finished
	_check(versus_result.find_child("MenuButton", true, false).visible, "versus_menu_option")
	print("[solo_flow_check] result=", "PASS" if _failures.is_empty() else "FAIL", " failures=", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _solo_result(game: GameManager) -> SoloResults:
	for child in game.get_children():
		if child is SoloResults:
			return child
	return null

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
		push_error("solo_flow_check: " + label)
