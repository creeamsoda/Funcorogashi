class_name Player
extends CharacterBody3D
## プレイヤー(フンコロガシ)。フン球を転がして移動し、接触でサイズが増える。
## 突進: ROLLING→DASH_WINDUP(前隙)→DASHING→(判定)→STUNNED。
##   壁=自滅 / 突進中の相手=相打ち(両者ノックバック+両者ドロップ) / 非突進の相手=命中。
##   被弾・自滅で drop_ratio 分を分裂ドロップ+スタン。自分のドロップはスタン明けまで回収不可。

signal size_changed(player_id: int, size: float)
signal dashed(player_id: int)
signal dash_hit(attacker_id: int, victim_id: int)

enum State { ROLLING, DASH_WINDUP, DASHING, STUNNED }

const DUNG_COLOR := Color(0.45, 0.30, 0.18)
const WINDUP_FLASH_COLOR := Color(1.0, 1.0, 1.0)
const WINDUP_FLASH_INTERVAL := 0.08

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
## 突進ボタン(結合ペア): 左ジョイコン=12(DpadDown) / 右ジョイコン=3(Y)。
const LEFT_DASH_BUTTON := 12
const RIGHT_DASH_BUTTON := 3
## 開発用キーボードの突進キー(矢印P=/, WASD P=Shift)。
const ARROWS_DASH_KEY := KEY_SLASH
const WASD_DASH_KEY := KEY_SHIFT
## アリーナ内寸(Stage.STAGE_SIZE の半分に一致)。ドロップを場外に出さないために使用。
const ARENA_HX := 18.0
const ARENA_HZ := 12.0
const DROP_MARGIN := 0.6

@export var player_id: int = 0
@export var input_device: int = -1     ## -1=キーボード矢印 / -2=WASD / 0..=Joy-Conデバイスid / その他=待機
@export var input_stick: int = 0       ## joypad時のスティック 0=左(Lジョイコン) / 1=右(Rジョイコン)
@export var input_rotation_deg: float = 0.0  ## 追加の微調整回転(既定0)
@export var initial_size: float = -1.0  ## >0 で開始サイズを上書き(スクショ/テスト用)

var size: float = 1.0
var facing: Vector3 = Vector3(0, 0, -1)
var state: State = State.ROLLING

var _dash_dir := Vector3(0, 0, -1)
var _windup_t := 0.0
var _dash_t := 0.0
var _stun_t := 0.0
var _cd_t := 0.0            ## 突進クールタイム残り
var _kb_vel := Vector3.ZERO ## ノックバック速度(相打ち時)
var _kb_t := 0.0
var _dash_prev := false     ## 突進ボタンの前フレーム状態(押下エッジ検出)
var _slow_t := 0.0          ## オランウータン直撃の軽スロウ残り
var _slow_factor := 1.0

var _ball_mesh: SphereMesh
var _ball_mi: MeshInstance3D
var _ball_mat: StandardMaterial3D
var _ball_shape: SphereShape3D
var _beetle: MeshInstance3D
var _beetle_mat: StandardMaterial3D
var _crown: Label3D


func _ready() -> void:
	add_to_group("player") # オランウータンの直撃判定などで参照
	size = initial_size if initial_size > 0.0 else Config.balance.size_start
	_build_visual()
	_apply_size_visual()


func _physics_process(delta: float) -> void:
	if _cd_t > 0.0:
		_cd_t -= delta
	if _slow_t > 0.0:
		_slow_t -= delta
	var dash_now := _dash_input_held()
	match state:
		State.ROLLING:
			_process_rolling(delta)
			if dash_now and not _dash_prev and _cd_t <= 0.0:
				_start_dash()
		State.DASH_WINDUP:
			_process_windup(delta)
		State.DASHING:
			_process_dashing(delta)
		State.STUNNED:
			_process_stunned(delta)
	_dash_prev = dash_now
	position.y = _radius()
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


## オランウータンのフン直撃効果。切替可(0=ボーナス+スロウ / 1=ボーナスのみ / 2=スロウのみ)。
func apply_orangutan_hit() -> void:
	var eff: int = Config.balance.orangutan_hit_effect
	if eff != 2: # SlowOnly以外 → ボーナス
		add_size(Config.balance.orangutan_bonus_size)
	if eff != 1: # BonusOnly以外 → 軽スロウ
		_slow_factor = Config.balance.orangutan_slow_factor
		_slow_t = Config.balance.orangutan_slow_time


