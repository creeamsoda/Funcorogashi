@tool
extends Node3D
## 紹介画像用シーン。ステージを出し、子の ShowcaseBeetle / ShowcaseDung を本物の見た目で並べる。
## エディタ: 子ノードを動かして配置し、インスペクタで状態(突進・ブラックホールなど)を選ぶ。
##           ShowcaseCamera を選んでプレビューすると、撮影する構図をエディタで確認できる。
## 実行(F6): マウスとキーで配置・状態をその場で変えられる(操作は画面左上のヘルプ)。
##           F12 でスクリーンショット(screenshots/ に保存)、Ctrl+S で今の配置をこのシーンへ保存。

const LAYOUT_NAMES := ["open", "center", "corners", "lanes", "circle_cross", "pedestal", "boost_pads"]
const SCREENSHOT_DIR := "res://screenshots"
const ROTATE_STEP_DEG := 15.0
const SIZE_STEP := 1.1
const ZOOM_STEP := 1.5

## ステージの形(Stage.LAYOUT_PATHS の順)。
@export_enum("open", "center", "corners", "lanes", "circle_cross", "pedestal", "boost_pads") var stage_layout: int = 0:
	set(v):
		stage_layout = v
		if Engine.is_editor_hint():
			_build_floor_preview()
## 実行開始時にヘルプを出すか(H で切り替え)。
@export var show_help: bool = true

var _stage: Stage
var _cam: Camera3D
var _cam_home: Transform3D
var _selected: ShowcaseItem
var _dragging := false
var _drag_offset := Vector3.ZERO
var _rotating := false
var _panning := false
var _ui: CanvasLayer
var _help: Label
var _status: Label
var _marker: MeshInstance3D
var _floor_preview: Node3D
var _message := ""
var _message_t := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		_build_floor_preview()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stage = (load("res://scenes/Stage.tscn") as PackedScene).instantiate() as Stage
	_stage.layout = Stage.load_layout(stage_layout)
	add_child(_stage)
	move_child(_stage, 0)
	_cam = get_node_or_null("ShowcaseCamera") as Camera3D
	if _cam == null:
		_cam = _stage.get_node("Camera3D") as Camera3D
	_cam.make_current()
	_cam_home = _cam.global_transform
	_build_ui()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _selected != null and not is_instance_valid(_selected):
		_selected = null
	_marker.visible = _selected != null and _ui.visible
	if _selected != null:
		var r := _selected.pick_radius()
		(_marker.mesh as TorusMesh).inner_radius = r
		(_marker.mesh as TorusMesh).outer_radius = r + 0.12
		_marker.global_position = _selected.global_position + Vector3(0, 0.05, 0)
	if _message_t > 0.0:
		_message_t -= delta
	_update_status()


## --- 入力 ---

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event as InputEventKey)


func _on_mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				var hit := _floor_hit(e.position)
				_selected = _pick(hit)
				_dragging = _selected != null
				if _dragging:
					_drag_offset = _selected.global_position - hit
					_drag_offset.y = 0.0
			else:
				_dragging = false
		MOUSE_BUTTON_RIGHT:
			_rotating = e.pressed and _selected != null
			if _rotating:
				_selected.face_toward(_floor_hit(e.position))
		MOUSE_BUTTON_MIDDLE:
			_panning = e.pressed
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not e.pressed:
				return
			var up := e.button_index == MOUSE_BUTTON_WHEEL_UP
			if _selected != null and not e.ctrl_pressed:
				_selected.scale_size(SIZE_STEP if up else 1.0 / SIZE_STEP)
			else:
				_cam.global_position += -_cam.global_basis.z * (ZOOM_STEP if up else -ZOOM_STEP)


func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	if _dragging and _selected != null:
		var hit := _floor_hit(e.position)
		_selected.global_position = Vector3(hit.x + _drag_offset.x, _selected.global_position.y, hit.z + _drag_offset.z)
	elif _rotating and _selected != null:
		_selected.face_toward(_floor_hit(e.position))
	elif _panning:
		var prev := _floor_hit(e.position - e.relative)
		var now := _floor_hit(e.position)
		_cam.global_position += prev - now


