extends Node3D
## タイトル画面。タイトル絵を背景に、右下へ「みんなでバトル！」「ひとりで遊ぶ」「クレジット」を置く。
## 「みんなでバトル！」→ 人数選択ウィンドウ(2人/3人/4人) → チュートリアル選択ウィンドウ(あり/なし)。
## 人数を選んだ時点から PlayerSlots がコントローラーを先着順でプレイヤーへ割り当て始める。

const TITLE_TEXTURE := preload("res://resources/Title/title.png")

var _launching := false
var _buttons: Array[Button] = []
var _credits: Control = null
var _credits_close: Button = null
var _count_dialog: Control = null
var _tutorial_dialog: Control = null

func _ready() -> void:
	PlayerSlots.end() # タイトルに戻ったら割り当てをやり直す
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root)
	var background := TextureRect.new()
	background.texture = TITLE_TEXTURE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	# 右下の空きスペースにボタンを右揃えで縦に並べる。
	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 18)
	buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buttons.grow_vertical = Control.GROW_DIRECTION_BEGIN
	buttons.offset_right = -56
	buttons.offset_bottom = -48
	root.add_child(buttons)
	var versus := _add_title_button(buttons, "みんなでバトル！", 1.0)
	versus.name = "VersusButton"
	versus.pressed.connect(_open_count_dialog)
	var solo := _add_title_button(buttons, "ひとりで遊ぶ", 0.8)
	solo.name = "SoloButton"
	solo.pressed.connect(_launch.bind("solo"))
	var credits := _add_title_button(buttons, "クレジット", 0.5)
	credits.name = "CreditsButton"
	credits.pressed.connect(_open_credits)
	for i in _buttons.size():
		var button := _buttons[i]
		button.focus_neighbor_top = button.get_path_to(_buttons[(i - 1 + _buttons.size()) % _buttons.size()])
		button.focus_neighbor_bottom = button.get_path_to(_buttons[(i + 1) % _buttons.size()])
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(button)

	_build_credits(root)
	_count_dialog = _build_choice_dialog(root, "何人でバトル？", ["2人", "3人", "4人"], _choose_count)
	_count_dialog.name = "CountDialog"
	_tutorial_dialog = _build_choice_dialog(root, "チュートリアル", ["あり", "なし"], _choose_tutorial)
	_tutorial_dialog.name = "TutorialDialog"
	versus.grab_focus()

func _add_title_button(parent: VBoxContainer, text: String, size_scale: float) -> Button:
	var button := MenuStyle.make_title_button(text, size_scale)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	parent.add_child(button)
	_buttons.append(button)
	# 選択中は大きさを周期的に変化させ、コントローラーでの選択位置を分かりやすくする。
	button.focus_entered.connect(_start_pulse.bind(button))
	button.focus_exited.connect(_stop_pulse.bind(button))
	return button

const PULSE_MIN_SCALE := 1.05
const PULSE_MAX_SCALE := 1.1
const PULSE_HALF_PERIOD := 0.45 ## 縮小→拡大(または拡大→縮小)にかける秒数

func _start_pulse(button: Button) -> void:
	_kill_pulse(button)
	# 右端を基準に拡大し、画面の右へはみ出さないようにする(ウィンドウ内のボタンは中心基準)。
	if button.has_meta("pulse_center"):
		button.pivot_offset = button.size * 0.5
	else:
		button.pivot_offset = Vector2(button.size.x, button.size.y * 0.5)
	var tween := button.create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * PULSE_MIN_SCALE, 0.08)
	var loop := button.create_tween().set_loops()
	loop.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	loop.tween_property(button, "scale", Vector2.ONE * PULSE_MAX_SCALE, PULSE_HALF_PERIOD)
	loop.tween_property(button, "scale", Vector2.ONE * PULSE_MIN_SCALE, PULSE_HALF_PERIOD)
	# 最初の「元の大きさ→最小」が終わってから周期変化を始める。
	loop.pause()
	tween.finished.connect(loop.play)
	button.set_meta("pulse_tweens", [tween, loop])

func _stop_pulse(button: Button) -> void:
	_kill_pulse(button)
	var tween := button.create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, 0.1)
	button.set_meta("pulse_tweens", [tween])

func _kill_pulse(button: Button) -> void:
	for tween: Tween in button.get_meta("pulse_tweens", []):
		if tween.is_valid():
			tween.kill()

## 空のクレジットウィンドウ。暗幕の上に中央表示し、ESC / Joy-Con 下ボタン / ×ボタンで閉じる。
func _build_credits(parent: Control) -> void:
	_credits = Control.new()
	_credits.name = "Credits"
	_credits.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_credits.mouse_filter = Control.MOUSE_FILTER_STOP
	_credits.visible = false
	parent.add_child(_credits)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_credits.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_credits.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 480)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f3e6cf")
	style.border_color = Color.BLACK
	style.set_border_width_all(6)
	style.set_corner_radius_all(28)
	style.content_margin_left = 32
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := MenuStyle.make_label("クレジット", 36, MenuStyle.TITLE_BUTTON_BG)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_credits_close = MenuStyle.make_title_button("×", 0.5)
	_credits_close.custom_minimum_size = Vector2(56, 56)
	_credits_close.add_theme_font_size_override("font_size", 34)
	_credits_close.name = "CloseButton"
	_credits_close.pressed.connect(_close_credits)
	# 開いている間は背後のボタンへフォーカスが逃げないようにする。
	for side in ["focus_neighbor_top", "focus_neighbor_bottom", "focus_neighbor_left", "focus_neighbor_right", "focus_next", "focus_previous"]:
		_credits_close.set(side, NodePath("."))
	header.add_child(_credits_close)
	# 本文は後で追加する。
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)

