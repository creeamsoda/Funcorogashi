class_name EffectPlayer
extends Node3D
## パーティクルエフェクトの共通スクリプト。エフェクトシーン(resources/effects/*.tscn)の根に付ける。
## 見た目(方向・密度・範囲・色・形・消える速さ)は子の GPUParticles3D をインスペクタで調整する。
## このスクリプトは「出す・止める・向ける・終わったら消す」だけを受け持つ。
##
## 使い方:
##   一回だけ出す : EffectPlayer.spawn(SURPRISE, self, global_position)
##   出し続ける   : var fx := EffectPlayer.spawn(FLEE, self, pos, dir); fx.set_active(running)
##
## 向き: ローカル -Z が「前」。set_direction(dir) で前を dir に向ける(後方へ流す粒は +Z へ飛ばす)。
##
## サブエミッター: 他の GPUParticles3D の Sub Emitter に指定されたノードは、出す・止める・大きさ合わせの対象から外す
## (親の粒に合わせて Godot が出すので触らない)。one_shot の自動削除と stop_and_free は、その粒が消えるまで待つ。

## 一回だけ出して、全部の粒が消えたら自分を消す(驚きなど)。オフなら set_active で出し続ける(逃げの土煙など)。
@export var one_shot := true
## 毎フレーム画面に正対させる(ローカル XZ 面 = 画面、-Z = 画面の上、+Y = カメラ側)。
## 放射状の線や渦を、見下ろしの透視カメラでも潰れたり傾いたりせず見せたいとき用。
## 床に置いたつもりで XZ 面に作ればそのまま画面に向く(放射は flatness = 1、渦の回転軸は Y)。
## オンの間は set_direction の向きは無視される。エディタ上では動かないので、真上から見て確認する。
@export var face_camera := false

## fit_radius の基準。エフェクトシーンはこの半径の球に付けるつもりで作る。
const REF_RADIUS := 0.5

## 出す・止めるを直接操作する GPUParticles3D(サブエミッターは含まない)。
var _particles: Array[GPUParticles3D] = []
## 他の GPUParticles3D の Sub Emitter に指定されているもの。
var _sub_emitters: Array[GPUParticles3D] = []
var _finished_count := 0
var _fitted_radius := REF_RADIUS
var _base := {} # GPUParticles3D -> fit_radius 前の位置・範囲


## エフェクトシーンを生成して parent に付け、位置と向きを合わせて再生する。
## dir を省略すると向きはシーンのまま。one_shot のシーンはすぐ再生し、そうでなければ出し始める。
static func spawn(scene: PackedScene, parent: Node, pos: Vector3, dir := Vector3.ZERO) -> EffectPlayer:
	var fx := scene.instantiate() as EffectPlayer
	parent.add_child(fx)
	fx.global_position = pos
	if not dir.is_zero_approx():
		fx.set_direction(dir)
	if fx.one_shot:
		fx.play()
	else:
		fx.set_active(true)
	return fx


func _ready() -> void:
	var all := find_children("*", "GPUParticles3D", true, false)
	for child in all:
		var p := child as GPUParticles3D
		if p.sub_emitter.is_empty():
			continue
		var sub := p.get_node_or_null(p.sub_emitter) as GPUParticles3D
		if sub != null and not _sub_emitters.has(sub):
			_sub_emitters.append(sub)
	for child in all:
		var p := child as GPUParticles3D
		if _sub_emitters.has(p):
			continue
		_particles.append(p)
		p.emitting = false
		if one_shot:
			p.one_shot = true
			p.finished.connect(_on_particles_finished)
	if face_camera:
		_face_camera()


func _process(_delta: float) -> void:
	if face_camera:
		_face_camera()


## 最初から出し直す(one_shot 用。続けて呼ぶと前の粒を消して出し直す)。
func play() -> void:
	_finished_count = 0
	for p in _particles:
		p.restart()


