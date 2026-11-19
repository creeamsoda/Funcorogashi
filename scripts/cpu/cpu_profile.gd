class_name CpuProfile
extends Resource
## CPUの強さ・性格の調整値(フンコロバトル_CPU実装計画 §1-3)。
## 既定は resources/cpu_profile_default.tres。F1の調整パネルの「CPU」グループから実行中に変えられる。

@export_group("CPU")
@export var think_interval: float = 0.3            ## ゴールを選び直す間隔(秒)
@export var reaction_delay: float = 0.25           ## 相手の溜めに気づいてから回避を始めるまでの遅れ(秒)
@export var aim_error_deg: float = 6.0             ## 突進の狙いのぶれ(度。±この範囲で一様)
@export var aggression: float = 1.0                ## 攻撃の点数にかける倍率。攻撃の後の休み(attack_rest_time)もこれで割る(0 = 攻撃しない)
@export var leader_bias: float = 0.5               ## 1位の相手を狙うときの点数の上乗せ(倍率に足す)
@export var same_target_penalty: float = 0.3       ## 同じ相手を続けて狙うときの点数の引き下げ(倍率から引く)
@export var collect_radius: float = 14.0           ## 回収で狙いに入れるフンまでの距離(m)
@export var dash_collect_min_distance: float = 6.0 ## 動くフンがこれより遠ければ突進で取りに行く(m)
@export var evade_detect_radius: float = 9.0       ## 回避を考える相手の溜めまでの距離(m)
@export_range(0.0, 90.0, 1.0) var evade_facing_deg: float = 20.0 ## 相手の向きが自分から何度以内なら「自分を狙っている」とみなすか
@export var special_give_up_time: float = 4.0      ## 特殊フンを狙い始めてから諦めを考えるまでの時間(秒)
@export var special_give_up_distance: float = 5.0  ## 上の時間を過ぎてもこれより遠ければ諦める(m)

@export_group("CPU Detail")
@export var attack_min_distance: float = 3.5       ## 攻撃の突進を打ち始める最短距離(m。突進加速の間は当たらないため)
@export var attack_max_distance: float = 12.0      ## 攻撃を考える最長距離(m)
@export var attack_overshoot: float = 1.5          ## 攻撃の突進を狙いの先まで伸ばす距離(m)
@export var attack_rest_time: float = 3.0          ## 攻撃の突進のあと、次の攻撃を考えるまでの時間(秒)。aggression で割る
@export var special_score_bonus: float = 2.5       ## 特殊フンの回収点数に掛ける倍率
@export var give_up_cooldown: float = 6.0          ## 諦めたフンを狙い直さない時間(秒)
@export var stuck_time: float = 0.8                ## 進もうとしてもほぼ動けない状態がこれだけ続いたら回り道する(秒)
@export var wall_probe_distance: float = 1.6       ## 歩くときに前方の壁・杭を探す距離(m)
