class_name BalanceConfig
extends Resource

## プレイテストで触りたい全パラメータの集約先(MVP構成 §3)。
## コード直書き禁止。挙動は必ずここを参照する。
## 既定値はこのスクリプトに持たせ、resources/balance_default.tres で個別上書きする。

@export_group("Match")
@export var match_duration: float = 180.0          ## 制限時間(秒)
@export var player_count: int = 4                  ## 同時プレイ人数

@export_group("Stage Layout")
## 対戦のフェンス配置(Stage.LAYOUT_PATHS の順)。試合開始時に反映(パネルで変えたらリトライ)。
@export_enum("Open", "Center", "Corners", "Lanes") var stage_layout: int = 1
## 一人プレイのフェンス配置。固定コースがフェンス前提でないため当面 Open。
@export_enum("Open", "Center", "Corners", "Lanes") var solo_stage_layout: int = 0

@export_group("Solo NPC")
@export var solo_npc_speed: float = 3.0            ## 横断の経路進行速度(m/s)
@export var solo_npc_initial_size: float = 12.0    ## 出現時の保有フン量
@export var solo_npc_sway: float = 0.65            ## 経路からの蛇行幅(m)
@export var solo_npc_sway_period: float = 3.0      ## 蛇行の周期(秒)
@export var solo_npc_lifetime: float = 24.0        ## スタン中も進む最大滞在時間(秒)

@export_group("Dung Growth")
@export_enum("Linear", "VolumeBased", "Logarithmic") var size_visual_mode: int = 0  ## 内部サイズから見た目半径を求める方式
@export var size_start: float = 1.0                ## 開始サイズ
@export var size_gain_per_pickup: float = 0.5      ## 動物由来の地面フン実量に掛ける獲得倍率
@export var size_log_strength: float = 1.0         ## Logarithmicの曲線強度(大きいほど半径の伸びを抑える)
@export var size_to_scale: float = 0.5             ## サイズ→見た目scale係数(球半径 = size * これ)
@export var visual_radius_max: float = 0.0         ## 表示半径の上限(m)。0 = 無制限。内部サイズ/スコアは制限しない


## 内部サイズを見た目用サイズへ変換する。スコアや獲得量には影響しない。
## size_start時の見た目をLinearと一致させるため、どちらの曲線も開始サイズを基準に正規化する。
func visual_size(amount: float) -> float:
	var reference := maxf(size_start, 0.001)
	var ratio := maxf(amount, 0.0) / reference
	match size_visual_mode:
		1: # VolumeBased: 内部サイズを体積とみなし、半径を立方根で求める。
			return reference * pow(ratio, 1.0 / 3.0)
		2: # Logarithmic: 0と開始サイズを固定した正規化対数曲線。
			var strength := maxf(size_log_strength, 0.0001)
			return reference * log(1.0 + strength * ratio) / log(1.0 + strength)
		_:
			return amount


func radius_for_size(amount: float, scale: float) -> float:
	var radius := maxf(0.2, visual_size(amount) * scale)
	if visual_radius_max > 0.0:
		radius = minf(radius, visual_radius_max)
	return radius

@export_group("Movement")
@export var move_speed_base: float = 6.0           ## 基本移動速度(m/s)

@export_group("Size Effects")
## 保有フンが大きいほど遅く・溜めが長くなる。どちらも開始サイズからの増加分(内部サイズ=スコア)で決まる。
@export var move_speed_size_penalty: float = 0.03  ## 移動の減速度合い。速度 = 基本 / (1 + これ × 増加分)。0 = 無効
@export_range(0.05, 1.0, 0.01) var move_speed_size_min_ratio: float = 0.5 ## 減速の下限(基本速度に対する倍率)
@export var dash_charge_size_penalty: float = 0.03 ## 溜め時間の延び度合い。最大溜めまでの時間 = 基本 × (1 + これ × 増加分)。0 = 無効
@export var dash_charge_size_max_ratio: float = 2.0 ## 溜め時間の延びの上限(基本に対する倍率)


## 開始サイズからの増加分。
func size_growth(amount: float) -> float:
	return maxf(amount - size_start, 0.0)


## 保有サイズによる移動速度の倍率(1 = 減速なし)。溜め中の移動にも掛かる。
func move_speed_scale(amount: float) -> float:
	var scale := 1.0 / (1.0 + maxf(move_speed_size_penalty, 0.0) * size_growth(amount))
	return maxf(scale, clampf(move_speed_size_min_ratio, 0.0, 1.0))


