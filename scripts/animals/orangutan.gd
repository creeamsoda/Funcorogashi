extends Animal
## オランウータン: ステージ外からフンを1個ずつ、ランダム間隔(上限下限)で投げ込む。
## 投げ切ったら少し間を置いて去る。直撃効果(ボーナス+軽スロウ)は I3/I4 で ThrownDung に追加。

const LEAVE_DELAY := 1.0
const FIRST_THROW_DELAY := 0.3

var _rng := RandomNumberGenerator.new()
var _throws_left := 2
var _throw_t := FIRST_THROW_DELAY
var _leave_t := LEAVE_DELAY

func _ready() -> void:
	_make_box(Vector3(1.6, 2.2, 1.4), Color(0.80, 0.45, 0.20))
	_rng.randomize()
	position = Vector3(_rng.randf_range(-HX * 0.5, HX * 0.5), 1.4, HZ + 3.0) # 南壁の外
	_throws_left = maxi(1, Config.balance.orangutan_throw_count)

func _process(delta: float) -> void:
	if _throws_left > 0:
		_throw_t -= delta
		if _throw_t <= 0.0:
			_throw_one()
			_throws_left -= 1
			_throw_t = _rng.randf_range(
				Config.balance.orangutan_throw_interval_min,
				Config.balance.orangutan_throw_interval_max)
	else:
		_leave_t -= delta
		if _leave_t <= 0.0:
			queue_free()

func _throw_one() -> void:
	var parent := _dung_parent()
	if parent == null:
		return
	var target := Vector3(_rng.randf_range(-HX * 0.7, HX * 0.7), 0.0, _rng.randf_range(-HZ * 0.6, HZ * 0.6))
	var td := ThrownDung.create(global_position + Vector3(0, 0.6, 0), target, 1.0)
	parent.add_child(td)
