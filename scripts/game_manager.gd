class_name GameManager
extends Node3D
## モード別の試合構築、共通時計、終了時の凍結と結果確定。

signal time_changed(time_left: float)
signal match_ended(results: Array)

const SPAWN_SPOTS := [
	Vector3(-9, 0, -6), Vector3(9, 0, -6), Vector3(-9, 0, 6), Vector3(9, 0, 6),
]
const SPAWN_SPOTS_2P := [Vector3(-9, 0, 0), Vector3(9, 0, 0)] ## 2人は左右中央に対称配置
const CROWN_HIDE_TIME := 30.0

@export_enum("session", "versus", "solo") var mode := "session"
@export var record_scores := true
var course: SoloCourse
var elapsed := 0.0
var duration := 0.0
var score_profile := ""
var final_results: Array = []
var npc_hit_counts: Dictionary = {}
var players: Array[Player] = []
var stats := {}          ## player_id -> {dash_hits:int, dash_hits_received:int, pickups:int}
var time_left := 0.0
var _running := false
var _dung: Node3D
var _hud: Hud
var _crown_hidden := false
var _world: Node3D
var _director: SoloDirector
var _score_store := ScoreStore.new()
var _run_id := ""


func _ready() -> void:
	# 時計を先に更新し、期限を迎えた物理tickでは成長・衝突を受け付けない。
	process_physics_priority = -100
	if mode == "session":
		mode = MatchSession.mode
	if mode == "solo":
		if course == null:
			course = MatchSession.load_course()
		duration = course.duration
		score_profile = MatchSession.score_profile(course, Config.balance)
		_run_id = MatchSession.new_run_id()
	else:
		duration = Config.balance.match_duration
	time_left = duration
	for device in Input.get_connected_joypads():
		if InputRouter.is_combined_joycon(device):
			push_warning(
				"[input] Joy-Con device %d is still combined. " % device
				+ "Restart Godot via tools/start_godot_separate_joycons.cmd."
			)
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	var stage := load("res://scenes/Stage.tscn").instantiate() as Stage
	stage.layout = Stage.load_layout(Config.balance.solo_stage_layout if mode == "solo" else Config.balance.stage_layout)
	_world.add_child(stage)

	_dung = Node3D.new()
	_dung.name = "Dung"
	_dung.add_to_group("dung_container")
	_world.add_child(_dung)

	_spawn_players()
	_update_leader_crown()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	if mode == "solo":
		_director = SoloDirector.new()
		_director.name = "SoloDirector"
		_director.course = course
		_director.npc_requested.connect(_spawn_npc)
		_world.add_child(_director)
	else:
		_world.add_child(load("res://scenes/animals/AnimalSpawner.tscn").instantiate())

	_hud = (load("res://scenes/ui/HUD.tscn") as PackedScene).instantiate() as Hud
	add_child(_hud)
	if mode == "solo":
		_hud.setup_solo(duration, _score_store.best(score_profile))
	else:
		_hud.setup(players.size())
	_hud.set_time(time_left)
	if OS.is_debug_build():
		var debug_tools := DebugTools.new()
		debug_tools.name = "DebugTools"
		add_child(debug_tools)
	_running = true
	if _director != null:
		_director.advance_to(0.0)


func _spawn_players() -> void:
	var n: int = 1 if mode == "solo" else InputRouter.versus_player_count(clampi(Config.balance.player_count, 1, 4))
	var srcs := InputRouter.sources(n)
	var spots: Array = SPAWN_SPOTS_2P if n == 2 else SPAWN_SPOTS
	var stage := get_tree().get_first_node_in_group("stage") as Stage
	if n != 2 and stage != null and stage.layout != null and stage.layout.spawn_spots.size() >= n:
		spots = stage.layout.spawn_spots
	for i in n:
		var p: Player = (load("res://scenes/Player.tscn") as PackedScene).instantiate()
		p.player_id = i
		p.input_device = srcs[i]["device"]
		if mode == "solo":
			p.set_scatter_seed(173 + i)
		_world.add_child(p)
		p.global_position = course.player_start if mode == "solo" else spots[i % spots.size()]
		p.suppress_dash_until_release()
		players.append(p)
		stats[i] = {"dash_hits": 0, "dash_hits_received": 0, "pickups": 0}
		p.size_changed.connect(_on_size_changed)
		p.dash_hit.connect(_on_dash_hit)
		_log_assignment(p)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	# 起動後にコントローラが増減したら割り当てを更新(起動直後の列挙漏れ対策)
	var srcs := InputRouter.sources(players.size())
	for i in players.size():
		players[i].input_device = srcs[i]["device"]
		players[i].suppress_dash_until_release()
		_log_assignment(players[i])

