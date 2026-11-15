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
## 入力は PlayerInput、SE は PlayerAudio、実機振動は PlayerVibration、
## 見た目の部品は BeetleModel / DashArrow / LeaderCrown に分けている。

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
const STUN_COLOR := Color(0.4, 0.4, 0.4)
## 溜め中はゆっくり、突進無敵中は素早く点滅する。突進加速中は点滅しない。
const CHARGE_FLASH_INTERVAL := 0.25
const INVINCIBLE_FLASH_INTERVAL := 0.05

const PLAYER_COLORS := [
	Color(0.90, 0.30, 0.25), # P1 赤
	Color(0.25, 0.55, 0.95), # P2 青
	Color(0.35, 0.80, 0.35), # P3 緑
	Color(0.95, 0.80, 0.25), # P4 黄
]

## アリーナ内寸の半分(Stage と同じ値)。
const ARENA_HX := Stage.HALF_X
const ARENA_HZ := Stage.HALF_Z
## ドロップを場外に出さないための内側の余白。
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
var _blackhole_t := 0.0     ## ブラックホール効果の残り(秒)
var _speed_boost_t := 0.0   ## 高速効果の残り(秒)
var _dash_suppressed := false
var _scatter_rng: RandomNumberGenerator
## 高低差のあるステージ(Stage.has_elevation)用の上下移動。平らなステージでは使わない(y=半径に固定)。
var _vy := 0.0
var _was_on_boost_pad := false  ## 前フレームに加速板の上にいたか(乗った瞬間の検出)
var _on_ground := true
var _applied_radius := -1.0

var _audio: PlayerAudio
var _ball_mesh: SphereMesh
var _ball_mi: MeshInstance3D
var _ball_mat: StandardMaterial3D
## 所持フンの色。他のフン(茶色)と区別するためプレイヤー色にする。
var _ball_color: Color = DUNG_COLOR
var _ball_shape: SphereShape3D
var _beetle: BeetleModel
var _beetle_base_colors: Array[Color] = []
var _dash_arrow: DashArrow
var _speed_lines: DashSpeedLines
var _blackhole_swirl: BlackholeSwirl
var _speed_boost_lines: DashSpeedLines
var _crown: LeaderCrown


## プレイヤー番号の色(HUD・羽・所持フンで共通)。
static func color_for(id: int) -> Color:
	return PLAYER_COLORS[id % PLAYER_COLORS.size()]


func _ready() -> void:
	add_to_group("player") # オランウータンの直撃判定などで参照
	add_to_group(DebugOverlay.GROUP)
	collision_layer = HUMAN_LAYER
	collision_mask = WALL_LAYER | HUMAN_LAYER | NPC_LAYER
	size = initial_size if initial_size > 0.0 else Config.balance.size_start
	_audio = PlayerAudio.new(self)
	_audio.charge.finished.connect(_on_charge_audio_finished)
	_build_visual()
	_apply_size_visual()


func _physics_process(delta: float) -> void:
	if not gameplay_active:
		return
	_tick_timers(delta)
	var dash_now := _dash_input_held()
	if _dash_suppressed:
		if not dash_now:
			_dash_suppressed = false
		dash_now = false
	_check_boost_pad()
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
	_update_vertical(delta)
	_update_beetle()
	_update_dash_arrow()
	_update_speed_lines()


func _tick_timers(delta: float) -> void:
	if _cd_t > 0.0:
		_cd_t -= delta
	if _slow_t > 0.0:
		_slow_t -= delta
	if _blackhole_t > 0.0:
		_blackhole_t -= delta
	if _speed_boost_t > 0.0:
		_speed_boost_t -= delta


func _unhandled_input(event: InputEvent) -> void:
	# 開発用: キーボード操作時のみ、Space で疑似的にフンを取り込んで成長を確認できる。
	if not gameplay_active or not debug_growth_enabled or not PlayerInput.is_keyboard(input_device):
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
	_blackhole_t = 0.0
	_speed_boost_t = 0.0
	_update_speed_lines()
	set_process_unhandled_input(false)
	if _audio != null:
		_audio.stop_all()
	if is_in_group("player") and InputRouter.is_joypad(input_device):
		Input.stop_joy_vibration(input_device)


