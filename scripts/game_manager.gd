class_name GameManager
extends Node3D
## コアループ統合(I1): ステージ + 4プレイヤー + 動物スポナー + HUD + 制限時間 + 勝敗判定→結果。
## 突進(I3)・4人入力(I2)は後続で拡張。ここでは P0=キーボード、他は待機。

signal time_changed(time_left: float)
signal match_ended(results: Array)

const SPAWN_SPOTS := [
	Vector3(-9, 0, -6), Vector3(9, 0, -6), Vector3(-9, 0, 6), Vector3(9, 0, 6),
]

var players: Array[Player] = []
var stats := {}          ## player_id -> {dash_hits:int, pickups:int}
var time_left := 0.0
var _running := false
var _dung: Node3D
var _hud: Hud


func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())

	_dung = Node3D.new()
	_dung.name = "Dung"
	_dung.add_to_group("dung_container")
	add_child(_dung)

	_spawn_players()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	add_child(load("res://scenes/animals/AnimalSpawner.tscn").instantiate())

	_hud = (load("res://scenes/ui/HUD.tscn") as PackedScene).instantiate() as Hud
	add_child(_hud)
	_hud.setup(players.size())

	time_left = Config.balance.match_duration
	_running = true


func _spawn_players() -> void:
	var n: int = Config.balance.player_count
	var srcs := InputRouter.sources(n)
	for i in n:
		var p: Player = (load("res://scenes/Player.tscn") as PackedScene).instantiate()
		p.player_id = i
		p.input_device = srcs[i]["device"]
		p.input_stick = srcs[i]["stick"]
		add_child(p)
		p.global_position = SPAWN_SPOTS[i % SPAWN_SPOTS.size()]
		players.append(p)
		stats[i] = {"dash_hits": 0, "pickups": 0}
		p.size_changed.connect(_on_size_changed)
		p.dash_hit.connect(_on_dash_hit)
		_log_assignment(p)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	# 起動後にコントローラが増減したら割り当てを更新(起動直後の列挙漏れ対策)
	var srcs := InputRouter.sources(players.size())
	for i in players.size():
		players[i].input_device = srcs[i]["device"]
		players[i].input_stick = srcs[i]["stick"]
		_log_assignment(players[i])

func _log_assignment(p: Player) -> void:
	var label := "idle"
	if p.input_device == -1:
		label = "keyboard-arrows"
	elif p.input_device == -2:
		label = "keyboard-WASD"
	elif p.input_device >= 0 and p.input_device < 9000:
		var stick := "R" if p.input_stick == 1 else "L"
		label = "joypad%d-%sstick (%s)" % [p.input_device, stick, Input.get_joy_name(p.input_device)]
	print("[input] P", p.player_id + 1, " (", label, ")")


func _process(delta: float) -> void:
	if not _running:
		return
	time_left -= delta
	time_changed.emit(time_left)
	if _hud != null:
		_hud.set_time(time_left)
	if time_left <= 0.0:
		_end_match()


func _on_size_changed(pid: int, size: float) -> void:
	if _hud != null:
		_hud.set_size(pid, size)


func _on_dash_hit(attacker_id: int, _victim_id: int) -> void:
	if stats.has(attacker_id):
		stats[attacker_id]["dash_hits"] += 1


## 契約 §6-2: 動物や突進ドロップからフンを生成する共通入口。
func spawn_pickup(pos: Vector3, size: float, owner_id: int = -1) -> DungPickup:
	var pk := DungPickup.create(size, owner_id)
	_dung.add_child(pk)
	pk.global_position = Vector3(pos.x, 0.0, pos.z)
	return pk


func _end_match() -> void:
	_running = false
	var results: Array = []
	for p in players:
		results.append({
			"player_id": p.player_id,
			"size": p.size,
			"dash_hits": stats[p.player_id]["dash_hits"],
		})
	match_ended.emit(results)
	var res := (load("res://scenes/ui/Results.tscn") as PackedScene).instantiate() as Results
	add_child(res)
	res.show_results(results)