func _on_key(e: InputEventKey) -> void:
	var k := e.keycode
	if e.ctrl_pressed and k == KEY_S:
		_save_layout()
		return
	match k:
		KEY_F12:
			_screenshot()
			return
		KEY_H:
			_ui.visible = not _ui.visible
			return
		KEY_SPACE:
			get_tree().paused = not get_tree().paused
			return
		KEY_HOME:
			_cam.global_transform = _cam_home
			return
		KEY_TAB:
			_cycle_selection(-1 if e.shift_pressed else 1)
			return
		KEY_N:
			_add_item(ShowcaseBeetle.new())
			return
		KEY_M:
			_add_item(ShowcaseDung.new())
			return
	if _selected == null:
		return
	match k:
		KEY_Q:
			_selected.rotation.y += deg_to_rad(ROTATE_STEP_DEG)
		KEY_E:
			_selected.rotation.y -= deg_to_rad(ROTATE_STEP_DEG)
		KEY_D:
			_duplicate_selected()
		KEY_DELETE, KEY_BACKSPACE:
			_selected.queue_free()
			_selected = null
		_:
			if _selected is ShowcaseBeetle:
				_on_beetle_key(_selected as ShowcaseBeetle, k)
			elif _selected is ShowcaseDung:
				_on_dung_key(_selected as ShowcaseDung, k)


func _on_beetle_key(b: ShowcaseBeetle, k: Key) -> void:
	match k:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			b.pose = k - KEY_1
		KEY_B:
			b.blackhole = not b.blackhole
		KEY_V:
			b.speed_boost = not b.speed_boost
		KEY_C:
			b.crown = not b.crown
		KEY_F:
			b.charge_flash = (b.charge_flash + 1) % ShowcaseBeetle.FLASH_NAMES.size()
		KEY_G:
			b.afterimage_count = (b.afterimage_count + 1) % 7
		KEY_UP:
			b.charge_ratio = minf(b.charge_ratio + 0.1, 1.0)
		KEY_DOWN:
			b.charge_ratio = maxf(b.charge_ratio - 0.1, 0.0)
		KEY_P:
			b.player_id = (b.player_id + 1) % Player.PLAYER_COLORS.size()


func _on_dung_key(d: ShowcaseDung, k: Key) -> void:
	match k:
		KEY_1, KEY_2, KEY_3:
			d.kind = k - KEY_1
		KEY_4:
			d.fleeing = not d.fleeing


## --- 配置の操作 ---

func _items() -> Array[ShowcaseItem]:
	var list: Array[ShowcaseItem] = []
	for child in get_children():
		if child is ShowcaseItem and not child.is_queued_for_deletion():
			list.append(child as ShowcaseItem)
	return list


## 床の点に一番近い(選択範囲内の)キャラ・フン。
func _pick(hit: Vector3) -> ShowcaseItem:
	var best: ShowcaseItem = null
	var best_d := INF
	for item in _items():
		var d := Vector2(item.global_position.x - hit.x, item.global_position.z - hit.z).length()
		if d <= item.pick_radius() and d < best_d:
			best = item
			best_d = d
	return best


func _cycle_selection(step: int) -> void:
	var list := _items()
	if list.is_empty():
		return
	var i := list.find(_selected)
	_selected = list[posmod(i + step, list.size())] if i >= 0 else list[0]


func _add_item(item: ShowcaseItem) -> void:
	var hit := _floor_hit(get_viewport().get_mouse_position())
	if item is ShowcaseBeetle:
		(item as ShowcaseBeetle).player_id = _next_player_id()
		item.name = "Beetle"
	else:
		item.name = "Dung"
	add_child(item, true)
	item.owner = self # Ctrl+S で保存されるように
	item.global_position = Vector3(hit.x, 0.0, hit.z)
	_selected = item


func _duplicate_selected() -> void:
	var copy := _selected.duplicate() as ShowcaseItem
	# 実行時に生成した Player / DungPickup は複製しない(各ノードが自分で作り直す)
	for child in copy.get_children():
		copy.remove_child(child)
		child.free()
	add_child(copy, true)
	copy.owner = self
	copy.global_transform = _selected.global_transform
	copy.global_position += Vector3(1.5, 0, 1.5)
	_selected = copy


func _next_player_id() -> int:
	var used := {}
	for item in _items():
		if item is ShowcaseBeetle:
			used[(item as ShowcaseBeetle).player_id] = true
	for i in Player.PLAYER_COLORS.size():
		if not used.has(i):
			return i
	return 0


