class_name AfterimageTrail
extends Node3D
## 高速効果中の残像。有効な間、対象メッシュ(フン球とフンコロガシ)のその瞬間の姿を
## 一定間隔でその場に複製し、透明から半透明へ浮かび上がらせてから短時間でフェードさせて消す。
## 複製は top_level にしてワールドに置き去りにする(プレイヤーが動いても付いてこない)。
## 生成間隔・消えるまでの時間・不透明度は BalanceConfig の afterimage_* で調整する。

var _targets: Array[MeshInstance3D] = []
var _color := Color.WHITE
var _active := false
var _spawn_t := 0.0
var _last_pos := Vector3.INF
## 前回の残像からこれ以下しか動いていなければ出さない(止まっている間に同じ場所へ重ねない)。
const MIN_MOVE := 0.05
## 残像を本体よりわずかに小さくし、出た瞬間に本体と同じ面で重なってちらつく(Zファイティング)のを防ぐ。
const GHOST_SCALE := 0.99


## targets: 残像にするメッシュ。color: 残像の色(アルファは afterimage_alpha で上書き)。
func setup(targets: Array[MeshInstance3D], color: Color) -> void:
	_targets = targets
	_color = color


func set_active(active: bool) -> void:
	if active and not _active:
		_spawn_t = 0.0 # 有効になった瞬間に1つ出す
	_active = active


func _process(delta: float) -> void:
	if not _active:
		return
	_spawn_t -= delta
	if _spawn_t > 0.0:
		return
	_spawn_t += maxf(Config.balance.afterimage_interval, 0.01)
	if _spawn_t <= 0.0:
		_spawn_t = Config.balance.afterimage_interval # 長いフレーム落ちで溜め込まない
	var pos := global_position
	if _last_pos.distance_to(pos) < MIN_MOVE:
		return
	_last_pos = pos
	_spawn()


func _spawn() -> void:
	var b := Config.balance
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(_color.r, _color.g, _color.b, 0.0)
	var ghost := Node3D.new()
	ghost.name = "Afterimage"
	ghost.top_level = true
	add_child(ghost)
	for src in _targets:
		if not is_instance_valid(src) or src.mesh == null or not src.is_visible_in_tree():
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = src.mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(mi)
		mi.global_transform = src.global_transform.scaled_local(Vector3.ONE * GHOST_SCALE)
	var tw := ghost.create_tween()
	# 0 → afterimage_alpha へ afterimage_fade_in 秒で上げ、そこから afterimage_lifetime 秒で 0 へ下げる。
	if b.afterimage_fade_in > 0.0:
		tw.tween_property(mat, "albedo_color:a", b.afterimage_alpha, b.afterimage_fade_in)
	else:
		mat.albedo_color.a = b.afterimage_alpha
	tw.tween_property(mat, "albedo_color:a", 0.0, maxf(b.afterimage_lifetime, 0.01))
	tw.tween_callback(ghost.queue_free)
