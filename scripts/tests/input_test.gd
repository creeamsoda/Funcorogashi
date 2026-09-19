extends Node3D
## 入力診断ツール:
##  上段=各コントローラの「マッピング済み」スティック/ボタン(標準API)
##  下段=生のjoypadイベント(device/軸番号/ボタン番号) ← 未マッピングでも拾える
## Joy-Con のスティックを倒す/ボタンを押して、何が来るか確認する。

var _label: Label
var _recent: Array[String] = []

func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	var cl := CanvasLayer.new()
	add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.position = Vector2.ZERO
	bg.size = Vector2(1280, 470)
	cl.add_child(bg)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 19)
	_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	_label.position = Vector2(16, 10)
	cl.add_child(_label)

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		if absf(m.axis_value) > 0.35:
			_push("dev%d  AXIS %d = %+.2f" % [m.device, m.axis, m.axis_value])
	elif event is InputEventJoypadButton:
		var b := event as InputEventJoypadButton
		if b.pressed:
			_push("dev%d  BTN %d" % [b.device, b.button_index])

func _push(s: String) -> void:
	if _recent.size() > 0 and _recent[_recent.size() - 1] == s:
		return
	_recent.append(s)
	while _recent.size() > 10:
		_recent.pop_front()

func _process(_dt: float) -> void:
	var pads := Input.get_connected_joypads()
	var lines: Array[String] = []
	lines.append("=== INPUT TEST ===  connected joypads: %d   (keyboard: arrows / WASD)" % pads.size())
	lines.append("[mapped API]")
	for id in pads:
		var lx := Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
		var ly := Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
		var rx := Input.get_joy_axis(id, JOY_AXIS_RIGHT_X)
		var ry := Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y)
		lines.append("  id %d  L(%+.2f, %+.2f)  R(%+.2f, %+.2f)  name: %s" % [id, lx, ly, rx, ry, Input.get_joy_name(id)])
	lines.append("")
	lines.append("[raw events] スティックを倒す/ボタンを押すと下に出ます:")
	for e in _recent:
		lines.append("  " + e)
	_label.text = "\n".join(lines)
