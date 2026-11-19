extends Node
## Autoload シングルトン。全スクリプトから `Config.balance.<param>` で調整値を参照する。
## CPUの調整値は `Config.cpu.<param>`(CpuProfile)。
## project.godot の [autoload] に Config="*res://scripts/config.gd" として登録。

const BALANCE_PATH := "res://resources/balance_default.tres"
const CPU_PROFILE_PATH := "res://resources/cpu_profile_default.tres"

var balance: BalanceConfig
var cpu: CpuProfile

func _ready() -> void:
	balance = load(BALANCE_PATH) as BalanceConfig
	if balance == null:
		balance = BalanceConfig.new()
		push_warning("balance_default.tres を読めなかったため BalanceConfig 既定値を使用")
	cpu = load(CPU_PROFILE_PATH) as CpuProfile
	if cpu == null:
		cpu = CpuProfile.new()
		push_warning("cpu_profile_default.tres を読めなかったため CpuProfile 既定値を使用")