func add_size(amount: float) -> void:
	if not gameplay_active or is_queued_for_deletion():
		return
	_set_size(size + amount)


## 実際の獲得量に応じて、通常・大きめ・最大級の取得SEを鳴らす。
func play_pickup_se(amount: float) -> void:
	if gameplay_active:
		_audio.play_pickup(amount)


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


## 特殊フンの回収効果。どちらも効果時間①。取り直したら残り時間を①に戻す。
func apply_special_dung(kind: DungPickup.Kind) -> void:
	if not gameplay_active or is_queued_for_deletion():
		return
	match kind:
		DungPickup.Kind.BLACKHOLE:
			_blackhole_t = Config.balance.special_effect_time
		DungPickup.Kind.SPEED:
			_speed_boost_t = Config.balance.special_effect_time


## ブラックホール効果中か(範囲②のフンを引き寄せる)。
func is_blackhole_active() -> bool:
	return gameplay_active and _blackhole_t > 0.0


## 高速効果中か(通常移動が固定速度④)。
func is_speed_boost_active() -> bool:
	return gameplay_active and _speed_boost_t > 0.0


## 突進加速中(離してから加速時間まで)。壁でスタンし、相手をドロップさせられない。
func is_dash_accelerating() -> bool:
	return state == State.DASHING and _dash_t < _dash_accel_time


## 突進無敵中(加速時間後〜止まるまで)。相手をドロップさせ、互いに無敵なら相打ち。
func is_dash_invincible() -> bool:
	return state == State.DASHING and _dash_t >= _dash_accel_time


## 空中(落下中)か。
func is_airborne() -> bool:
	return not _on_ground


func body_radius() -> float:
	return _radius()


## F2 デバッグ表示: 向き(突進方向)と本体半径。
func debug_draw(overlay: DebugOverlay) -> void:
	var base := Vector3(global_position.x, 0.05, global_position.z)
	var color := color_for(player_id)
	overlay.line(base, base + facing * 3.0, color)
	overlay.circle(base, _radius(), color)
	if state == State.DASH_CHARGING:
		# 今離した場合の直進距離(曲げなし)。減速区間は平均速度で概算。
		var ratio := _charge_ratio()
		var reach := _dash_speed_for(ratio) * (_dash_duration_for(ratio) + Config.balance.dash_end_decel_time * 0.5)
		overlay.line(base, base + facing * reach, Color.WHITE)
		overlay.circle(base + facing * reach, 0.3, Color.WHITE, 12)
	if is_blackhole_active():
		overlay.circle(base, _radius() + Config.balance.blackhole_radius, Color(0.5, 0.4, 1.0), 48)


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
		_set_size(size - detached)
		var loss_ratio := clampf(Config.balance.drop_loss_ratio, 0.0, 1.0)
		var ground_amount := detached * (1.0 - loss_ratio)
		if ground_amount > 0.0:
			_scatter_drops(ground_amount)
	_enter_stun()


func _set_size(value: float) -> void:
	size = value
	_apply_size_visual()
	size_changed.emit(player_id, size)


## --- 速度・時間(保有サイズで変わる値) ---

func _current_slow() -> float:
	return _slow_factor if _slow_t > 0.0 else 1.0


## 通常移動の速度。保有フンが大きいほど遅く、オランウータン直撃のスロウも掛かる。
## 高速効果中は重さ・スロウに関係なく固定の速度④(突進には影響しない)。
func _move_speed() -> float:
	if is_speed_boost_active():
		return Config.balance.speed_boost_move_speed
	return Config.balance.move_speed_base * Config.balance.move_speed_scale(size) * _current_slow()


## 最大溜めまでの時間(秒)。保有フンが大きいほど長い。
func _charge_full_time() -> float:
	return Config.balance.dash_charge_time * Config.balance.charge_time_scale(size)


## 突進加速の時間(秒)。保有フンが大きいほど長い。
func _accel_time() -> float:
	return maxf(Config.balance.dash_accel_time, 0.0) * Config.balance.accel_time_scale(size)