func _log_assignment(p: Player) -> void:
	var label := "idle"
	if p.input_device == -1:
		label = "keyboard-arrows"
	elif p.input_device == -2:
		label = "keyboard-WASD"
	elif InputRouter.is_joypad(p.input_device):
		label = "joypad%d (%s)" % [p.input_device, Input.get_joy_name(p.input_device)]
	print("[input] P", p.player_id + 1, " (", label, ")")


func _physics_process(delta: float) -> void:
	if not _running:
		return
	time_left = maxf(0.0, time_left - delta)
	elapsed = duration - time_left
	if not _crown_hidden and time_left <= CROWN_HIDE_TIME:
		_crown_hidden = true
		_hide_all_crowns()
	time_changed.emit(time_left)
	if _hud != null:
		_hud.set_time(time_left)
	# 最後のフレームでも、期限より前の予定を消化してから確定する。
	if _director != null:
		_director.advance_to(minf(elapsed, maxf(0.0, duration - 0.000001)))
	if time_left <= 0.0:
		_end_match()


func _on_size_changed(pid: int, size: float) -> void:
	if not _running:
		return
	if _hud != null:
		_hud.set_size(pid, size)
	if not _crown_hidden:
		_update_leader_crown()


func _on_dash_hit(attacker_id: int, victim_id: int) -> void:
	if not _running:
		return
	if stats.has(attacker_id):
		stats[attacker_id]["dash_hits"] += 1
	if stats.has(victim_id):
		stats[victim_id]["dash_hits_received"] += 1
	elif mode == "solo" and stats.has(attacker_id):
		npc_hit_counts[victim_id] = int(npc_hit_counts.get(victim_id, 0)) + 1
		_hud.set_npc_hits(int(stats[attacker_id]["dash_hits"]))


func _spawn_npc(event: SoloEvent, event_index: int) -> void:
	if not _running:
		return
	var npc := NpcBeetle.new()
	npc.name = "Npc%d" % event_index
	npc.player_id = 1000 + event_index
	npc.initial_size = event.npc_size
	npc.set_scatter_seed(7919 + event_index * 37)
	npc.setup_route(event.path, event.speed, event.npc_sway, event.npc_sway_period, event.npc_lifetime)
	_world.add_child(npc)
	npc.advance_spawn_age(maxf(0.0, elapsed - event.at))


## 契約 §6-2: 動物や突進ドロップからフンを生成する共通入口。
func spawn_pickup(pos: Vector3, size: float, owner_id: int = -1) -> DungPickup:
	if not _running:
		return null
	var pk := DungPickup.create(size, owner_id)
	_dung.add_child(pk)
	pk.global_position = Vector3(pos.x, 0.0, pos.z)
	return pk


func _end_match() -> void:
	if not _running:
		return
	_running = false
	_hide_all_crowns()
	for node in _world.get_children():
		if node is Player:
			node.stop_gameplay()
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	var results: Array = []
	for p in players:
		results.append({
			"player_id": p.player_id,
			"size": p.size,
			"dash_hits": stats[p.player_id]["dash_hits"],
			"dash_hits_received": stats[p.player_id]["dash_hits_received"],
		})
	final_results = results.duplicate(true)
	match_ended.emit(results.duplicate(true))
	if mode == "solo":
		var final_score: float = final_results[0]["size"]
		var record_result := {
			"saved": false, "new_best": false, "best": _score_store.best(score_profile),
			"records": _score_store.records(score_profile), "error": "",
		}
		var eligible := record_scores and time_left <= 0.0 and not players[0].debug_growth_enabled and not players[0].debug_growth_used
		# 実行中に調整値を書き換えた試合は通常記録と混ぜない。
		eligible = eligible and score_profile == MatchSession.score_profile(course, Config.balance)
		if eligible:
			record_result = _score_store.submit(score_profile, final_score, _run_id)
		else:
			record_result["error"] = "練習プレイ：記録は保存しません"
		var solo_results := SoloResults.new()
		add_child(solo_results)
		solo_results.retry_requested.connect(_retry)
		solo_results.menu_requested.connect(_menu)
		solo_results.show_score(final_score, int(final_results[0]["dash_hits"]), record_result)
	else:
		var res := (load("res://scenes/ui/Results.tscn") as PackedScene).instantiate() as Results
		add_child(res)
		res.retry_requested.connect(_retry)
		res.menu_requested.connect(_menu)
		res.show_results(results)


func _retry() -> void:
	MatchSession.mode = mode
	if mode == "solo":
		MatchSession.course_override = course
	MatchSession.retry(get_tree())


func _menu() -> void:
	MatchSession.show_menu(get_tree())


func _update_leader_crown() -> void:
	if players.is_empty() or _crown_hidden or mode == "solo":
		return
	var leader: Player = players[0]
	for p in players:
		if p.size > leader.size:
			leader = p
	for p in players:
		p.set_crown_visible(p == leader)


func _hide_all_crowns() -> void:
	for p in players:
		p.set_crown_visible(false)
