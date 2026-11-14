class_name PlayerInput
## プレイヤーの入力読み取り(移動ベクトルと突進ボタン)。デバイス番号の意味は InputRouter を参照。
##   -1=キーボード矢印 / -2=WASD / 0..=Joy-Conデバイスid / 9000+=待機(入力なし)

const ARROWS_DEVICE := -1
const WASD_DEVICE := -2
const STICK_DEADZONE := 0.2
## 移動入力を「入力あり」とみなす長さ(これ以下は向きを変えない)。
const MOVE_THRESHOLD := 0.15
## SDL mini-gamepadモードで報告されるBTN 1を突進に使用する。
const JOYCON_DASH_BUTTON := JOY_BUTTON_B
## 開発用キーボードの突進キー(矢印P=/, WASD P=Shift)。
const ARROWS_DASH_KEY := KEY_SLASH
const WASD_DASH_KEY := KEY_SHIFT


static func is_keyboard(device: int) -> bool:
	return device == ARROWS_DEVICE or device == WASD_DEVICE


## 移動入力(x=右, y=下)。rotation_deg はドライバ差異に対する手動微調整(通常は0)。
static func read_move(device: int, rotation_deg: float = 0.0) -> Vector2:
	var v := Vector2.ZERO
	if device == ARROWS_DEVICE:
		# 生キーを読む(ui_*はjoypadも拾うため使わない)
		v = _key_vector(KEY_RIGHT, KEY_LEFT, KEY_DOWN, KEY_UP)
	elif device == WASD_DEVICE:
		v = _key_vector(KEY_D, KEY_A, KEY_S, KEY_W)
	elif InputRouter.is_joypad(device):
		v = _joypad_vector(device)
	if rotation_deg != 0.0:
		v = v.rotated(deg_to_rad(rotation_deg))
	return v


static func dash_held(device: int) -> bool:
	if device == ARROWS_DEVICE:
		return Input.is_key_pressed(ARROWS_DASH_KEY)
	elif device == WASD_DEVICE:
		return Input.is_key_pressed(WASD_DASH_KEY)
	elif InputRouter.is_joypad(device):
		return Input.is_joy_button_pressed(device, JOYCON_DASH_BUTTON)
	return false


## SDL mini-gamepadモードはL/Rどちらも横持ち補正済みの左スティック軸として公開する。
static func _joypad_vector(device: int) -> Vector2:
	var v := Vector2(
		Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	)
	if v.length() < STICK_DEADZONE:
		return Vector2.ZERO
	return v


static func _key_vector(right: Key, left: Key, down: Key, up: Key) -> Vector2:
	var x := (1.0 if Input.is_key_pressed(right) else 0.0) - (1.0 if Input.is_key_pressed(left) else 0.0)
	var y := (1.0 if Input.is_key_pressed(down) else 0.0) - (1.0 if Input.is_key_pressed(up) else 0.0)
	return Vector2(x, y)
