class_name DashSpeedLines
extends GPUParticles3D
## 突進中の加速線。プレイヤー前方の箱から細長い線を出し、突進と逆向き(後方)へ飛ばす。
## 線は地面と平行な板(PlaneMesh。長辺 = ローカル Z)で、ワールド座標に残るので
## プレイヤーが進むほど後ろへ流れて見える。高さをばらけさせて立体感を出す。
## 見た目は speed_line.gdshader。描いた PNG に差し替えるときは line_texture を設定する。

const SHADER: Shader = preload("res://resources/shaders/speed_line.gdshader")
## 通常合成版(色をそのまま出す。加速板の風用)。
const SHADER_MIX: Shader = preload("res://resources/shaders/speed_line_mix.gdshader")

const LINE_WIDTH := 0.10
const LINE_LENGTH := 1.8
const LIFETIME := 0.28
const AMOUNT := 18
const SPEED_MIN := 6.0
const SPEED_MAX := 11.0
## setup_area(加速板の風)の線の太さ倍率。通常合成なので細いと見えにくい。
const AREA_LINE_WIDTH_SCALE := 2.5

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


## 固定の範囲から常に流す(加速板の風)。center = 範囲の中心、dir = 線が流れる向き、extents = 範囲の半分の大きさ(ワールド軸)。
## 線は範囲の中から出て dir へ流れる。範囲は dir に合わせて回すので extents の x/z は向きに応じて入れ替える。
func setup_area(center: Vector3, dir: Vector3, extents: Vector3, color: Color) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	# 粒子はローカル -Z へ飛ぶので、ローカル -Z が dir を向くよう回す。
	global_position = center
	global_rotation = Vector3(0.0, atan2(-flat.x, -flat.z), 0.0)
	var along_z := absf(flat.z) >= absf(flat.x)
	if along_z:
		_process_mat.emission_box_extents = extents
	else:
		_process_mat.emission_box_extents = Vector3(extents.z, extents.y, extents.x)
	amount = int(clampf(extents.x * extents.z * 3.0, 16.0, 64.0))
	_line_mat.shader = SHADER_MIX
	var mesh := draw_pass_1 as PlaneMesh
	mesh.size = Vector2(LINE_WIDTH * AREA_LINE_WIDTH_SCALE, LINE_LENGTH)
	set_tint(color)
	emitting = true


## 毎フレーム呼ぶ。active の間だけ新しい線を出す(止めても出ている線は寿命まで残る)。
## dir = 突進方向、center = フン球の中心(ワールド)。
func update_emitter(active: bool, dir: Vector3, center: Vector3, r: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if active and not flat.is_zero_approx():
		flat = flat.normalized()
		set_radius(r)
		global_position = center + flat * (r + 0.6)
		global_rotation = Vector3(0.0, atan2(flat.x, flat.z), 0.0)
	if emitting != active:
		emitting = active
