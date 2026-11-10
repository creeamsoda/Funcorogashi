class_name Player
extends CharacterBody3D
## プレイヤー(フンコロガシ)。フン球を転がして移動し、接触でサイズが増える。
## 突進: ROLLING→DASH_CHARGING(長押しで溜め)→離して DASHING→(判定)→STUNNED。
##   溜めるほど速く長く進み、突進中もスティックで少し曲がれる。継続時間を過ぎたら減速して止まる。
##   DASHING は離してから加速時間(dash_accel_time × 保有サイズ倍率。フンが大きいほど短い)までが「突進加速」、以降止まるまでが「突進無敵」。
##   壁=どちらのフェーズでもスタン(wall_crash_drops でドロップも。進入角 wall_slide_max_angle 以下なら壁沿いに滑って継続)。
##   突進加速: 相手=ドロップさせず突進を続ける(相手に沿って進む) / 相手が突進無敵ならこちらだけドロップ。
##   突進無敵: 相手が突進無敵なら相打ち(両者ノックバック+両者ドロップ) / それ以外の相手=命中。
##   被弾で drop_ratio 分を分裂ドロップ+スタン。自分のドロップはスタン明けまで回収不可。

signal size_changed(player_id: int, size: float)
signal dashed(player_id: int)
signal dash_hit(attacker_id: int, victim_id: int)
## 実機振動の発火契機をテスト・演出連携から観測するための通知。
signal vibration_requested(player_id: int)
## 共有デバイス上の全プレイヤーが対象ならtrue。一部だけなら誤振動防止のためfalse。
signal vibration_route_resolved(device: int, allowed: bool)

enum State { ROLLING, DASH_CHARGING, DASHING, STUNNED }

const DUNG_COLOR := Color(0.45, 0.30, 0.18)
const WINDUP_FLASH_COLOR := Color(1.0, 1.0, 1.0)
## 溜め中はゆっくり、突進無敵中は素早く点滅する。突進加速中は点滅しない。
const CHARGE_FLASH_INTERVAL := 0.25
const INVINCIBLE_FLASH_INTERVAL := 0.05
## 溜め中の方向矢印(見た目のみ)。長さは溜め量で補間する。
const DASH_ARROW_MIN_LENGTH := 1.0
const DASH_ARROW_MAX_LENGTH := 3.5
const DASH_ARROW_WIDTH := 0.35
const DASH_ARROW_HEAD := 0.8
const DASH_ARROW_FULL_COLOR := Color(1.0, 0.85, 0.2)
const BEETLE_SCENE: PackedScene = preload("res://resources/models/beetle/beetle.glb")
## 仮キューブの全長0.9を基準に、脚を含むモデル全長を約1.2倍にする。
const BEETLE_REFERENCE_LENGTH := 0.9
const BEETLE_VISUAL_SIZE_RATIO := 1.2
## 初期の12度姿勢でサイズを合わせ、傾きの調整でモデル自体が拡大しないようにする。
const BEETLE_SIZE_REFERENCE_DEGREES := 12.0
const BEETLE_HEAD_DOWN_DEGREES := 45.0
## 球の外接矩形へ少し入れ、球面に腹側を近づける。
const BEETLE_BALL_GAP := -0.10

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
## アリーナ内寸の半分。ドロップを場外に出さないために使用。
const ARENA_HX := Stage.HALF_X
const ARENA_HZ := Stage.HALF_Z
const DROP_MARGIN := 0.6
## 物理レイヤーのビット値。NPCは専用レイヤーで壁の外から出入りする。
const WALL_LAYER := 1
const HUMAN_LAYER := 2
const NPC_LAYER := 4

@export var player_id: int = 0
@export var input_device: int = -1     ## -1=キーボード矢印 / -2=WASD / 0..=Joy-Conデバイスid / その他=待機
@export var input_rotation_deg: float = 0.0  ## ドライバ差異に対する手動微調整(通常は0)
@export var initial_size: float = -1.0  ## >0 で開始サイズを上書き(スクショ/テスト用)

var size: float = 1.0
var facing: Vector3 = Vector3(0, 0, -1)
var state: State = State.ROLLING
var gameplay_active: bool = true
var can_collect: bool = true
var debug_growth_used: bool = false
var debug_growth_enabled: bool = false:
	set(value):
		debug_growth_enabled = value
		if value:
			debug_growth_used = true