## 出し続けるエフェクトのオン/オフ。止めても出ている粒は寿命まで残る。
func set_active(active: bool) -> void:
	for p in _particles:
		if p.emitting != active:
			p.emitting = active


## 出し続けるエフェクトが今出ているか。
func is_active() -> bool:
	for p in _particles:
		if p.emitting:
			return true
	return false


## 前(ローカル -Z)を dir の水平成分へ向ける。
func set_direction(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.is_zero_approx():
		return
	flat = flat.normalized()
	global_rotation = Vector3(0.0, atan2(-flat.x, -flat.z), 0.0)


## 球の大きさに合わせる。シーンは半径 REF_RADIUS の球のつもりで作っておき、実際の半径 r との差だけ:
##  - 子の発生位置を水平方向へ外にずらす(前に置いた発生源が球に埋もれないように)
##  - リング状の発生範囲の半径を広げる(球の縁からの距離を保つ)
##  - 箱状の発生範囲の幅(X)と高さ(Y)を r / REF_RADIUS 倍にする
## 粒の大きさ・速さは変えない。初回に Process Material を複製するので、同じシーンの他の個体には影響しない。
func fit_radius(r: float) -> void:
	if is_equal_approx(r, _fitted_radius):
		return
	if _base.is_empty():
		_capture_base()
	_fitted_radius = r
	var diff := r - REF_RADIUS
	var ratio := r / REF_RADIUS
	for p in _particles:
		var base: Dictionary = _base[p]
		var pos: Vector3 = base["pos"]
		var flat := Vector3(pos.x, 0.0, pos.z)
		if not flat.is_zero_approx():
			pos += flat.normalized() * diff
		p.position = pos
		var mat := p.process_material as ParticleProcessMaterial
		if mat == null:
			continue
		match mat.emission_shape:
			ParticleProcessMaterial.EMISSION_SHAPE_RING:
				mat.emission_ring_radius = base["ring"] + diff
				mat.emission_ring_inner_radius = maxf(base["ring_inner"] + diff, 0.0)
			ParticleProcessMaterial.EMISSION_SHAPE_BOX:
				var ext: Vector3 = base["box"]
				mat.emission_box_extents = Vector3(ext.x * ratio, ext.y * ratio, ext.z)


func _capture_base() -> void:
	for p in _particles:
		var base := {"pos": p.position}
		var mat := p.process_material as ParticleProcessMaterial
		if mat != null:
			mat = mat.duplicate()
			p.process_material = mat
			base["ring"] = mat.emission_ring_radius
			base["ring_inner"] = mat.emission_ring_inner_radius
			base["box"] = mat.emission_box_extents
		_base[p] = base


## 出し続けるエフェクトを止め、残った粒が消えてから自分を消す。
func stop_and_free() -> void:
	set_active(false)
	var longest := 0.0
	for p in _particles:
		longest = maxf(longest, p.lifetime)
	get_tree().create_timer(longest + _sub_lifetime()).timeout.connect(queue_free)


## サブエミッターの粒が消えるまでの最長時間(なければ 0)。
func _sub_lifetime() -> float:
	var longest := 0.0
	for sub in _sub_emitters:
		longest = maxf(longest, sub.lifetime)
	return longest


func _face_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Y = 自分からカメラへ向かう向き、X = 画面右、-Z = 画面上。
	# カメラの向きそのものではなく「自分→カメラ」を使うので、画面の端にいても透視で斜めに歪まない。
	var y := cam.global_position - global_position
	if y.is_zero_approx():
		y = cam.global_basis.z
	y = y.normalized()
	var x := cam.global_basis.x
	x = (x - y * x.dot(y)).normalized()
	global_basis = Basis(x, y, x.cross(y))


func _on_particles_finished() -> void:
	_finished_count += 1
	if _finished_count < _particles.size():
		return
	var wait := _sub_lifetime()
	if wait > 0.0:
		get_tree().create_timer(wait).timeout.connect(queue_free)
	else:
		queue_free()
