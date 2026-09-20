class_name SoloEvent
extends Resource
## コース開始から at 秒で出現。供給時刻はこのイベントからの相対秒。

@export var at: float = 0.0
@export_enum("bird", "raptor", "orangutan", "npc") var kind: String = "bird"
@export var path: PackedVector3Array = PackedVector3Array()
@export var speed: float = 5.0
@export var lifetime: float = 0.0
@export var drop_times: PackedFloat32Array = PackedFloat32Array()
@export var drop_positions: PackedVector3Array = PackedVector3Array()
@export var drop_sizes: PackedFloat32Array = PackedFloat32Array()
@export var throw_times: PackedFloat32Array = PackedFloat32Array()
@export var throw_targets: PackedVector3Array = PackedVector3Array()
@export var throw_sizes: PackedFloat32Array = PackedFloat32Array()
@export var npc_size: float = 12.0
@export var npc_sway: float = 0.65
@export var npc_sway_period: float = 3.0
@export var npc_lifetime: float = 24.0


func position_at(age: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	var remaining := maxf(0.0, age) * maxf(0.0, speed)
	for i in range(1, path.size()):
		var length := path[i - 1].distance_to(path[i])
		if length > 0.0 and remaining < length:
			return path[i - 1].lerp(path[i], remaining / length)
		remaining -= length
	return path[path.size() - 1]


func path_duration() -> float:
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length / maxf(speed, 0.001)


func end_age() -> float:
	var result := maxf(lifetime, path_duration())
	for drop_at in drop_times:
		result = maxf(result, drop_at + 0.1)
	for throw_at in throw_times:
		result = maxf(result, throw_at + 2.0)
	return maxf(result, 1.0)


func drop_position(index: int) -> Vector3:
	if index < drop_positions.size():
		return drop_positions[index]
	return position_at(drop_times[index])


func drop_size(index: int) -> float:
	return drop_sizes[index] if index < drop_sizes.size() else 0.6


func throw_size(index: int) -> float:
	return throw_sizes[index] if index < throw_sizes.size() else 1.0