var _dash_dir := Vector3(0, 0, -1)
var _charge_t := 0.0        ## 溜め開始からの経過(秒)
var _dash_t := 0.0
var _dash_speed := 0.0      ## 今回の突進速度(発動時の溜め量で決定)
var _dash_duration := 0.0   ## 今回の突進継続時間(減速を除く)
var _dash_turn_rate := 0.0  ## 今回の突進中の旋回上限(度/秒)
var _dash_accel_time := 0.0 ## 今回の突進加速時間(発動時の保有サイズで決定)。これを過ぎると突進無敵
var _stun_t := 0.0
var _cd_t := 0.0            ## 突進クールタイム残り
var _kb_vel := Vector3.ZERO ## ノックバック速度(相打ち時)
var _kb_t := 0.0
var _dash_prev := false     ## 突進ボタンの前フレーム状態(押下エッジ検出)
var _slow_t := 0.0          ## オランウータン直撃の軽スロウ残り
var _slow_factor := 1.0
var _dash_suppressed := false
var _scatter_rng: RandomNumberGenerator

var _ball_mesh: SphereMesh
var _ball_mi: MeshInstance3D
var _ball_mat: StandardMaterial3D
## 所持フンの色。他のフン(茶色)と区別するためプレイヤー色にする。
var _ball_color: Color = DUNG_COLOR
var _ball_shape: SphereShape3D
var _beetle: Node3D
var _dash_arrow: Node3D
var _dash_arrow_shaft: MeshInstance3D
var _dash_arrow_head: MeshInstance3D
var _dash_arrow_mat: StandardMaterial3D
var _beetle_model: Node3D
var _beetle_meshes: Array[MeshInstance3D] = []
var _beetle_materials: Array[StandardMaterial3D] = []
var _beetle_base_colors: Array[Color] = []
var _beetle_rear_extent := 0.0
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
	add_to_group(DebugOverlay.GROUP)
	collision_layer = HUMAN_LAYER
	collision_mask = WALL_LAYER | HUMAN_LAYER | NPC_LAYER
	size = initial_size if initial_size > 0.0 else Config.balance.size_start
	_build_audio()
	_build_visual()
	_apply_size_visual()


func _physics_process(delta: float) -> void:
	if not gameplay_active:
		return
	if _cd_t > 0.0:
		_cd_t -= delta
	if _slow_t > 0.0:
		_slow_t -= delta
	var dash_now := _dash_input_held()
	if _dash_suppressed:
		if not dash_now:
			_dash_suppressed = false
		dash_now = false
	match state:
		State.ROLLING:
			_process_rolling(delta)
			if dash_now and not _dash_prev and _cd_t <= 0.0:
				_start_dash()
		State.DASH_CHARGING:
			_process_charging(delta, dash_now)
		State.DASHING:
			_process_dashing(delta)
		State.STUNNED:
			_process_stunned(delta)
	_dash_prev = dash_now
	position.y = _radius()
	_update_beetle()
	_update_dash_arrow()


func _unhandled_input(event: InputEvent) -> void:
	# 開発用: キーボード操作時のみ、Space で疑似的にフンを取り込んで成長を確認できる。
	if not gameplay_active or not debug_growth_enabled or input_device not in [-1, -2]:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		# 標準サイズ1.0の動物フンを拾った場合の疑似成長。
		debug_growth_used = true
		add_size(Config.balance.animal_dung_amount_multiplier * Config.balance.size_gain_per_pickup)


## --- 公開API(契約 §6-2) ---

## 一人用の散布だけを個体専用乱数にする。対戦は従来の乱数を維持する。
func set_scatter_seed(value: int) -> void:
	_scatter_rng = RandomNumberGenerator.new()
	_scatter_rng.seed = value


## モード選択・リトライの決定ボタンを離すまで最初の突進を抑止する。
func suppress_dash_until_release() -> void:
	_dash_suppressed = true
	_dash_prev = false


## 終了後に直接コールバックが届いても、入力・得点・衝突効果を受け付けない。
func stop_gameplay() -> void:
	gameplay_active = false
	velocity = Vector3.ZERO
	_kb_vel = Vector3.ZERO
	state = State.ROLLING
	set_process_unhandled_input(false)
	for child in get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stop()
	if is_in_group("player") and InputRouter.is_joypad(input_device):
		Input.stop_joy_vibration(input_device)


func add_size(amount: float) -> void:
	if not gameplay_active or is_queued_for_deletion():
		return
	size += amount
	_apply_size_visual()
	size_changed.emit(player_id, size)


