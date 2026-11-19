class_name MenuStyle
extends RefCounted

const BG := Color("15231e")
const PANEL := Color("20372c")
const TEXT := Color("f7f3dd")
const MUTED := Color("b5c6b2")
const GOLD := Color("f4d36b")
const GREEN := Color("416c42")


## UI 共通の日本語フォント(ふてほど丸ゴシック / OFL 1.1 + M+ FONT LICENSE)。
## ライセンス文は resources/fonts/ に同梱。
const JAPANESE_FONT: Font = preload("res://resources/fonts/Futehodo-MaruGothic.ttf")


static func japanese_font() -> Font:
	return JAPANESE_FONT


static func make_label(text: String, font_size: int = 24, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", japanese_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


static func make_button(text: String, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(260, 60)
	button.add_theme_font_override("font", japanese_font())
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_focus_color", TEXT)
	button.add_theme_stylebox_override("normal", panel_style(GREEN if primary else PANEL))
	button.add_theme_stylebox_override("hover", panel_style(Color("537c4e"), GOLD))
	button.add_theme_stylebox_override("pressed", panel_style(Color("284e32"), GOLD))
	button.add_theme_stylebox_override("focus", panel_style(Color.TRANSPARENT, GOLD))
	return button


const TITLE_BUTTON_BG := Color("734d2e")
const TITLE_BUTTON_FOCUS_BG := Color("94653d")
const TITLE_BUTTON_PRESSED_BG := Color("5a3b22")


## タイトル画面のボタン。黒縁取り・#734D2E下地・白文字・角丸。
## size_scale はボタンの大きさの倍率(1.0 = みんなでバトル！ボタン)。
static func make_title_button(text: String, size_scale: float = 1.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(420, 100) * size_scale
	button.add_theme_font_override("font", japanese_font())
	button.add_theme_font_size_override("font_size", roundi(44 * size_scale))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, Color.WHITE)
	button.add_theme_stylebox_override("normal", _title_button_style(TITLE_BUTTON_BG, size_scale))
	button.add_theme_stylebox_override("hover", _title_button_style(TITLE_BUTTON_FOCUS_BG, size_scale))
	button.add_theme_stylebox_override("pressed", _title_button_style(TITLE_BUTTON_PRESSED_BG, size_scale))
	button.add_theme_stylebox_override("focus", _title_button_style(TITLE_BUTTON_FOCUS_BG, size_scale))
	return button


static func _title_button_style(color: Color, size_scale: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color.BLACK
	style.set_border_width_all(maxi(2, roundi(6 * size_scale)))
	style.set_corner_radius_all(roundi(28 * size_scale))
	style.content_margin_left = 24 * size_scale
	style.content_margin_right = 24 * size_scale
	return style


static func panel_style(color: Color = PANEL, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	return style
