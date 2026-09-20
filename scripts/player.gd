class_name Player
extends CharacterBody3D
## プレイヤー(フンコロガシ)。フン球を転がして移動し、接触でサイズが増える。
## 突進: ROLLING→DASH_WINDUP(前隙)→DASHING→(判定)→STUNNED。
##   壁=自滅 / 突進中の相手=相打ち(両者ノックバック+両者ドロップ) / 非突進の相手=命中。
##   被弾・自滅で drop_ratio 分を分裂ドロップ+スタン。自分のドロップはスタン明けまで回収不可。

signal size_changed(player_id: int, size: float)
signal dashed(player_id: int)
signal dash_hit(attacker_id: int, victim_id: int)
## 実機振動の発火契機をテスト・演出連携から観測するための通知。
signal vibration_requested(player_id: int)
## 共有デバイス上の全プレイヤーが対象ならtrue。一部だけなら誤振動防止のためfalse。
signal vibration_route_resolved(device: int, allowed: bool)

enum State { ROLLING, DASH_WINDUP, DASHING, STUNNED }

const DUNG_COLOR := Color(0.45, 0.30, 0.18)
const WINDUP_FLASH_COLOR := Color(1.0, 1.0, 1.0)
const WINDUP_FLASH_INTERVAL := 0.08

const HIT_SE: AudioStream = preload("res://resources/audio/hit.wav")
const WALL_HIT_SE: AudioStream = preload("res://resources/audio/wallHit.wav")
const CHARGE_SE: AudioStream = preload("res://resources/audio/charge.wav")
const DASH_SE: AudioStream = preload("res://resources/audio/dash.wav")
const GET_NEUTRAL_SE: AudioStream = preload("res://resources/audio/getNeutral.wav")
const GET_HIGH_SE: AudioStream = preload("res://resources/audio/getHigh.wav")
const GET_HIGH_HIGH_SE: AudioStream = preload("res://resources/audio/getHighHigh.wav")

const PLAYER_COLORS := [
	Color(0.90, 0.30, 0.25), # P1 赤
	Color(0.25, 0.55, 0.95), # P2 青
	Color(0.35, 0.80, 0.35), # P3 緑
	Color(0.95, 0.80, 0.25), # P4 黄
]

const STICK_DEADZONE := 0.2
## SDL mini-gamepadモードで報告されるBTN 1を突進に使用する。
const JOYCON_DASH_BUTTON := JOY_BUTTON_B
## 開発用キーボードの突進キー(矢印P=/, WASD P=Shift)。
const ARROWS_DASH_KEY := KEY_SLASH
const WASD_DASH_KEY := KEY_SHIFT
## アリーナ内寸(Stage.STAGE_SIZE の半分に一致)。ドロップを場外に出さないために使用。
const ARENA_HX := 18.0
const ARENA_HZ := 12.0
const DROP_MARGIN := 0.6

@export var player_id: int = 0
@export var input_device: int = -1     ## -1=キーボード矢印 / -2=WASD / 0..=Joy-Conデバイスid / その他=待機
@export var input_rotation_deg: float = 0.0  ## ドライバ差異に対する手動微調整(通常は0)
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
var _hit_audio: AudioStreamPlayer
var _wall_hit_audio: AudioStreamPlayer
var _charge_audio: AudioStreamPlayer
var _dash_audio: AudioStreamPlayer
var _get_neutral_audio: AudioStreamPlayer
var _get_high_audio: AudioStreamPlayer
var _get_high_high_audio: AudioStreamPlayer


func _ready() -> void:
	add_to_group("player") # オランウータンの直撃判定などで参照
	size = initial_size if initial_size > 0.0 else Config.balance.size_start
	_build_audio()
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
		# 標準サイズ1.0の動物フンを拾った場合の疑似成長。
		add_size(Config.balance.animal_dung_amount_multiplier * Config.balance.size_gain_per_pickup)