func _current_slow() -> float:
	return _slow_factor if _slow_t > 0.0 else 1.0


func body_radius() -> float:
	return _radius()


## 現在1位を示す仮の王冠表示。順位判定と残り30秒の制御は GameManager が行う。
func set_crown_visible(show: bool) -> void:
	if _crown != null:
		_crown.visible = show


## 保有フンの drop_ratio 分を地面に分裂ドロップし、スタン状態に入る。
func drop_and_stun(_is_self_crash: bool = false) -> void:
	var total: float = size * Config.balance.drop_ratio
	if total > 0.0:
		size -= total
		_apply_size_visual()
		size_changed.emit(player_id, size)
		_scatter_drops(total)
	_enter_stun()


## --- 突進 ---

func _start_dash() -> void:
	state = State.DASH_WINDUP
	_windup_t = Config.balance.dash_windup
	_dash_dir = facing
	velocity = Vector3.ZERO
	_cd_t = Config.balance.dash_cooldown
	dashed.emit(player_id)


func _process_windup(_delta: float) -> void:
	velocity = Vector3.ZERO
	_windup_t -= _delta
	if _windup_t <= 0.0:
		state = State.DASHING
		_dash_t = 0.0


func _process_dashing(delta: float) -> void:
	_dash_t += delta
	velocity = _dash_dir * Config.balance.dash_speed # 転がし演出用
	var motion := _dash_dir * Config.balance.dash_speed * delta
	var col := move_and_collide(motion)
	if col != null:
		var other := col.get_collider()
		if other is Player:
			_resolve_dash_contact(other as Player)
		elif other is Node and (other as Node).is_in_group("wall"):
			drop_and_stun(true) # 壁激突=自滅
		else:
			_end_dash() # 想定外の障害物はそのまま停止
	elif _dash_t >= Config.balance.dash_max_time:
		_end_dash() # 保険(通常は壁かプレイヤーに当たる)
	_roll_ball(delta)


func _resolve_dash_contact(victim: Player) -> void:
	if victim.state == State.DASHING:
		# 相打ち: 両者ノックバック+両者ドロップ
		var away := global_position - victim.global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else -_dash_dir
		_apply_knockback(away)
		victim._apply_knockback(-away)
		drop_and_stun()
		victim.drop_and_stun()
	else:
		# 命中: 相手だけドロップ+スタン、自分は無傷
		victim.drop_and_stun()
		dash_hit.emit(player_id, victim.player_id)
		_end_dash()


func _apply_knockback(dir: Vector3) -> void:
	_kb_vel = dir.normalized() * Config.balance.dash_knockback_speed
	_kb_t = Config.balance.dash_knockback_time


func _end_dash() -> void:
	state = State.ROLLING
	velocity = Vector3.ZERO


func _enter_stun() -> void:
	state = State.STUNNED
	_stun_t = Config.balance.stun_duration
	velocity = Vector3.ZERO


func _process_stunned(delta: float) -> void:
	_stun_t -= delta
	if _kb_t > 0.0:
		_kb_t -= delta
		move_and_collide(_kb_vel * delta)
	if _stun_t <= 0.0:
		state = State.ROLLING


func _scatter_drops(total: float) -> void:
	var container := get_tree().get_first_node_in_group("dung_container")
	if container == null:
		container = get_parent()
	if container == null:
		return
	var n: int = maxi(1, Config.balance.drop_scatter_count)
	var each: float = total / float(n)
	var ready_at: float = Time.get_ticks_msec() / 1000.0 + Config.balance.stun_duration
	var origin := global_position
	for i in n:
		var pk := DungPickup.create(each, player_id)
		pk.collectible_at = ready_at # 自分はスタン明けまで回収不可
		container.add_child(pk)
		pk.global_position = _drop_position(origin)