## 画面上の点から床(y=0)への交点。
func _floor_hit(screen_pos: Vector2) -> Vector3:
	var origin := _cam.project_ray_origin(screen_pos)
	var normal := _cam.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, normal)
	return hit if hit != null else Vector3.ZERO


## --- 保存・撮影 ---

## 今の配置・状態・カメラをこのシーンファイルへ上書き保存する(実行時に作ったノードは除く)。
func _save_layout() -> void:
	var path := scene_file_path
	if path.is_empty():
		_flash_message("保存先のシーンが分かりません")
		return
	var packed := PackedScene.new()
	var err := packed.pack(self)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	_flash_message(("保存しました: " + path) if err == OK else ("保存に失敗しました (err=%d)" % err))


func _screenshot() -> void:
	var ui_was := _ui.visible
	_ui.visible = false
	_marker.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_ui.visible = ui_was
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCREENSHOT_DIR))
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var path := "%s/showcase_%s.png" % [SCREENSHOT_DIR, stamp]
	var err := img.save_png(path)
	var abs_path := ProjectSettings.globalize_path(path)
	print("[showcase] screenshot ", abs_path, " err=", err)
	_flash_message(("保存しました: " + abs_path) if err == OK else ("撮影に失敗しました (err=%d)" % err))


## --- UI ---

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "ShowcaseUI"
	add_child(_ui)
	_ui.visible = show_help
	_help = MenuStyle.make_label(_help_text(), 15)
	_help.position = Vector2(12, 10)
	_help.add_theme_color_override("font_outline_color", Color.BLACK)
	_help.add_theme_constant_override("outline_size", 5)
	_ui.add_child(_help)
	_status = MenuStyle.make_label("", 18, MenuStyle.GOLD)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 6)
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_left = 12
	_status.offset_top = -64
	_ui.add_child(_status)

	_marker = MeshInstance3D.new()
	_marker.name = "SelectionMarker"
	_marker.mesh = TorusMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.2)
	mat.no_depth_test = true
	_marker.material_override = mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)


func _help_text() -> String:
	return "\n".join([
		"[紹介画像シーン]  H: この表示を消す  F12: スクショ  Ctrl+S: 配置をシーンに保存  Space: 一時停止",
		"左ドラッグ: 選択・移動  右ドラッグ: 向き  Q/E: 回転  ホイール: フンのサイズ  Tab: 選択切替",
		"N: キャラ追加  M: フン追加  D: 複製  Delete: 削除",
		"カメラ  中ドラッグ: 移動  Ctrl+ホイール(未選択ならホイール): 寄る/引く  Home: 元に戻す",
		"キャラ  1:通常 2:溜め 3:突進加速(線なし) 4:突進無敵(加速線) 5:スタン",
		"        B:ブラックホール V:加速フン G:残像の数 C:王冠 P:色  溜め中 ↑↓:溜め量 F:点滅",
		"フン    1:通常 2:ブラックホール 3:加速  4:逃げ土煙",
	])


func _update_status() -> void:
	var lines: Array[String] = []
	if _selected != null:
		lines.append("選択中: " + _selected.describe())
	if get_tree().paused:
		lines.append("一時停止中")
	if _message_t > 0.0:
		lines.append(_message)
	_status.text = "\n".join(lines)


func _flash_message(text: String) -> void:
	_message = text
	_message_t = 4.0


## --- エディタ用の床の目安(保存されない内部ノード) ---

func _build_floor_preview() -> void:
	if not is_inside_tree():
		return
	if _floor_preview != null:
		_floor_preview.queue_free()
	_floor_preview = Node3D.new()
	add_child(_floor_preview, false, Node.INTERNAL_MODE_BACK)
	var layout: Resource = load(Stage.LAYOUT_PATHS[clampi(stage_layout, 0, Stage.LAYOUT_PATHS.size() - 1)])
	var mi := MeshInstance3D.new()
	if layout != null and int(layout.get("arena_shape")) == 1:
		var cyl := CylinderMesh.new()
		cyl.top_radius = float(layout.get("arena_radius"))
		cyl.bottom_radius = cyl.top_radius
		cyl.height = 0.02
		mi.mesh = cyl
	else:
		var plane := PlaneMesh.new()
		plane.size = Stage.STAGE_SIZE
		mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.45, 0.3)
	mi.material_override = mat
	mi.position.y = -0.01
	_floor_preview.add_child(mi)
