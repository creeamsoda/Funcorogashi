class_name SoloResults
extends CanvasLayer

signal retry_requested
signal menu_requested

var _root: Control
var _retry_button: Button
var _menu_button: Button
var _leaving := false


func show_score(score: float, npc_hits: int, record_result: Dictionary) -> void:
	if _root != null:
		return
	layer = 100
	_root = Control.new()
	_root.name = "SoloResultOverlay"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var background := ColorRect.new()
	background.color = Color(0.045, 0.075, 0.06, 0.94)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var layout := VBoxContainer.new()
	layout.custom_minimum_size = Vector2(1080, 0)
	layout.add_theme_constant_override("separation", 20)
	center.add_child(layout)
	var heading := MenuStyle.make_label("一人プレイ  /  結果", 34)
	heading.name = "Heading"
	layout.add_child(heading)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	layout.add_child(columns)
	var score_panel := PanelContainer.new()
	score_panel.custom_minimum_size = Vector2(490, 430)
	score_panel.add_theme_stylebox_override("panel", MenuStyle.panel_style())
	columns.add_child(score_panel)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 10)
	score_panel.add_child(details)
	details.add_child(MenuStyle.make_label("今回のスコア", 24, MenuStyle.MUTED))
	var score_label := MenuStyle.make_label("%.2f" % score, 72, MenuStyle.GOLD)
	score_label.name = "FinalScore"
	details.add_child(score_label)
	var new_best := bool(record_result.get("new_best", false))
	var status_text := "自己ベスト更新！" if new_best else "プレイおつかれさま！"
	var saved := bool(record_result.get("saved", false))
	if not saved:
		status_text = "今回は記録されていません"
	var status := MenuStyle.make_label(status_text, 27, MenuStyle.GOLD if new_best else MenuStyle.TEXT)
	status.name = "RecordStatus"
	details.add_child(status)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 12
	details.add_child(spacer)
	details.add_child(MenuStyle.make_label("自己ベスト     %.2f" % float(record_result.get("best", 0.0)), 26))
	details.add_child(MenuStyle.make_label("NPCへの命中     %d 回" % npc_hits, 24, MenuStyle.MUTED))
	var note_text := "同じコースでもう一度、記録に挑戦。" if saved else str(record_result.get("error", ""))
	var note := MenuStyle.make_label(note_text, 18, MenuStyle.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 410
	details.add_child(note)

	var record_panel := PanelContainer.new()
	record_panel.custom_minimum_size = Vector2(562, 430)
	record_panel.add_theme_stylebox_override("panel", MenuStyle.panel_style())
	columns.add_child(record_panel)
	var records_box := VBoxContainer.new()
	records_box.add_theme_constant_override("separation", 5)
	record_panel.add_child(records_box)
	records_box.add_child(MenuStyle.make_label("この条件の自己記録  TOP 10", 25))
	var record_entries: Array = record_result.get("records", [])
	if record_entries.is_empty():
		records_box.add_child(MenuStyle.make_label("まだ記録がありません", 22, MenuStyle.MUTED))
	for index in mini(record_entries.size(), 10):
		var entry: Dictionary = record_entries[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		records_box.add_child(row)
		var rank := MenuStyle.make_label("%02d" % (index + 1), 20, MenuStyle.GOLD if index == 0 else MenuStyle.MUTED)
		rank.custom_minimum_size.x = 40
		row.add_child(rank)
		var value := MenuStyle.make_label("%.2f" % float(entry.get("score", 0.0)), 21)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(value)
		var date_text := str(entry.get("timestamp", "")).replace("T", " ").substr(0, 16) + " UTC"
		row.add_child(MenuStyle.make_label(date_text, 18, MenuStyle.MUTED))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	layout.add_child(buttons)
	_retry_button = MenuStyle.make_button("同じコースでリトライ", true)
	_retry_button.name = "RetryButton"
	_retry_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_retry_button.pressed.connect(_choose.bind(true))
	buttons.add_child(_retry_button)
	_menu_button = MenuStyle.make_button("タイトルに戻る")
	_menu_button.name = "MenuButton"
	_menu_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_button.pressed.connect(_choose.bind(false))
	buttons.add_child(_menu_button)
	_retry_button.focus_neighbor_right = _menu_button.get_path()
	_retry_button.focus_neighbor_left = _menu_button.get_path()
	_menu_button.focus_neighbor_right = _retry_button.get_path()
	_menu_button.focus_neighbor_left = _retry_button.get_path()
	layout.add_child(MenuStyle.make_label("矢印 / スティックで選択    Enter / 突進ボタンで決定", 18, MenuStyle.MUTED))
	_retry_button.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if _root == null or _leaving:
		return
	# 横持ち Joy-Con の突進ボタンは標準 ui_accept と異なる。
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B and event.pressed:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is Button and _root.is_ancestor_of(focused):
			get_viewport().set_input_as_handled()
			focused.pressed.emit()


func _choose(retry: bool) -> void:
	if _leaving:
		return
	_leaving = true
	_retry_button.disabled = true
	_menu_button.disabled = true
	if retry:
		retry_requested.emit()
	else:
		menu_requested.emit()
