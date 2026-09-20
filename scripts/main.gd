extends Node3D
## 一人用と対戦の入口。現在のコース条件の端末内ランキングを掲示する。

var _launching := false

func _ready() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root)
	var background := ColorRect.new()
	background.color = MenuStyle.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	root.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)
	layout.add_child(MenuStyle.make_label("フンコロバトル", 50, MenuStyle.GOLD))
	layout.add_child(MenuStyle.make_label("転がして、集めて、突進！", 22, MenuStyle.MUTED))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 30)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)
	var modes := VBoxContainer.new()
	modes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes.add_theme_constant_override("separation", 14)
	columns.add_child(modes)
	var solo := _mode_card(modes, "一人プレイ", "3分間のスコアアタック", "動物の動きを覚えて、自己ベストに挑戦。\n横切るフンコロガシに連続突進！", true)
	solo.name = "SoloButton"
	solo.pressed.connect(_launch.bind("solo"))
	var versus := _mode_card(modes, "対戦", "みんなでフンを奪い合おう", "突進を当てて、大きなフンを横取り。\n時間切れで一番大きいプレイヤーの勝ち！", false)
	versus.name = "VersusButton"
	versus.pressed.connect(_launch.bind("versus"))
	_build_records(columns)
	layout.add_child(MenuStyle.make_label("移動：スティック / 矢印キー　　突進：Joy-Con ボタン1 / ［/］キー", 18, MenuStyle.MUTED))
	layout.add_child(MenuStyle.make_label("メニュー：方向キーで選択、Enter / Joy-Con ボタン1で決定", 17, MenuStyle.MUTED))
	solo.focus_neighbor_bottom = solo.get_path_to(versus)
	versus.focus_neighbor_top = versus.get_path_to(solo)
	solo.grab_focus()

func _mode_card(parent: VBoxContainer, title: String, subtitle: String, description: String, primary: bool) -> Button:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", MenuStyle.panel_style())
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var button := MenuStyle.make_button(title, primary)
	button.custom_minimum_size.y = 58
	box.add_child(button)
	box.add_child(MenuStyle.make_label(subtitle, 22, MenuStyle.GOLD if primary else MenuStyle.TEXT))
	box.add_child(MenuStyle.make_label(description, 19, MenuStyle.MUTED))
	return button

func _build_records(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 400
	panel.add_theme_stylebox_override("panel", MenuStyle.panel_style())
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	box.add_child(MenuStyle.make_label("ハイスコア", 29, MenuStyle.GOLD))
	box.add_child(MenuStyle.make_label("この端末の記録 · 現在のコース", 16, MenuStyle.MUTED))
	box.add_child(HSeparator.new())
	var course := MatchSession.load_course()
	var records: Array = ScoreStore.new().records(MatchSession.score_profile(course, Config.balance))
	if records.is_empty():
		var empty := MenuStyle.make_label("最初の記録をつくろう！\n\n一人プレイを選んで\nスコアアタックに挑戦。", 22, MenuStyle.MUTED)
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(empty)
	else:
		for i in records.size():
			var row: Dictionary = records[i]
			box.add_child(MenuStyle.make_label("%2d   %8.2f" % [i + 1, float(row["score"])], 23, MenuStyle.GOLD if i == 0 else MenuStyle.TEXT))

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B and event.pressed:
		var button := get_viewport().gui_get_focus_owner() as Button
		if button != null and not button.disabled:
			get_viewport().set_input_as_handled()
			button.pressed.emit()

func _launch(selected_mode: String) -> void:
	if _launching:
		return
	_launching = true
	MatchSession.start(get_tree(), selected_mode)
