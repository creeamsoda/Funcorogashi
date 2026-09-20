extends Node3D
## 乱数呼び出しとフレーム幅を変えても供給予定が一致することを実座標で検証。

var _failures: Array[String] = []


func _ready() -> void:
	var course := _probe_course()
	var fine := _simulate(course, 0.125, false)
	var coarse := _simulate(course, 8.0, true)
	_check(fine.pickups == coarse.pickups, "small/large frames preserve pickup positions and amounts")
	_check(fine.events == [1, 3, 0, 2], "events are chronological, ties keep resource order")
	_check(coarse.events == fine.events and coarse.npcs == [3], "crossed events and NPC request occur once")
	_check(fine.pickups.size() == 7, "all drops and throws land without duplicates")
	var amount := Config.balance.animal_dung_amount_multiplier
	_check(fine.pickups.has(_pickup_key(Vector3(3, 0, 2), 1.25 * amount)), "first throw lands exactly on its preview")
	_check(fine.pickups.has(_pickup_key(Vector3(-4, 0, 1), 0.75 * amount)), "second throw lands exactly on its preview")
	var turn := course.events[0]
	_check(turn.position_at(1.5).is_equal_approx(Vector3(2, 0.4, 1)), "multi-segment path uses distance at scheduled time")
	_check(_stopped_world_stays_stopped(course), "disabled world blocks generation and projectile landing")

	var full := load("res://resources/solo/default_course.tres") as SoloCourse
	_check(full != null and is_equal_approx(full.duration, 180.0), "default course lasts 180 seconds")
	if full != null:
		var full_fine := _simulate(full, 0.37, false)
		var full_coarse := _simulate(full, 180.0, true)
		_check(full_fine.pickups == full_coarse.pickups, "full course supply is independent of frame partition and random calls")
		_check(full_fine.events == full_coarse.events and full_fine.events.size() == full.events.size(), "all full-course events occur")
		_check(full_fine.npcs.size() == 10, "NPC opportunities span the course")
		_check(_all_drops_inside(full_fine.positions), "full course ground supply stays in the arena")
	for failure in _failures:
		push_error("[solo_pattern_check] " + failure)
	print("[solo_pattern_check] result=", "PASS" if _failures.is_empty() else "FAIL", " failures=", _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _simulate(course: SoloCourse, step: float, noise: bool) -> Dictionary:
	var world := Node3D.new()
	add_child(world)
	var dung := Node3D.new()
	dung.add_to_group("dung_container")
	world.add_child(dung)
	var director := SoloDirector.new()
	director.course = course
	var event_ids: Array[int] = []
	var npc_ids: Array[int] = []
	director.event_started.connect(func(_event: SoloEvent, index: int): event_ids.append(index))
	director.npc_requested.connect(func(_event: SoloEvent, index: int): npc_ids.append(index))
	world.add_child(director)
	var elapsed := 0.0
	director.advance_to(0.0)
	while elapsed < course.duration:
		if noise:
			for i in range(23):
				randf()
		elapsed = minf(elapsed + step, course.duration)
		director.advance_to(elapsed)
	# 同時刻を再送してもドロップ・出現・着地を再実行しない。
	director.advance_to(elapsed)
	var pickups: Array[String] = []
	var positions: Array[Vector3] = []
	for child in dung.get_children():
		if child is DungPickup:
			pickups.append(_pickup_key(child.global_position, child.size))
			positions.append(child.global_position)
	pickups.sort()
	world.free()
	return {"pickups": pickups, "events": event_ids, "npcs": npc_ids, "positions": positions}


func _probe_course() -> SoloCourse:
	var result := SoloCourse.new()
	result.duration = 8.0
	var raptor := SoloEvent.new()
	raptor.at = 0.5
	raptor.kind = "raptor"
	raptor.path = PackedVector3Array([Vector3(0, 0.4, 0), Vector3(2, 0.4, 0), Vector3(2, 0.4, 2)])
	raptor.speed = 2.0
	raptor.drop_times = PackedFloat32Array([0.5, 1.5])
	var bird := SoloEvent.new()
	bird.kind = "bird"
	bird.path = PackedVector3Array([Vector3(-5, 2.5, -2), Vector3(5, 2.5, -2)])
	bird.speed = 2.0
	bird.drop_times = PackedFloat32Array([0.0, 1.0, 2.0])
	var orangutan := SoloEvent.new()
	orangutan.at = 0.5
	orangutan.kind = "orangutan"
	orangutan.path = PackedVector3Array([Vector3(1, 1.4, 15)])
	orangutan.throw_times = PackedFloat32Array([0.3, 1.4])
	orangutan.throw_targets = PackedVector3Array([Vector3(3, 0, 2), Vector3(-4, 0, 1)])
	orangutan.throw_sizes = PackedFloat32Array([1.25, 0.75])
	var npc := SoloEvent.new()
	npc.at = 0.25
	npc.kind = "npc"
	var late := SoloEvent.new()
	late.at = result.duration
	late.kind = "npc"
	# あえて時刻順ではない Resource を使う。
	result.events.assign([raptor, bird, orangutan, npc, late])
	return result


func _stopped_world_stays_stopped(course: SoloCourse) -> bool:
	var world := Node3D.new()
	add_child(world)
	var dung := Node3D.new()
	dung.add_to_group("dung_container")
	world.add_child(dung)
	var director := SoloDirector.new()
	director.course = course
	world.add_child(director)
	var thrown := ThrownDung.create(Vector3(0, 2, 0), Vector3(2, 0, 2))
	thrown.externally_clocked = true
	world.add_child(thrown)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	director.advance_to(8.0)
	thrown.advance_solo(2.0)
	thrown._land()
	var result := dung.get_child_count() == 0 and director.get_child_count() == 0
	world.free()
	return result


func _all_drops_inside(positions: Array[Vector3]) -> bool:
	for position in positions:
		if absf(position.x) > Animal.HX - 0.2 or absf(position.z) > Animal.HZ - 0.2:
			return false
	return true


func _pickup_key(position: Vector3, size: float) -> String:
	return "%.5f,%.5f:%.5f" % [position.x, position.z, size]


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
