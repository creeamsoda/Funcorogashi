class_name TutorialNpc
extends NpcBeetle
## チュートリアルの的。茶色のフンコロガシがデカいフンを持ってその場に居続ける。
## 突進を当てられるとフンを散らしてスタンするが、保有フンは減らさず(デカいまま)、押されても元の位置へ戻る。

const BEETLE_COLOR := Color(0.36, 0.24, 0.13)
const BALL_COLOR := Color(0.50, 0.33, 0.19)
const RETURN_SPEED := 3.0

var home := Vector3.ZERO


func _ready() -> void:
	super._ready()
	position = Vector3(home.x, position.y, home.z)
	facing = Vector3.RIGHT # 横向き(フンコロガシがフンの左に見える)
	_ball_color = BALL_COLOR
	for i in _beetle_base_colors.size():
		_beetle_base_colors[i] = BEETLE_COLOR
	_update_beetle()


func _process_rolling(delta: float) -> void:
	velocity = Vector3.ZERO
	var to := home - position
	to.y = 0.0
	if to.length() > 0.05:
		move_and_collide(to.limit_length(RETURN_SPEED * delta))


func drop_and_stun(is_self_crash: bool = false) -> void:
	var keep := size
	super.drop_and_stun(is_self_crash)
	if gameplay_active:
		_set_size(keep)
