class_name Hud
extends CanvasLayer
## ゲーム中HUD: 残時間(上中央) + 各プレイヤーのサイズ(四隅)。
## GameManager の time_changed / 各Playerの size_changed を購読して更新(I1/I5で接続)。
## 文字はASCII(標準フォントがCJK非対応のため。日本語フォント導入はMVP仕上げで対応)。

var _time_label: Label
var _size_labels: Array[Label] = []

func setup(player_count: int) -> void:
	_time_label = _make_label(34)
	_time_label.position = Vector2(580, 14)
	add_child(_time_label)

	var corners := [Vector2(24, 18), Vector2(1070, 18), Vector2(24, 672), Vector2(1070, 672)]
	for i in player_count:
		var l := _make_label(24)
		l.add_theme_color_override("font_color", Player.PLAYER_COLORS[i % Player.PLAYER_COLORS.size()])
		l.position = corners[i % corners.size()]
		add_child(l)
		_size_labels.append(l)
		set_size(i, Config.balance.size_start)
	set_time(Config.balance.match_duration)

func set_time(sec: float) -> void:
	var s := int(maxf(0.0, sec))
	_time_label.text = "%02d:%02d" % [s / 60, s % 60]

func set_size(id: int, size: float) -> void:
	if id >= 0 and id < _size_labels.size():
		_size_labels[id].text = "P%d  %.1f" % [id + 1, size]

func _make_label(fs: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	return l
