class_name MenuStyle
extends RefCounted

const BG := Color("15231e")
const PANEL := Color("20372c")
const TEXT := Color("f7f3dd")
const MUTED := Color("b5c6b2")
const GOLD := Color("f4d36b")
const GREEN := Color("416c42")


static func japanese_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo UI", "Noto Sans CJK JP", "sans-serif"])
	font.font_weight = 700
	return font


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
