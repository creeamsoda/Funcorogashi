class_name GameManager
extends Node3D
## モード別の試合構築、共通時計、終了時の凍結と結果確定。
## versus: 人間2〜4人の対戦。solo(「ひとりで遊ぶ」): 人間1人+CPU3体の対戦(ルールは versus と同じ)。

signal time_changed(time_left: float)
signal match_ended(results: Array)

const SPAWN_SPOTS := [
	Vector3(-9, 0, -6), Vector3(9, 0, -6), Vector3(-9, 0, 6), Vector3(9, 0, 6),
]
const SPAWN_SPOTS_2P := [Vector3(-9, 0, 0), Vector3(9, 0, 0)] ## 2人は左右中央に対称配置
const CROWN_HIDE_TIME := 30.0
## 「ひとりで遊ぶ」の参加人数(人間1人+CPU)。
const SOLO_TOTAL_PLAYERS := 4
const SOLO_HUMAN_PLAYERS := 1
## 対戦開始の演出: 画面が切り替わった瞬間から動けるが、時計は「スタート！」表示から進める。
const INTRO_TEXT := "フンを一番でっかくしよう！"
const INTRO_FONT_SIZE := 84
const INTRO_TIME := 1.5
const START_TEXT := "スタート！"
const START_FONT_SIZE := 180
const START_SHOW_TIME := 1.0
## 試合中に集計して結果に載せる成績(結果画面の表彰に使う)。
const STAT_KEYS := [
	"dash_hits", "dash_hits_received", "dash_drop_amount",
	"pickups", "special_pickups", "wall_crashes", "boost_pads",
]

@export_enum("session", "versus", "solo") var mode := "session"
## 「ひとりで遊ぶ」の人間の人数と全体の人数(残りはCPU)。テストでCPUだけの試合にするときに変える。
@export var solo_human_count := SOLO_HUMAN_PLAYERS
@export var solo_total_count := SOLO_TOTAL_PLAYERS
var elapsed := 0.0
var duration := 0.0
var final_results: Array = []
var players: Array[Player] = []
## player_id -> 結果画面の表彰用の集計(STAT_KEYS 参照)
var stats := {}
var time_left := 0.0
var _running := false
var _clock_started := true
var _dung: Node3D
var _hud: Hud
var _crown_hidden := false
var _world: Node3D


func _ready() -> void:
	# 時計を先に更新し、期限を迎えた物理tickでは成長・衝突を受け付けない。
	process_physics_priority = -100
	# タイトル/チュートリアルから来た対戦だけ開始演出を出す(テストが mode を直接指定した場合は出さない)。
	var play_intro := false
	if mode == "session":
		mode = MatchSession.mode
		play_intro = mode == "versus" or mode == "solo"
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
	stage.layout = Stage.load_layout(Config.balance.stage_layout)
	_world.add_child(stage)

	_dung = Node3D.new()
	_dung.name = "Dung"
	_dung.add_to_group("dung_container")
	_world.add_child(_dung)

	_spawn_players()
	_update_leader_crown()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if mode != "solo" and PlayerSlots.is_active():
		PlayerSlots.assigned.connect(_on_slot_assigned)

	_world.add_child(load("res://scenes/animals/AnimalSpawner.tscn").instantiate())

	_hud = (load("res://scenes/ui/HUD.tscn") as PackedScene).instantiate() as Hud
	add_child(_hud)
	var names: Array[String] = []
	for p in players:
		names.append(display_name(p))
	_hud.setup(players.size(), names)
	_hud.set_time(time_left)
	if OS.is_debug_build():
		var debug_tools := DebugTools.new()
		debug_tools.name = "DebugTools"
		add_child(debug_tools)
	_running = true
	if play_intro:
		_play_intro()


func _play_intro() -> void:
	_clock_started = false
	_hud.show_banner(INTRO_TEXT, INTRO_FONT_SIZE)
	await get_tree().create_timer(INTRO_TIME, false).timeout
	if not is_inside_tree() or not _running:
		return
	_hud.show_banner(START_TEXT, START_FONT_SIZE)
	_clock_started = true
	await get_tree().create_timer(START_SHOW_TIME, false).timeout
	if is_inside_tree():
		_hud.hide_banner()


## 対戦の人数。タイトルで選んだ人数(PlayerSlots)があればそれ、無ければ接続台数から決める。
static func versus_player_count() -> int:
	if PlayerSlots.is_active():
		return PlayerSlots.count
	return InputRouter.versus_player_count(clampi(Config.balance.player_count, 1, 4))


## 対戦の入力デバイス(プレイヤーindex順)。
static func versus_devices(n: int) -> Array[int]:
	var out: Array[int] = []
	if PlayerSlots.is_active():
		for i in n:
			out.append(PlayerSlots.device_for(i))
	else:
		out = InputRouter.devices(n)
	return out