## 実際の獲得量に応じて、通常・大きめ・最大級の取得SEを鳴らす。
func play_pickup_se(amount: float) -> void:
	if not gameplay_active:
		return
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
	if not gameplay_active or not can_collect or is_queued_for_deletion():
		return
	var eff: int = Config.balance.orangutan_hit_effect
	if eff != 2: # SlowOnly以外 → ボーナス
		add_size(Config.balance.orangutan_bonus_size)
	if eff != 1: # BonusOnly以外 → 軽スロウ
		_slow_factor = Config.balance.orangutan_slow_factor
		_slow_t = Config.balance.orangutan_slow_time


func _current_slow() -> float:
	return _slow_factor if _slow_t > 0.0 else 1.0


## 通常移動の速度。保有フンが大きいほど遅く、オランウータン直撃のスロウも掛かる。
func _move_speed() -> float:
	return Config.balance.move_speed_base * Config.balance.move_speed_scale(size) * _current_slow()


## 最大溜めまでの時間(秒)。保有フンが大きいほど長い。
func _charge_full_time() -> float:
	return Config.balance.dash_charge_time * Config.balance.charge_time_scale(size)


## 突進加速の時間(秒)。保有フンが大きいほど長い。
func _accel_time() -> float:
	return maxf(Config.balance.dash_accel_time, 0.0) * Config.balance.accel_time_scale(size)


## 突進加速中(離してから加速時間まで)。壁でスタンし、相手をドロップさせられない。
func is_dash_accelerating() -> bool:
	return state == State.DASHING and _dash_t < _dash_accel_time


## 突進無敵中(加速時間後〜止まるまで)。相手をドロップさせ、互いに無敵なら相打ち。
func is_dash_invincible() -> bool:
	return state == State.DASHING and _dash_t >= _dash_accel_time


## 今の溜め量(0..1)。保有フンによる溜め時間の延びを反映する。
func _charge_ratio() -> float:
	return Config.balance.dash_charge_ratio(_charge_t, Config.balance.charge_time_scale(size))


func body_radius() -> float:
	return _radius()


## F2 デバッグ表示: 向き(突進方向)と本体半径。
func debug_draw(overlay: DebugOverlay) -> void:
	var base := Vector3(global_position.x, 0.05, global_position.z)
	var color: Color = PLAYER_COLORS[player_id % PLAYER_COLORS.size()]
	overlay.line(base, base + facing * 3.0, color)
	overlay.circle(base, _radius(), color)
	if state == State.DASH_CHARGING:
		# 今離した場合の直進距離(曲げなし)。減速区間は平均速度で概算。
		var ratio := _charge_ratio()
		var reach := _dash_speed_for(ratio) * (_dash_duration_for(ratio) + Config.balance.dash_end_decel_time * 0.5)
		overlay.line(base, base + facing * reach, Color.WHITE)
		overlay.circle(base + facing * reach, 0.3, Color.WHITE, 12)


## 現在1位を示す仮の王冠表示。順位判定と残り30秒の制御は GameManager が行う。
func set_crown_visible(show: bool) -> void:
	if _crown != null:
		_crown.visible = show


## 保有フンの drop_ratio 分を切り離し、lossを除いた量を地面に分裂ドロップしてスタンする。
func drop_and_stun(_is_self_crash: bool = false) -> void:
	if not gameplay_active or is_queued_for_deletion():
		return
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

## 突進ボタンの押下で溜めを開始する。発動はボタンを離した時(_process_charging)。
func _start_dash() -> void:
	if not gameplay_active:
		return
	state = State.DASH_CHARGING
	_charge_t = 0.0
	_play_charge_audio()
	dashed.emit(player_id)


## 溜め中: 低速で移動・向き変更でき、離すと発動。最低溜め前に離しても最低溜めで発動する。
func _process_charging(delta: float, held: bool) -> void:
	_charge_t += delta
	var iv := _read_move()
	var dir := Vector3(iv.x, 0.0, iv.y)
	if dir.length() > 0.15:
		facing = dir.normalized()
		velocity = facing * _move_speed() * Config.balance.dash_charge_move_ratio
	else:
		velocity = Vector3.ZERO
	move_and_slide()
	_roll_ball(delta)
	var b := Config.balance
	var auto_release := b.dash_charge_hold_max > 0.0 and _charge_t >= _charge_full_time() + b.dash_charge_hold_max
	if (not held and _charge_t >= b.dash_charge_min) or auto_release:
		_launch_dash()


