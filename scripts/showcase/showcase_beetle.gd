@tool
class_name ShowcaseBeetle
extends ShowcaseItem
## 紹介画像用シーン(Showcase.tscn)に置くフンコロガシ。
## エディタではこのノードを動かして配置する(向き = ノードの -Z。青い矢印の方向へ進んでいる姿になる)。
## 実行すると本物の Player を生成し、操作・物理を止めたまま、指定した状態の見た目とエフェクトを出し続ける。

const PLAYER_SCENE := "res://scenes/Player.tscn"
const BALANCE_PATH := "res://resources/balance_default.tres"
const POSE_NAMES := ["通常", "溜め", "突進加速(線なし)", "突進無敵(加速線)", "スタン"]
const FLASH_NAMES := ["点滅なし", "白く光る", "点滅アニメ"]
enum Pose { NORMAL, CHARGING, DASH_ACCEL, DASH, STUNNED }
enum Flash { OFF, ON, BLINK }

## プレイヤー番号(色)。0=赤 1=青 2=緑 3=黄。
@export_range(0, 3) var player_id: int = 0:
	set(v):
		player_id = v
		_changed()
## 所持フンのサイズ(対戦開始時は 1)。
@export_range(0.2, 60.0, 0.1, "or_greater") var dung_size: float = 1.0:
	set(v):
		dung_size = v
		_changed()
@export_enum("通常", "溜め", "突進加速(線なし)", "突進無敵(加速線)", "スタン") var pose: int = Pose.NORMAL:
	set(v):
		pose = v
		_changed()
@export_group("溜め")
## 溜め量(矢印の長さ)。
@export_range(0.0, 1.0, 0.01) var charge_ratio: float = 0.7:
	set(v):
		charge_ratio = v
		_changed()
@export_enum("点滅なし", "白く光る", "点滅アニメ") var charge_flash: int = Flash.OFF:
	set(v):
		charge_flash = v
		_changed()
@export_group("特殊効果")
## ブラックホール効果中(渦)。
@export var blackhole: bool = false:
	set(v):
		blackhole = v
		_changed()
## 加速フン効果中(上昇線+残像)。
@export var speed_boost: bool = false:
	set(v):
		speed_boost = v
		_changed()
## 加速フン効果の残像の数(止まっていても後ろに並べて出す)。
@export_range(0, 8) var afterimage_count: int = 3:
	set(v):
		afterimage_count = v
		_changed()
## 残像の間隔(m)。
@export_range(0.1, 3.0, 0.05) var afterimage_spacing: float = 0.8:
	set(v):
		afterimage_spacing = v
		_changed()
## 1位の王冠。
@export var crown: bool = false:
	set(v):
		crown = v
		_changed()
@export_group("")
## 突進・加速中にフン球を転がすアニメをするか。
@export var roll_ball: bool = true

var player: Player
var _ghosts: Node3D
var _ghost_key := ""
var _built_player_id := -1
var _preview: Node3D
var _blink_t := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		_build_preview()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS # 一時停止中もドラッグ・状態変更を反映する
	_spawn_player()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or player == null:
		return
	if _built_player_id != player_id:
		_spawn_player()
	if not get_tree().paused:
		_blink_t += delta
	apply_pose(delta if not get_tree().paused else 0.0)


## 説明用の短い名前(ヘルプ表示)。
func describe() -> String:
	var parts: Array[String] = ["P%d" % (player_id + 1), POSE_NAMES[pose], "サイズ %.1f" % dung_size]
	if pose == Pose.CHARGING:
		parts.append("溜め %d%% %s" % [roundi(charge_ratio * 100.0), FLASH_NAMES[charge_flash]])
	if blackhole:
		parts.append("ブラックホール")
	if speed_boost:
		parts.append("加速フン(残像%d)" % afterimage_count)
	if crown:
		parts.append("王冠")
	return " / ".join(parts)


## 選択判定に使う半径(フン球+フンコロガシ)。
func pick_radius() -> float:
	return _radius() + 0.6


