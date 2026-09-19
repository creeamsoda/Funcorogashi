class_name BalanceConfig
extends Resource

## プレイテストで触りたい全パラメータの集約先(MVP構成 §3)。
## コード直書き禁止。挙動は必ずここを参照する。
## 既定値はこのスクリプトに持たせ、resources/balance_default.tres で個別上書きする。

@export_group("Match")
@export var match_duration: float = 180.0          ## 制限時間(秒)
@export var player_count: int = 4                  ## 同時プレイ人数

@export_group("Dung Growth")
@export_enum("Linear", "Log") var size_growth_mode: int = 0  ## サイズの伸び方
@export var size_start: float = 1.0                ## 開始サイズ
@export var size_gain_per_pickup: float = 0.5      ## 取り込み1回の増加量(線形時)
@export var size_log_scale: float = 1.0            ## 対数モード時の係数
@export var size_max: float = 0.0                  ## サイズ上限(0 = 無制限)
@export var size_to_scale: float = 0.5             ## サイズ→見た目scale係数(球半径 = size * これ)

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

@export_group("Drop & Pickup")
@export var drop_ratio: float = 0.5                ## 被弾/自滅時のドロップ割合
@export var drop_scatter_count: int = 4            ## 1回の分裂ドロップ個数
@export var drop_scatter_radius: float = 2.0       ## 散らばり半径(m)
@export var pickup_collect_radius: float = 0.4     ## 回収判定の追加余裕(m)
@export var pickup_despawn_enabled: bool = false   ## 地面フンの自然消滅(既定オフ)
@export var pickup_despawn_time: float = 10.0      ## 消滅までの秒数

@export_group("Animals")
@export var animal_spawn_interval_min: float = 2.0 ## 出現間隔の下限(秒)
@export var animal_spawn_interval_max: float = 4.0 ## 出現間隔の上限(秒)
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
