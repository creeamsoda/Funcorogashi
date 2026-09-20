class_name SoloCourse
extends Resource
## 固定パターンと記録の識別子。内容を変えるときは version も更新する。

@export var course_id: String = "meadow"
@export var version: int = 1
@export var duration: float = 180.0
@export var player_start: Vector3 = Vector3.ZERO
@export var events: Array[SoloEvent] = []
