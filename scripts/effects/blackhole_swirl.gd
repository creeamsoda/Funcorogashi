class_name BlackholeSwirl
extends Node3D
## ブラックホール効果中の渦巻き。突進の加速線(DashSpeedLines)を数本の腕に分けて球の周りに置き、
## 腕ごと回し続ける。線はローカル座標で出るので回転に引きずられ、内側へ寄りながら台風のように渦を巻く。
## 親(プレイヤー)の原点 = 球の中心。

const ARMS := 3
const LINES_PER_ARM := 10
const SPIN_SPEED := 7.0          ## 回転の速さ(rad/s。上から見て反時計回り)
const ARM_GAP := 1.2             ## 腕の中心を球の縁からどれだけ外に置くか(m)
const COLOR := Color(0.35, 0.05, 1.0)  ## 彩度の高い青紫(通常合成なので床の上でも色が残る)

var _arms: Array[DashSpeedLines] = []


func _init() -> void:
	name = "BlackholeSwirl"
	for i in ARMS:
		var arm := DashSpeedLines.new()
		arm.name = "Arm%d" % i
		arm.setup_swirl_arm(LINES_PER_ARM, COLOR)
		_arms.append(arm)
		add_child(arm)
	_place_arms(0.5)


## 毎フレーム呼ぶ。active の間だけ回しながら線を出す(止めても出ている線は寿命まで残る)。r = フン球の半径。
func update_swirl(active: bool, r: float) -> void:
	if active:
		_place_arms(r)
		rotation.y = wrapf(rotation.y + SPIN_SPEED * get_physics_process_delta_time(), 0.0, TAU)
	for arm in _arms:
		if arm.emitting != active:
			arm.emitting = active


## 腕を等間隔に並べ、それぞれの -Z を回る向き(接線)へ向ける。ローカル X は外向きになる。
func _place_arms(r: float) -> void:
	for i in _arms.size():
		var outward := Vector3.RIGHT.rotated(Vector3.UP, TAU * i / _arms.size())
		var tangent := outward.rotated(Vector3.UP, PI * 0.5)
		var arm := _arms[i]
		arm.position = outward * (r + ARM_GAP) + Vector3(0.0, -r * 0.5, 0.0)
		arm.rotation = Vector3(0.0, atan2(-tangent.x, -tangent.z), 0.0)
		arm.set_swirl_extents(0.6, r * 0.4)
