extends Node3D
## チュートリアル(「みんなでバトル！」→人数→チュートリアルあり)。
## 1. 突進練習: 加速板を除いた現在の対戦ステージ。中央上部にデカいフンを持った茶色のNPC。
##    画面上部にJoy-Conの操作説明、その下に「突進を当てよう！(k/N人)」。
##    全プレイヤーが突進を当てたら(NPC・プレイヤー同士を問わない)次へ。
## 2. 特殊フン紹介(5秒): 寄せたカメラで左にブラックホールのフン、右に8の字で動く加速フン。各フンの下に固定の説明。
## 3. 試合(Game.tscn)へ。
## + / − / ESC でスキップ(次の段階へ)。

enum Phase { HIT, CLEARED, EXPLAIN, DONE }

const NPC_POS := Vector3(0, 0, -3.5)
const NPC_SIZE := 30.0
const CLEAR_WAIT := 1.2          ## 全員達成から紹介へ移るまで(達成表示を見せる)
const EXPLAIN_TIME := 5.0
const EXPLAIN_DUNG_SIZE := 1.5
const EXPLAIN_ZOOM := 4.0        ## 俯瞰カメラに対する寄り(距離 1/4)
const EXPLAIN_LOOK_AT := Vector3(0, 0, 0.6)
const EXPLAIN_LABEL_GAP := 0.3   ## フンの動く範囲の下端から説明文まで(m)
const BLACKHOLE_POS := Vector3(-3.6, 0, 0)
const SPEED_CENTER := Vector3(3.6, 0, 0)
const SPEED_PATH_HALF := Vector3(1.5, 0, 0.6) ## 8の字の半幅(x, z)
const SPEED_LOOP_TIME := 2.5     ## 8の字1周の秒数
const PROGRESS_FONT_SIZE := 72
const EXPLAIN_FONT_SIZE := 40

var players: Array[Player] = []
var _hit := {}                   ## player_id -> true(突進を当てた)
var _phase := Phase.HIT
var _world: Node3D
var _canvas: CanvasLayer
var _hit_ui: Control
var _progress: Label
var _explain_ui: Control
var _explain_t := 0.0
var _speed_dung: DungPickup
var _camera: Camera3D


func _ready() -> void:
	_canvas = CanvasLayer.new()
	add_child(_canvas)
	_build_hit_phase()
	if PlayerSlots.is_active():
		PlayerSlots.assigned.connect(_on_slot_assigned)


## --- 1. 突進練習 ---

func _build_hit_phase() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	var stage := (load("res://scenes/Stage.tscn") as PackedScene).instantiate() as Stage
	stage.layout = _layout_without_boost_pads(Stage.load_layout(Config.balance.stage_layout))
	_world.add_child(stage)
	_camera = stage.get_node("Camera3D") as Camera3D
	var dung := Node3D.new()
	dung.name = "Dung"
	dung.add_to_group("dung_container")
	_world.add_child(dung)

	var npc := TutorialNpc.new()
	npc.name = "TutorialNpc"
	npc.player_id = 1000
	npc.initial_size = NPC_SIZE
	npc.home = NPC_POS
	_world.add_child(npc)

	var n: int = GameManager.versus_player_count()
	var devices: Array[int] = GameManager.versus_devices(n)
	var spots: Array = GameManager.spawn_spots_for(n, stage)
	for i in n:
		var p: Player = (load("res://scenes/Player.tscn") as PackedScene).instantiate()
		p.player_id = i
		p.input_device = devices[i]
		_world.add_child(p)
		p.global_position = spots[i % spots.size()]
		p.suppress_dash_until_release()
		p.dash_hit.connect(_on_dash_hit)
		players.append(p)
		# キーボード併用時の空き枠(操作できない)は達成扱いにする。
		if not PlayerSlots.first_come and not _controllable(p.input_device):
			_hit[i] = true

	_hit_ui = Control.new()
	_hit_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hit_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_hit_ui)
	var band := ColorRect.new()
	band.color = Color(0, 0, 0, 0.3)
	band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	band.offset_bottom = 170
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_ui.add_child(band)
	var guide := JoyconGuide.new()
	guide.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	guide.offset_top = 10
	guide.offset_bottom = 160
	_hit_ui.add_child(guide)
	_progress = MenuStyle.make_label("", PROGRESS_FONT_SIZE, Color.WHITE)
	_progress.add_theme_color_override("font_outline_color", Color.BLACK)
	_progress.add_theme_constant_override("outline_size", 16)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_progress.offset_top = 175
	_progress.offset_bottom = 275
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_ui.add_child(_progress)
	_hit_ui.add_child(_skip_hint())
	_update_progress()


## 対戦ステージ設定の複製から加速板だけ除く(共有リソースは書き換えない)。
static func _layout_without_boost_pads(source: StageLayout) -> StageLayout:
	var layout := source.duplicate() as StageLayout
	var no_pads: Array[BoostPadSpec] = []
	layout.boost_pads = no_pads
	return layout


static func _controllable(device: int) -> bool:
	return InputRouter.is_joypad(device) or PlayerInput.is_keyboard(device)


func _on_dash_hit(attacker_id: int, _victim_id: int) -> void:
	if _phase != Phase.HIT or attacker_id < 0 or attacker_id >= players.size():
		return
	if _hit.has(attacker_id):
		return
	_hit[attacker_id] = true
	_update_progress()
	if _hit.size() >= players.size():
		_phase = Phase.CLEARED
		_finish_hit_phase.call_deferred()


func _finish_hit_phase() -> void:
	await get_tree().create_timer(CLEAR_WAIT, false).timeout
	if _phase == Phase.CLEARED:
		_start_explain()