## n人の初期位置。2人は左右中央、それ以外はステージ指定(あれば)か四隅。
static func spawn_spots_for(n: int, stage: Stage) -> Array:
	if n == 2:
		return SPAWN_SPOTS_2P
	if stage != null and stage.layout != null and stage.layout.spawn_spots.size() >= n:
		return stage.layout.spawn_spots
	return SPAWN_SPOTS


## 人間の人数(残りはCPU)。
func human_count() -> int:
	return clampi(solo_human_count, 0, solo_total_count) if mode == "solo" else versus_player_count()


## 人間プレイヤーの入力デバイス(プレイヤーindex順)。
func _human_devices(n: int) -> Array[int]:
	return InputRouter.devices(n) if mode == "solo" else versus_devices(n)


## HUD・結果画面の名前。CPUは「CPU」、人間は「P番号」。
static func display_name(p: Player) -> String:
	return "CPU" if p is CpuBeetle else "P%d" % (p.player_id + 1)


func _spawn_players() -> void:
	var humans := human_count()
	var n: int = solo_total_count if mode == "solo" else humans
	var devices := _human_devices(humans)
	var spots: Array = spawn_spots_for(n, get_tree().get_first_node_in_group("stage") as Stage)
	for i in n:
		var p: Player
		if i < humans:
			p = (load("res://scenes/Player.tscn") as PackedScene).instantiate()
			p.input_device = devices[i]
		else:
			p = CpuBeetle.new()
			p.name = "Cpu%d" % i
		p.player_id = i
		_world.add_child(p)
		p.global_position = spots[i % spots.size()]
		p.suppress_dash_until_release()
		players.append(p)
		stats[i] = {}
		for key in STAT_KEYS:
			stats[i][key] = 0.0 if key == "dash_drop_amount" else 0
		p.size_changed.connect(_on_size_changed)
		p.dash_hit.connect(_on_dash_hit)
		p.dash_drop_caused.connect(_on_dash_drop_caused)
		p.dung_picked_up.connect(_on_dung_picked_up)
		p.wall_crashed.connect(func(pid: int) -> void: _add_stat(pid, "wall_crashes", 1))
		p.boost_pad_entered.connect(func(pid: int) -> void: _add_stat(pid, "boost_pads", 1))
		_log_assignment(p)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	# 先着順の割り当ては PlayerSlots が管理する(assigned で届く)。
	if mode != "solo" and PlayerSlots.first_come:
		return
	# 起動後にコントローラが増減したら割り当てを更新(起動直後の列挙漏れ対策)
	var humans := human_count()
	var devices := _human_devices(humans)
	for i in mini(humans, players.size()):
		players[i].input_device = devices[i]
		players[i].suppress_dash_until_release()
		_log_assignment(players[i])


func _on_slot_assigned(slot: int, _device: int) -> void:
	if slot < 0 or slot >= players.size() or players[slot] is CpuBeetle:
		return
	players[slot].input_device = PlayerSlots.device_for(slot)
	players[slot].suppress_dash_until_release()
	_log_assignment(players[slot])

func _log_assignment(p: Player) -> void:
	var label := "idle"
	if p is CpuBeetle:
		label = "CPU"
	elif p.input_device == -1:
		label = "keyboard-arrows"
	elif p.input_device == -2:
		label = "keyboard-WASD"
	elif InputRouter.is_joypad(p.input_device):
		label = "joypad%d (%s)" % [p.input_device, Input.get_joy_name(p.input_device)]
	print("[input] P", p.player_id + 1, " (", label, ")")


func _physics_process(delta: float) -> void:
	if not _running:
		return
	if _clock_started: # 開始演出の間は時計を止める(動くことはできる)
		time_left = maxf(0.0, time_left - delta)
	elapsed = duration - time_left
	if not _crown_hidden and time_left <= CROWN_HIDE_TIME:
		_crown_hidden = true
		_hide_all_crowns()
	time_changed.emit(time_left)
	if _hud != null:
		_hud.set_time(time_left)
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


func _on_dash_drop_caused(attacker_id: int, amount: float) -> void:
	_add_stat(attacker_id, "dash_drop_amount", amount)


func _on_dung_picked_up(pid: int, special: bool) -> void:
	_add_stat(pid, "pickups", 1)
	if special:
		_add_stat(pid, "special_pickups", 1)


func _add_stat(pid: int, key: String, amount: Variant) -> void:
	if _running and stats.has(pid):
		stats[pid][key] += amount


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
		var entry := {"player_id": p.player_id, "size": p.size, "cpu": p is CpuBeetle}
		entry.merge(stats[p.player_id])
		results.append(entry)
	final_results = results.duplicate(true)
	match_ended.emit(results.duplicate(true))
	var res := (load("res://scenes/ui/Results.tscn") as PackedScene).instantiate() as Results
	add_child(res)
	res.retry_requested.connect(_retry)
	res.menu_requested.connect(_menu)
	res.show_results(results)


func _retry() -> void:
	MatchSession.mode = mode
	MatchSession.retry(get_tree())


func _menu() -> void:
	MatchSession.show_menu(get_tree())


func _update_leader_crown() -> void:
	if players.is_empty() or _crown_hidden:
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
