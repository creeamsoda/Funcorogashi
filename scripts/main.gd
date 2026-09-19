extends Node3D
## エントリポイント(暫定)。Phase I1 でコアループ(ステージ/プレイヤー/タイマー)を組み込む。
## 調整値は autoload `Config.balance` から参照する。

func _ready() -> void:
	var b := Config.balance
	print("[funcorogashi] boot OK / match_duration=", b.match_duration,
		" / players=", b.player_count, " / dash_speed=", b.dash_speed)
