class_name StageLayout
extends Resource
## ステージのオブジェクト配置(resources/stages/*.tres)。外壁の形とフェンス。
## 選択は BalanceConfig.stage_layout / solo_stage_layout(Stage.LAYOUT_PATHS の番号)。

enum ArenaShape { RECT, CIRCLE }

@export var layout_id := ""
@export var display_name := ""
## 外壁の形。RECT は Stage.HALF_X/HALF_Z の長方形、CIRCLE は arena_radius の円。
@export var arena_shape: ArenaShape = ArenaShape.RECT
@export var arena_radius: float = 15.0
@export var fences: Array[FenceSpec] = []
## 杭: 外壁と同じ高さの角柱(中心 x, z)。壁と同じく突進で激突する。
@export var pillars: Array[Vector2] = []
@export var pillar_size: float = 0.6   ## 杭の太さ(正方形の一辺。フンコロガシ本体ぐらい)
## 加速板(乗ると即座に突進無敵)。
@export var boost_pads: Array[BoostPadSpec] = []
## 中央の台座(円錐台+半周のスロープ)。天面の高さは Stage.WALL_HEIGHT。
## スロープは手前(+z)の地面から始まり、右(+x)回りに半周して奥(-z)で天面へつながる。
@export var pedestal_enabled := false
@export var pedestal_top_radius: float = 3.5    ## 天面の半径
@export var pedestal_base_radius: float = 4.5   ## 底面の半径(天面より大きい=側面は急斜面で登れない)
@export var pedestal_ramp_width: float = 2.5    ## スロープの幅
## 4人対戦の初期位置(P1〜P4)。空なら GameManager.SPAWN_SPOTS。フェンスと重なる配置で上書きする。
@export var spawn_spots: Array[Vector3] = []
