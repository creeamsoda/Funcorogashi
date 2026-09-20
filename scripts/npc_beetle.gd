class_name NpcBeetle
extends Player
## 一人プレイの横断目標。人間の被弾・フン散布・モデル表示を共用する。
## 経路時計はスタン中に停止し、最大滞在時間は止まらない。

var _route := PackedVector3Array()
var _route_length := 0.0
var _route_speed := 3.0
var _sway := 0.65
var _sway_period := 3.0
var _max_lifetime := 24.0
var _route_elapsed := 0.0
var _alive_elapsed := 0.0


## add_childより前に指定する。経路座標はステージと同じローカル座標系。
func setup_route(points: PackedVector3Array, speed: float, sway: float,
		sway_period: float, lifetime: float) -> void:
	_route = points.duplicate()
	_route_length = 0.0
	for i in _route.size():
		_route[i].y = 0.0
		if i > 0:
			_route_length += _route[i - 1].distance_to(_route[i])
	_route_speed = maxf(speed, 0.01)
	_sway = maxf(sway, 0.0)
	_sway_period = maxf(sway_period, 0.1)
	_max_lifetime = maxf(lifetime, 0.01)
	_route_elapsed = 0.0
	_alive_elapsed = 0.0
	if not _route.is_empty():
		position = _route[0]
	if _route.size() >= 2:
		facing = (_route[1] - _route[0]).normalized()


func _ready() -> void:
	input_device = -3 # 待機。NPCは入力メソッド自体も無効にする。
	can_collect = false
	debug_growth_enabled = false
	if initial_size <= 0.0:
		initial_size = Config.balance.solo_npc_initial_size
	if _route.size() < 2:
		setup_route(PackedVector3Array([Vector3(-21, 0, 0), Vector3(21, 0, 0)]),
			Config.balance.solo_npc_speed, Config.balance.solo_npc_sway,
			Config.balance.solo_npc_sway_period, Config.balance.solo_npc_lifetime)
	super._ready()
	remove_from_group("player") # 人間の入力再割当・順位・投擲直撃・振動から除外する。
	add_to_group("npc")
	collision_layer = NPC_LAYER
	collision_mask = HUMAN_LAYER
	set_process_unhandled_input(false)


## 低FPSで出現時刻をまたいだ分を、追加直後に試合時計へ合わせる。
## 未出現だった時間なので被弾・衝突は評価せず、供給経路と寿命だけを進める。
func advance_spawn_age(age: float) -> void:
	if not gameplay_active or is_queued_for_deletion():
		return
	var missed := maxf(age, 0.0)
	_alive_elapsed += missed
	_route_elapsed += missed
	if _alive_elapsed >= _max_lifetime or _route_elapsed * _route_speed >= _route_length:
		stop_gameplay()
		queue_free()
		return
	var target := _route_position(_route_elapsed)
	var direction := _route_position(_route_elapsed + 0.01) - target
	if not direction.is_zero_approx():
		facing = direction.normalized()
	position = Vector3(target.x, _radius(), target.z)
	_update_beetle()


func _physics_process(delta: float) -> void:
	if not gameplay_active or is_queued_for_deletion():
		return
	_alive_elapsed += delta
	if _alive_elapsed >= _max_lifetime:
		stop_gameplay()
		queue_free()
		return
	super._physics_process(delta)


func _process_rolling(delta: float) -> void:
	var proposed_time := _route_elapsed + delta
	var target := _route_position(proposed_time)
	target.y = position.y
	var motion := target - position
	if motion.length_squared() > 0.000001:
		facing = motion.normalized()
		velocity = motion / maxf(delta, 0.000001)
		var collision := move_and_collide(motion)
		# 人間に塞がれた距離を経路時計へ足さず、離れた後も現在位置から進む。
		var fraction := 1.0
		if collision != null:
			fraction = clampf(collision.get_travel().length() / motion.length(), 0.0, 1.0)
		_route_elapsed += delta * fraction
	else:
		velocity = Vector3.ZERO
		_route_elapsed = proposed_time
	_roll_ball(delta)
	if _route_elapsed * _route_speed >= _route_length:
		stop_gameplay()
		queue_free()


func _route_position(elapsed: float) -> Vector3:
	var remaining := clampf(elapsed * _route_speed, 0.0, _route_length)
	for i in range(1, _route.size()):
		var segment := _route[i] - _route[i - 1]
		var length := segment.length()
		if length <= 0.000001:
			continue
		if remaining <= length or i == _route.size() - 1:
			var tangent := segment / length
			var side := Vector3(-tangent.z, 0, tangent.x)
			var center := _route[i - 1] + tangent * minf(remaining, length)
			return center + side * _sway * sin(TAU * elapsed / _sway_period)
		remaining -= length
	return _route[-1] if not _route.is_empty() else position


func _read_move() -> Vector2:
	return Vector2.ZERO


func _dash_input_held() -> bool:
	return false


func _start_dash() -> void:
	pass


func _unhandled_input(_event: InputEvent) -> void:
	pass
