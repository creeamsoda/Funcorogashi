extends Node
## Autoload シングルトン。全スクリプトから `Config.balance.<param>` で調整値を参照する。
## project.godot の [autoload] に Config="*res://scripts/config.gd" として登録。

const BALANCE_PATH := "res://resources/balance_default.tres"

var balance: BalanceConfig

func _ready() -> void:
	balance = load(BALANCE_PATH) as BalanceConfig
	if balance == null:
		balance = BalanceConfig.new()
		push_warning("balance_default.tres を読めなかったため BalanceConfig 既定値を使用")