## --- 公開API(契約 §6-2) ---

func add_size(amount: float) -> void:
	size += amount
	_apply_size_visual()
	size_changed.emit(player_id, size)


## 実際の獲得量に応じて、通常・大きめ・最大級の取得SEを鳴らす。
func play_pickup_se(amount: float) -> void:
	var neutral_max := maxf(Config.balance.pickup_se_neutral_max, 0.0)
	var high_high_min := maxf(Config.balance.pickup_se_high_high_min, neutral_max)
	if amount >= high_high_min:
		_play_audio_overlapping(_get_high_high_audio)
	elif amount > neutral_max:
		_play_audio_overlapping(_get_high_audio)
	else:
		_play_audio_overlapping(_get_neutral_audio)


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


## 保有フンの drop_ratio 分を切り離し、lossを除いた量を地面に分裂ドロップしてスタンする。
func drop_and_stun(_is_self_crash: bool = false) -> void:
	var detached: float = size * clampf(Config.balance.drop_ratio, 0.0, 1.0)
	if detached > 0.0:
		size -= detached
		_apply_size_visual()
		size_changed.emit(player_id, size)
		var loss_ratio := clampf(Config.balance.drop_loss_ratio, 0.0, 1.0)
		var ground_amount := detached * (1.0 - loss_ratio)
		if ground_amount > 0.0:
			_scatter_drops(ground_amount)
	_enter_stun()


## --- 突進 ---

func _start_dash() -> void:
	state = State.DASH_WINDUP
	_windup_t = Config.balance.dash_windup
	_dash_dir = facing
	velocity = Vector3.ZERO
	_cd_t = Config.balance.dash_cooldown
	_play_charge_audio()
	dashed.emit(player_id)


func _process_windup(_delta: float) -> void:
	velocity = Vector3.ZERO
	_windup_t -= _delta
	if _windup_t <= 0.0:
		_stop_charge_audio()
		state = State.DASHING
		_dash_t = 0.0
		_play_audio(_dash_audio)


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
			_play_audio(_wall_hit_audio)
			_play_impact_vibrations([self])
			drop_and_stun(true) # 壁激突=自滅
		else:
			_end_dash() # 想定外の障害物はそのまま停止
	elif _dash_t >= Config.balance.dash_max_time:
		_end_dash() # 保険(通常は壁かプレイヤーに当たる)
	_roll_ball(delta)


func _resolve_dash_contact(victim: Player) -> void:
	if victim.state == State.DASHING:
		# 相打ち: 両者ノックバック+両者ドロップ
		_play_audio(_hit_audio)
		var away := global_position - victim.global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else -_dash_dir
		_apply_knockback(away)
		victim._apply_knockback(-away)
		_play_impact_vibrations([self, victim])
		drop_and_stun()
		victim.drop_and_stun()
	else:
		# 命中: 相手だけドロップ+スタン、自分は無傷
		_play_audio(_hit_audio)
		_play_impact_vibrations([victim])
		victim.drop_and_stun()
		dash_hit.emit(player_id, victim.player_id)
		_end_dash()


## MVP対象の衝撃を、対象プレイヤーのデバイスごとにまとめて振動させる。
## 結合ペアなど同じdeviceを複数人が共有する場合、共有者の一部だけを振動させることはできない。
## 無関係なプレイヤーへの誤振動を避けるため、共有者全員がtargetsに含まれる場合だけ実機振動を許可する。
func _play_impact_vibrations(targets: Array) -> void:
	var targets_by_device := {}
	for node in targets:
		if not node is Player:
			continue
		var target := node as Player
		target.vibration_requested.emit(target.player_id)
		if not InputRouter.is_joypad(target.input_device):
			continue
		if not targets_by_device.has(target.input_device):
			targets_by_device[target.input_device] = {}
		targets_by_device[target.input_device][target.get_instance_id()] = true

	for device_value in targets_by_device:
		var device := int(device_value)
		var target_ids: Dictionary = targets_by_device[device]
		var assigned_ids := {}
		for node in get_tree().get_nodes_in_group("player"):
			if node is Player:
				var assigned := node as Player
				if not assigned.is_queued_for_deletion() and assigned.input_device == device:
					assigned_ids[assigned.get_instance_id()] = true
		var exclusive := assigned_ids.size() == target_ids.size()
		vibration_route_resolved.emit(device, exclusive)
		if exclusive:
			_start_device_vibration(device)


