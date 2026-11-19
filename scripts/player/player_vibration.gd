class_name PlayerVibration
## 衝撃の実機振動。対象プレイヤーのデバイスごとにまとめて振動させる。
## 結合ペアなど同じdeviceを複数人が共有する場合、共有者の一部だけを振動させることはできない。
## 無関係なプレイヤーへの誤振動を避けるため、共有者全員がtargetsに含まれる場合だけ実機振動を許可する。
## 各プレイヤーの vibration_requested と、source の vibration_route_resolved で結果を通知する。
## targets は被弾・壁スタン(joy_vibration_duration)、light_targets は突進を当てた側
## (joy_vibration_hit_duration)。同じdeviceに両方いる場合は長い方の時間で振動させる。


static func play_impact(source: Player, targets: Array, light_targets: Array = []) -> void:
	var targets_by_device := {}
	var duration_by_device := {}
	var entries: Array = []
	for node in targets:
		entries.append([node, Config.balance.joy_vibration_duration])
	for node in light_targets:
		entries.append([node, Config.balance.joy_vibration_hit_duration])
	for entry in entries:
		var node = entry[0]
		if not node is Player:
			continue
		var target := node as Player
		if not target.gameplay_active or not target.is_in_group("player") or target.is_queued_for_deletion():
			continue
		target.vibration_requested.emit(target.player_id)
		if not InputRouter.is_joypad(target.input_device):
			continue
		var device := target.input_device
		if not targets_by_device.has(device):
			targets_by_device[device] = {}
			duration_by_device[device] = 0.0
		targets_by_device[device][target.get_instance_id()] = true
		duration_by_device[device] = maxf(float(duration_by_device[device]), float(entry[1]))

	for device_value in targets_by_device:
		var device := int(device_value)
		var target_ids: Dictionary = targets_by_device[device]
		var exclusive := _players_on_device(source.get_tree(), device) == target_ids.size()
		source.vibration_route_resolved.emit(device, exclusive)
		if exclusive:
			start_device_vibration(device, float(duration_by_device[device]))


## device を割り当てられているプレイヤーの人数。
static func _players_on_device(tree: SceneTree, device: int) -> int:
	var n := 0
	for node in tree.get_nodes_in_group("player"):
		var assigned := node as Player
		if assigned != null and not assigned.is_queued_for_deletion() and assigned.input_device == device:
			n += 1
	return n


## キーボード・待機割当・切断済みjoypadでは何もしない、デバイス単位の振動処理。
## duration 省略時は joy_vibration_duration を使う。
static func start_device_vibration(device: int, duration: float = -1.0) -> void:
	if not Input.get_connected_joypads().has(device):
		return
	if not Input.has_joy_vibration(device):
		return
	var weak := clampf(Config.balance.joy_vibration_weak_magnitude, 0.0, 1.0)
	var strong := clampf(Config.balance.joy_vibration_strong_magnitude, 0.0, 1.0)
	if duration < 0.0:
		duration = Config.balance.joy_vibration_duration
	duration = maxf(duration, 0.0)
	# Godotではduration=0が無期限振動なので、0は設定上の「無効」として扱う。
	if duration <= 0.0 or (weak <= 0.0 and strong <= 0.0):
		return
	Input.start_joy_vibration(device, weak, strong, duration)