func _update_progress() -> void:
	_progress.text = "突進を当てよう！(%d/%d人)" % [_hit.size(), players.size()]


func _on_slot_assigned(slot: int, _device: int) -> void:
	if _phase != Phase.HIT or slot < 0 or slot >= players.size():
		return
	players[slot].input_device = PlayerSlots.device_for(slot)
	players[slot].suppress_dash_until_release()


## --- 2. 特殊フン紹介 ---
## 通常の俯瞰より EXPLAIN_ZOOM 倍寄せたカメラで、左にブラックホール、右に加速フンを映す。
## 加速フンは画面から出ないよう、逃走AIを止めて決め打ちの8の字で動かす(残像は移動で自動的に出る)。
## 説明文は画面に固定(各フンの定位置の下)。

func _start_explain() -> void:
	_phase = Phase.EXPLAIN
	_explain_t = 0.0
	for p in players:
		p.stop_gameplay()
	players.clear()
	remove_child(_world)
	_world.queue_free()
	_hit_ui.queue_free()

	_world = Node3D.new()
	_world.name = "ExplainWorld"
	add_child(_world)
	var stage := (load("res://scenes/Stage.tscn") as PackedScene).instantiate() as Stage
	stage.layout = Stage.load_layout(0) # 障害物なし
	_world.add_child(stage)
	var stage_cam := stage.get_node("Camera3D") as Camera3D
	_camera = Camera3D.new()
	_camera.name = "ExplainCamera"
	_camera.fov = stage_cam.fov
	_world.add_child(_camera)
	# 俯瞰カメラと同じ向きのまま、注視点までの距離を 1/EXPLAIN_ZOOM にする。
	var offset := stage_cam.global_position / EXPLAIN_ZOOM
	_camera.global_position = EXPLAIN_LOOK_AT + offset
	_camera.look_at(EXPLAIN_LOOK_AT, Vector3.UP)
	_camera.make_current()

	_explain_ui = Control.new()
	_explain_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_explain_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_explain_ui)
	_add_explained_dung(DungPickup.Kind.BLACKHOLE, BLACKHOLE_POS, SPEED_PATH_HALF, "まわりのフンを吸い込む")
	_speed_dung = _add_explained_dung(DungPickup.Kind.SPEED, SPEED_CENTER, SPEED_PATH_HALF, "スピードアップ")
	_explain_ui.add_child(_skip_hint())


## 動きを止めた(見た目だけの)特殊フンを置き、その定位置の下へ説明文を固定表示する。
## reach = フンが動く範囲の半幅(x, z)。説明文はその範囲の下へ置く(左右で高さを揃えるため同じ値を渡す)。
func _add_explained_dung(kind: DungPickup.Kind, pos: Vector3, reach: Vector3, text: String) -> DungPickup:
	var pk := DungPickup.create(EXPLAIN_DUNG_SIZE)
	pk.kind = kind
	_world.add_child(pk)
	pk.global_position = pos
	pk.set_physics_process(false) # 逃走・引き寄せ・回収をしない
	pk.collision_layer = 0
	pk._placed = true
	pk._heading = Vector3.RIGHT
	pk._update_visual()
	var label := MenuStyle.make_label(text, EXPLAIN_FONT_SIZE, Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_explain_ui.add_child(label)
	label.reset_size()
	var bottom := pos + Vector3(0, 0, reach.z + pk._radius() + EXPLAIN_LABEL_GAP)
	var screen := _camera.unproject_position(bottom)
	label.position = Vector2(_camera.unproject_position(pos).x - label.size.x * 0.5, screen.y)
	return pk


## 加速フンの決め打ちの動き: SPEED_CENTER を中心に横長の8の字を描く。
func _speed_path(t: float) -> Vector3:
	var a := t * TAU / SPEED_LOOP_TIME
	return SPEED_CENTER + Vector3(sin(a) * SPEED_PATH_HALF.x, 0.0, sin(a * 2.0) * SPEED_PATH_HALF.z)


func _process(delta: float) -> void:
	if _phase != Phase.EXPLAIN:
		return
	_explain_t += delta
	if is_instance_valid(_speed_dung):
		var pos := _speed_path(_explain_t)
		var dir := _speed_path(_explain_t + 0.02) - pos
		_speed_dung.global_position = pos
		if dir.length() > 0.0001:
			_speed_dung._heading = dir.normalized()
		_speed_dung._state = DungPickup.FleeState.RUNNING
		_speed_dung._update_visual()
	if _explain_t >= EXPLAIN_TIME:
		_go_to_battle()


## --- 3. 試合へ ---

func _go_to_battle() -> void:
	if _phase == Phase.DONE:
		return
	_phase = Phase.DONE
	MatchSession.start(get_tree(), "versus")


## --- スキップ ---

func _skip_hint() -> Label:
	var hint := MenuStyle.make_label("＋ / ESC：スキップ", 20, Color(1, 1, 1, 0.8))
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 6)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_right = -20
	hint.offset_bottom = -14
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return hint


func _unhandled_input(event: InputEvent) -> void:
	if not _is_skip_event(event):
		return
	get_viewport().set_input_as_handled()
	match _phase:
		Phase.HIT, Phase.CLEARED:
			_start_explain()
		Phase.EXPLAIN:
			_go_to_battle()


func _is_skip_event(event: InputEvent) -> bool:
	if event.is_echo():
		return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		return true
	if event is InputEventJoypadButton and event.pressed:
		return event.button_index == JOY_BUTTON_START or event.button_index == JOY_BUTTON_BACK
	return false
