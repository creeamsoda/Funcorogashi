class_name NpcBeetle
extends Player
## 入力を持たない的のフンコロガシ(チュートリアル用)。人間の被弾・フン散布・モデル表示を共用する。
## その場に留まり、"player" グループ・入力割り当て・振動・フン回収の対象から外れる。


func _ready() -> void:
	input_device = -3 # 待機。NPCは入力メソッド自体も無効にする。
	can_collect = false
	debug_growth_enabled = false
	super._ready()
	remove_from_group("player") # 人間の入力再割当・順位・投擲直撃・振動から除外する。
	add_to_group("npc")
	collision_layer = NPC_LAYER
	collision_mask = HUMAN_LAYER
	set_process_unhandled_input(false)


func _process_rolling(_delta: float) -> void:
	velocity = Vector3.ZERO


func _read_move() -> Vector2:
	return Vector2.ZERO


func _dash_input_held() -> bool:
	return false


func _start_dash() -> void:
	pass


func _unhandled_input(_event: InputEvent) -> void:
	pass
