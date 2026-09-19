class_name ThrownDung
extends Node3D
## オランウータンが投げるフン(放物線)。着地で DungPickup を生成。

const G := 14.0
const FLIGHT := 1.0

var _vel := Vector3.ZERO
var _size := 1.0
var _start := Vector3.ZERO
var _target := Vector3.ZERO

static func create(from: Vector3, to: Vector3, sz: float = 1.0) -> ThrownDung:
	var t := ThrownDung.new()
	t._start = from
	t._target = to
	t._size = sz
	return t

func _ready() -> void:
	global_position = _start
	_vel = (_target - _start) / FLIGHT
	_vel.y += 0.5 * G * FLIGHT # FLIGHT秒で target に着地する初速
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.3
	m.height = 0.6
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.40, 0.26, 0.15)
	mi.material_override = mat
	add_child(mi)

const HIT_RADIUS := 0.3

func _physics_process(delta: float) -> void:
	_vel.y -= G * delta
	global_position += _vel * delta
	var target := _check_player_hit()
	if target != null:
		target.apply_orangutan_hit() # 直撃: ボーナス+軽スロウ(切替可)。地面フンは残さない
		queue_free()
		return
	if global_position.y <= 0.0:
		_land()


func _check_player_hit() -> Player:
	for node in get_tree().get_nodes_in_group("player"):
		if node is Player:
			var pl := node as Player
			if global_position.distance_to(pl.global_position) < pl.body_radius() + HIT_RADIUS:
				return pl
	return null

func _land() -> void:
	var c := get_tree().get_first_node_in_group("dung_container")
	var parent: Node = c if c != null else get_parent()
	if parent != null:
		var pk := DungPickup.create(_size)
		parent.add_child(pk)
		pk.global_position = Vector3(global_position.x, 0.0, global_position.z)
	queue_free()
