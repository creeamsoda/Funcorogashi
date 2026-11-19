extends Node3D
## エフェクトの見た目確認(実行して眺める / ScreenshotRunner 用)。カメラは対戦と同じ見下ろし角度。
##  左上: 止まった球の頭上で驚きエフェクトを一定間隔で出す
##  右上: 円を描いて走る球の後ろに逃げエフェクト
##  左下: 左右に往復して突進する球の前に加速線
##  右下: 止まった球の周りにブラックホールの渦
##  左端: フィールド上のブラックホールフン(実物の DungPickup。渦は blackhole_dung_swirl.tscn)

const SURPRISE: PackedScene = preload("res://resources/effects/surprise_burst.tscn")
const FLEE: PackedScene = preload("res://resources/effects/flee_dust.tscn")
const DASH: PackedScene = preload("res://resources/effects/dash_lines.tscn")
const BLACKHOLE: PackedScene = preload("res://resources/effects/blackhole_swirl.tscn")

const BLACKHOLE_DUNG_POS := Vector3(-10, 0, -3)

const SURPRISE_INTERVAL := 1.2
const RUN_CENTER := Vector3(5, 0.5, -3)
const RUN_RADIUS := 2.0
const RUN_SPEED := 1.6 # rad/s
const DASH_FROM := -8.0
const DASH_TO := -1.0
const DASH_Z := 4.0
const DASH_SPEED := 8.0

var _still: MeshInstance3D
var _runner: MeshInstance3D
var _dasher: MeshInstance3D
var _flee: EffectPlayer
var _dash: EffectPlayer
var _dash_dir := 1.0
var _t := 0.0
var _surprise_t := 0.0


func _ready() -> void:
	add_child(load("res://scenes/Stage.tscn").instantiate())
	_still = _ball(Vector3(-4, 0.5, -3))
	_runner = _ball(RUN_CENTER)
	_dasher = _ball(Vector3(DASH_FROM, 0.5, DASH_Z))
	var hole := _ball(Vector3(5, 0.5, 4))
	_flee = EffectPlayer.spawn(FLEE, self, _runner.global_position)
	_dash = EffectPlayer.spawn(DASH, self, _dasher.global_position, Vector3.RIGHT)
	EffectPlayer.spawn(BLACKHOLE, self, hole.global_position)
	_spawn_blackhole_dung()
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	# 対戦カメラと同じ向き(仰角約62°)で近寄せる
	cam.look_at_from_position(Vector3(0, 20.0, 11.6), Vector3(0, 0, 1))
	cam.make_current()
	_spawn_surprise()


func _process(delta: float) -> void:
	_t += delta
	_update_runner()
	_update_dasher(delta)
	_surprise_t += delta
	if _surprise_t >= SURPRISE_INTERVAL:
		_surprise_t = 0.0
		_spawn_surprise()


func _update_runner() -> void:
	var a := _t * RUN_SPEED
	var prev := _runner.global_position
	_runner.global_position = RUN_CENTER + Vector3(cos(a), 0, sin(a)) * RUN_RADIUS
	_flee.global_position = _runner.global_position - Vector3(0, 0.5, 0)
	_flee.set_direction(_runner.global_position - prev)


func _update_dasher(delta: float) -> void:
	var x := _dasher.global_position.x + _dash_dir * DASH_SPEED * delta
	if x > DASH_TO or x < DASH_FROM:
		_dash_dir = -_dash_dir
		x = clampf(x, DASH_FROM, DASH_TO)
	_dasher.global_position.x = x
	_dash.global_position = _dasher.global_position
	_dash.set_direction(Vector3(_dash_dir, 0, 0))


## 実際のブラックホールフンを置く(プレイヤーがいないので逃げずにその場で渦を出し続ける)。
func _spawn_blackhole_dung() -> void:
	# オランウータンが投げるデフォルトサイズ(orangutan.gd の _throw_one と同じ)
	var pk := DungPickup.create(1.0 * Config.balance.animal_dung_amount_multiplier)
	pk.kind = DungPickup.Kind.BLACKHOLE
	pk.position = BLACKHOLE_DUNG_POS
	add_child(pk)


func _spawn_surprise() -> void:
	EffectPlayer.spawn(SURPRISE, self, _still.global_position + Vector3(0, 0.8, 0))


func _ball(pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.3, 0.18)
	s.material = mat
	m.mesh = s
	add_child(m)
	m.global_position = pos
	return m
