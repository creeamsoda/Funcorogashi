class_name Bird
extends Animal
## 鳥: ステージ外からランダムな角度(真横〜斜め)で横断し、経路にフンを落として外へ抜ける。
## ゆっくり動くので低年齢層でも追従しやすい。

var _vel := Vector3.ZERO
var _drops_left := 1
var _drop_t := 0.0
var _drop_interval := 2.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_make_box(Vector3(1.6, 0.5, 0.7), Color(0.85, 0.90, 1.0))
	_rng.randomize()
	_setup_flight()
	_drops_left = maxi(1, Config.balance.bird_drop_count)
	_drop_interval = (2.0 * HX / maxf(Config.balance.bird_speed, 0.1)) / float(_drops_left + 1)
	_drop_t = _drop_interval

func _setup_flight() -> void:
	var speed := Config.balance.bird_speed
	var dirx := 1.0 if _rng.randf() < 0.5 else -1.0   # 左右どちらから入るか
	position = Vector3(-(HX + 2.0) * dirx, 2.5, _rng.randf_range(-HZ * 0.7, HZ * 0.7))
	var tilt := _rng.randf_range(-0.7, 0.7)            # z成分で斜め横断(0で真横)
	_vel = Vector3(dirx, 0.0, tilt).normalized() * speed

func _process(delta: float) -> void:
	position += _vel * delta
	if _drops_left > 0 and _inside():
		_drop_t -= delta
		if _drop_t <= 0.0:
			drop_pickup(position, 0.6)
			_drops_left -= 1
			_drop_t = _drop_interval
	if absf(position.x) > HX + 3.0 or absf(position.z) > HZ + 3.0:
		queue_free()

func _inside() -> bool:
	return absf(position.x) < HX - 0.2 and absf(position.z) < HZ - 0.2