## 今の溜め量(0..1)。保有フンによる溜め時間の延びを反映する。
func _charge_ratio() -> float:
	return Config.balance.dash_charge_ratio(_charge_t, Config.balance.charge_time_scale(size))


func _dash_speed_for(ratio: float) -> float:
	return lerpf(Config.balance.dash_speed_min, Config.balance.dash_speed_max, ratio)


func _dash_duration_for(ratio: float) -> float:
	return lerpf(Config.balance.dash_duration_min, Config.balance.dash_duration_max, ratio)


## --- 通常移動・溜め ---

func _process_rolling(delta: float) -> void:
	_walk(delta, 1.0)


## 溜め中: 低速で移動・向き変更でき、離すと発動。最低溜め前に離しても最低溜めで発動する。
func _process_charging(delta: float, held: bool) -> void:
	_charge_t += delta
	_walk(delta, Config.balance.dash_charge_move_ratio)
	var b := Config.balance
	var auto_release := b.dash_charge_hold_max > 0.0 and _charge_t >= _charge_full_time() + b.dash_charge_hold_max
	if (not held and _charge_t >= b.dash_charge_min) or auto_release:
		_launch_dash()


## 入力方向へ向きを変え、通常速度 × speed_ratio で進む(入力なしなら止まる)。
func _walk(delta: float, speed_ratio: float) -> void:
	var dir := _move_input_dir()
	if dir != Vector3.ZERO:
		facing = dir
		velocity = dir * _move_speed() * speed_ratio
	else:
		velocity = Vector3.ZERO
	_slide_move(velocity * delta)
	_roll_ball(delta)


## --- 突進 ---

## 突進ボタンの押下で溜めを開始する。発動はボタンを離した時(_process_charging)。
func _start_dash() -> void:
	if not gameplay_active:
		return
	state = State.DASH_CHARGING
	_charge_t = 0.0
	_play_audio(_audio.charge)
	dashed.emit(player_id)


func _launch_dash() -> void:
	_begin_dash(facing, _charge_ratio(), _accel_time())


## 加速板: 乗った瞬間、または板の上で突進無敵でなくなったら、即座に突進無敵の突進を始める(スタン中を除く)。
## 向きは入力方向(無ければ今の向き)。溜め中なら溜めを打ち切る。突進無敵中に乗ったら突進をかけ直す。
func _check_boost_pad() -> void:
	var on := Stage.is_on_boost_pad(global_position)
	var entered := on and not _was_on_boost_pad
	_was_on_boost_pad = on
	if not on or state == State.STUNNED:
		return
	if is_dash_invincible() and not entered:
		return
	_boost_dash()


func _boost_dash() -> void:
	var dir := _move_input_dir()
	if dir == Vector3.ZERO:
		dir = Vector3(facing.x, 0.0, facing.z)
	if dir.is_zero_approx():
		dir = Vector3.FORWARD
	var ratio := clampf(Config.balance.boost_pad_charge_ratio, 0.0, 1.0)
	_begin_dash(dir.normalized(), ratio, 0.0) # 加速を飛ばして即座に突進無敵


## 溜め量 ratio の突進を dir へ始める。accel_time を過ぎると突進無敵になる。
func _begin_dash(dir: Vector3, ratio: float, accel_time: float) -> void:
	_stop_charge_audio()
	state = State.DASHING
	_dash_t = 0.0
	_dash_dir = dir
	facing = dir
	_dash_speed = _dash_speed_for(ratio)
	_dash_duration = _dash_duration_for(ratio)
	_dash_turn_rate = lerpf(Config.balance.dash_turn_rate, Config.balance.dash_turn_rate_at_max, ratio)
	_dash_accel_time = accel_time
	_cd_t = Config.balance.dash_cooldown
	_play_audio(_audio.dash)


