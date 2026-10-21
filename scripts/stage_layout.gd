class_name StageLayout
extends Resource
## ステージのオブジェクト配置(resources/stages/*.tres)。今はフェンスのみ。
## 選択は BalanceConfig.stage_layout / solo_stage_layout(Stage.LAYOUT_PATHS の番号)。

@export var layout_id := ""
@export var display_name := ""
@export var fences: Array[FenceSpec] = []
