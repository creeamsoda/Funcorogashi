class_name AnimalSpawner
extends Node3D
## 一定間隔(ランダム)で動物3種のいずれかを出現させる。
## 生成した動物は自分の子にする(ドロップは group "dung_container" 経由)。

var _t := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_schedule()

func _schedule() -> void:
	_t = _rng.randf_range(Config.balance.animal_spawn_interval_min, Config.balance.animal_spawn_interval_max)

func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_spawn()
		_schedule()

func _spawn() -> void:
	var paths: Array[String] = [
		"res://scenes/animals/Bird.tscn",
		"res://scenes/animals/Raptor.tscn",
		"res://scenes/animals/Orangutan.tscn",
	]
	var kind := _rng.randi() % paths.size()
	add_child((load(paths[kind]) as PackedScene).instantiate())