func _process_dashing(delta: float) -> void:
	_dash_t += delta
	_steer_dash(delta)
	var speed := _dash_speed
	var decel := maxf(Config.balance.dash_end_decel_time, 0.0)
	if _dash_t > _dash_duration:
		speed *= clampf(1.0 - (_dash_t - _dash_duration) / maxf(decel, 0.001), 0.0, 1.0)
	velocity = _dash_dir * speed # 転がし演出用
	var col := _ground_move(_dash_dir * speed * delta)
	if col != null:
		var other := col.get_collider()
		if other is Player:
			_resolve_dash_contact(other as Player, col)
		elif other is Node and (other as Node).is_in_group("wall"):
			if not _try_wall_slide(col):
				_crash_into_wall()
		else:
			_end_dash() # 想定外の障害物はそのまま停止
	# 相手に押し付けたまま突進を続けている場合も、時間切れで止める。
	if state == State.DASHING and _dash_t >= _dash_duration + decel:
		_end_dash()
	_roll_ball(delta)


func _crash_into_wall() -> void:
	_play_audio(_audio.wall_hit)
	_play_impact_vibrations([self])
	if Config.balance.wall_crash_drops:
		drop_and_stun(true)
	else:
		_enter_stun()


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
	_ground_move(_dash_dir * rem.length())
	return true


## スティック方向へ、今回の旋回上限(度/秒)まで突進方向を曲げる。
func _steer_dash(delta: float) -> void:
	var want := _move_input_dir()
	if want == Vector3.ZERO:
		return
	var angle := _dash_dir.signed_angle_to(want, Vector3.UP)
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
		_play_audio(_audio.hit)
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
				_ground_move(rem)
	else:
		# 命中: 相手だけドロップ+スタン、自分は無傷
		_play_audio(_audio.hit)
		_play_impact_vibrations([victim])
		victim.drop_and_stun()
		dash_hit.emit(player_id, victim.player_id)
		_end_dash()


## MVP対象の衝撃を、対象プレイヤーのデバイスごとにまとめて振動させる(詳細は PlayerVibration)。
func _play_impact_vibrations(targets: Array) -> void:
	if gameplay_active:
		PlayerVibration.play_impact(self, targets)


func _apply_knockback(dir: Vector3) -> void:
	_kb_vel = dir.normalized() * Config.balance.dash_knockback_speed
	_kb_t = Config.balance.dash_knockback_time


func _end_dash() -> void:
	_stop_charge_audio()
	state = State.ROLLING
	velocity = Vector3.ZERO


## --- スタン・ドロップ ---

func _enter_stun() -> void:
	_stop_charge_audio()
	state = State.STUNNED
	_stun_t = Config.balance.stun_duration
	velocity = Vector3.ZERO


func _process_stunned(delta: float) -> void:
	_stun_t -= delta
	if _kb_t > 0.0:
		_kb_t -= delta
		_ground_move(_kb_vel * delta)
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
	var min_r: float = Config.balance.drop_scatter_min_radius
	var max_r: float = maxf(min_r, Config.balance.drop_scatter_radius)
	for _attempt in 12:
		var ang := (_scatter_rng.randf() if _scatter_rng != null else randf()) * TAU
		var d := _scatter_rng.randf_range(min_r, max_r) if _scatter_rng != null else randf_range(min_r, max_r)
		var p := origin + Vector3(cos(ang), 0.0, sin(ang)) * d
		if Stage.is_inside_arena(p, DROP_MARGIN) and not _drop_lands_above(p):
			return Vector3(p.x, 0.0, p.z)
	# フォールバック(隅などで内側候補が出なかった時): 中心方向へ min_r 離し境界内へ
	var to_center := Vector3(-origin.x, 0.0, -origin.z)
	var dir := to_center.normalized() if to_center.length() > 0.01 else Vector3(0, 0, -1)
	var fp := origin + dir * min_r
	return Stage.clamp_to_arena(Vector3(fp.x, 0.0, fp.z), DROP_MARGIN)


## 高低差のあるステージで、散らばり先が自分の足元より段差を超えて高い(台の上など)か。
## 台の下にいるプレイヤーのフンが台の上へ飛び上がらないようにする。
func _drop_lands_above(p: Vector3) -> bool:
	if not Stage.has_elevation():
		return false
	var feet := global_position.y - _radius()
	return Stage.top_ground_height(p) > feet + Config.balance.step_height


## --- 移動(地形) ---