## 保有サイズによる「最大溜めまでの時間」の倍率(1 = 延びなし)。最低溜め時間は延ばさない。
func charge_time_scale(amount: float) -> float:
	var scale := 1.0 + maxf(dash_charge_size_penalty, 0.0) * size_growth(amount)
	return minf(scale, maxf(dash_charge_size_max_ratio, 1.0))

@export_group("Dash")
@export var dash_cooldown: float = 1.5             ## クールタイム(秒)。突進開始(ボタンを離した時)から数える
@export var stun_duration: float = 1.0             ## スタン時間(秒)
@export var dash_knockback_speed: float = 8.0      ## 相打ち時ノックバック初速
@export var dash_knockback_time: float = 0.25      ## ノックバック持続(秒)
@export var wall_crash_drops: bool = false         ## 壁激突でフンを落とすか(false = スタンのみ)
@export_range(0.0, 90.0, 1.0) var wall_slide_max_angle: float = 15.0 ## 壁への進入角(度)がこれ以下ならスタンせず壁沿いに滑って突進継続。0で常にスタン

@export_group("Dash Charge")
@export var dash_charge_min: float = 0.15          ## 最低溜め時間(秒)。これより早く離しても溜め切ってから発動(予備動作)
@export var dash_charge_time: float = 1.0          ## 押し始めから最大溜めになるまでの時間(秒)
@export var dash_charge_hold_max: float = 2.0      ## 最大溜めのまま押し続けると自動発動するまでの秒数。0 = 無効
@export var dash_charge_curve: float = 1.0         ## 溜め量の補間カーブ(ease)。1 = 線形、>1 = 終盤で伸びる
@export var dash_charge_move_ratio: float = 0.2    ## 溜め中の移動速度倍率
@export var dash_speed_min: float = 10.0           ## 最小溜めの突進速度(m/s)
@export var dash_speed_max: float = 20.0           ## 最大溜めの突進速度(m/s)
@export var dash_duration_min: float = 0.35        ## 最小溜めの突進継続時間(秒)
@export var dash_duration_max: float = 0.8         ## 最大溜めの突進継続時間(秒)
@export var dash_end_decel_time: float = 0.15      ## 継続時間の後、停止までの減速時間(秒)
@export var dash_turn_rate: float = 120.0          ## 最小溜め時の突進中の曲がりやすさ(度/秒)
@export var dash_turn_rate_at_max: float = 60.0    ## 最大溜め時の突進中の曲がりやすさ(度/秒)


## 溜め時間(秒) → 0..1 の溜め量。最低溜めで0、最大溜めで1。
## time_scale は最大溜めまでの時間の倍率(保有サイズによる延び。charge_time_scale)。
func dash_charge_ratio(held_time: float, time_scale: float = 1.0) -> float:
	var span := maxf(dash_charge_time * maxf(time_scale, 0.01) - dash_charge_min, 0.001)
	return ease(clampf((held_time - dash_charge_min) / span, 0.0, 1.0), maxf(dash_charge_curve, 0.01))

@export_group("Joy-Con Vibration")
@export_range(0.0, 1.0, 0.01) var joy_vibration_weak_magnitude: float = 0.25 ## 低周波側の振動強度
@export_range(0.0, 1.0, 0.01) var joy_vibration_strong_magnitude: float = 0.4 ## 高周波側の振動強度
@export_range(0.0, 2.0, 0.01) var joy_vibration_duration: float = 0.16       ## 振動時間(秒)

@export_group("Drop & Pickup")
@export var drop_ratio: float = 0.5                ## 被弾/自滅時に本体から切り離す割合
@export_range(0.0, 1.0, 0.01) var drop_loss_ratio: float = 0.0 ## 切り離した量のうち地面に残らず消失する割合
@export var drop_scatter_count: int = 4            ## 1回の分裂ドロップ個数
@export var drop_scatter_radius: float = 2.0       ## 散らばり半径の最大(m)
@export var drop_scatter_min_radius: float = 2.0   ## 散らばり半径の最小(m)。本人の直近に落とさない
@export var pickup_size_to_scale: float = 0.5      ## 地面フンのサイズ→見た目倍率(プレイヤーのsize_to_scaleとは別)
@export var pickup_collect_radius: float = 0.4     ## 回収判定の追加余裕(m)
@export var pickup_despawn_enabled: bool = false   ## 地面フンの自然消滅(既定オフ)
@export var pickup_despawn_time: float = 10.0      ## 消滅までの秒数
@export var pickup_se_neutral_max: float = 1.2     ## この獲得量までは通常SE(動物フン約2個分)
@export var pickup_se_high_high_min: float = 2.5   ## この獲得量以上は最大級SE(巨大プレイヤーの分裂フン目安)

