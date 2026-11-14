class_name Hud
extends CanvasLayer
## ゲーム中HUD: 残時間(上中央) + 各プレイヤーのサイズ(四隅)。
## GameManager の time_changed / 各Playerの size_changed を購読して更新(I1/I5で接続)。
## 文字はASCII(標準フォントがCJK非対応のため。日本語フォント導入はMVP仕上げで対応)。

var _time_label: Label
var _size_labels: Array[Label] = []
var _solo := false
var _npc_label: Label

func setup_solo(duration: float, best: float) -> void:
	_solo = true
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 16)
	panel.size = Vector2(1232, 76)
	panel.add_theme_stylebox_override("panel", MenuStyle.panel_style(Color(0.08, 0.12, 0.10, 0.88)))
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	panel.add_child(row)
	var score := MenuStyle.make_label("", 28, MenuStyle.GOLD)
	score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(score)
	_size_labels.append(score)
	_time_label = MenuStyle.make_label("", 32)
	row.add_child(_time_label)
	var record := MenuStyle.make_label("BEST  %.2f" % best, 23, MenuStyle.MUTED)
	record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(record)
	_npc_label = MenuStyle.make_label("NPC 命中  0", 20)
	_npc_label.position = Vector2(30, 655)
	add_child(_npc_label)
	var help := MenuStyle.make_label("移動：スティック / 矢印　突進：ボタン1 / ［/］", 18)
	help.position = Vector2(670, 655)
	add_child(help)
	set_size(0, Config.balance.size_start)
	set_time(duration)

func set_npc_hits(hits: int) -> void:
	if _npc_label != null:
		_npc_label.text = "NPC 命中  %d" % hits

func setup(player_count: int) -> void:
	_time_label = _make_label(34)
	_time_label.position = Vector2(580, 14)
	add_child(_time_label)

	var corners := [Vector2(24, 18), Vector2(1070, 18), Vector2(24, 672), Vector2(1070, 672)]
	for i in player_count:
		var l := _make_label(24)
		l.add_theme_color_override("font_color", Player.color_for(i))
		l.position = corners[i % corners.size()]
		add_child(l)
		_size_labels.append(l)
		set_size(i, Config.balance.size_start)
	set_time(Config.balance.match_duration)

func set_time(sec: float) -> void:
	var s := int(ceilf(maxf(0.0, sec)))
	_time_label.text = "%02d:%02d" % [s / 60, s % 60]

func set_size(id: int, size: float) -> void:
	if id >= 0 and id < _size_labels.size():
		_size_labels[id].text = "SCORE  %.2f" % size if _solo else "P%d  %.1f" % [id + 1, size]

func _make_label(fs: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	return l
