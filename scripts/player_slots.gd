extends Node
## Autoload(PlayerSlots)。「みんなでバトル！」で選んだ人数と、コントローラー→プレイヤーの割り当てを
## シーン遷移(タイトル→チュートリアル→試合→リトライ)をまたいで保持する。
## 人数選択の時点で認識済みJoy-Conが2台以上なら「先着順」モード:
##   選択した瞬間より後に入力(ボタン押下・スティック倒し)があったコントローラーから順に P1, P2, ... へ割り当てる。
##   人数を超える分の入力は無視する。未割り当てのプレイヤーは待機(入力なし)。
## それ以外(0〜1台)は従来どおり InputRouter.sources の接続順+キーボード併用。
## count == 0(タイトルを経由しないテスト起動など)のときは使わない。

signal assigned(slot: int, device: int) ## device = -1 は割り当て解除(切断)

## スティックをこれ以上倒したら「入力あり」とみなす(ドリフトで割り当てない)。
const AXIS_THRESHOLD := 0.5
const POLL_BUTTONS := 21 ## JOY_BUTTON_SDL_MAX 相当

var count := 0
var first_come := false
var _devices: Array[int] = []  ## slot -> device(-1 = 未割り当て)
var _prev_active := {}         ## device -> 前フレームに何か入力していたか


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## 人数を確定して割り当てを始める。この時点で押しっぱなしの入力は数えない(離して押し直すと数える)。
func begin(player_count: int) -> void:
	begin_with_pads(player_count, InputRouter.known_pads())
	for d in _prev_active.keys():
		_prev_active[d] = _any_input(d)


## 実デバイスと切り離した本体(テスト用)。
func begin_with_pads(player_count: int, pads: Array[int]) -> void:
	count = clampi(player_count, 1, 4)
	first_come = pads.size() >= 2
	_devices.clear()
	_devices.resize(count)
	_devices.fill(-1)
	_prev_active.clear()
	for d in pads:
		_prev_active[d] = false


func end() -> void:
	count = 0
	first_come = false
	_devices.clear()
	_prev_active.clear()


func is_active() -> bool:
	return count > 0


## プレイヤー slot の入力デバイス(PlayerInput の番号規則)。
func device_for(slot: int) -> int:
	if first_come:
		if slot >= 0 and slot < _devices.size() and _devices[slot] >= 0:
			return _devices[slot]
		return 9000 + slot # 待機
	return InputRouter.sources(count)[slot]["device"]


func is_assigned(slot: int) -> bool:
	return not first_come or (slot >= 0 and slot < _devices.size() and _devices[slot] >= 0)


func _process(_delta: float) -> void:
	if not first_come:
		return
	for d in Input.get_connected_joypads():
		if not Input.is_joy_known(d) or InputRouter.is_combined_joycon(d):
			continue
		observe(d, _any_input(d))


## device の今フレームの入力有無を渡す。押していない→押した、の変化で空き枠へ割り当てる。
func observe(device: int, active: bool) -> void:
	var was: bool = _prev_active.get(device, false)
	_prev_active[device] = active
	if not first_come or not active or was or _devices.has(device):
		return
	var slot := _devices.find(-1)
	if slot < 0:
		return # 人数を超える分は無視
	_devices[slot] = device
	print("[input] P%d <- joypad%d (%s) 先着順" % [slot + 1, device, Input.get_joy_name(device)])
	assigned.emit(slot, device)


func _any_input(device: int) -> bool:
	for b in POLL_BUTTONS:
		if Input.is_joy_button_pressed(device, b):
			return true
	var v := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	return v.length() >= AXIS_THRESHOLD


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected or not first_come:
		return
	_prev_active.erase(device)
	var slot := _devices.find(device)
	if slot >= 0:
		# 抜けた枠は空きに戻し、次に入力したコントローラーで埋める。
		_devices[slot] = -1
		assigned.emit(slot, -1)