func _open_credits() -> void:
	_credits.visible = true
	_credits_close.grab_focus()

func _close_credits() -> void:
	if not _credits.visible:
		return
	_credits.visible = false
	_buttons[2].grab_focus()

## 暗幕+中央のウィンドウに、見出しと横並びの選択ボタンを置く。ボタン i を押すと on_choose(i)。
func _build_choice_dialog(parent: Control, heading: String, options: Array, on_choose: Callable) -> Control:
	var dialog := Control.new()
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.visible = false
	parent.add_child(dialog)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	panel.add_theme_stylebox_override("panel", _window_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 28)
	panel.add_child(box)
	var title := MenuStyle.make_label(heading, 44, MenuStyle.TITLE_BUTTON_BG)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	box.add_child(row)
	var buttons: Array[Button] = []
	for i in options.size():
		var button := MenuStyle.make_title_button(options[i], 0.6)
		button.custom_minimum_size.x = 170
		button.set_meta("pulse_center", true)
		button.focus_entered.connect(_start_pulse.bind(button))
		button.focus_exited.connect(_stop_pulse.bind(button))
		button.pressed.connect(func() -> void: on_choose.call(i))
		row.add_child(button)
		buttons.append(button)
	# 開いている間は背後のボタンへフォーカスが逃げないよう、左右だけで巡回させる。
	for i in buttons.size():
		var button := buttons[i]
		button.focus_neighbor_left = button.get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		button.focus_neighbor_right = button.get_path_to(buttons[(i + 1) % buttons.size()])
		button.focus_neighbor_top = NodePath(".")
		button.focus_neighbor_bottom = NodePath(".")
		button.focus_next = button.focus_neighbor_right
		button.focus_previous = button.focus_neighbor_left
	dialog.set_meta("buttons", buttons)
	return dialog


func _window_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f3e6cf")
	style.border_color = Color.BLACK
	style.set_border_width_all(6)
	style.set_corner_radius_all(28)
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 28
	style.content_margin_bottom = 36
	return style


func _show_dialog(dialog: Control) -> void:
	_count_dialog.visible = dialog == _count_dialog
	_tutorial_dialog.visible = dialog == _tutorial_dialog
	if dialog != null:
		(dialog.get_meta("buttons")[0] as Button).grab_focus()


func _open_count_dialog() -> void:
	if _launching:
		return
	_show_dialog(_count_dialog)


func _choose_count(index: int) -> void:
	if not _count_dialog.visible:
		return
	# この時点から入力のあったコントローラーを先着順で P1, P2, ... に割り当てる。
	PlayerSlots.begin(index + 2)
	_show_dialog(_tutorial_dialog)


func _choose_tutorial(index: int) -> void:
	if _launching or not _tutorial_dialog.visible:
		return
	_launching = true
	MatchSession.start_versus(get_tree(), index == 0)


## ESC: チュートリアル選択→人数選択→タイトルの順に戻る。
func _dialog_back() -> void:
	if _tutorial_dialog.visible:
		PlayerSlots.end()
		_show_dialog(_count_dialog)
	elif _count_dialog.visible:
		_show_dialog(null)
		_buttons[0].grab_focus()


func _input(event: InputEvent) -> void:
	if _count_dialog != null and (_count_dialog.visible or _tutorial_dialog.visible):
		if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_dialog_back()
			return
	if _credits != null and _credits.visible:
		if _is_credits_close_event(event):
			get_viewport().set_input_as_handled()
			_close_credits()
		return
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B and event.pressed:
		var button := get_viewport().gui_get_focus_owner() as Button
		if button != null and not button.disabled:
			get_viewport().set_input_as_handled()
			button.pressed.emit()

func _is_credits_close_event(event: InputEvent) -> bool:
	if event.is_echo():
		return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		return true
	# Joy-Con 片手持ちの下ボタン(右 Joy-Con の A / 左 Joy-Con の右ボタン)。
	# 環境によって A / B どちらに割り当たるか異なるため両方受け付ける。
	if event is InputEventJoypadButton and event.pressed:
		return event.button_index == JOY_BUTTON_A or event.button_index == JOY_BUTTON_B
	return false

func _launch(selected_mode: String) -> void:
	if _launching:
		return
	_launching = true
	MatchSession.start(get_tree(), selected_mode)

## ランキング表示。タイトル画面からは外したが、専用画面を作るときに再利用するため残しておく。
func _build_records(parent: Control) -> void:
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
		var empty := MenuStyle.make_label("最初の記録をつくろう！\n\nひとりで遊ぶを選んで\nスコアアタックに挑戦。", 22, MenuStyle.MUTED)
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(empty)
	else:
		for i in records.size():
			var row: Dictionary = records[i]
			box.add_child(MenuStyle.make_label("%2d   %8.2f" % [i + 1, float(row["score"])], 23, MenuStyle.GOLD if i == 0 else MenuStyle.TEXT))
