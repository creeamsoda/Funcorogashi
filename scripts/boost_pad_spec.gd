class_name BoostPadSpec
extends Resource
## ステージ内の加速板1枚。中心(x, z)と大きさ(x 幅, z 長さ)で指定する。床に描かれた板で、ぶつからない。
## 乗ったプレイヤーは即座に突進無敵状態になる(Player._check_boost_pad)。

@export var center := Vector2.ZERO
@export var size := Vector2(2.5, 6.0)
## 板の上空に出す風(流線)の向き(x, z)。
@export var wind_dir := Vector2(0, -1)
