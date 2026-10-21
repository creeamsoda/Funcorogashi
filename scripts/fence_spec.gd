class_name FenceSpec
extends Resource
## ステージ内のフェンス1本。中心(x, z)・長さ・向きで指定する。
## rotation_deg = 0 で X 方向(左右)に伸び、90 で Z 方向(奥行き)に伸びる。

@export var center := Vector2.ZERO
@export var length: float = 4.0
@export var rotation_deg: float = 0.0
