class_name SoloDirector
extends Node3D
## GameManager の試合時計だけで進む。各動物は経過秒から位置と供給を評価する。

signal npc_requested(event: SoloEvent, event_index: int)
signal event_started(event: SoloEvent, event_index: int)

const ANIMAL_SCENES := {
	"bird": preload("res://scenes/animals/Bird.tscn"),
	"raptor": preload("res://scenes/animals/Raptor.tscn"),
	"orangutan": preload("res://scenes/animals/Orangutan.tscn"),
}

var course: SoloCourse
var _order: Array[int] = []
var _next_event: int = 0
var _elapsed: float = -1.0
var _animals: Array[Animal] = []


func _ready() -> void:
	if course == null:
		return
	for i in range(course.events.size()):
		if course.events[i] != null:
			_order.append(i)
	_order.sort_custom(func(a: int, b: int) -> bool:
		if is_equal_approx(course.events[a].at, course.events[b].at):
			return a < b
		return course.events[a].at < course.events[b].at)


func advance_to(elapsed: float) -> void:
	if course == null or elapsed < _elapsed or not can_process():
		return
	_elapsed = minf(elapsed, course.duration)
	# while で同一フレームの複数出現もすべて処理し、元のイベント番号を維持する。
	while _next_event < _order.size():
		var index := _order[_next_event]
		var event := course.events[index]
		if event.at > _elapsed or event.at >= course.duration:
			break
		_next_event += 1
		event_started.emit(event, index)
		if event.kind == "npc":
			npc_requested.emit(event, index)
		elif ANIMAL_SCENES.has(event.kind):
			var animal: Animal = ANIMAL_SCENES[event.kind].instantiate()
			animal.configure_solo(event)
			add_child(animal)
			_animals.append(animal)
	for i in range(_animals.size() - 1, -1, -1):
		var animal := _animals[i]
		if not is_instance_valid(animal) or animal.is_queued_for_deletion():
			_animals.remove_at(i)
			continue
		animal.advance_solo(_elapsed - animal.solo_event.at)