func _launch_dash() -> void:
	var ratio := _charge_ratio()
	_stop_charge_audio()
	state = State.DASHING
	_dash_t = 0.0
	_dash_dir = facing
	_dash_speed = _dash_speed_for(ratio)
	_dash_duration = _dash_duration_for(ratio)
	_dash_turn_rate = lerpf(Config.balance.dash_turn_rate, Config.balance.dash_turn_rate_at_max, ratio)
	_dash_accel_time = _accel_time()
	_cd_t = Config.balance.dash_cooldown
	_play_audio(_dash_audio)


func _dash_speed_for(ratio: float) -> float:
	return lerpf(Config.balance.dash_speed_min, Config.balance.dash_speed_max, ratio)


func _dash_duration_for(ratio: float) -> float:
	return lerpf(Config.balance.dash_duration_min, Config.balance.dash_duration_max, ratio)


func _process_dashing(delta: float) -> void:
	_dash_t += delta
	_steer_dash(delta)
	var speed := _dash_speed
	var decel := maxf(Config.balance.dash_end_decel_time, 0.0)
	if _dash_t > _dash_duration:
		speed *= clampf(1.0 - (_dash_t - _dash_duration) / maxf(decel, 0.001), 0.0, 1.0)
	velocity = _dash_dir * speed # 転がし演出用
	var col := move_and_collide(_dash_dir * speed * delta)
	if col != null:
		var other := col.get_collider()
		if other is Player:
			_resolve_dash_contact(other as Player, col)
		elif other is Node and (other as Node).is_in_group("wall"):
			if not _try_wall_slide(col):
				_play_audio(_wall_hit_audio)
				_play_impact_vibrations([self])
				if Config.balance.wall_crash_drops:
					drop_and_stun(true)
				else:
					_enter_stun()
		else:
			_end_dash() # 想定外の障害物はそのまま停止
	# 相手に押し付けたまま突進を続けている場合も、時間切れで止める。
	if state == State.DASHING and _dash_t >= _dash_duration + decel:
		_end_dash()
	_roll_ball(delta)


## 壁への進入角(壁面と突進方向のなす角)が wall_slide_max_angle 以下なら、
## 突進方向を壁面に沿わせて残りの移動を続け true を返す。深い角度なら false(激突)。
func _try_wall_slide(col: KinematicCollision3D) -> bool:
	var normal := col.get_normal()
	normal.y = 0.0
	if normal.length() < 0.01:
		return false
	normal = normal.normalized()
	var into := -_dash_dir.dot(normal) # 壁へ向かう成分(=sin(進入角))
	if into <= 0.0:
		return true # 壁から離れる向きの接触は無視して継続
	var incidence := rad_to_deg(asin(clampf(into, 0.0, 1.0)))
	if incidence > Config.balance.wall_slide_max_angle:
		return false
	var along := _dash_dir - normal * _dash_dir.dot(normal)
	if along.length() < 0.01:
		return false
	_dash_dir = along.normalized()
	facing = _dash_dir
	var rem := col.get_remainder()
	rem.y = 0.0
	move_and_collide(_dash_dir * rem.length())
	return true


## スティック方向へ、今回の旋回上限(度/秒)まで突進方向を曲げる。
func _steer_dash(delta: float) -> void:
	var iv := _read_move()
	var want := Vector3(iv.x, 0.0, iv.y)
	if want.length() <= 0.15:
		return
	var angle := _dash_dir.signed_angle_to(want.normalized(), Vector3.UP)
	var max_step := deg_to_rad(_dash_turn_rate) * delta
	_dash_dir = _dash_dir.rotated(Vector3.UP, clampf(angle, -max_step, max_step)).normalized()
	facing = _dash_dir


