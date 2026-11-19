class_name DashSpeedLines
extends GPUParticles3D
## 高速効果中の上昇線(球の下から上へ流す細長い線)。
## 突進の加速線とブラックホールの渦は resources/effects/ のエフェクトシーン(EffectPlayer)に移した。
## 見た目は speed_line.gdshader。描いた PNG に差し替えるときは line_texture を設定する。

const SHADER: Shader = preload("res://resources/shaders/speed_line.gdshader")

const LINE_WIDTH := 0.10
const LINE_LENGTH := 1.8
const LIFETIME := 0.28
const AMOUNT := 18
const SPEED_MIN := 6.0
const SPEED_MAX := 11.0
## 高速効果の線の色(水色)。
const RISING_COLOR := Color(0.55, 0.9, 1.0)

## 描き下ろし素材(白・縦長・上端が先端)。null なら手続き生成の仮の線。
@export var line_texture: Texture2D:
	set(value):
		line_texture = value
		if _line_mat != null:
			_line_mat.set_shader_parameter("use_texture", value != null)
			_line_mat.set_shader_parameter("streak_tex", value)

var _line_mat: ShaderMaterial
var _process_mat: ParticleProcessMaterial


func _init() -> void:
	name = "DashSpeedLines"
	amount = AMOUNT
	lifetime = LIFETIME
	emitting = false
	local_coords = false # 出た線はワールドに残し、プレイヤーとの相対速度で流す
	randomness = 0.3
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 6, 16))

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(LINE_WIDTH, LINE_LENGTH)
	_line_mat = ShaderMaterial.new()
	_line_mat.shader = SHADER
	mesh.material = _line_mat
	draw_pass_1 = mesh

	_process_mat = ParticleProcessMaterial.new()
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_mat.direction = Vector3(0, 0, -1)
	_process_mat.spread = 0.0
	_process_mat.gravity = Vector3.ZERO
	_process_mat.initial_velocity_min = SPEED_MIN
	_process_mat.initial_velocity_max = SPEED_MAX
	_process_mat.scale_min = 0.6
	_process_mat.scale_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color(1, 1, 1, 0.9))
	fade.add_point(0.6, Color(1, 1, 1, 0.6))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	_process_mat.color_ramp = ramp
	process_material = _process_mat
	set_radius(0.5)


## フン球の大きさに合わせて出現範囲を広げる。
func set_radius(r: float) -> void:
	_process_mat.emission_box_extents = Vector3(r * 1.4, r * 0.9, 0.8)


## 線の色を変える(既定は白)。加算合成なので明るい色ほど目立つ。
func set_tint(color: Color) -> void:
	var fade := Gradient.new()
	fade.set_color(0, Color(color, 0))
	fade.set_color(1, Color(color, 0))
	fade.add_point(0.15, Color(color, 0.9))
	fade.add_point(0.6, Color(color, 0.6))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	_process_mat.color_ramp = ramp


## 高速効果の線にする(add_child 前に呼ぶ)。突進の半分の本数を、球の下から上へ流す。
## プレイヤーに付いて動くようローカル座標で出す。
func setup_rising() -> void:
	amount = maxi(AMOUNT / 2, 1)
	local_coords = true
	set_tint(RISING_COLOR)


## 毎フレーム呼ぶ(setup_rising 用)。r = フン球の半径。親(プレイヤー)の原点 = 球の中心。
func update_rising(active: bool, r: float) -> void:
	if active:
		# ローカル -Z(線の飛ぶ向き)を真上へ。ローカル Y はワールド Z、ローカル Z はワールド -Y になる。
		global_rotation = Vector3(PI * 0.5, 0.0, 0.0)
		position = Vector3(0.0, -r * 0.6, 0.0)
		_process_mat.emission_box_extents = Vector3(r * 1.3, r * 1.0, 0.3)
	if emitting != active:
		emitting = active
