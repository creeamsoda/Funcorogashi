class_name Player
extends CharacterBody3D
## プレイヤー(フンコロガシ)。フン球を転がして移動し、接触でサイズが増える。
## 突進(DASH_WINDUP/DASHING)とドロップ処理は Phase I3 で実装。
## 本フェーズ(B)は「移動」と「サイズ成長」まで。

signal size_changed(player_id: int, size: float)
signal dashed(player_id: int)
signal dash_hit(attacker_id: int, victim_id: int)

enum State { ROLLING, DASH_WINDUP, DASHING, STUNNED }

const PLAYER_COLORS := [
	Color(0.90, 0.30, 0.25), # P1 赤
	Color(0.25, 0.55, 0.95), # P2 青
	Color(0.35, 0.80, 0.35), # P3 緑
	Color(0.95, 0.80, 0.25), # P4 黄
]

## Joy-Con横持ちの補正。左スティック(Lジョイコン)→-90(270)、右スティック(Rジョイコン)→+90。
const LEFT_JOYCON_ROT := 270.0
const RIGHT_JOYCON_ROT := 90.0
const STICK_DEADZONE := 0.2
## 突進ボタン(結合ペア): 左ジョイコン=13(DpadLeft) / 右ジョイコン=3(Y)。I3で使用。
const LEFT_DASH_BUTTON := 13
const RIGHT_DASH_BUTTON := 3

@export var player_id: int = 0
@export var input_device: int = -1     ## -1=キーボード矢印 / -2=WASD / 0..=Joy-Conデバイスid / その他=待機
@export var input_stick: int = 0       ## joypad時のスティック 0=左(Lジョイコン) / 1=右(Rジョイコン)
@export var input_rotation_deg: float = 0.0  ## 追加の微調整回転(既定0)
@export var initial_size: float = -1.0  ## >0 で開始サイズを上書き(スクショ/テスト用)

var size: float = 1.0
var facing: Vector3 = Vector3(0, 0, -1)
var state: State = State.ROLLING

var _ball_mesh: SphereMesh
var _ball_mi: MeshInstance3D
var _ball_shape: SphereShape3D
var _beetle: MeshInstance3D


func _ready() -> void:
	size = initial_size if initial_size > 0.0 else Config.balance.size_start
	_build_visual()
	_apply_size_visual()


func _physics_process(delta: float) -> void:
	if state != State.ROLLING:
		return
	var iv := _read_move()
	var dir := Vector3(iv.x, 0.0, iv.y)
	if dir.length() > 0.15:
		dir = dir.normalized()
		facing = dir
		velocity = dir * Config.balance.move_speed_base
	else:
		velocity = Vector3.ZERO
	move_and_slide()
	position.y = _radius()
	_roll_ball(delta)
	_update_beetle()


func _unhandled_input(event: InputEvent) -> void:
	# 開発用: キーボード操作時のみ、Space で疑似的にフンを取り込んで成長を確認できる。
	if input_device >= 0:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		add_size(Config.balance.size_gain_per_pickup)


## --- 公開API(契約 §6-2) ---

func add_size(amount: float) -> void:
	if Config.balance.size_growth_mode == 1: # Log
		size += amount * Config.balance.size_log_scale / (1.0 + size)
	else: # Linear
		size += amount
	var cap: float = Config.balance.size_max
	if cap > 0.0:
		size = minf(size, cap)
	_apply_size_visual()
	size_changed.emit(player_id, size)


func drop_and_stun(_is_self_crash: bool) -> void:
	pass # Phase I3 で実装(50%ドロップ＋スタン)


## --- 内部 ---

func _read_move() -> Vector2:
	var v := Vector2.ZERO
	if input_device == -1:
		v = _arrows_vector()       # キーボード矢印(生キー。ui_*はjoypadも拾うため使わない)
	elif input_device == -2:
		v = _wasd_vector()
	elif input_device >= 0 and input_device < 9000:
		v = _joypad_vector(input_device)
	if input_rotation_deg != 0.0:  # 追加の微調整オフセット(既定0)
		v = v.rotated(deg_to_rad(input_rotation_deg))
	return v

## 割り当てられたスティック(input_stick)だけを読む。結合ペアは左右を別プレイヤーに割り当てるため。
func _joypad_vector(dev: int) -> Vector2:
	var ax: JoyAxis = JOY_AXIS_RIGHT_X if input_stick == 1 else JOY_AXIS_LEFT_X
	var ay: JoyAxis = JOY_AXIS_RIGHT_Y if input_stick == 1 else JOY_AXIS_LEFT_Y
	var v := Vector2(Input.get_joy_axis(dev, ax), Input.get_joy_axis(dev, ay))
	if v.length() < STICK_DEADZONE:
		return Vector2.ZERO
	var rot: float = RIGHT_JOYCON_ROT if input_stick == 1 else LEFT_JOYCON_ROT
	return v.rotated(deg_to_rad(rot))

func _arrows_vector() -> Vector2:
	var x := (1.0 if Input.is_key_pressed(KEY_RIGHT) else 0.0) - (1.0 if Input.is_key_pressed(KEY_LEFT) else 0.0)
	var y := (1.0 if Input.is_key_pressed(KEY_DOWN) else 0.0) - (1.0 if Input.is_key_pressed(KEY_UP) else 0.0)
	return Vector2(x, y)

func _wasd_vector() -> Vector2:
	var x := (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
	var y := (1.0 if Input.is_key_pressed(KEY_S) else 0.0) - (1.0 if Input.is_key_pressed(KEY_W) else 0.0)
	return Vector2(x, y)


func _radius() -> float:
	return maxf(0.2, size * Config.balance.size_to_scale)


func _build_visual() -> void:
	var col: Color = PLAYER_COLORS[player_id % PLAYER_COLORS.size()]

	_ball_shape = SphereShape3D.new()
	var ball_col := CollisionShape3D.new()
	ball_col.shape = _ball_shape
	add_child(ball_col)

	_ball_mesh = SphereMesh.new()
	_ball_mi = MeshInstance3D.new()
	_ball_mi.mesh = _ball_mesh
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color(0.45, 0.30, 0.18) # フンの茶色
	_ball_mi.material_override = ball_mat
	add_child(_ball_mi)

	_beetle = MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.7, 0.3, 0.9)
	_beetle.mesh = bmesh
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = col
	_beetle.material_override = bmat
	add_child(_beetle)


func _apply_size_visual() -> void:
	var r := _radius()
	_ball_mesh.radius = r
	_ball_mesh.height = r * 2.0
	_ball_shape.radius = r
	position.y = r
	_update_beetle()


func _update_beetle() -> void:
	var r := _radius()
	_beetle.position = -facing * (r + 0.35) + Vector3(0, -r + 0.15, 0)


func _roll_ball(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.01:
		return
	var axis := Vector3.UP.cross(facing)
	if axis.length() < 0.01:
		return
	_ball_mi.rotate(axis.normalized(), (speed * delta) / maxf(_radius(), 0.2))
