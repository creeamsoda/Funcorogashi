extends Node3D
## 入力キャリブ画面: 4プレイヤーを実際に動かして、割り当て・回転・入力を確認・調整する。
##  [1][2][3][4] : そのプレイヤー(P1〜P4)の入力を90°回転(横持ちの向き合わせ)
##  各Joy-Conを動かして「どのPが動くか」「上倒し→キャラが上へ」になるよう回転を合わせ、
##  画面下部に出る rot 値を教えてください(ゲーム本編に反映します)。

const SPOTS := [Vector3(-6, 0, -4), Vector3(6, 0, -4), Vector3(-6, 0, 4), Vector3(6, 0, 4)]

var _players: Array[Player] = []
var _label: Label
var _last_btn := "(まだ押されていません)"

func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	var dung := Node3D.new()
	dung.add_to_group("dung_container")
	add_child(dung)

	var srcs := InputRouter.sources(4)
	for i in 4:
		var p: Player = (load("res://scenes/Player.tscn") as PackedScene).instantiate()
		p.player_id = i
		p.input_device = srcs[i]["device"]
		p.input_stick = srcs[i]["stick"]
		add_child(p)
		p.global_position = SPOTS[i]
		_players.append(p)

	var cl := CanvasLayer.new()
	add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.size = Vector2(1280, 250)
	cl.add_child(bg)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	_label.position = Vector2(16, 10)
	cl.add_child(_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var idx := -1
		match (event as InputEventKey).keycode:
			KEY_1: idx = 0
			KEY_2: idx = 1
			KEY_3: idx = 2
			KEY_4: idx = 3
		if idx >= 0 and idx < _players.size():
			var p := _players[idx]
			p.input_rotation_deg = fmod(p.input_rotation_deg + 90.0, 360.0)
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var b := event as InputEventJoypadButton
		_last_btn = "dev%d  BTN %d" % [b.device, b.button_index]

func _process(_dt: float) -> void:
	var lines: Array[String] = ["=== INPUT CALIB ===  [1][2][3][4] = そのPの入力を90度回転"]
	lines.append("各Joy-Conを動かして、上倒し→キャラ上 になるよう合わせて rot を報告してください")
	for i in _players.size():
		var p := _players[i]
		var v := p.call("_read_move") as Vector2
		var color: String = ["赤", "青", "緑", "黄"][i]
		var src := "kbd"
		if p.input_device >= 0 and p.input_device < 9000:
			src = "dev%d-%s" % [p.input_device, ("R" if p.input_stick == 1 else "L")]
		lines.append("P%d(%s)  %s  in(%+.2f,%+.2f)" % [i + 1, color, src, v.x, v.y])
	lines.append("突進ボタン確認: 押したボタン = " + _last_btn)
	_label.text = "\n".join(lines)