func _resolve_dash_contact(victim: Player, col: KinematicCollision3D = null) -> void:
	if not gameplay_active or not victim.gameplay_active or victim.is_queued_for_deletion():
		return
	var away := global_position - victim.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -_dash_dir
	if victim.is_dash_invincible():
		_play_audio(_hit_audio)
		if is_dash_invincible():
			# 相打ち: 両者ノックバック+両者ドロップ
			_apply_knockback(away)
			victim._apply_knockback(-away)
			_play_impact_vibrations([self, victim])
			drop_and_stun()
			victim.drop_and_stun()
		else:
			# 突進加速中に相手の突進無敵へぶつかった: こちらだけドロップ
			_apply_knockback(away)
			_play_impact_vibrations([self])
			drop_and_stun()
			dash_hit.emit(victim.player_id, player_id)
	elif not is_dash_invincible():
		# 突進加速中(または突進外)の接触: ドロップさせず突進を続ける。
		# 残りの移動は相手の表面に沿わせる(正面なら押し付けたまま、突進無敵になった時点で命中)。
		if col != null:
			var rem := col.get_remainder().slide(col.get_normal())
			rem.y = 0.0
			if rem.length() > 0.0001:
				move_and_collide(rem)
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
	if not gameplay_active:
		return
	var targets_by_device := {}
	for node in targets:
		if not node is Player:
			continue
		var target := node as Player
		if not target.gameplay_active or not target.is_in_group("player") or target.is_queued_for_deletion():
			continue
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
		var ang := (_scatter_rng.randf() if _scatter_rng != null else randf()) * TAU
		var d := _scatter_rng.randf_range(min_r, max_r) if _scatter_rng != null else randf_range(min_r, max_r)
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
		velocity = dir * _move_speed()
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
	if not gameplay_active or player == null:
		return
	player.stop()
	player.play()


## 密集したフンを連続取得した場合も、直前の取得音を打ち切らず重ねて鳴らす。
func _play_audio_overlapping(player: AudioStreamPlayer) -> void:
	if gameplay_active and player != null:
		player.play()


func _play_charge_audio() -> void:
	_play_audio(_charge_audio)


func _stop_charge_audio() -> void:
	if _charge_audio != null:
		_charge_audio.stop()


## 音源の末尾まで到達しても溜め中なら、発動まで繰り返す。
func _on_charge_audio_finished() -> void:
	if gameplay_active and state == State.DASH_CHARGING:
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
	_ball_color = col
	_ball_mat.albedo_color = _ball_color
	_ball_mi.material_override = _ball_mat
	add_child(_ball_mi)

	_build_beetle_visual(col)
	_build_dash_arrow(col)

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


func _build_beetle_visual(player_color: Color) -> void:
	_beetle = Node3D.new()
	_beetle.name = "Beetle"
	add_child(_beetle)
	_beetle_model = BEETLE_SCENE.instantiate() as Node3D
	_beetle_model.name = "Model"
	_beetle.add_child(_beetle_model)
	# GLBの頭は-Z、腹は+Z。サイズは基準姿勢で測り、頭下げの角度と分離する。
	_beetle_model.rotation.x = deg_to_rad(-BEETLE_SIZE_REFERENCE_DEGREES)
	for node in _beetle_model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		_beetle_meshes.append(part)
		for surface in part.mesh.get_surface_count():
			# GLBの共有マテリアルを書き換えず、プレイヤーごとに色と点滅を保持する。
			var mat := part.get_active_material(surface).duplicate() as StandardMaterial3D
			if mat.resource_name == "Wing_Image":
				mat.albedo_color = player_color
			part.set_surface_override_material(surface, mat)
			_beetle_materials.append(mat)
			_beetle_base_colors.append(mat.albedo_color)
	var bounds := _beetle_visual_bounds()
	var visual_scale := BEETLE_REFERENCE_LENGTH * BEETLE_VISUAL_SIZE_RATIO / bounds.size.z
	_beetle_model.scale = Vector3.ONE * visual_scale
	_beetle_model.rotation.x = deg_to_rad(-BEETLE_HEAD_DOWN_DEGREES)
	bounds = _beetle_visual_bounds()
	# 傾けた後の足先を地面へ合わせ、腹側の張り出しに応じて球との間隔を取る。
	_beetle_model.position.y = -bounds.position.y + 0.005
	_beetle_rear_extent = bounds.end.z


