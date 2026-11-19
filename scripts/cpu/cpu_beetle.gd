class_name CpuBeetle
extends Player
## CPUのフンコロガシ(「ひとりで遊ぶ」の対戦相手)。人間と同じ移動・溜め・突進・被弾・回収のルールで動き、
## 入力だけを CpuBrain が出す仮想入力(スティック・突進ボタン)に置き換える。
## "player" グループに残る(フンの回収・オランウータンの直撃・王冠・順位・結果画面の対象)。
## 入力デバイスの割り当て・Joy-Conの振動・開発用の疑似成長(Space)の対象からは外れる(input_device は待機)。

const GROUP := "cpu"
## 入力デバイス番号: 待機(キーボードでもJoy-Conでもない)。振動・入力の割り当てに含まれない。
const IDLE_DEVICE := -3

## 調整値。null なら Config.cpu を使う(F1パネルの変更がそのまま効く)。
var profile: CpuProfile
var brain: CpuBrain
## true の間は CpuBrain を使わず scripted_move / scripted_dash をそのまま入力にする(テスト用)。
var scripted := false
var scripted_move := Vector2.ZERO
var scripted_dash := false


func _ready() -> void:
	input_device = IDLE_DEVICE
	debug_growth_enabled = false
	super._ready()
	debug_growth_used = false
	add_to_group(GROUP)
	set_process_unhandled_input(false)
	if profile == null:
		profile = Config.cpu if Config.cpu != null else CpuProfile.new()
	brain = CpuBrain.new(self, profile)
	wall_crashed.connect(func(_id: int) -> void: brain.on_wall_crashed())


func _physics_process(delta: float) -> void:
	if gameplay_active and not scripted and brain != null:
		brain.update(delta)
	super._physics_process(delta)


## 台本どおりの仮想入力に切り替える(テスト用)。
func set_scripted_input(move: Vector2, dash_held: bool) -> void:
	scripted = true
	scripted_move = move
	scripted_dash = dash_held


func _read_move() -> Vector2:
	if scripted:
		return scripted_move
	return brain.move if brain != null else Vector2.ZERO


func _dash_input_held() -> bool:
	if scripted:
		return scripted_dash
	return brain.dash if brain != null else false


func _unhandled_input(_event: InputEvent) -> void:
	pass


## F2 デバッグ表示: Player の表示に加え、今のゴール(色)と狙いの先。
func debug_draw(overlay: DebugOverlay) -> void:
	super.debug_draw(overlay)
	if brain == null or not gameplay_active:
		return
	var color := brain.goal_color()
	var base := Vector3(global_position.x, 0.08, global_position.z)
	var aim := Vector3(brain.target_point.x, 0.08, brain.target_point.z)
	overlay.line(base, aim, color)
	overlay.circle(aim, 0.45, color, 16)
	overlay.circle(base, body_radius() + 0.25, color, 24)