## キーボード・待機割当・切断済みjoypadでは呼ばれないデバイス単位の振動処理。
func _start_device_vibration(device: int) -> void:
	if not Input.get_connected_joypads().has(device):
		return
	if not Input.has_joy_vibration(device):
		return
	var weak := clampf(Config.balance.joy_vibration_weak_magnitude, 0.0, 1.0)
	var strong := clampf(Config.balance.joy_vibration_strong_magnitude, 0.0, 1.0)
	var duration := maxf(Config.balance.joy_vibration_duration, 0.0)
	# Godotではduration=0が無期限振動なので、0は設定上の「無効」として扱う。
	if duration <= 0.0 or (weak <= 0.0 and strong <= 0.0):
		return
	Input.start_joy_vibration(
		device,
		weak,
		strong,
		duration
	)


func _apply_knockback(dir: Vector3) -> void:
	_kb_vel = dir.normalized() * Config.balance.dash_knockback_speed
	_kb_t = Config.balance.dash_knockback_time


func _end_dash() -> void:
	_stop_charge_audio()
	state = State.ROLLING
	velocity = Vector3.ZERO


func _enter_stun() -> void:
	_stop_charge_audio()
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
		return Input.is_joy_button_pressed(input_device, JOYCON_DASH_BUTTON)
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


## --- SE ---

func _build_audio() -> void:
	_hit_audio = _create_audio_player("HitSE", HIT_SE)
	_wall_hit_audio = _create_audio_player("WallHitSE", WALL_HIT_SE)
	_charge_audio = _create_audio_player("ChargeSE", CHARGE_SE)
	_dash_audio = _create_audio_player("DashSE", DASH_SE)
	_get_neutral_audio = _create_audio_player("GetNeutralSE", GET_NEUTRAL_SE)
	_get_high_audio = _create_audio_player("GetHighSE", GET_HIGH_SE)
	_get_high_high_audio = _create_audio_player("GetHighHighSE", GET_HIGH_HIGH_SE)
	_get_neutral_audio.max_polyphony = 4
	_get_high_audio.max_polyphony = 4
	_get_high_high_audio.max_polyphony = 4
	_charge_audio.finished.connect(_on_charge_audio_finished)


func _create_audio_player(node_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	add_child(player)
	return player


func _play_audio(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	player.stop()
	player.play()


## 密集したフンを連続取得した場合も、直前の取得音を打ち切らず重ねて鳴らす。
func _play_audio_overlapping(player: AudioStreamPlayer) -> void:
	if player != null:
		player.play()


func _play_charge_audio() -> void:
	_play_audio(_charge_audio)


func _stop_charge_audio() -> void:
	if _charge_audio != null:
		_charge_audio.stop()


## 音源の末尾まで到達しても予備動作中なら、予備動作が終わるまで繰り返す。
func _on_charge_audio_finished() -> void:
	if state == State.DASH_WINDUP:
		_charge_audio.play()

## SDL mini-gamepadモードはL/Rどちらも横持ち補正済みの左スティック軸として公開する。
func _joypad_vector(dev: int) -> Vector2:
	var v := Vector2(
		Input.get_joy_axis(dev, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
	)
	if v.length() < STICK_DEADZONE:
		return Vector2.ZERO
	return v

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
	return Config.balance.radius_for_size(size, Config.balance.size_to_scale)


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