## 水平方向へ motion だけ動かす。床(上向きの面: 斜面・天面)は面に沿って登り、
## 壁やプレイヤーに当たったら小さい段差なら乗り越え、乗り越えられなければその衝突を返す(残りは動かない)。
func _ground_move(motion: Vector3) -> KinematicCollision3D:
	var rem := Vector3(motion.x, 0.0, motion.z)
	for _i in 4:
		if rem.length_squared() < 1e-10:
			return null
		var col := move_and_collide(rem)
		if col == null:
			return null
		if _is_floor_collision(col):
			rem = col.get_remainder().slide(col.get_normal()) # 斜面: 面に沿って登る
			continue
		if not (col.get_collider() is Player) and _try_step_up(col.get_remainder()):
			return null
		return col
	return null


## 通常移動用: 壁やプレイヤーに当たったら面に沿って滑らせる(旧 move_and_slide 相当)。
func _slide_move(motion: Vector3) -> void:
	var rem := Vector3(motion.x, 0.0, motion.z)
	for _i in 4:
		if rem.length_squared() < 1e-10:
			return
		var col := _ground_move(rem)
		if col == null:
			return
		var n := col.get_normal()
		n.y = 0.0
		if n.length_squared() < 1e-6:
			return
		rem = col.get_remainder().slide(n.normalized())
		rem.y = 0.0


func _is_floor_collision(col: KinematicCollision3D) -> bool:
	return not (col.get_collider() is Player) and col.get_normal().y >= Stage.FLOOR_MIN_NORMAL_Y


## 小さい段差の乗り越え: 段差の高さだけ持ち上げて前へ進み、下ろして床に乗れたら採用。だめなら元に戻す。
func _try_step_up(rem: Vector3) -> bool:
	var step: float = Config.balance.step_height
	if not Stage.has_elevation() or not _on_ground or step <= 0.0:
		return false
	var horiz := Vector3(rem.x, 0.0, rem.z)
	if horiz.length_squared() < 1e-8:
		return false
	var start := global_transform
	move_and_collide(Vector3.UP * step)
	var lifted := global_position.y - start.origin.y
	move_and_collide(horiz)
	var moved := Vector2(global_position.x - start.origin.x, global_position.z - start.origin.z).length()
	var down := move_and_collide(Vector3.DOWN * (lifted + 0.05))
	if moved > 0.001 and down != null and _is_floor_collision(down) and global_position.y >= start.origin.y - 0.001:
		return true
	global_transform = start
	return false


## 上下移動: 平らなステージは y=半径に固定。高低差があれば、接地中は段差ぶんまで地面に吸着し、
## 足場がなければ重力で落ちる(スロープや天面の縁から自由に落ちられる)。
func _update_vertical(delta: float) -> void:
	if not Stage.has_elevation():
		position.y = _radius()
		_vy = 0.0
		_on_ground = true
		return
	if global_position.y < _radius() * 0.5:
		global_position.y = _radius() # 地面(y=0)より下に置かれた(生成・テスト配置)場合は地上へ
	if _on_ground:
		var snap := move_and_collide(Vector3.DOWN * Config.balance.step_height, true)
		if snap != null and _is_floor_collision(snap):
			global_position += snap.get_travel()
			_vy = 0.0
			return
		_on_ground = false
		_vy = 0.0
	_vy -= Config.balance.fall_gravity * delta
	var motion := Vector3(0.0, _vy * delta, 0.0)
	for _i in 2:
		var col := move_and_collide(motion)
		if col == null:
			return
		if _is_floor_collision(col):
			_on_ground = true
			_vy = 0.0
			return
		# 急斜面や他プレイヤーの上: 面に沿って滑り落ちる
		motion = col.get_remainder().slide(col.get_normal())


## --- 入力(NpcBeetle が上書きする) ---

func _dash_input_held() -> bool:
	return PlayerInput.dash_held(input_device)


func _read_move() -> Vector2:
	return PlayerInput.read_move(input_device, input_rotation_deg)


## 入力方向(水平・正規化)。入力が小さければ ZERO。
func _move_input_dir() -> Vector3:
	var iv := _read_move()
	var dir := Vector3(iv.x, 0.0, iv.y)
	return dir.normalized() if dir.length() > PlayerInput.MOVE_THRESHOLD else Vector3.ZERO


## --- SE ---

