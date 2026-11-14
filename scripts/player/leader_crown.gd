class_name LeaderCrown
extends Label3D
## 現在1位を示す仮の王冠表示。順位判定と表示の切替は GameManager が行う。

## フン球の上端からの高さ。
const HEIGHT_ABOVE_BALL := 1.0


func _init() -> void:
	name = "LeaderCrown"
	text = "👑"
	font_size = 96
	pixel_size = 0.012
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	outline_size = 10
	var emoji_font := SystemFont.new()
	emoji_font.font_names = PackedStringArray(["Segoe UI Emoji", "Noto Color Emoji"])
	font = emoji_font
	visible = false


## フン球の半径に合わせて置き直す。
func fit_to_ball(radius: float) -> void:
	position = Vector3(0, radius + HEIGHT_ABOVE_BALL, 0)
