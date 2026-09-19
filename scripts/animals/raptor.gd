extends Animal
## 恐竜ラプトル: ステージ外から走り込み、壁で2〜3回折り返して場内を走行 → 外へ走り去り消滅。
## ドロップは「1レッグ(折り返し〜次の折り返し)ごとに 1〜3個」。折り返すたびに個数をリセット。

const ENTER_OFFSET := 3.0
const EXIT_MARGIN := 3.5
const SAFETY_LIFE := 16.0

var _vel := Vector3.ZERO
var _entered := false
var _bounces_left := 2
var _leg_drops_left := 0
var _drop_t := 0.0
var _age := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_make_box(Vector3(0.6, 0.6, 1.4), Color(0.30, 0.55, 0.30))
	_rng.randomize()
	_setup_entry()
	_bounces_left = _rng.randi_range(2, 3) # 場内で折り返す回数

func _setup_entry() -> void:
	var speed := Config.balance.raptor_speed
	match _rng.randi() % 4:
		0: position = Vector3(-(HX + ENTER_OFFSET), 0.4, _rng.randf_range(-HZ * 0.5, HZ * 0.5))
		1: position = Vector3(HX + ENTER_OFFSET, 0.4, _rng.randf_range(-HZ * 0.5, HZ * 0.5))
		2: position = Vector3(_rng.randf_range(-HX * 0.5, HX * 0.5), 0.4, HZ + ENTER_OFFSET)
		_: position = Vector3(_rng.randf_range(-HX * 0.5, HX * 0.5), 0.4, -(HZ + ENTER_OFFSET))
	var target := Vector3(_rng.randf_range(-HX * 0.5, HX * 0.5), 0.4, _rng.randf_range(-HZ * 0.5, HZ * 0.5))
	var dir := target - position
	dir.y = 0.0
	_vel = dir.normalized() * speed

func _process(delta: float) -> void:
	_age += delta
	position += _vel * delta

	if not _entered and _inside():
		_entered = true
		_reset_leg_drops() # 最初のレッグ開始

	if _entered:
		_bounce()
		if _leg_drops_left > 0:
			_drop_t -= delta
			if _drop_t <= 0.0:
				drop_pickup(position, 0.5)
				_leg_drops_left -= 1
				_drop_t = _next_gap()

	# 折り返しを使い切ると反射しなくなり、そのまま場外へ抜けて消滅
	if (_entered and _out()) or _age > SAFETY_LIFE:
		queue_free()

func _bounce() -> void:
	if _bounces_left <= 0:
		return
	var hit := false
	if position.x > HX - 0.5:
		position.x = HX - 0.5
		_vel.x = -absf(_vel.x)
		hit = true
	elif position.x < -(HX - 0.5):
		position.x = -(HX - 0.5)
		_vel.x = absf(_vel.x)
		hit = true
	if position.z > HZ - 0.5:
		position.z = HZ - 0.5
		_vel.z = -absf(_vel.z)
		hit = true
	elif position.z < -(HZ - 0.5):
		position.z = -(HZ - 0.5)
		_vel.z = absf(_vel.z)
		hit = true
	if hit:
		_bounces_left -= 1
		_vel = _vel.rotated(Vector3.UP, _rng.randf_range(-0.4, 0.4)) # 進路を少し散らす
		_reset_leg_drops() # 折り返すたびにドロップ個数をリセット

func _reset_leg_drops() -> void:
	var lo: int = maxi(0, Config.balance.raptor_leg_drop_min)
	var hi: int = maxi(lo, Config.balance.raptor_leg_drop_max)
	_leg_drops_left = _rng.randi_range(lo, hi)
	_drop_t = _next_gap()

func _next_gap() -> float:
	return _rng.randf_range(Config.balance.raptor_drop_gap_min, Config.balance.raptor_drop_gap_max)

func _inside() -> bool:
	return absf(position.x) < HX - 0.5 and absf(position.z) < HZ - 0.5

func _out() -> bool:
	return absf(position.x) > HX + EXIT_MARGIN or absf(position.z) > HZ + EXIT_MARGIN