@export_group("Dung Flee")
## 止まっている → ⓪以内にプレイヤー → その場で①秒驚く → 驚き終わった時の一番近いプレイヤーから離れる向きへ速度②で進む
## → 進行中に③以内にプレイヤー(全員)/前方③以内に壁 → また驚く → 驚かずに④秒進んだら減速度⑤で止まる
## 壁に驚いた時は専用の驚き時間の後、近く(flee_wall_escape_radius 以内)にプレイヤーがいれば離れる向きに一番近い
## 「前方③以内に壁がない向き」へ逃げ(全方向ふさがりなら驚き続ける)、いなければ壁の前で止まる。
## 距離はプレイヤーの球の縁からフンの縁まで。スタン中のプレイヤーは無視する。
@export var flee_enabled: bool = true              ## 地面フンがプレイヤーから逃げるか
@export var flee_idle_alert_radius: float = 4.0    ## ⓪ 止まっている時に驚く距離(m)
@export var flee_surprise_time: float = 0.5        ## ① 驚きモーション(その場で震えながらジャンプ)の時間(秒)
@export var flee_speed: float = 6.5                ## ② 逃げる速度(m/s)
@export var flee_moving_alert_radius: float = 2.0  ## ③ 進んでいる時に驚く距離(m)。プレイヤー全員と、前方の壁に対して
@export var flee_wall_surprise_time: float = 0.4   ## 壁に驚いた時の驚き時間(秒)。終わったら壁を避けた向きへ逃げる
@export var flee_wall_search_step: float = 10.0    ## 壁を避ける向きを探す角度の刻み(度)。離れる向きから左右へ交互に広げる
@export var flee_wall_escape_radius: float = 4.0   ## 壁に驚き終わった時、この距離以内にプレイヤーがいれば壁を避けて逃げ、いなければ壁の前で止まる(m)
@export var flee_run_time: float = 1.5             ## ④ 驚かずにこの秒数進んだら減速を始める
@export var flee_stop_decel: float = 8.0           ## ⑤ 止まる時の減速度(m/s²)
@export var flee_speed_size_penalty: float = 0.0   ## 大きいフンほど遅く(速度 / (1 + これ×サイズ))。0 = 無効

@export_group("Animals")
@export var animal_spawn_interval_min: float = 2.0 ## 出現間隔の下限(秒)
@export var animal_spawn_interval_max: float = 4.0 ## 出現間隔の上限(秒)
@export var animal_dung_amount_multiplier: float = 1.0 ## 動物が落とすフンの実量倍率(見た目と獲得量の元になる)
@export var bird_speed: float = 3.0
@export var bird_drop_count: int = 3               ## 横断中に落とす個数
@export var raptor_speed: float = 9.0
@export var raptor_leg_drop_min: int = 1           ## 1レッグ(折り返し間)で落とす最小個数
@export var raptor_leg_drop_max: int = 3           ## 1レッグ(折り返し間)で落とす最大個数
@export var raptor_drop_gap_min: float = 0.25      ## レッグ内のドロップ間隔(下限, 秒)
@export var raptor_drop_gap_max: float = 0.55      ## レッグ内のドロップ間隔(上限, 秒)
@export var orangutan_throw_count: int = 2         ## 投げ込む総数(1個ずつ間隔を空けて投擲)
@export var orangutan_throw_interval_min: float = 0.6  ## 投擲間隔(下限, 秒)
@export var orangutan_throw_interval_max: float = 1.4  ## 投擲間隔(上限, 秒)
@export_enum("BonusSlow", "BonusOnly", "SlowOnly") var orangutan_hit_effect: int = 0  ## 直撃効果(切替可)
@export var orangutan_bonus_size: float = 1.0      ## 直撃ボーナスのサイズ量
@export var orangutan_slow_factor: float = 0.6     ## 直撃スロウ倍率(移動速度に乗算)
@export var orangutan_slow_time: float = 2.0       ## スロウ持続(秒)
