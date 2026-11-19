class_name Hud
extends CanvasLayer
## ゲーム中HUD: 残時間(上中央) + 各プレイヤーのサイズ(四隅)。
## GameManager の time_changed / 各Playerの size_changed を購読して更新(I1/I5で接続)。
## 文字はASCII(標準フォントがCJK非対応のため。日本語フォント導入はMVP仕上げで対応)。

const COUNTDOWN_SECONDS := 10
const COUNTDOWN_FONT_SIZE := 220
const COUNTDOWN_COLOR := Color(1.0, 1.0, 1.0, 0.45)

var _time_label: Label
var _countdown_label: Label
var _banner_label: Label
var _size_labels: Array[Label] = []
var _names: Array[String] = []

## names はプレイヤーindex順の表示名(省略時は P1, P2, ...)。
func setup(player_count: int, names: Array[String] = []) -> void:
	_names = names
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
	var counting := sec > 0.0 and s <= COUNTDOWN_SECONDS
	# 残り10秒は画面中央の大きなカウントに切り替え、上部の表示は消す(レイアウトは保つ)。
	_time_label.modulate.a = 0.0 if s <= COUNTDOWN_SECONDS else 1.0
	if counting:
		_ensure_countdown_label()
		_countdown_label.text = str(s)
	if _countdown_label != null:
		_countdown_label.visible = counting

func _ensure_countdown_label() -> void:
	if _countdown_label != null:
		return
	_countdown_label = MenuStyle.make_label("", COUNTDOWN_FONT_SIZE, COUNTDOWN_COLOR)
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_countdown_label)

## 画面中央の半透明の大きな文字(残り10秒のカウントと同じ見せ方)。対戦開始の演出に使う。
func show_banner(text: String, font_size: int) -> void:
	if _banner_label == null:
		_banner_label = MenuStyle.make_label("", font_size, COUNTDOWN_COLOR)
		_banner_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_banner_label)
	_banner_label.add_theme_font_size_override("font_size", font_size)
	_banner_label.text = text
	_banner_label.visible = true

func hide_banner() -> void:
	if _banner_label != null:
		_banner_label.visible = false

func set_size(id: int, size: float) -> void:
	if id >= 0 and id < _size_labels.size():
		var label := _names[id] if id < _names.size() else "P%d" % (id + 1)
		_size_labels[id].text = "%s  %.1f" % [label, size]

func _make_label(fs: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	return l
