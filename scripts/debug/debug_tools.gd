class_name DebugTools
extends Node
## 開発用ツールの入口。デバッグビルドでのみ GameManager が追加する。
##   F1: 調整パネル(TuningPanel)  /  F2: デバッグ線表示(DebugOverlay)

var panel: TuningPanel
var overlay: DebugOverlay


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = TuningPanel.new()
	panel.name = "TuningPanel"
	add_child(panel)
	overlay = DebugOverlay.new()
	overlay.name = "DebugOverlay"
	add_child(overlay)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			panel.toggle()
			get_viewport().set_input_as_handled()
		KEY_F2:
			overlay.visible = not overlay.visible
			get_viewport().set_input_as_handled()