func scale_size(factor: float) -> void:
	dung_size *= factor


## --- 実行時 ---

func _spawn_player() -> void:
	if player != null:
		player.queue_free()
	_clear_ghosts()
	player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	player.name = "Player"
	player.player_id = player_id
	player.input_device = 9999 # 入力なし
	player.initial_size = dung_size
	player.process_mode = Node.PROCESS_MODE_PAUSABLE # 一時停止でエフェクトも止める
	add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.collision_layer = 0 # 並べたキャラ同士・フンと干渉させない
	player.collision_mask = 0
	_built_player_id = player_id


## 指定の状態を Player に当てて見た目を更新する(物理処理は止めているので毎フレームここで反映する)。
func apply_pose(delta: float) -> void:
	var p := player
	# 向きはこのノードの回転で表すが、Player 自体は本編と同じく無回転に保つ(矢印・虫の向きがローカル回転のため)。
	p.global_basis = Basis.IDENTITY
	var dir := forward()
	p.facing = dir
	p._dash_dir = dir
	if not is_equal_approx(p.size, dung_size):
		p.size = dung_size
		p._apply_size_visual()
	p._charge_t = 0.0
	match pose:
		Pose.NORMAL:
			p.state = Player.State.ROLLING
		Pose.CHARGING:
			p.state = Player.State.DASH_CHARGING
			p._charge_t = _charge_time_for(charge_ratio)
		Pose.DASH_ACCEL, Pose.DASH:
			p.state = Player.State.DASHING
			p._dash_t = 0.0
			p._dash_duration = 1.0e9
			p._dash_accel_time = 1.0e9 if pose == Pose.DASH_ACCEL else 0.0
		Pose.STUNNED:
			p.state = Player.State.STUNNED
	p._blackhole_t = 1.0e9 if blackhole else 0.0
	p._speed_boost_t = 1.0e9 if speed_boost else 0.0
	p._update_beetle()
	if pose == Pose.CHARGING:
		_apply_charge_flash()
	p._update_dash_arrow()
	p._update_speed_lines()
	p._afterimage.set_active(false) # 本物の残像は動かないと出ないので、下で並べた残像を使う
	p.set_crown_visible(crown)
	if roll_ball and delta > 0.0 and (pose == Pose.DASH_ACCEL or pose == Pose.DASH or speed_boost):
		var speed := 14.0 if pose == Pose.DASH or pose == Pose.DASH_ACCEL else 7.0
		var axis := Vector3.UP.cross(dir)
		p._ball_mi.rotate(axis.normalized(), speed * delta / maxf(p._radius(), 0.2))
	_update_ghosts()


## 溜め量 ratio になる溜め時間(dash_charge_ratio の逆算。単調増加なので二分探索)。
func _charge_time_for(ratio: float) -> float:
	var b := Config.balance
	var scale := b.charge_time_scale(dung_size)
	var lo := b.dash_charge_min
	var hi := maxf(b.dash_charge_time * maxf(scale, 0.01), lo + 0.001)
	for _i in 24:
		var mid := (lo + hi) * 0.5
		if b.dash_charge_ratio(mid, scale) < ratio:
			lo = mid
		else:
			hi = mid
	return hi


func _apply_charge_flash() -> void:
	var white := false
	match charge_flash:
		Flash.ON:
			white = true
		Flash.BLINK:
			white = int(_blink_t / Player.CHARGE_FLASH_INTERVAL) % 2 == 0
	var p := player
	for i in p._beetle.materials.size():
		p._beetle.materials[i].albedo_color = Player.WINDUP_FLASH_COLOR if white else p._beetle_base_colors[i]
	p._ball_mat.albedo_color = Player.WINDUP_FLASH_COLOR if white else p._ball_color