## 回転前のBeetleローカル空間で、脚まで含めた実頂点の範囲を測る。
func _beetle_visual_bounds() -> AABB:
	var bounds := AABB()
	var has_point := false
	for part in _beetle_meshes:
		var to_beetle := _beetle.global_transform.affine_inverse() * part.global_transform
		for surface in part.mesh.get_surface_count():
			var vertices: PackedVector3Array = part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := to_beetle * vertex
				if not has_point:
					bounds = AABB(point, Vector3.ZERO)
					has_point = true
				else:
					bounds = bounds.expand(point)
	return bounds


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
	var direction := Vector3(facing.x, 0.0, facing.z).normalized()
	if direction.is_zero_approx():
		direction = Vector3.FORWARD
	_beetle.position = -direction * (r + _beetle_rear_extent + BEETLE_BALL_GAP) + Vector3(0, -r, 0)
	_beetle.rotation.y = atan2(direction.x, direction.z)
	var flash_on := _flash_on()
	for i in _beetle_materials.size():
		var color := _state_tint() if state == State.STUNNED else _beetle_base_colors[i]
		_beetle_materials[i].albedo_color = WINDUP_FLASH_COLOR if flash_on else color
	if _ball_mat != null:
		_ball_mat.albedo_color = WINDUP_FLASH_COLOR if flash_on else _ball_color


## 足元に平たい矢印(+Z向き)。軸は長さに合わせて伸ばし、先端は固定サイズで先に置く。
func _build_dash_arrow(player_color: Color) -> void:
	_dash_arrow = Node3D.new()
	_dash_arrow.name = "DashArrow"
	_dash_arrow.visible = false
	add_child(_dash_arrow)
	_dash_arrow_mat = StandardMaterial3D.new()
	_dash_arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dash_arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dash_arrow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_dash_arrow_mat.albedo_color = player_color
	var shaft_mesh := PlaneMesh.new()
	shaft_mesh.size = Vector2(DASH_ARROW_WIDTH, 1.0)
	_dash_arrow_shaft = MeshInstance3D.new()
	_dash_arrow_shaft.name = "Shaft"
	_dash_arrow_shaft.mesh = shaft_mesh
	_dash_arrow_shaft.material_override = _dash_arrow_mat
	_dash_arrow_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dash_arrow.add_child(_dash_arrow_shaft)
	var head_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-DASH_ARROW_HEAD * 0.5, 0, 0), Vector3(0, 0, DASH_ARROW_HEAD), Vector3(DASH_ARROW_HEAD * 0.5, 0, 0),
	])
	head_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_dash_arrow_head = MeshInstance3D.new()
	_dash_arrow_head.name = "Head"
	_dash_arrow_head.mesh = head_mesh
	_dash_arrow_head.material_override = _dash_arrow_mat
	_dash_arrow_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dash_arrow.add_child(_dash_arrow_head)


## 溜め中だけ、フン球の前縁から向いている方向へ矢印を伸ばす。最大溜めで金色になる。
func _update_dash_arrow() -> void:
	if _dash_arrow == null:
		return
	_dash_arrow.visible = state == State.DASH_CHARGING and gameplay_active
	if not _dash_arrow.visible:
		return
	var r := _radius()
	var ratio := _charge_ratio()
	var length := lerpf(DASH_ARROW_MIN_LENGTH, DASH_ARROW_MAX_LENGTH, ratio)
	_dash_arrow.position = Vector3(0, -r + 0.04, 0)
	_dash_arrow.rotation.y = atan2(facing.x, facing.z)
	_dash_arrow_shaft.scale = Vector3(1, 1, length)
	_dash_arrow_shaft.position = Vector3(0, 0, r + length * 0.5)
	_dash_arrow_head.position = Vector3(0, 0, r + length)
	var base: Color = PLAYER_COLORS[player_id % PLAYER_COLORS.size()]
	var color := base.lerp(DASH_ARROW_FULL_COLOR, ratio)
	color.a = 0.85
	_dash_arrow_mat.albedo_color = color


## 状態に応じた本体の色。前隙=白で予備動作を予告 / スタン=灰。
func _state_tint() -> Color:
	match state:
		State.STUNNED:
			return Color(0.4, 0.4, 0.4)
		_:
			return PLAYER_COLORS[player_id % PLAYER_COLORS.size()]


## 溜め中=ゆっくり点滅 / 突進加速中=点滅なし / 突進無敵中=素早く点滅。
func _flash_on() -> bool:
	if state == State.DASH_CHARGING:
		return int(_charge_t / CHARGE_FLASH_INTERVAL) % 2 == 0
	if is_dash_invincible():
		return int((_dash_t - _dash_accel_time) / INVINCIBLE_FLASH_INTERVAL) % 2 == 0
	return false


func _roll_ball(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.01:
		return
	var axis := Vector3.UP.cross(facing)
	if axis.length() < 0.01:
		return
	_ball_mi.rotate(axis.normalized(), (speed * delta) / maxf(_radius(), 0.2))