func _play_audio(player: AudioStreamPlayer) -> void:
	if gameplay_active:
		PlayerAudio.restart(player)


func _stop_charge_audio() -> void:
	if _audio != null:
		_audio.stop_charge()


## 音源の末尾まで到達しても溜め中なら、発動まで繰り返す。
func _on_charge_audio_finished() -> void:
	if gameplay_active and state == State.DASH_CHARGING:
		_audio.charge.play()


## --- 見た目 ---

func _radius() -> float:
	return Config.balance.radius_for_size(size, Config.balance.size_to_scale)


func _build_visual() -> void:
	var col := color_for(player_id)

	_ball_shape = SphereShape3D.new()
	var ball_col := CollisionShape3D.new()
	ball_col.shape = _ball_shape
	add_child(ball_col)

	_ball_mesh = SphereMesh.new()
	_ball_mi = MeshInstance3D.new()
	_ball_mi.name = "DungBall"
	_ball_mi.mesh = _ball_mesh
	_ball_color = col
	_ball_mat = ToonMaterial.create(_ball_color)
	_ball_mi.material_override = _ball_mat
	add_child(_ball_mi)

	# 全身をフン球と同じ色で塗る(点滅で色を書き換えるため、マテリアルは個体ごと)。
	_beetle = BeetleModel.create(self, col)
	for mat in _beetle.materials:
		_beetle_base_colors.append(mat.albedo_color)
	_dash_arrow = DashArrow.new(col)
	add_child(_dash_arrow)
	_speed_lines = DashSpeedLines.new()
	add_child(_speed_lines)
	_blackhole_swirl = BlackholeSwirl.new()
	add_child(_blackhole_swirl)
	_speed_boost_lines = DashSpeedLines.new()
	_speed_boost_lines.name = "SpeedBoostLines"
	_speed_boost_lines.setup_rising()
	add_child(_speed_boost_lines)
	_crown = LeaderCrown.new()
	add_child(_crown)


func _apply_size_visual() -> void:
	var r := _radius()
	_ball_mesh.radius = r
	_ball_mesh.height = r * 2.0
	_ball_shape.radius = r
	if Stage.has_elevation() and _applied_radius >= 0.0:
		position.y += r - _applied_radius # 足元の高さを保つ(台の上でも沈まない)
	else:
		position.y = r
	_applied_radius = r
	if _crown != null:
		_crown.fit_to_ball(r)
	_update_beetle()


## フンコロガシを球の後ろ(向きの反対側)に置き、状態に応じて点滅・灰色にする。
func _update_beetle() -> void:
	var r := _radius()
	var direction := Vector3(facing.x, 0.0, facing.z).normalized()
	if direction.is_zero_approx():
		direction = Vector3.FORWARD
	_beetle.root.position = -direction * _beetle.distance_from_ball(r) + Vector3(0, -r, 0)
	_beetle.root.rotation.y = atan2(direction.x, direction.z)
	var flash_on := _flash_on()
	var stunned := state == State.STUNNED
	for i in _beetle.materials.size():
		var color := STUN_COLOR if stunned else _beetle_base_colors[i]
		_beetle.materials[i].albedo_color = WINDUP_FLASH_COLOR if flash_on else color
	if _ball_mat != null:
		_ball_mat.albedo_color = WINDUP_FLASH_COLOR if flash_on else _ball_color


## 突進無敵中(減速に入るまで)だけ加速線を出す。突進加速中は出さない。
func _update_speed_lines() -> void:
	if _speed_lines == null:
		return
	var active := gameplay_active and is_dash_invincible() and _dash_t < _dash_duration
	_speed_lines.update_emitter(active, _dash_dir, global_position, _radius())
	_blackhole_swirl.update_swirl(is_blackhole_active(), _radius())
	_speed_boost_lines.update_rising(is_speed_boost_active(), _radius())


## 溜め中だけ、フン球の前縁から向いている方向へ矢印を伸ばす。
func _update_dash_arrow() -> void:
	if _dash_arrow == null:
		return
	if state == State.DASH_CHARGING and gameplay_active:
		_dash_arrow.show_charge(facing, _radius(), _charge_ratio())
	else:
		_dash_arrow.visible = false


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
