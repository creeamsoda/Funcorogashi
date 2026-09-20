class_name Results
extends CanvasLayer
## タイムアップ後の結果発表演出。
## show_results(results) で表示。results 要素:
## {player_id:int, size:float, dash_hits_received:int}
## 注: Dictionary の "size" キーは r["size"] で参照(r.size は Dictionary.size() と衝突するため)。

signal presentation_finished
signal retry_requested
signal menu_requested

const RETRY_BUTTON_SIZE := Vector2(300, 64)
const CONTESTANT_SIZE := ResultContestant.DISPLAY_SIZE
const OVERLAY_COLOR := Color(0.13, 0.14, 0.16, 0.72)

## テスト用。通常は1.0。小さくすると演出時間だけを短縮できる。
var animation_speed_scale := 1.0

var _root: Control
var _background: ColorRect
var _announcement: Label
var _rank_labels: Array[Label] = []
var _contestants: Array[ResultContestant] = []
var _contestant_targets: Array[Vector2] = []
var _award_label: Label
var _retry_button: Button
var _menu_button: Button
var _sorted_results: Array = []
var _sequence_started := false


func show_results(results: Array) -> void:
	if _root != null:
		return
	layer = 100
	_sorted_results = results.duplicate(true)
	_sorted_results.sort_custom(_rank_before)
	_build_ui()
	_play_sequence.call_deferred()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "ResultOverlay"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_background = ColorRect.new()
	_background.name = "DimBackground"
	_background.color = Color(OVERLAY_COLOR.r, OVERLAY_COLOR.g, OVERLAY_COLOR.b, 0.0)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_background)

	_announcement = _label("結果発表！！", 68, Color(1.0, 0.88, 0.22))
	_announcement.name = "Announcement"
	_announcement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announcement.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_announcement.size = Vector2(720, 120)
	_announcement.pivot_offset = _announcement.size * 0.5
	_root.add_child(_announcement)

	for rank in _sorted_results.size():
		var rank_label := _label(str(rank + 1), 72, Color.WHITE)
		rank_label.name = "Rank%d" % (rank + 1)
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rank_label.size = Vector2(120, 100)
		rank_label.modulate.a = 0.0
		_root.add_child(rank_label)
		_rank_labels.append(rank_label)

		var result: Dictionary = _sorted_results[rank]
		var contestant := ResultContestant.new()
		contestant.name = "Placement%d" % (rank + 1)
		contestant.setup(int(result["player_id"]), float(result["size"]))
		contestant.modulate.a = 0.0
		_root.add_child(contestant)
		_contestants.append(contestant)

	_award_label = _label("一番突進を食らった", 21, Color(1.0, 0.91, 0.42))
	_award_label.name = "MostDashedAward"
	_award_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_award_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_award_label.size = Vector2(280, 54)
	_award_label.pivot_offset = _award_label.size * 0.5
	_award_label.modulate.a = 0.0
	_award_label.scale = Vector2(0.72, 0.72)
	_root.add_child(_award_label)

	_retry_button = Button.new()
	_retry_button.name = "RetryButton"
	_retry_button.text = "リトライ"
	_retry_button.custom_minimum_size = RETRY_BUTTON_SIZE
	_retry_button.size = RETRY_BUTTON_SIZE
	_retry_button.pivot_offset = RETRY_BUTTON_SIZE * 0.5
	_retry_button.add_theme_font_size_override("font_size", 28)
	_retry_button.add_theme_font_override("font", _japanese_font())
	_retry_button.add_theme_stylebox_override("normal", _button_style(Color(0.12, 0.38, 0.22)))
	_retry_button.add_theme_stylebox_override("hover", _button_style(Color(0.18, 0.52, 0.30), 3))
	_retry_button.add_theme_stylebox_override("pressed", _button_style(Color(0.08, 0.27, 0.15)))
	_retry_button.add_theme_stylebox_override("focus", _button_style(Color(0.12, 0.38, 0.22), 4))
	_retry_button.modulate.a = 0.0
	_retry_button.scale = Vector2(0.82, 0.82)
	_retry_button.disabled = true
	_retry_button.pressed.connect(_on_retry_pressed)
	_root.add_child(_retry_button)
	_menu_button = MenuStyle.make_button("モード選択へ")
	_menu_button.name = "MenuButton"
	_menu_button.size = RETRY_BUTTON_SIZE
	_menu_button.visible = false
	_menu_button.disabled = true
	_menu_button.pressed.connect(func() -> void: menu_requested.emit())
	_root.add_child(_menu_button)


