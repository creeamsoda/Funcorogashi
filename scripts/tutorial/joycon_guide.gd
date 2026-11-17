class_name JoyconGuide
extends Control
## 横持ちJoy-Con 1本のイラスト(コードで描画)。スティックを指して「移動」、突進ボタンを指して「長押しで突進」。
## 突進は SDL mini-gamepad の BTN 1(JOY_BUTTON_B)。横持ちで右側に来るボタンとして描く(DASH_BUTTON で変更可)。

const BODY_SIZE := Vector2(300, 120)
const BODY_COLOR := Color("3cbcf0")
const OUTLINE_COLOR := Color.BLACK
const STICK_COLOR := Color("2b2b2b")
const BUTTON_COLOR := Color("2b2b2b")
const HIGHLIGHT_COLOR := Color("ff5a3c")
const LINE_COLOR := Color.WHITE
const LABEL_FONT_SIZE := 34
## 突進ボタンの位置(フェイスボタンの菱形内: 0=上 1=右 2=下 3=左)。
const DASH_BUTTON := 1
const FACE_OFFSETS := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
const FACE_SPACING := 26.0
const FACE_RADIUS := 13.0

var _move_label: Label
var _dash_label: Label
var _blink_t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(900, 150)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_move_label = _make_label("移動")
	_dash_label = _make_label("長押しで突進")
	resized.connect(_layout_labels)
	_layout_labels()


func _process(delta: float) -> void:
	_blink_t += delta
	queue_redraw()


func _make_label(text: String) -> Label:
	var label := MenuStyle.make_label(text, LABEL_FONT_SIZE, Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _body_rect() -> Rect2:
	return Rect2(size * 0.5 - BODY_SIZE * 0.5, BODY_SIZE)


func _stick_center() -> Vector2:
	var r := _body_rect()
	return Vector2(r.position.x + r.size.x * 0.24, r.get_center().y)


func _face_center() -> Vector2:
	var r := _body_rect()
	return Vector2(r.position.x + r.size.x * 0.74, r.get_center().y)


func _dash_button_center() -> Vector2:
	return _face_center() + FACE_OFFSETS[DASH_BUTTON] * FACE_SPACING


func _layout_labels() -> void:
	if _move_label == null:
		return
	var r := _body_rect()
	_move_label.reset_size()
	_dash_label.reset_size()
	_move_label.position = Vector2(r.position.x - 120 - _move_label.size.x, r.get_center().y - _move_label.size.y * 0.5)
	_dash_label.position = Vector2(r.end.x + 120, r.get_center().y - _dash_label.size.y * 0.5)


func _draw() -> void:
	var r := _body_rect()
	var body := StyleBoxFlat.new()
	body.bg_color = BODY_COLOR
	body.border_color = OUTLINE_COLOR
	body.set_border_width_all(5)
	body.set_corner_radius_all(int(BODY_SIZE.y * 0.5))
	draw_style_box(body, r)
	# スティック
	var stick := _stick_center()
	draw_circle(stick, 30, OUTLINE_COLOR)
	draw_circle(stick, 26, STICK_COLOR)
	draw_circle(stick, 15, Color("444444"))
	# フェイスボタン(突進ボタンだけ色を付けて点滅)
	var face := _face_center()
	var pulse := 0.5 + 0.5 * sin(_blink_t * TAU * 1.2)
	for i in FACE_OFFSETS.size():
		var c: Vector2 = face + FACE_OFFSETS[i] * FACE_SPACING
		var dash := i == DASH_BUTTON
		draw_circle(c, FACE_RADIUS + 3, OUTLINE_COLOR)
		draw_circle(c, FACE_RADIUS, HIGHLIGHT_COLOR.lerp(Color.WHITE, pulse * 0.35) if dash else BUTTON_COLOR)
	# 指し示す線(ラベル→部位)
	if _move_label != null:
		var from_move := Vector2(_move_label.position.x + _move_label.size.x + 12, stick.y)
		_draw_pointer(from_move, stick + Vector2(-34, 0))
		var dash_c := _dash_button_center()
		var from_dash := Vector2(_dash_label.position.x - 12, dash_c.y)
		_draw_pointer(from_dash, dash_c + Vector2(FACE_RADIUS + 6, 0))


func _draw_pointer(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, OUTLINE_COLOR, 10, true)
	draw_line(from, to, LINE_COLOR, 5, true)
	draw_circle(to, 7, OUTLINE_COLOR)
	draw_circle(to, 4.5, LINE_COLOR)
