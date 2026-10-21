class_name TuningPanel
extends CanvasLayer
## 開発用の調整パネル(F1)。Config.balance の export 値をグループ別に実行中に書き換える。
## 開いている間はゲームを一時停止する。「保存」で balance_default.tres へ書き出す。
## 一人プレイは終了時の設定が開始時と異なると記録しないため、調整した試合は練習扱いになる。

const PANEL_WIDTH := 470.0

var _group_select: OptionButton
var _rows: GridContainer
var _status: Label
var _groups: Dictionary = {}  ## group名 -> Array[Dictionary(property)]
var _group_names: Array[String] = []
var _was_paused := false


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_collect_groups()
	_build_ui()
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	_show_group(_group_select.selected)


func close() -> void:
	if not visible:
		return
	get_viewport().gui_release_focus()
	visible = false
	get_tree().paused = _was_paused


## BalanceConfig のスクリプト変数を @export_group 単位にまとめる。
func _collect_groups() -> void:
	var current := "その他"
	for prop in Config.balance.get_property_list():
		var usage := int(prop["usage"])
		if usage & PROPERTY_USAGE_GROUP:
			current = prop["name"]
		elif usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE:
			if not _groups.has(current):
				_groups[current] = []
				_group_names.append(current)
			_groups[current].append(prop)


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_WIDTH
	panel.add_theme_stylebox_override("panel", MenuStyle.panel_style(Color(0.08, 0.12, 0.10, 0.94)))
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(MenuStyle.make_label("調整パネル", 24, MenuStyle.GOLD))
	box.add_child(MenuStyle.make_label("F1 閉じる(一時停止解除) / F2 デバッグ表示", 15, MenuStyle.MUTED))

	_group_select = OptionButton.new()
	for group_name in _group_names:
		_group_select.add_item(group_name)
	_group_select.item_selected.connect(_show_group)
	box.add_child(_group_select)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var save := Button.new()
	save.text = "保存(tres)"
	save.pressed.connect(save_to_file)
	buttons.add_child(save)
	var reload := Button.new()
	reload.text = "ファイルから再読込"
	reload.pressed.connect(reload_from_file)
	buttons.add_child(reload)
	_status = MenuStyle.make_label("", 15, MenuStyle.MUTED)
	box.add_child(_status)


func _show_group(index: int) -> void:
	for child in _rows.get_children():
		child.queue_free()
	if index < 0 or index >= _group_names.size():
		return
	for prop in _groups[_group_names[index]]:
		var label := Label.new()
		label.text = prop["name"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		_rows.add_child(label)
		_rows.add_child(_make_editor(prop))


func _make_editor(prop: Dictionary) -> Control:
	var key: String = prop["name"]
	var value: Variant = Config.balance.get(key)
	var hint := int(prop["hint"])
	var hint_string: String = prop["hint_string"]
	match int(prop["type"]):
		TYPE_BOOL:
			var check := CheckBox.new()
			check.button_pressed = value
			check.toggled.connect(func(on: bool) -> void: _set_value(key, on))
			return check
		TYPE_INT when hint == PROPERTY_HINT_ENUM:
			var option := OptionButton.new()
			for item in hint_string.split(","):
				option.add_item(item.get_slice(":", 0))
			option.selected = int(value)
			option.item_selected.connect(func(i: int) -> void: _set_value(key, i))
			return option
		TYPE_INT, TYPE_FLOAT:
			var is_int := int(prop["type"]) == TYPE_INT
			var spin := SpinBox.new()
			spin.custom_minimum_size.x = 140
			spin.step = 1.0 if is_int else 0.01
			spin.min_value = -1000.0
			spin.max_value = 1000.0
			spin.allow_lesser = true
			spin.allow_greater = true
			if hint == PROPERTY_HINT_RANGE:
				var parts := hint_string.split(",")
				spin.min_value = float(parts[0])
				spin.max_value = float(parts[1])
				spin.allow_lesser = false
				spin.allow_greater = false
				if parts.size() > 2:
					spin.step = float(parts[2])
			spin.value = float(value)
			spin.value_changed.connect(func(v: float) -> void: _set_value(key, int(v) if is_int else v))
			return spin
	var unsupported := Label.new()
	unsupported.text = str(value)
	return unsupported


func _set_value(key: String, value: Variant) -> void:
	Config.balance.set(key, value)
	_status.text = "%s = %s (未保存)" % [key, str(value)]


func save_to_file(path: String = Config.BALANCE_PATH) -> Error:
	var err := ResourceSaver.save(Config.balance, path)
	_status.text = "保存しました: %s" % path if err == OK else "保存に失敗: %s" % error_string(err)
	return err


## ディスク上の tres を読み直し、同じ Config.balance インスタンスへ値を書き戻す(参照を保つ)。
func reload_from_file(path: String = Config.BALANCE_PATH) -> void:
	var fresh := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as BalanceConfig
	if fresh == null:
		_status.text = "読み込みに失敗: %s" % path
		return
	for group_name in _group_names:
		for prop in _groups[group_name]:
			Config.balance.set(prop["name"], fresh.get(prop["name"]))
	_show_group(_group_select.selected)
	_status.text = "ファイルの値に戻しました"


func group_names() -> Array[String]:
	return _group_names