func _play_sequence() -> void:
	if _sequence_started or not is_inside_tree():
		return
	_sequence_started = true
	await get_tree().process_frame
	var viewport_size := get_viewport().get_visible_rect().size
	_layout_targets(viewport_size)

	# 1. 既存のグレー半透明背景をフェードイン。
	var background_tween := create_tween()
	background_tween.tween_property(_background, "color", OVERLAY_COLOR, _scaled(0.24))
	await background_tween.finished

	# 2. 見出しが左から入り、中央で読ませてから右へ抜ける。
	var title_target := Vector2((viewport_size.x - _announcement.size.x) * 0.5, viewport_size.y * 0.35)
	_announcement.position = Vector2(-_announcement.size.x - 40.0, title_target.y)
	var title_in := create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	title_in.tween_property(_announcement, "position", title_target, _scaled(0.58))
	await title_in.finished
	await get_tree().create_timer(_scaled(0.82)).timeout
	var title_out := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	title_out.tween_property(
		_announcement,
		"position",
		Vector2(viewport_size.x + 40.0, title_target.y),
		_scaled(0.46)
	)
	await title_out.finished
	_announcement.visible = false

	# 3. 1〜4の順位番号だけが流れてきて定位置で止まる。
	var number_tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in _rank_labels.size():
		var label := _rank_labels[i]
		label.position = Vector2(-150.0 - float(i) * 95.0, _rank_target(i, viewport_size).y)
		label.modulate.a = 1.0
		number_tween.tween_property(label, "position", _rank_target(i, viewport_size), _scaled(0.68)) \
			.set_delay(_scaled(float(i) * 0.055))
	await number_tween.finished
	await get_tree().create_timer(_scaled(0.18)).timeout

	# 4. 4位から順に、背中側から見た3Dモデルとフンをひとまとまりで落とす。
	for rank_index in range(_contestants.size() - 1, -1, -1):
		var contestant := _contestants[rank_index]
		contestant.position = Vector2(_contestant_targets[rank_index].x, -CONTESTANT_SIZE.y - 40.0)
		contestant.modulate.a = 1.0
		var drop_tween := create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		drop_tween.tween_property(contestant, "position", _contestant_targets[rank_index], _scaled(0.46))
		await drop_tween.finished
		await get_tree().create_timer(_scaled(0.12)).timeout

	# 5. 1位だけ、嬉しそうに上下へ飛び跳ね続ける。
	_start_winner_bounce()
	await get_tree().create_timer(_scaled(0.34)).timeout

	# 6. 最多被突進プレイヤーの下へ副賞を表示。
	var most_dashed_rank := _most_dashed_rank()
	var award_x := _contestant_targets[most_dashed_rank].x + (CONTESTANT_SIZE.x - _award_label.size.x) * 0.5
	_award_label.position = Vector2(award_x, viewport_size.y - 156.0)
	var award_tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	award_tween.tween_property(_award_label, "modulate:a", 1.0, _scaled(0.28))
	award_tween.tween_property(_award_label, "scale", Vector2.ONE, _scaled(0.34))
	await award_tween.finished
	await get_tree().create_timer(_scaled(0.38)).timeout

	# 7. 最後にリトライボタン。
	_retry_button.position = Vector2(viewport_size.x * 0.5 - RETRY_BUTTON_SIZE.x - 12.0, viewport_size.y - 78.0)
	_menu_button.position = Vector2(viewport_size.x * 0.5 + 12.0, viewport_size.y - 78.0)
	var retry_tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	retry_tween.tween_property(_retry_button, "modulate:a", 1.0, _scaled(0.24))
	retry_tween.tween_property(_retry_button, "scale", Vector2.ONE, _scaled(0.30))
	await retry_tween.finished
	_retry_button.disabled = false
	_menu_button.disabled = false
	_menu_button.visible = true
	_retry_button.focus_neighbor_right = _retry_button.get_path_to(_menu_button)
	_menu_button.focus_neighbor_left = _menu_button.get_path_to(_retry_button)
	_retry_button.grab_focus()
	presentation_finished.emit()


func _layout_targets(viewport_size: Vector2) -> void:
	_contestant_targets.clear()
	for i in _contestants.size():
		var center_x := viewport_size.x * float(i + 1) / float(_contestants.size() + 1)
		_contestant_targets.append(Vector2(center_x - CONTESTANT_SIZE.x * 0.5, 150.0))


func _rank_target(rank_index: int, viewport_size: Vector2) -> Vector2:
	var center_x := viewport_size.x * float(rank_index + 1) / float(_rank_labels.size() + 1)
	return Vector2(center_x - 60.0, 58.0)


func _start_winner_bounce() -> void:
	if _contestants.is_empty():
		return
	var winner := _contestants[0]
	var resting_y := _contestant_targets[0].y
	var bounce := create_tween().set_loops().set_trans(Tween.TRANS_QUAD)
	bounce.tween_property(winner, "position:y", resting_y - 24.0, _scaled(0.22)).set_ease(Tween.EASE_OUT)
	bounce.tween_property(winner, "position:y", resting_y, _scaled(0.22)).set_ease(Tween.EASE_IN)


func _most_dashed_rank() -> int:
	var best_rank := 0
	var best_count := -1
	for i in _sorted_results.size():
		var count := _dash_hits_received(_sorted_results[i])
		if count > best_count:
			best_count = count
			best_rank = i
	return best_rank


func _dash_hits_received(result: Dictionary) -> int:
	if result.has("dash_hits_received"):
		return int(result["dash_hits_received"])
	# 旧テストデータとの互換用。ゲーム本編は dash_hits_received を渡す。
	return int(result.get("dash_hits", 0))


func _rank_before(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a["size"]), float(b["size"])):
		return float(a["size"]) > float(b["size"])
	return int(a["player_id"]) < int(b["player_id"])


func _scaled(seconds: float) -> float:
	return maxf(seconds * animation_speed_scale, 0.001)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _japanese_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.05, 0.98))
	label.add_theme_constant_override("outline_size", 7)
	return label


func _japanese_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo UI", "Noto Sans CJK JP", "sans-serif"])
	font.font_weight = 700
	return font


func _button_style(color: Color, border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(1.0, 0.90, 0.45)
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(10)
	return style


func _on_retry_pressed() -> void:
	_retry_button.disabled = true
	if retry_requested.get_connections().is_empty():
		get_tree().reload_current_scene()
	else:
		retry_requested.emit()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B and event.pressed:
		var button := get_viewport().gui_get_focus_owner() as Button
		if button != null and is_ancestor_of(button) and not button.disabled:
			get_viewport().set_input_as_handled()
			button.pressed.emit()