## 散らばり位置: アリーナ内(場外に出さない) かつ 本人から min〜max の距離(直近には落とさない)。
func _drop_position(origin: Vector3) -> Vector3:
	var bx: float = ARENA_HX - DROP_MARGIN
	var bz: float = ARENA_HZ - DROP_MARGIN
	var min_r: float = Config.balance.drop_scatter_min_radius
	var max_r: float = maxf(min_r, Config.balance.drop_scatter_radius)
	for _attempt in 12:
		var ang := randf() * TAU
		var d := randf_range(min_r, max_r)
		var p := origin + Vector3(cos(ang), 0.0, sin(ang)) * d
		if absf(p.x) <= bx and absf(p.z) <= bz:
			return Vector3(p.x, 0.0, p.z)
	# フォールバック(隅などで内側候補が出なかった時): 中心方向へ min_r 離し境界内へ
	var to_center := Vector3(-origin.x, 0.0, -origin.z)
	var dir := to_center.normalized() if to_center.length() > 0.01 else Vector3(0, 0, -1)
	var fp := origin + dir * min_r
	return Vector3(clampf(fp.x, -bx, bx), 0.0, clampf(fp.z, -bz, bz))


## --- 入力 ---

func _process_rolling(delta: float) -> void:
	var iv := _read_move()
	var dir := Vector3(iv.x, 0.0, iv.y)
	if dir.length() > 0.15:
		dir = dir.normalized()
		facing = dir
		velocity = dir * Config.balance.move_speed_base * _current_slow()
	else:
		velocity = Vector3.ZERO
	move_and_slide()
	_roll_ball(delta)


func _dash_input_held() -> bool:
	if input_device == -1:
		return Input.is_key_pressed(ARROWS_DASH_KEY)
	elif input_device == -2:
		return Input.is_key_pressed(WASD_DASH_KEY)
	elif input_device >= 0 and input_device < 9000:
		var btn: int = RIGHT_DASH_BUTTON if input_stick == 1 else LEFT_DASH_BUTTON
		return Input.is_joy_button_pressed(input_device, btn)
	return false


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


## --- 見た目 ---

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
	_ball_mi.name = "DungBall"
	_ball_mi.mesh = _ball_mesh
	_ball_mat = StandardMaterial3D.new()
	_ball_mat.albedo_color = DUNG_COLOR
	_ball_mi.material_override = _ball_mat
	add_child(_ball_mi)

	_beetle = MeshInstance3D.new()
	_beetle.name = "Beetle"
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.7, 0.3, 0.9)
	_beetle.mesh = bmesh
	_beetle_mat = StandardMaterial3D.new()
	_beetle_mat.albedo_color = col
	_beetle.material_override = _beetle_mat
	add_child(_beetle)

	_crown = Label3D.new()
	_crown.name = "LeaderCrown"
	_crown.text = "👑"
	_crown.font_size = 96
	_crown.pixel_size = 0.012
	_crown.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_crown.no_depth_test = true
	_crown.outline_size = 10
	var emoji_font := SystemFont.new()
	emoji_font.font_names = PackedStringArray(["Segoe UI Emoji", "Noto Color Emoji"])
	_crown.font = emoji_font
	_crown.visible = false
	add_child(_crown)


func _apply_size_visual() -> void:
	var r := _radius()
	_ball_mesh.radius = r
	_ball_mesh.height = r * 2.0
	_ball_shape.radius = r
	position.y = r
	if _crown != null:
		_crown.position = Vector3(0, r + 1.0, 0)
	_update_beetle()


func _update_beetle() -> void:
	var r := _radius()
	_beetle.position = -facing * (r + 0.35) + Vector3(0, -r + 0.15, 0)
	var flash_on := _windup_flash_on()
	if _beetle_mat != null:
		_beetle_mat.albedo_color = WINDUP_FLASH_COLOR if flash_on else _state_tint()
	if _ball_mat != null:
		_ball_mat.albedo_color = WINDUP_FLASH_COLOR if flash_on else DUNG_COLOR


## 状態に応じた本体の色。前隙=白で予備動作を予告 / スタン=灰。
func _state_tint() -> Color:
	match state:
		State.STUNNED:
			return Color(0.4, 0.4, 0.4)
		_:
			return PLAYER_COLORS[player_id % PLAYER_COLORS.size()]


func _windup_flash_on() -> bool:
	if state != State.DASH_WINDUP:
		return false
	return int(_windup_t / WINDUP_FLASH_INTERVAL) % 2 == 0


func _roll_ball(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.01:
		return
	var axis := Vector3.UP.cross(facing)
	if axis.length() < 0.01:
		return
	_ball_mi.rotate(axis.normalized(), (speed * delta) / maxf(_radius(), 0.2))
