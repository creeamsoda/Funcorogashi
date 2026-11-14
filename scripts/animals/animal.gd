class_name Animal
extends Node3D
## 動物の共通基底。ステージ内寸(HX,HZ)とドロップ処理を持つ。
## ドロップは group "dung_container" のノードへ生成(無ければ自分の親)。

const HX := Stage.HALF_X
const HZ := Stage.HALF_Z

var solo_event: SoloEvent
var _solo_drop_done: Dictionary = {}
var _solo_throw_done: Dictionary = {}
var _solo_projectiles: Array[ThrownDung] = []
var _solo_projectile_times: Array[float] = []


func configure_solo(event: SoloEvent) -> void:
	solo_event = event


## 各派生の _ready から、見た目生成後・乱数初期化前に呼ぶ。
func begin_solo() -> bool:
	if solo_event == null:
		return false
	set_process(false)
	set_physics_process(false)
	global_position = solo_event.position_at(0.0)
	return true


func advance_solo(age: float) -> void:
	if solo_event == null or age < 0.0 or not can_process():
		return
	global_position = solo_event.position_at(age)
	# 供給位置は現在位置ではなく、予定時刻で評価する。長いフレームでも変わらない。
	for i in range(solo_event.drop_times.size()):
		if not _solo_drop_done.has(i) and solo_event.drop_times[i] <= age:
			_solo_drop_done[i] = true
			drop_pickup(solo_event.drop_position(i), solo_event.drop_size(i))
	for i in range(mini(solo_event.throw_times.size(), solo_event.throw_targets.size())):
		if not _solo_throw_done.has(i) and solo_event.throw_times[i] <= age:
			_solo_throw_done[i] = true
			var parent := _dung_parent()
			if parent != null:
				var from := solo_event.position_at(solo_event.throw_times[i]) + Vector3(0, 0.6, 0)
				var amount := solo_event.throw_size(i) * Config.balance.animal_dung_amount_multiplier
				var thrown := ThrownDung.create(from, solo_event.throw_targets[i], amount)
				thrown.externally_clocked = true
				parent.add_child(thrown)
				_solo_projectiles.append(thrown)
				_solo_projectile_times.append(solo_event.throw_times[i])
	for i in range(_solo_projectiles.size() - 1, -1, -1):
		var projectile := _solo_projectiles[i]
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
			_solo_projectiles.remove_at(i)
			_solo_projectile_times.remove_at(i)
			continue
		projectile.advance_solo(age - _solo_projectile_times[i])
	if age >= solo_event.end_age():
		queue_free()

func drop_pickup(world_pos: Vector3, sz: float) -> void:
	var parent := _dung_parent()
	if parent == null:
		return
	var actual_size := sz * Config.balance.animal_dung_amount_multiplier
	var pk := DungPickup.create(actual_size)
	parent.add_child(pk)
	pk.global_position = Vector3(world_pos.x, 0.0, world_pos.z)

func _dung_parent() -> Node:
	var c := get_tree().get_first_node_in_group("dung_container")
	return c if c != null else get_parent()

func _make_box(sz: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	var mat := ToonMaterial.create(color)
	mi.material_override = mat
	add_child(mi)
	return mi