## 加速フン効果の残像を、向きの後ろへ間隔ごとに並べる(後ろほど薄い)。状態が変わった時だけ作り直す。
func _update_ghosts() -> void:
	var count := afterimage_count if speed_boost else 0
	var key := "%s|%s|%d|%.3f|%.3f|%d" % [global_transform, player._ball_mi.transform, count, afterimage_spacing, dung_size, pose]
	if key == _ghost_key:
		return
	_ghost_key = key
	_clear_ghosts()
	if count <= 0:
		return
	_ghosts = Node3D.new()
	_ghosts.name = "Afterimages"
	_ghosts.top_level = true
	add_child(_ghosts)
	var b := Config.balance
	var color := Player.color_for(player_id)
	var sources: Array[MeshInstance3D] = [player._ball_mi]
	sources.append_array(player._beetle.meshes)
	var back := -forward()
	for i in count:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var fade := 1.0 - float(i) / float(count)
		mat.albedo_color = Color(color.r, color.g, color.b, b.afterimage_alpha * fade)
		var offset := back * afterimage_spacing * float(i + 1)
		for src in sources:
			if src.mesh == null or not src.is_visible_in_tree():
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = src.mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ghosts.add_child(mi)
			var t := src.global_transform.scaled_local(Vector3.ONE * AfterimageTrail.GHOST_SCALE)
			t.origin += offset
			mi.global_transform = t


func _clear_ghosts() -> void:
	if _ghosts != null:
		_ghosts.queue_free()
		_ghosts = null
	_ghost_key = ""


func _radius() -> float:
	if Engine.is_editor_hint():
		return editor_radius(dung_size, "size_to_scale")
	return Config.balance.radius_for_size(dung_size, Config.balance.size_to_scale)


## --- エディタ用の簡易表示(保存されない内部ノード) ---

func _changed() -> void:
	if Engine.is_editor_hint():
		_build_preview()
	else:
		_ghost_key = ""


## エディタでは Config(オートロード)が無いので、調整値ファイルから半径を計算する(BalanceConfig.radius_for_size と同じ式)。
static func editor_radius(amount: float, scale_key: String) -> float:
	var b: Resource = load(BALANCE_PATH)
	var size_start: float = maxf(float(b.get("size_start")), 0.001)
	var scale: float = float(b.get(scale_key))
	var mode: int = int(b.get("size_visual_mode"))
	var ratio := maxf(amount, 0.0) / size_start
	var visual := amount
	if mode == 1:
		visual = size_start * pow(ratio, 1.0 / 3.0)
	elif mode == 2:
		var strength := maxf(float(b.get("size_log_strength")), 0.0001)
		visual = size_start * log(1.0 + strength * ratio) / log(1.0 + strength)
	var r := maxf(0.2, visual * scale)
	var max_r: float = float(b.get("visual_radius_max"))
	return minf(r, max_r) if max_r > 0.0 else r


func _build_preview() -> void:
	if not is_inside_tree():
		return
	if _preview != null:
		_preview.queue_free()
	_preview = Node3D.new()
	add_child(_preview, false, Node.INTERNAL_MODE_BACK)
	var r := _radius()
	var color: Color = Player.PLAYER_COLORS[player_id % Player.PLAYER_COLORS.size()]
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	ball.mesh = sphere
	ball.position.y = r
	ball.material_override = _flat_mat(color)
	_preview.add_child(ball)
	# フンコロガシ(球の後ろ = +Z 側)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.35, 0.9)
	body.mesh = box
	body.position = Vector3(0, 0.25, r + 0.4)
	body.material_override = _flat_mat(color.darkened(0.4))
	_preview.add_child(body)
	# 進む向き(-Z)の矢印
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.3
	cone.height = 0.7
	arrow.mesh = cone
	arrow.rotation.x = -PI * 0.5
	arrow.position = Vector3(0, 0.1, -r - 0.5)
	arrow.material_override = _flat_mat(Color(0.3, 0.6, 1.0))
	_preview.add_child(arrow)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 48
	label.pixel_size = 0.01
	label.position.y = r * 2.0 + 0.6
	var text: String = "P%d %s" % [player_id + 1, POSE_NAMES[pose]]
	if blackhole:
		text += "\nブラックホール"
	if speed_boost:
		text += "\n加速フン"
	label.text = text
	_preview.add_child(label)


static func _flat_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m
