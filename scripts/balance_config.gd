class_name BalanceConfig
extends Resource

## プレイテストで触りたい全パラメータの集約先(MVP構成 §3)。
## コード直書き禁止。挙動は必ずここを参照する。
## 既定値はこのスクリプトに持たせ、resources/balance_default.tres で個別上書きする。

@export_group("Match")
@export var match_duration: float = 180.0          ## 制限時間(秒)
@export var player_count: int = 4                  ## 同時プレイ人数

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
@export var move_speed_size_penalty: float = 0.0   ## サイズ連動の減速(0 = 無効。MVP既定オフ)

@export_group("Dash")
@export var dash_cooldown: float = 1.5             ## クールタイム(秒)
@export var dash_windup: float = 0.25              ## 前隙(予備動作, 秒)
@export var dash_speed: float = 16.0               ## 突進速度(m/s)
@export var dash_max_time: float = 1.5             ## 突進継続の安全上限(秒)。距離は無限だが保険
@export var stun_duration: float = 1.0             ## スタン時間(秒)
@export var dash_knockback_speed: float = 8.0      ## 相打ち時ノックバック初速
@export var dash_knockback_time: float = 0.25      ## ノックバック持続(秒)

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
